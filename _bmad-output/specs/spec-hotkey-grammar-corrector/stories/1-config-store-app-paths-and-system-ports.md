---
title: 'Config store, app paths, and system ports'
type: 'feature'
created: '2026-08-07'
status: 'done'
baseline_revision: 'b6b3b9d'
final_revision: 'f2ee154'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/lib/src/domain/config/config_store.dart'
  - '{project-root}/lib/src/domain/config/app_config.dart'
  - '{project-root}/lib/src/domain/clock.dart'
  - '{project-root}/lib/src/domain/logger.dart'
warnings: ['multiple-goals', 'oversized']
---

<intent-contract>

## Intent

**Problem:** `ConfigStore`, `Clock` and `Logger` are ports with no adapters, no type resolves the XDG config/data paths, and nothing enforces AD-14's singleton — so CAP-8's config half cannot work and the daemon has no foundations to be wired onto in story 4. Two deferred-work defects hang off the same gap: the shipped preset's `systemPrompt` does not exist yet, so `RegisterTaggedStreamParser` cannot tell a truncated response from a complete one, and `ClaudeAgentSdkCorrectionProvider` has no timeout value, so a stalled sidecar hangs forever and `CorrectionFailureKind.timeout` is unreachable.

**Approach:** Add five infrastructure types behind the existing ports — `AppPaths`, `JsonConfigStore`, `SystemClock`, `StderrLogger`, `SingleInstanceLock` — plus the shipped default `AppConfig`, whose preset prompt mandates a terminating `END` sentinel that the parser now requires, and whose provider settings carry the correction timeout the adapter now enforces.

## Boundaries & Constraints

**Always:**
- AD-1: every new file lives under `lib/src/infrastructure/`; `lib/src/domain/**` and `lib/src/application/**` are not edited at all. `test/architecture/ad1_import_rule_test.dart` must stay green.
- AD-13: `JsonConfigStore` is the only code that opens the config file. A missing, unreadable, unparseable, or cross-field-invalid file yields the injected defaults plus a non-null `ConfigLoadResult.warning` — `load()` never throws.
- Consistency Conventions: config at `${XDG_CONFIG_HOME:-$HOME/.config}/hotkey-grammar-corrector/config.json`, data at `${XDG_DATA_HOME:-$HOME/.local/share}/hotkey-grammar-corrector/history.sqlite`, both resolved in the one `AppPaths` type from an injected environment map.
- Enums (`HotkeyModifier`) serialize and parse by `.name`, never index.
- `SystemClock` is the only place in `lib/` that may call `DateTime.now()`.
- `Logger` never receives `input_text` or suggestion bodies; `StderrLogger` writes one line per call and timestamps it from an injected `Clock`.
- AD-19 stays intact: the timeout terminal kills the process **group** (existing `_killProcessGroup`, SIGTERM then SIGKILL), and the interpreter/sidecar/timeout values all arrive from config.
- AD-3: the new timeout terminal goes through the adapter's existing single `_emit` funnel — still exactly one terminal event, still no thrown error.
- Every new test runs headless over a temp directory and a fake environment map. No Flutter binding, no real desktop, no real sidecar.

**Block If:**
- Honouring any of the above would require editing a file under `lib/src/domain/` or `lib/src/application/`.
- Making the `END` sentinel mandatory turns out to be unimplementable without weakening another parser guarantee (a real conflict, not merely updating test fixtures).

