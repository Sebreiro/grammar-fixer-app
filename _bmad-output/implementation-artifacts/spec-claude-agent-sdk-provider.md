---
title: 'Claude Agent SDK provider: Dart adapter, sidecar protocol, Python sidecar'
type: 'feature'
created: '2026-08-07'
status: 'done'
review_loop_iteration: 0
baseline_commit: '0c397f9be826857d345cafc907772c4aba3aa61f'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Domain ring, controllers, and `RegisterTaggedStreamParser` exist, but no real `CorrectionProvider` — the shipped default (AD-19) and the id→factory registry (AD-15) are missing, so no correction can run.

**Approach:** Build the AD-19 chain: a Python sidecar (transport shim over `claude_agent_sdk`, pinned `0.2.132`), a Dart adapter spawning one sidecar **per correction** in its own **process group**, and `ProviderRegistry` (id→factory lookup).

## Boundaries & Constraints

**Always:**
- AD-3: zero+ `SuggestionDelta`, exactly one terminal, then close; `correct()` never throws.
- AD-4: single-subscription; cancel tears down the whole process group; no event after cancel.
- AD-19 protocol verbatim: one JSON line `{"text","model","system_prompt"}` to stdin, then close stdin; sidecar streams NDJSON `{"type":"text"|"done"|"error"...}`. `done` ≠ success — the parser decides.
- Kill the process **group** (spawn via `setsid`; SIGTERM → short grace → SIGKILL; reap).
- Failure translation in the adapter: spawn failure → `providerUnavailable`; non-zero exit, bad NDJSON line, or EOF without terminal → `providerError`; sidecar `error.kind` mapped by name (unknown → `providerError`).
- Sidecar = transport shim only: raw model text verbatim; no register parsing, prompt assembly, or retry. Failed `claude_agent_sdk` import → `error` line `providerUnavailable` naming the package.
- AD-15: interpreter+sidecar paths only from `ProviderConfig.settings`; no process/SDK detail escapes the adapter directory; registry is a map lookup, no switch.
- Sidecar stderr → `Logger` port; never log input text or suggestions.
- Reuse `RegisterTaggedStreamParser`; pin `claude-agent-sdk==0.2.132` in `requirements.txt`; update spine Stack table to that version.

**Ask First:**
- Any change to the AD-2 port, event shapes, or the AD-19 wire protocol; new pub dependencies.

**Never:**
- UI, hotkey/tray/panel adapters, drift, config store, `main.dart` wiring.
- Fallback/cascade, session reuse, retry policy.
- Timeout enforcement (`timeout` kind) — deferred to the config-store story that supplies the value.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | stub emits tagged text + `done` | deltas then `CorrectionCompleted` (3 registers), close | N/A |
| Malformed NDJSON line | non-JSON / wrong-shape line | one `CorrectionFailed(providerError)` | teardown, reap |
| Sidecar error line | `{"type":"error","kind":"providerUnavailable",...}` | `CorrectionFailed(providerUnavailable)` | teardown |
| Non-zero exit, no terminal | stub exits 3 silently | `CorrectionFailed(providerError)` naming exit code | reap |
| Spawn failure | nonexistent interpreter | `CorrectionFailed(providerUnavailable)` | no throw |
| Cancel mid-stream | cancel after first delta | zero events after cancel | group SIGTERM→SIGKILL |
| Grandchild kill | stub spawns `sleep` grandchild; cancel | grandchild dead (group kill proven) | `kill -0` fails |
| Untagged model text | garbage text + `done` | `CorrectionFailed(malformedResponse)` via parser | teardown |
| Live smoke | real sidecar + `claude` CLI | `CorrectionCompleted`, 3 non-empty suggestions | SKIP when deps absent |

</frozen-after-approval>

## Code Map

- `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` -- existing, tested; `Stream<String>` in, AD-3 events out. Feed it, don't touch it.
- `lib/src/domain/correction/*` -- AD-2 port and types, frozen.
- `lib/src/domain/config/provider_config.dart` -- opaque `settings` map; adapter reads `interpreter` + `sidecar` keys.
- `lib/src/domain/logger.dart` -- Logger port for stderr forwarding.
- `test/fakes/fake_correction_provider.dart` -- existing port fake (AD-15 fake requirement satisfied).
- `.venv-sidecar/` -- uv venv with `claude-agent-sdk==0.2.132`, used by the live smoke test.

## Tasks & Acceptance

