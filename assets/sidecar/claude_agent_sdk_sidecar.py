"""Claude Agent SDK sidecar: the transport half of the AD-19 protocol.

Reads exactly one JSON request line from stdin, streams the model's raw text
back as NDJSON on stdout, and exits. All interpretation of that text —
register tags, prompt shape, retries — is the Dart side's job: logic here
would be reachable by neither `dart analyze` nor `dart test`, so this file
must stay describable as "move bytes and translate lifecycle".
"""

import asyncio
import json
import os
import sys
from typing import NoReturn


def emit(line: dict) -> None:
    # Flush per line: the daemon renders deltas as they stream (CAP-5), so a
    # buffered stdout would defeat the whole protocol.
    try:
        print(json.dumps(line), flush=True)
    except BrokenPipeError:
        # The daemon exited mid-correction. The adapter spawns us through
        # `setsid`, so we outlive it and every subsequent write fails — first
        # here, and then again inside `main()`'s handler when it tries to report
        # this one, which is an uncaught traceback on the stderr the story just
        # finished clearing. There is no reader left to tell anything to.
        #
        # os._exit, not sys.exit: the interpreter flushes stdout at shutdown,
        # and that flush would fail too, printing "Exception ignored in:
        # <_io.TextIOWrapper name='<stdout>'>" after we had already given up.
        os._exit(1)


class SidecarFailure(Exception):
    """A failure carried out to `main()` instead of exiting where it is found.

    `sys.exit` inside the SDK's `async for` unwinds through an async generator
    that is still running, and the interpreter then prints a `SystemExit`
    traceback plus `RuntimeError: aclose(): asynchronous generator is already
    running` onto stderr — which the adapter forwards verbatim into an all-day
    daemon's log, beside the one error line the protocol actually asked for.
    Raising instead lets `asyncio.run` close the generator normally and leaves
    `main()`, the one frame outside every generator, to emit and exit.
    """

    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message


def fail(kind: str, message: str) -> NoReturn:
    """Emit the protocol's error line and exit. Safe only outside a generator.

    Callers inside `stream_correction` raise `SidecarFailure` instead. Every
    call site left is outside every loop: the module-level import guard, which
    runs before one exists, and the three handlers in `main()`.

    `NoReturn`, not `None`: the module-level `except ImportError: fail(...)` is
    the one call site that runs before an event loop exists, and with a `-> None`
    annotation a checker sees execution continue past it into a module where
    `query`, `ClaudeAgentOptions` and every other SDK symbol is unbound. The
    annotation is what makes the guard's control flow legible to a tool.
    """
    emit({"type": "error", "kind": kind, "message": message})
    sys.exit(1)


# Import failure is the "interpreter exists but is not provisioned" case:
# naming the package makes the panel error actionable (AD-19).
try:
    from claude_agent_sdk import (
        AssistantMessage,
        ClaudeAgentOptions,
        CLIConnectionError,
        CLINotFoundError,
        ResultMessage,
        StreamEvent,
        TextBlock,
        query,
    )
except ImportError as error:
    fail("providerUnavailable", f"cannot import claude_agent_sdk: {error}")


# How long the SDK's stream gets to shut its `claude` child down. Generous
# against a slow teardown and far below the adapter's 60 s correction deadline,
# so a stuck close costs a late `done` rather than the whole correction.
CLOSE_TIMEOUT_SECONDS = 5.0


def is_text_delta(event: dict) -> bool:
    return (
        event.get("type") == "content_block_delta"
        and event.get("delta", {}).get("type") == "text_delta"
    )


def validated(request: object) -> dict:
    # The Dart side validates every line we send; validating the line it
    # sends keeps the protocol strict in both directions, so a serialization
    # regression names the offending field instead of surfacing a KeyError.
    if not isinstance(request, dict):
        raise SidecarFailure("providerError", "request line is not a JSON object")
    for field in ("text", "model", "system_prompt"):
        if not isinstance(request.get(field), str):
            raise SidecarFailure(
                "providerError", f'request missing string field "{field}"'
            )
    return request


async def close_quietly(messages: object) -> None:
    """Close the SDK's stream, and never let the closing become the failure.

    Closing explicitly is what keeps a traceback off stderr: leaving the loop
    early does not close the generator (PEP 533 was deferred), so the
    interpreter closes it during loop shutdown, concurrently with the
    generator's own nested aclose, and prints "RuntimeError: aclose():
    asynchronous generator is already running".

    Both guards below exist because this runs in a `finally`, where anything
    raised *replaces* whatever was already unwinding:

    * an SDK that handed back a plain async iterator has no `aclose` at all,
      and the resulting AttributeError would turn every **successful**
      correction into `providerError: AttributeError`;
    * a close that raises while a `SidecarFailure` is on its way out would
      take its place, so `main()` would report the cleanup error and the
      actual reason for the failure would be gone.

    A close that fails is not news the protocol has any use for: the process
    is about to exit, and the adapter kills the whole group anyway (AD-19).

    Two details of the `except` matter. It catches `BaseException`, because
    `CancelledError` has not been an `Exception` since 3.8 and is exactly what an
    `aclose()` on a generator whose task is unwinding raises — it would escape
    this `finally`, miss every handler in `main()`, and produce a traceback with
    no protocol line at all. And the close is bounded, because it is what tears
    down the SDK's `claude` child: an unbounded one withholds `done` on the
    *happy* path until the adapter's 60 s deadline fires, turning a successful
    correction into a reported timeout.
    """
    close = getattr(messages, "aclose", None)
    if close is None:
        return
    try:
        await asyncio.wait_for(close(), timeout=CLOSE_TIMEOUT_SECONDS)
    except BaseException:  # noqa: BLE001 — cleanup must never outrank what it interrupts
        pass


async def stream_correction(request: dict) -> None:
    options = ClaudeAgentOptions(
        system_prompt=request["system_prompt"],
        model=request["model"],
        tools=[],  # a correction is text-only; no tool may ever run
        max_turns=1,  # stateless single exchange (provider contract)
        include_partial_messages=True,
    )
    forwarded_deltas = 0
    fallback_text: list[str] = []
    messages = query(prompt=request["text"], options=options)
    try:
        async for message in messages:
            if isinstance(message, StreamEvent):
                if is_text_delta(message.event):
                    emit({"type": "text", "text": message.event["delta"]["text"]})
                    forwarded_deltas += 1
            elif isinstance(message, AssistantMessage):
                fallback_text += [
                    block.text
                    for block in message.content
                    if isinstance(block, TextBlock)
                ]
            elif isinstance(message, ResultMessage) and message.is_error:
                raise SidecarFailure(
                    "providerError",
                    f"result {message.subtype}: {message.errors or message.result}",
                )
    finally:
        await close_quietly(messages)
    # The SDK yields both partial deltas and the final AssistantMessage;
    # replaying the latter would double every character, so it is forwarded
    # only when no deltas arrived at all (non-streaming fallback).
    if forwarded_deltas == 0:
        for text in fallback_text:
            emit({"type": "text", "text": text})
    emit({"type": "done"})


def main() -> None:
    try:
        request = validated(json.loads(sys.stdin.readline()))
        asyncio.run(stream_correction(request))
    except SidecarFailure as failure:
        fail(failure.kind, failure.message)
    except (CLINotFoundError, CLIConnectionError) as error:
        # The SDK could not reach its `claude` CLI child: a host-provisioning
        # problem, not a correction failure.
        fail("providerUnavailable", str(error))
    except Exception as error:  # noqa: BLE001 — every failure must become an error line
        fail("providerError", f"{type(error).__name__}: {error}")


if __name__ == "__main__":
    main()