**Never:**
- No composition root, no `main.dart` wiring, no Riverpod, no window/tray/hotkey adapters, no settings UI — stories 4–10 own those.
- Never bridge `AppConfig.sidecarPath`/`interpreterPath` to `ProviderConfig.settings`; that unbridged-homes decision is story 4's. Put the timeout in exactly ONE home (`ProviderConfig.settings`) so the duplication is not deepened.
- Never derive the installed `flutter_assets` sidecar path — story 11 owns that; the default config uses the repo-relative asset path.
- Never tune the shipped prompt for output quality (SPEC non-goal); it fixes the AD-16 wire format only.
- Never widen a pubspec pin or add a dependency.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Paths, XDG set | `XDG_CONFIG_HOME=/x`, `XDG_DATA_HOME=/y`, `XDG_RUNTIME_DIR=/z` | `/x/hotkey-grammar-corrector/config.json`, `/y/hotkey-grammar-corrector/history.sqlite`, runtime dir `/z/hotkey-grammar-corrector`; `warning` null | No error expected |
| Paths, XDG unset | only `HOME=/home/u` | `~/.config/...` and `~/.local/share/...` per the convention | No error expected |
| Paths, relative XDG value | `XDG_CONFIG_HOME=relative/path` | Ignored per the XDG spec; the `$HOME` default is used | No error expected |
| Paths, no `XDG_RUNTIME_DIR` | unset or empty | Falls back to `${TMPDIR:-/tmp}/hotkey-grammar-corrector-<user>`; `warning` names the fallback | No error expected |
| Paths, no `HOME` and no XDG override | both unset | — | `StateError` naming the missing variable |
| Config, no file | config file absent | Defaults become `current`; `warning` null; the defaults are written to disk so CAP-8's "edit the config" half has a file to edit | A failed seed write yields a `warning`, not a throw |
| Config, valid file | well-formed JSON | Parsed `AppConfig` becomes `current`; `warning` null | No error expected |
| Config, malformed | invalid JSON, wrong field type, or unknown `HotkeyModifier` name | Defaults become `current`; `warning` names the offending field/value | Never throws |
| Config, bad cross-reference | `activePresetId` names no preset, or a preset's `providerId` names no provider | Defaults become `current`; `warning` names the dangling id | Never throws |
| Config, round trip | `write(c)` then a fresh store's `load()` | Returns a config equal field-by-field to `c`, modifiers by `.name` | No error expected |
| Config, write | valid config | File replaced atomically (temp file + rename); `current` updated; `changes` emits once | Directory created if absent |
| Config, invalid write | config failing cross-field validation | Nothing written; `current` and `changes` unchanged | `ArgumentError` naming the dangling id |
| Config, unwritable target | write to a read-only directory (skip with an explicit reason when the test process is root, which ignores mode bits) | Nothing written; `current` unchanged | `FileSystemException` propagates (story 3 handles the controller side) |
| Config, `current` before `load` | fresh store | — | `StateError`, as the port documents |
| Config, two listeners | two subscribers on `changes` | Both receive every write (broadcast) | No error expected |
| Lock, free | no instance holding the address | `acquired`; `showRequests` is live | No error expected |
| Lock, held | a second `SingleInstanceLock` on the same address | Second reports `alreadyRunning`; the holder's `showRequests` emits exactly one event | No error expected |
| Lock, unusable address | bind fails and connect also fails | `unavailable` plus a warning naming both failures; the daemon may still start | Never throws |
| Lock, over-long name | a runtime directory long enough to exceed the 108-byte `sun_path` limit | `unavailable` plus a warning naming the limit; no bind is attempted | Never throws |
| Lock, released | holder `release()`d | A new lock on the same address reports `acquired` | No error expected |
| Timeout | stub sidecar reads the request and then emits nothing, ever | Exactly one `CorrectionFailed(timeout, …)`; the sidecar's grandchild process is dead | Never throws |
| Timeout, not reached | stub completes normally with a 300 ms timeout configured | `CorrectionCompleted`, and waiting past the deadline afterwards yields no further event on the closed stream | No error expected |
| Timeout, unparseable setting | `timeoutMillis: "soon"` | The adapter default is used and the registry logs a warning naming the key | Never throws |
| Parser, complete | `FORMAL: a\nCASUAL: b\nSHORTER: c\nEND` | `CorrectionCompleted` with all three registers | No error expected |
| Parser, truncated final line | `FORMAL: a\nCASUAL: b\nSHORTER: c` (no `END`) | — | `CorrectionFailed(malformedResponse)` naming the missing `END` |
| Parser, truncated sentinel | `…SHORTER: c\nEN` | — | `CorrectionFailed(malformedResponse)` naming the missing `END` |
| Parser, junk after sentinel | `…\nEND\nanything` | — | `CorrectionFailed(malformedResponse)` |

</intent-contract>

## Code Map