**Execution:**
- [x] `lib/src/infrastructure/correction/claude_agent_sdk/sidecar_protocol.dart` -- `SidecarRequest` (stdin line) + sealed `SidecarLine` (`text`/`done`/`error` with kind mapping) with strict `parse` -- AD-19 shapes in one place.
- [x] `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` -- implements `CorrectionProvider`; ctor: `interpreterPath`, `sidecarPath`, `Logger`; spawn `setsid <interpreter> <sidecar>`, write request, close stdin, decode NDJSON, route `text` into the parser, enforce one-terminal/never-throw, group-kill on cancel.
- [x] `lib/src/infrastructure/correction/provider_registry.dart` -- `ProviderRegistry` over `Map<String, CorrectionProvider Function(ProviderConfig)>` with the `claude-agent-sdk` entry; unknown id → null -- AD-15.
- [x] `assets/sidecar/claude_agent_sdk_sidecar.py` -- asyncio shim: read stdin line, `query(prompt, ClaudeAgentOptions(system_prompt, model, tools=[], max_turns=1, include_partial_messages=True))`, forward `text_delta` events verbatim (fallback: `AssistantMessage` text only if zero deltas arrived), then `done`; `CLINotFoundError`/`CLIConnectionError`/`ImportError` → `providerUnavailable`, else → `providerError`; non-zero exit on error.
- [x] `assets/sidecar/requirements.txt` -- `claude-agent-sdk==0.2.132`; register `assets/sidecar/` in `pubspec.yaml`.
- [x] `ARCHITECTURE-SPINE.md` Stack table -- pin `claude_agent_sdk` row to `0.2.132`.
- [x] `test/infrastructure/correction/claude_agent_sdk/sidecar_protocol_test.dart` -- line-shape units incl. unknown kind → `providerError`.
- [x] `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart` -- all matrix rows except live smoke, via bash stub sidecars in a temp dir (interpreter=`/bin/bash`).
- [x] `test/infrastructure/correction/provider_registry_test.dart` -- known id → instance; unknown → null.
- [x] `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- one CAP-5/CAP-9 smoke vs `.venv-sidecar/bin/python3`; `skip` when interpreter, SDK import, or `claude` CLI unavailable.

**Acceptance Criteria:**
- Given each stub scenario, when `correct()` runs, then exactly one terminal event, no throw, event kinds per matrix (CAP ids in test names).
- Given the grandchild stub, when the subscription is cancelled, then the grandchild PID no longer exists (AD-19 group kill).
- Given `flutter analyze` / `flutter test`, then clean / all green (78 pre-existing + new).
- Given real deps locally, the live smoke completes with three non-empty suggestions; without them it reports skipped.

## Design Notes

- **Process group without ffi:** `Process.start('setsid', [interpreter, sidecar])` — `setsid` execs in place (child isn't a group leader), so the returned PID is the sidecar and group leader. Teardown: `Process.killPid(-pid, sigterm)` (POSIX kill accepts negative pgid), ~2s grace on `exitCode`, then sigkill. The grandchild test proves it.
- **One-terminal funnel:** error lines, exit-code failures, and spawn failures bypass the parser and race against the parser's own terminal — a single `_terminated` guard mirrors the parser's internal pattern.
- **Delta duplication guard:** with `include_partial_messages=True` the SDK yields both `StreamEvent` deltas and a final `AssistantMessage`; forward deltas, use `AssistantMessage` text only when zero deltas arrived.

## Spec Change Log

## Verification

**Commands:**
- `export PATH="$PATH:/home/vscode/flutter/bin" && flutter analyze` -- expected: No issues found
- `flutter test` -- expected: all green, ≥ 78 + new
- `flutter test test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- expected: passes locally (skips where deps missing)

## Suggested Review Order

**The port contract — start here**

- The whole design in one screen: stateless provider, one `_SidecarRun` per correction.
  [`claude_agent_sdk_correction_provider.dart:23`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L23)

- The AD-3 funnel: first terminal wins, everything after it drops.
  [`claude_agent_sdk_correction_provider.dart:333`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L333)

**Process-group teardown (AD-4, AD-19 — the highest-risk code)**

- Negative-pid group kill, SIGTERM then SIGKILL, with a pid-reuse guard.
  [`claude_agent_sdk_correction_provider.dart:368`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L368)

- Proof the grandchild dies even when the sidecar traps SIGTERM.
  [`provider_test.dart:300`](../../test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart#L300)

- Cancel inside the spawn gap must not leak a group nobody holds yet.
  [`provider_test.dart:330`](../../test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart#L330)

**The wire protocol (AD-19)**

- Strict parse: an unknown dialect is a transport fault, never guess-repaired.
  [`sidecar_protocol.dart:36`](../../lib/src/infrastructure/correction/claude_agent_sdk/sidecar_protocol.dart#L36)

- Unknown error kinds degrade to `providerError` so a newer sidecar cannot brick the daemon.
  [`sidecar_protocol.dart:71`](../../lib/src/infrastructure/correction/claude_agent_sdk/sidecar_protocol.dart#L71)

- `done` closes the parser input; the parser — not the sidecar — rules on success.
  [`claude_agent_sdk_correction_provider.dart:256`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L256)

**Failure translation (AD-15, CAP-13)**

- EOF without a terminal, bounded so a live-but-silent sidecar cannot hang a correction.
  [`claude_agent_sdk_correction_provider.dart:291`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L291)

- Unset setting, wrong path, and bare PATH command are three different user mistakes.
  [`claude_agent_sdk_correction_provider.dart:183`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L183)

- stderr forwarded for diagnosis; the log is sensitive, not guaranteed clean.
  [`claude_agent_sdk_correction_provider.dart:222`](../../lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart#L222)

**The sidecar as a transport shim**

- Import guard names the missing package so the panel error is actionable.
  [`claude_agent_sdk_sidecar.py:39`](../../assets/sidecar/claude_agent_sdk_sidecar.py#L39)

- Request validated in both directions, so a serialization regression names its field.
  [`claude_agent_sdk_sidecar.py:50`](../../assets/sidecar/claude_agent_sdk_sidecar.py#L50)

- Deltas forwarded verbatim; the final message replays only when no delta arrived.
  [`claude_agent_sdk_sidecar.py:89`](../../assets/sidecar/claude_agent_sdk_sidecar.py#L89)

**Provider selection (AD-15) and peripherals**

- A map lookup with the id and settings keys owned by the adapter — no switch.
  [`provider_registry.dart:17`](../../lib/src/infrastructure/correction/provider_registry.dart#L17)

- The real sidecar's import guard, verified without needing the `claude` CLI.
  [`live_test.dart:68`](../../test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart#L68)

- One process per correction: stray lines after `done` ignored, sequential calls succeed.
  [`provider_test.dart:200`](../../test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart#L200)

- Stack table now pins the SDK version the sidecar was built against.
  [`ARCHITECTURE-SPINE.md:406`](../planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md#L406)
