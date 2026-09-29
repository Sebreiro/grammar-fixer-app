"""A stub standing in for the `claude` CLI that `claude_agent_sdk` spawns.

The subject under test is the Python sidecar, and two of its branches — an
error `result` message, and the zero-delta `AssistantMessage` fallback — are
only reachable through whatever the SDK's child process says. Reaching them
against the real CLI would need a network, a model, and a nested `claude`
process that has been observed terminating the surrounding session. This
speaks the CLI's side of the wire instead.

It does three things and no more:

* answers `-v` / `--version`, for a caller that did not set
  `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK`;
* answers the SDK's `initialize` control request, which the SDK sends and then
  blocks on before it will send any prompt at all;
* replays the NDJSON fixture named by `FAKE_CLAUDE_FIXTURE` once the prompt
  arrives, then exits 0.

`FAKE_CLAUDE_LOG`, when set, receives one line per event. It is what proves the
SDK spawned *this* file rather than reaching a real CLI — an assertion the
tests could otherwise only make by trusting `PATH`.
"""

import json
import os
import sys

VERSION_FLAGS = ("-v", "--version")

# Enough of an initialize response to unblock the SDK. The CLI sends much more;
# the SDK reads none of it on this path, and inventing fields would be a claim
# about a protocol this stub does not implement.
INITIALIZE_RESPONSE = {"commands": [], "output_style": "default"}


def log(event: str) -> None:
    path = os.environ.get("FAKE_CLAUDE_LOG")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(event + "\n")


def emit(message: dict) -> None:
    print(json.dumps(message), flush=True)


def replay_fixture() -> None:
    with open(os.environ["FAKE_CLAUDE_FIXTURE"], encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                print(line.strip(), flush=True)


def main() -> int:
    log("spawned as: " + os.environ.get("FAKE_CLAUDE_INVOKED_AS", "<unknown>"))
    log("argv: " + json.dumps(sys.argv))
    if any(flag in VERSION_FLAGS for flag in sys.argv[1:]):
        print("2.0.0 (Claude Code)", flush=True)
        return 0

    seen: list[str] = []
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
        except ValueError:
            log("unparseable input line")
            seen.append("<unparseable>")
            continue
        kind = str(message.get("type"))
        seen.append(kind)
        log("received: " + kind)
        if kind == "control_request":
            emit(
                {
                    "type": "control_response",
                    "response": {
                        "subtype": "success",
                        "request_id": message.get("request_id"),
                        "response": INITIALIZE_RESPONSE,
                    },
                }
            )
            continue
        if kind == "user":
            replay_fixture()
            log("replayed: " + os.environ["FAKE_CLAUDE_FIXTURE"])
            return 0

    # Reaching here means stdin closed without a prompt ever arriving, so no
    # fixture was replayed and the sidecar saw an empty stream. Exiting 0 would
    # let the two rows that assert "no deltas were forwarded" pass on nothing —
    # which is exactly what an SDK upgrade that renamed the prompt message
    # would produce. The message types actually seen are the diagnostic.
    diagnostic = (
        "fake claude CLI: stdin closed with no prompt message; "
        f"saw {seen or ['<nothing>']}"
    )
    log(diagnostic)
    print(diagnostic, file=sys.stderr, flush=True)
    return 3


if __name__ == "__main__":
    sys.exit(main())