- `lib/src/domain/config/config_store.dart`, `app_config.dart`, `provider_config.dart`, `config_load_result.dart` -- the ports and value types being implemented. **Read-only.**
- `lib/src/domain/clock.dart`, `logger.dart` -- the two other ports being implemented. **Read-only.**
- `lib/src/domain/hotkey/hotkey_binding.dart` -- `HotkeyModifier` is the enum the config serializes by `.name`. **Read-only.**
- `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` -- owns `providerId`, `interpreterSettingsKey`, `sidecarSettingsKey`; `_SidecarRun` already has `_killGrace`, `_emit`, `_teardown`, `_killProcessGroup`. The timeout hooks in here.
- `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` -- `_ParseSession._Phase` state machine; `_Phase.afterFinalRegister` and `finish()` are what the sentinel changes.
- `lib/src/infrastructure/correction/provider_registry.dart` -- reads the settings map; the timeout setting is parsed here.
- `test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart` -- ~20 three-line fixtures that all need the `END` line.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart` -- bash-stub harness (`providerForStub`, `_processDied`) the timeout tests reuse; its happy-path stubs need `END`.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- carries its own inline prompt; must switch to the shipped one or it breaks.
- `test/fakes/fake_config_store.dart`, `fake_clock.dart`, `fake_logger.dart` -- no port contract changes, so these stay as they are.
- `test/architecture/ad1_import_rule_test.dart` -- the AD-1 merge gate.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- holds the two entries this story closes.

## Tasks & Acceptance

**Execution:**
- `lib/src/infrastructure/config/app_paths.dart` -- create `AppPaths` with `AppPaths.fromEnvironment(Map<String, String> environment)`, exposing `configFile`, `databaseFile`, `runtimeDirectory`, `warning` -- one place resolves the XDG layout, and injecting the environment is what makes it headless-testable.
- `lib/src/infrastructure/config/json_config_store.dart` -- create `JsonConfigStore implements ConfigStore`, taking `AppPaths` and the default `AppConfig`; JSON codec, cross-field validation, atomic write, broadcast `changes`, plus a `close()` that is not part of the port -- AD-13's single owner.
- `lib/src/infrastructure/system/system_clock.dart` -- create `SystemClock implements Clock` -- the only `DateTime.now()` in `lib/`.
- `lib/src/infrastructure/system/stderr_logger.dart` -- create `StderrLogger implements Logger`, taking a `Clock` and an optional `IOSink` defaulting to `stderr`, writing one JSON line per call -- the injectable sink is the only way to assert on output headlessly.
- `lib/src/infrastructure/system/single_instance_lock.dart` -- create `SingleInstanceLock` (AD-14) over an abstract-namespace unix socket derived from `AppPaths.runtimeDirectory`, exposing `acquire()`, `Stream<void> showRequests`, and `release()` -- see Design Notes for the algorithm.
- `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` -- require a final `END` line: add the sentinel phase, drop the missing-trailing-newline tolerance for the last register, expose `static const String endSentinel = 'END'`, and rewrite the class doc to state exactly which end-of-stream shapes are now trusted -- closes deferred-work item 1.
- `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` -- add a `timeout` constructor parameter (default `Duration(seconds: 60)`) and `static const String timeoutSettingsKey = 'timeoutMillis'`; start a wall-clock `Timer` in `_SidecarRun._start()` that emits `CorrectionFailed(timeout, …)` through `_emit`, and cancel it in `_teardown()` -- closes deferred-work item 2.
- `lib/src/infrastructure/correction/provider_registry.dart` -- read `timeoutSettingsKey` from the settings map, fall back to the adapter default when absent or unparseable, and log a warning in the unparseable case -- keeps one home for the value.
- `lib/src/infrastructure/config/default_app_config.dart` -- create `DefaultAppConfig` with `static AppConfig build()`, `static const String shippedPresetId`, and `static const String shippedSystemPrompt` -- the shipped preset's prompt is a config default (AD-5, CAP-9's seam) and must mandate the AD-16 tags plus the `END` sentinel.
- `test/infrastructure/config/app_paths_test.dart` -- create; cover every Paths row of the matrix.
- `test/infrastructure/config/json_config_store_test.dart` -- create; cover every Config row of the matrix over a temp directory, plus one AD-13 ownership test in the style of the AD-1 gate: no file under `lib/` other than `json_config_store.dart` mentions the config filename.
- `test/infrastructure/config/default_app_config_test.dart` -- create; assert the shipped prompt names all three AD-16 tags in declaration order and mandates `RegisterTaggedStreamParser.endSentinel`, that `DefaultAppConfig.build()` survives the store's own validation and round-trips, and that its provider entry keys match the adapter's `providerId`/settings-key constants -- this is the test the ledger requires before the parser's tolerance may be weakened.
- `test/infrastructure/system/system_clock_test.dart`, `test/infrastructure/system/stderr_logger_test.dart` -- create; clock returns unix millis bracketed by the test's own reading, logger emits one parseable JSON line per call carrying level, message, context and the fake clock's timestamp.
- `test/infrastructure/system/single_instance_lock_test.dart` -- create; cover every Lock row, plus one cross-process case that spawns a second Dart VM on a helper script and asserts it reports `alreadyRunning` while the in-process holder receives the show request.
- `test/support/single_instance_child.dart` -- create; the child entry point the cross-process lock test spawns.
- `test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart` -- update every fixture to the `END`-terminated grammar and add the truncation rows from the matrix.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart` -- append `END` to the happy-path stubs and add a `timeout` group using a stub that reads its request then sleeps, asserting one `CorrectionFailed(timeout, …)` and a dead grandchild pid.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- use `DefaultAppConfig.shippedSystemPrompt` instead of the inline prompt, and add `@Tags(['live'])`; add `dart_test.yaml` declaring the tag -- so the shipped prompt is what the live chain actually proves, and routine runs can exclude it.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- retain the register-tagged-parser truncation and sidecar-timeout headings and historical text; set each `status: done <date>` and add a `resolution:` citing the closing evidence. Leave every other entry untouched.

**Acceptance Criteria:**
- Given a config file written by `write()`, when a fresh `JsonConfigStore` loads it, then `current` equals the written config field-by-field including `HotkeyModifier`s restored from their `.name` strings, and no other file in `lib/` opens that path (CAP-8, AD-13).
- Given `DefaultAppConfig.build()`, when `ProviderRegistry.create` is called with the active preset's `providerId` and that provider's `ProviderConfig`, then a provider is returned and the settings map carries the adapter's `interpreterSettingsKey`, `sidecarSettingsKey` and `timeoutSettingsKey`, so no compiled-in constant stands in for an AD-19 config value.
- Given a provider built by `ProviderRegistry` from a settings map whose `timeoutMillis` is a few hundred milliseconds, and a stub sidecar that reads its request and then emits nothing, when that deadline passes, then the stream yields exactly one `CorrectionFailed(timeout, …)` within the configured window rather than the 60 s default, and the stub's own child process is dead afterwards (AD-19, CAP-13).
- Given the shipped prompt and a response cut off inside its `SHORTER` line, when the stream ends, then the correction fails as `malformedResponse` rather than completing with partial text.
- Given the deferred-work ledger, when the story completes, then the parser-truncation and sidecar-timeout headings remain, each entry has `status: done <date>` and a `resolution:` citing the closing evidence, and all other entries remain unchanged.
- Given the full suite, when `dart analyze`, `dart format --set-exit-if-changed lib test` and `dart test --exclude-tags=live` run, then all three pass, including `test/architecture/ad1_import_rule_test.dart` and the pre-existing application-layer tests.

## Spec Change Log

## Review Triage Log

### 2026-08-07 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 17: (high 1, medium 9, low 7)
- defer: 3: (high 0, medium 3, low 0)
- reject: 4: (high 0, medium 1, low 3)
- addressed_findings:
  - `[high]` `[patch]` A provider setting written as a JSON number instead of a string condemned the whole config file to defaults, silently discarding the user's presets and hotkey on a hand-edit CAP-8 invites — `num`/`bool` scalars are now coerced to their string form.
  - `[medium]` `[patch]` `SingleInstanceLock._onConnection` added to a controller `release()` had closed, and a re-acquire returned `acquired` with a dead notification channel — `release()` (frees the address) is now split from `dispose()` (closes the channel), and both adds are `isClosed`-guarded, as is `JsonConfigStore`'s.
  - `[medium]` `[patch]` `StderrLogger` threw `JsonCyclicError` past its `toEncodable` rescue, so a diagnostic could kill the path reporting a failure — encoding now falls back to a degraded line.
  - `[medium]` `[patch]` A fixed `.tmp` path made overlapping `write()` calls truncate each other and fail on rename — writes are serialized single-flight with per-write temp names and best-effort cleanup.
  - `[medium]` `[patch]` `danglingReference` passed duplicate preset ids and an empty hotkey key though the port calls itself the single validation point — both are now rejected on load and write; empty modifier sets stay legal by decision.
  - `[medium]` `[patch]` `timeoutMillis` accepted values that overflow `Duration` (silently reinstating the unbounded hang AD-19 exists to prevent, or firing instantly) — an upper bound was added and the three failure messages made distinct.
  - `[medium]` `[patch]` The second-launch handshake had no deadline, so a wedged holder hung a launch forever instead of returning a status — `connect`/`flush` are now bounded and resolve to `unavailable`.
  - `[medium]` `[patch]` `dart_test.yaml` declared the `live` tag with `skip: false`, so a bare `dart test` still spawned a nested `claude` CLI — the tag now skips with a reason naming the opt-in command.
  - `[medium]` `[patch]` The wall-clock timeout was only tested against silent stubs, so an idle-rearmed timer passed every test (mutation-verified) — a stub that streams past the deadline now pins it.
  - `[medium]` `[patch]` Neither registry timeout fallback's value was observed, so replacing either with 1 ms stayed green (mutation-verified) — both are now asserted behaviourally.
  - `[low]` `[patch]` `_onConnection` accepted unbounded lines with no read deadline, and the class doc omitted that an abstract name carries no filesystem permissions — both addressed.
  - `[low]` `[patch]` The live smoke ran under the 30 s framework default while the adapter it drives is bounded at 60 s — given a 3-minute timeout.
  - `[low]` `[patch]` A relative XDG override was discarded silently though `AppPaths` carries a `warning` field — now reported.
  - `[low]` `[patch]` The missing-sentinel failure did not name its likeliest cause — it now points at the active preset's system prompt.
  - `[low]` `[patch]` `elapsed < 60 s` against a 300 ms deadline proved nothing, and "a completed run cancels its deadline" could not fail — the bound was tightened and the unprovable claim dropped.
  - `[low]` `[patch]` The AD-13 ownership test asserted source spelling and was already routed around by `AppPaths`, via an import cycle created to satisfy it — `configFileName` moved to `AppPaths`, cycle removed, assertion restated.
  - `[low]` `[patch]` Nothing in the suite showed a real model honouring the sentinel — the verified `claude-sonnet-5` response is now a labelled fixture.


## Design Notes

**`SingleInstanceLock` uses an abstract-namespace socket, measured not assumed.** Verified in this container on 2026-08-07: binding `InternetAddress(name, type: InternetAddressType.unix)` where `name` starts with a NUL byte (`\u0000` in Dart source) succeeds, and a *second process* binding the same name fails with `errorCode 98` (EADDRINUSE). A filesystem socket instead fails with "File exists" even when the previous owner is dead — the classic stale-socket trap — and Dart's `RandomAccessFile.lock` did not hold across processes in this container. The abstract namespace is AD-14's first-named option, needs no unlink, and is reclaimed by the kernel when the holder dies. Because the abstract namespace is flat and per-network-namespace rather than per-directory, the name embeds the resolved runtime directory (`'\u0000' + '<runtimeDirectory>/daemon.sock'`), which both honours AD-14's `$XDG_RUNTIME_DIR` scoping, keeps two users on one machine apart, and gives every test its own name for free.

Do **not** branch on the errno: a same-process rebind fails with a different Dart-level error than a cross-process one, so the algorithm is uniform — try bind; on *any* `SocketException`, connect to the same address and write one `show-panel\n` line (`alreadyRunning`); if that connect also fails, report `unavailable` with both errors in the warning and let the caller start anyway, because refusing to start a desktop daemon is worse than the race it would prevent. That last branch is near-unreachable (EADDRINUSE implies a live listener) but must not throw.

**Why the `END` sentinel and not just a trailing newline.** Both close the ledger's defect, but a trailing newline is whitespace that models and transports routinely drop, so requiring it would fail most real corrections; `END` is content the model emits deliberately, and it also catches a truncation that lands exactly on a line boundary, which a newline rule cannot. The sentinel is defined once as `RegisterTaggedStreamParser.endSentinel` and interpolated into `DefaultAppConfig.shippedSystemPrompt`, so prompt and parser cannot drift; `default_app_config_test.dart` is the drift check and the ledger's required proof.

**Why the timeout lives in `ProviderConfig.settings` and not on `AppConfig`.** AD-15 keeps transport concerns inside the adapter, and `AppConfig` already has one unbridged-duplication problem that story 4 must settle. Adding a second first-class field would deepen it; a settings key is the home the adapter actually reads today.

**The timeout is total wall clock, not idle time** — the ledger names "a wall-clock timeout on a correction". Start the timer when the run starts, not on the last delta.

Shipped prompt shape (wording is deliberately format-only; output-quality tuning is a SPEC non-goal):

```text
Reply with exactly four lines and nothing else:
FORMAL: <the corrected text in a formal register>
CASUAL: <the corrected text in a casual register>
SHORTER: <the shortest correct rewrite>
END
Each tag appears exactly once, in that order, and the final line is exactly END.
Do not add other text, blank lines, quotes, or markdown.
```

**Defaults.** Provider `claude-agent-sdk` with `interpreter: python3` (a bare name, which the adapter's preflight deliberately leaves to `PATH`), `sidecar: assets/sidecar/claude_agent_sdk_sidecar.py` (repo-relative; story 11 owns the installed-asset derivation), `timeoutMillis: 60000`; one preset `default-formal-casual-shorter` on `claude-sonnet-5`; hotkey `Ctrl+Shift+G`, matching the spine's own `<Ctrl><Shift>g` example. `AppConfig.sidecarPath`/`interpreterPath` get the same values so the two homes at least agree until story 4 collapses them.

**Fallback details, so they are not re-invented.** The runtime fallback's `<user>` segment is `USER`, then `LOGNAME`, then the literal `unknown`. The abstract socket name is length-checked against the 108-byte `sun_path` limit before any bind, because an over-long name is a configuration problem to report, not an exception to catch.

**A missing `HOME` throws where a missing `XDG_RUNTIME_DIR` does not.** The XDG spec prescribes a warned fallback for the runtime directory and gives none for `HOME`; silently writing user config into `/tmp` would lose settings invisibly, so that case is loud. AD-13's never-fail-startup rule is about a malformed *file*, not a broken environment.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --set-exit-if-changed lib test` -- expected: no reformatting needed.
- `dart test --exclude-tags=live` -- expected: all pass, including the 138 pre-existing tests and `test/architecture/ad1_import_rule_test.dart`.
- `dart test test/infrastructure/config test/infrastructure/system` -- expected: the new suites pass in isolation, proving they need no Flutter binding.

**Manual checks (if no CLI):**
- The live smoke (`dart test --tags=live`) exercises the real `claude` CLI and is the only check that a real model honours the `END` sentinel. It is worth running once after the prompt change, but it spawns a nested `claude` process — under a bmad-loop run that nested CLI has been observed to terminate the dev session, so run it deliberately and separately, never as part of the routine gate.
- Confirm by inspection that `lib/src/infrastructure/config/json_config_store.dart` is the only file in `lib/` that references the config filename, and `lib/src/infrastructure/system/system_clock.dart` the only one that calls `DateTime.now()`.

## Auto Run Result

Status: done

### What was implemented

The five infrastructure adapters the daemon needs before anything can be wired — `AppPaths`, `JsonConfigStore`, `SystemClock`, `StderrLogger`, `SingleInstanceLock` — behind the domain ports that already existed, plus the shipped default `AppConfig`. Two deferred-work defects were closed along the way: the shipped preset's prompt now mandates a terminating `END` sentinel that `RegisterTaggedStreamParser` enforces, so a truncated response can no longer complete as a success with partial text; and `ClaudeAgentSdkCorrectionProvider` now enforces a config-supplied wall-clock timeout, killing the process group, so `CorrectionFailureKind.timeout` is finally produced.

### Files changed

**New — `lib/`**
- `src/infrastructure/config/app_paths.dart` — resolves config, data and runtime paths from an injected environment; XDG overrides, relative-value rejection, `TMPDIR` runtime fallback, and a joined warning for every degraded resolution.
- `src/infrastructure/config/json_config_store.dart` — AD-13's single owner: JSON codec, cross-field validation, serialized atomic writes, broadcast `changes`; `load()` never throws.
- `src/infrastructure/config/default_app_config.dart` — the shipped provider, preset, prompt and hotkey; the prompt interpolates the parser's own sentinel constant so the two cannot drift.
- `src/infrastructure/system/system_clock.dart` — the only `DateTime.now()` in `lib/`.
- `src/infrastructure/system/stderr_logger.dart` — one JSON line per call, `Clock`-sourced timestamp, injectable sink, and it never throws.
- `src/infrastructure/system/single_instance_lock.dart` — AD-14 over an abstract-namespace socket, with `acquire`/`showRequests`/`release`/`dispose`.

**Modified — `lib/`**
- `register_tagged_stream_parser.dart` — `endSentinel`, two new phases, the missing-trailing-newline tolerance removed, contract doc rewritten to state which endings are trusted.
- `claude_agent_sdk_correction_provider.dart` — a total wall-clock deadline armed at run start, terminating through the existing single `_emit` funnel and tearing down the process group.
- `provider_registry.dart` — parses `timeoutMillis` from the settings map with bounds and distinct warnings.
- `drift_correction_repository.dart` — formatter-only (see residual artifacts).

**New/modified — `test/`** — suites for all five new types, the fd-exhaustion and cross-process lock children under `test/support/`, the parser fixtures moved to the `END` grammar plus truncation rows, a timeout group for the adapter, timeout-setting rows for the registry, and `dart_test.yaml` declaring a `live` tag that now skips by default.

**Other** — `deferred-work.md`: the two named entries removed, three new ones added.

### Review findings

17 patches applied (1 high, 9 medium, 7 low), 3 deferred, 4 rejected, 0 intent gaps, 0 spec defects. Full detail in the Review Triage Log above. Ten findings were confirmed by reviewers executing probe code, and five patches were mutation-verified — each new guard was shown to fail on the regression it targets before being kept.

Rejected: a lower bound on `timeoutMillis` (the tests legitimately configure 250–300 ms deadlines); the shipped `python3` / repo-relative sidecar defaults (already tracked by story 11's ledger entry); AD-19 runtime value provenance (needs the composition root, story 4); and the `dart format` churn in the persistence files (those files were unformatted at baseline, so the story's own format gate could not pass without touching them).

Follow-up review recommended: **true** — one patched finding was high severity (patched counts: high 1, medium 9, low 7; score 3×9 + 7 = 34).

### Verification

- `dart analyze` — no issues.
- `dart format --output=none --set-exit-if-changed lib test` — 0 changed.
- `dart test --exclude-tags=live` — 215 tests, 214 passed, 1 skipped, 0 failed (baseline was 138).
- `dart test test/infrastructure/config test/infrastructure/system` — passes standalone, so the new suites need no Flutter binding.
- Matrix audit — all 27 I/O matrix rows are covered by tests that ran and passed. The single remaining skip is not a matrix row: it is an extra test for the handshake deadline against a holder that binds and then stops accepting, which Dart cannot stage because `ServerSocket.bind` already calls `listen(2)`. Its reason is recorded in the test.
- **Real-model check.** Rather than leave the sentinel decision resting on string assertions, I drove the real Python sidecar, the real `claude_agent_sdk` and the real `claude` CLI with the shipped prompt on `claude-sonnet-5`. It returned exactly `FORMAL: … / CASUAL: … / SHORTER: … / END`, with no trailing newline after `END`. That response is now a labelled regression fixture. It was run outside the repo cwd with the bmad-loop environment stripped, so the nested CLI could not claim this session's task identity.

### Residual risks

1. **The `END` sentinel is now load-bearing for every correction.** One real-model run validates it; a model that omits the line fails the correction as `malformedResponse`. The failure message names the preset prompt so it is diagnosable, and the parser cannot be defended further without coupling the config store to one adapter's wire format, which AD-16 forbids.
2. **The spine's AD-16 still says "exactly three lines".** The shipped format is now four. Recorded in the ledger rather than hand-edited into the spine; a future reader deriving a prompt from the spine alone would write one that fails.
3. **Timing-sensitive tests.** The timeout rows use 250–400 ms deadlines against spawned bash stubs. Stable across many runs here, but a heavily loaded machine could flake them.
4. **One lock test flaked exactly once**, early on, under heavy concurrent load, and did not reproduce in 20 subsequent runs. Rather than guess at the cause, the acquire assertions now surface the lock's own warning, so a recurrence will name itself instead of failing as a bare status mismatch.
5. **`AppConfig` still has two unbridged homes** for the sidecar and interpreter paths. The defaults keep them in agreement; story 4 owns collapsing them.
6. **Nothing consumes any of this yet** — `main.dart` is still a stub, so the config→registry→adapter path is exercised only by tests until story 4.

### Residual artifacts

`.bmad-loop/bmad_loop_hook.py` is modified in the working tree. It is not part of this change — it was not touched by this run — so it was deliberately left uncommitted and un-ignored.
