---
title: 'Packaging and sidecar provisioning'
type: 'feature'
created: '2026-08-11'
status: 'done'
baseline_revision: 'ec36968'
final_revision: 'fea4d7a'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
warnings: [multiple-goals, oversized]
---

<intent-contract>

## Intent

**Problem:** Three things the daemon depends on exist nowhere on disk. AD-11's app-id desktop entry is a *hard requirement of the Wayland hotkey working* — GNOME discards the bind without it — and it has never been written; the Wayland adapter registers `com.divertedriver.HotkeyGrammarCorrector` while the GTK/prgname id in `linux/CMakeLists.txt` is a different string (`com.divertedriver.hotkey_grammar_corrector`), so even a shipped file would not match what the compositor sees. AD-14's autostart entry does not exist either. And the AD-19 sidecar is unreproducible: nothing creates the pinned `.venv-sidecar`, no code derives the sidecar path inside an installed `flutter_assets` bundle (the default config is repo-relative), the `claude_agent_sdk` pin is duplicated between the spine's Stack table and `requirements.txt` with no drift check, the live smoke skips on every machine without saying so, and the sidecar's two non-happy branches (`ResultMessage.is_error`, zero-delta `AssistantMessage` fallback) are executed by no test.

**Approach:** Ship both `.desktop` entries plus an installer that puts them in the two XDG destinations, align the three spellings of the app id, derive the installed-bundle sidecar path in one pure function, add a provisioning script that builds the pinned venv, pin the pin with a drift test, make every skip print why it skipped and the command that enables it, and build the fake-`claude`-CLI harness that makes the sidecar's error branches testable without a network or a real model.

## Boundaries & Constraints

**Always:**
- The app-id file is `linux/packaging/com.divertedriver.HotkeyGrammarCorrector.desktop` (spine Structural Seed). Its basename minus `.desktop` equals `WaylandPortalGlobalHotkey.applicationId` **and** `APPLICATION_ID` in `linux/CMakeLists.txt`. One string, three sites, pinned by a test.
- The two destinations are separate and both are XDG-derived: the app-id entry goes to `${XDG_DATA_HOME:-$HOME/.local/share}/applications/`, the autostart entry to `${XDG_CONFIG_HOME:-$HOME/.config}/autostart/`.
- The autostart entry's `Exec` is the same command as the app-id entry's, so an autostarted daemon plus a manual launch collide on AD-14's singleton lock instead of becoming two instances.
- The sidecar stays a transport shim (AD-19): no register parsing, no prompt assembly, no retry policy. The only sidecar edit sanctioned here is how a failure *exits*.
- One home for the AD-19 paths: `ProviderConfig.settings`. The new derivation may not name `interpreterSettingsKey`/`sidecarSettingsKey` or their literals — `test/architecture/ad19_path_home_test.dart`'s allowlist must still pass unedited.
- Every test that cannot run here prints, in the run output, what it skipped, why, and the exact command that makes it run.

**Block If:**
- The spine's Stack table and `assets/sidecar/requirements.txt` already disagree on the `claude_agent_sdk` version on the tree as found (both read `0.2.132` at planning time). Reconciling them means editing the spine or moving the pin — a human decision, not a drift-check bug.
- Aligning `APPLICATION_ID` breaks `flutter build linux --debug` for a reason other than a stale build directory.

**Never:**
- Never run the `live`-tagged smoke in this session, and never weaken `dart_test.yaml`'s `live` skip. It spawns a real nested `claude` CLI, which has been observed terminating the surrounding session, and its result is not needed by any acceptance criterion here.
- Never choose or invent a packaging format (deb / Flatpak / AppImage), and never write a Flatpak manifest. The spine defers the format, and Flatpak sandboxing changes the AD-11 handshake — a sandboxed app must **not** call `Registry.Register`. Record it in the completion notes; do not act on it.
- Never hand-edit `ARCHITECTURE-SPINE.md` or `SPEC.md`; drift goes to the deferred-work ledger, as stories 1, 2 and 4 did.
- Never let a test install packages, reach the network, or mutate `.venv-sidecar`.
- Never fake a pass. A row that cannot run skips with a printed reason; a gate that cannot find what it parses fails rather than passing vacuously.
- Never add a CI job beyond `dart analyze` and `dart test`; no deployment pipeline (spine Operational envelope: no CI deployment target in MVP).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Installed build | `resolvedExecutable=/opt/hgc/hotkey_grammar_corrector`, `data/flutter_assets/assets/sidecar/claude_agent_sdk_sidecar.py` exists beside it | Derived path is that absolute bundle path | No error expected |
| Repo run | No `data/flutter_assets` beside the executable | Derived path is the repo-relative `assets/sidecar/claude_agent_sdk_sidecar.py` | No error expected |
| Pin drift | `requirements.txt` pins `0.2.131`, spine Stack table says `0.2.132` | Drift test fails, message quotes both values and both file paths | Test failure |
| Gate blinded | Spine Stack table has no parseable `claude_agent_sdk` row | Drift test fails naming "row not found" | Never passes vacuously |
| Install run | `tool/install_desktop_entries.sh --exec /opt/hgc/hotkey_grammar_corrector` with XDG vars pointed at a temp tree | Both entries written to their two destinations with that `Exec`; icon installed; both paths printed; rerun is idempotent, exit 0 | Missing source file → non-zero exit naming it |
| Sidecar error branch | Fake CLI replays a `result` line with `is_error: true` | stdout is exactly one `{"type":"error","kind":"providerError",…}` naming the subtype; exit 1; **no traceback on stderr** | The failure *is* the output |
| Sidecar fallback branch | Fake CLI replays an `assistant` message and no `stream_event` | One `{"type":"text"}` carrying the assistant text, then `{"type":"done"}`; exit 0 | No error expected |
| Streaming control | Fake CLI replays two `stream_event` text deltas plus the same text as an `assistant` message | One `text` line per delta in order, then `done` — the assistant message is **not** replayed | No error expected |
| Unprovisioned host | No `.venv-sidecar` | Harness rows skip; run output names the rows, the reason, and `tool/provision_sidecar.sh` | Never a silent skip, never a fake pass |

</intent-contract>

## Code Map

- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:124` -- `applicationId`, the reverse-DNS id AD-11 fixes; the desktop file's basename must equal it.
- `linux/CMakeLists.txt:10` -- `APPLICATION_ID`, today `com.divertedriver.hotkey_grammar_corrector`; feeds `g_set_prgname` and the GTK application id in `linux/runner/my_application.cc:140`.
- `lib/src/infrastructure/config/default_app_config.dart:42-47` -- the shipped `interpreter` / `sidecar` settings; `sidecarPath` is the repo-relative constant this story replaces with a derivation.
- `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` -- reads both paths from settings; unchanged here.
- `assets/sidecar/claude_agent_sdk_sidecar.py:81-92` -- the two untested branches; `fail()` at :21 is what exits.
- `assets/sidecar/requirements.txt` -- `claude-agent-sdk==0.2.132`, one half of the duplicated pin; the spine's Stack table row is the other.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- the silently-skipping live smoke.
- `test/architecture/ad19_path_home_test.dart` -- the allowlist the derivation must not disturb.
- `dart_test.yaml` -- the `live` tag skip; keep it.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- the two entries this story closes in place, retaining their headings and historical text.

## Tasks & Acceptance

**Execution:**
- `linux/packaging/com.divertedriver.HotkeyGrammarCorrector.desktop` -- new; `[Desktop Entry]`, `Type=Application`, `Name`, `Comment`, `Exec=hotkey_grammar_corrector` (bare, overridable at install), `Icon=com.divertedriver.HotkeyGrammarCorrector`, `Terminal=false`, `Categories=Utility;TextTools;`, `StartupWMClass=com.divertedriver.HotkeyGrammarCorrector` -- AD-11's hard requirement.
- `linux/packaging/autostart/com.divertedriver.HotkeyGrammarCorrector.desktop` -- new; same `Exec`, plus `X-GNOME-Autostart-enabled=true` and its own `Comment` -- AD-14's login start, separate destination from the entry above.
- `linux/CMakeLists.txt` -- set `APPLICATION_ID` to `com.divertedriver.HotkeyGrammarCorrector` -- so prgname, the GTK id, the registered portal id and the file basename are one string.
- `tool/install_desktop_entries.sh` -- new; installs both entries into their XDG destinations and the 32x32 tray PNG into `hicolor/32x32/apps/<app-id>.png`; `--exec <path>` rewrites `Exec=`; prints every path written; runs `update-desktop-database` only if present.
- `tool/provision_sidecar.sh` -- new; creates `.venv-sidecar` and installs `assets/sidecar/requirements.txt` into it, then verifies the installed version equals the pin and prints the interpreter path plus the follow-on commands. Interpreters with no `ensurepip` (this container) get `--without-pip` plus a printed, network-dependent `get-pip.py` bootstrap rather than a mystery failure.
- `lib/src/infrastructure/correction/claude_agent_sdk/sidecar_asset_path.dart` -- new; pure resolution of the sidecar path from an executable path and an existence probe, both injected -- makes the installed-bundle row testable headlessly.
- `lib/src/infrastructure/config/default_app_config.dart` -- seed the `sidecar` setting from that derivation instead of the bare repo-relative constant.
- `assets/sidecar/claude_agent_sdk_sidecar.py` -- raise a private failure type inside the async generator and let `main()` emit-and-exit, so an `is_error` result no longer exits from inside `async for` and dumps `RuntimeError: aclose(): asynchronous generator is already running` into the daemon log.
- `test/support/fake_claude_cli.dart` + `test/support/fake_claude_cli/claude.py` + `test/support/fake_claude_cli/fixtures/*.ndjson` -- new; the harness: a stub `claude` on `PATH`, a `claude_agent_sdk` view with `_bundled` omitted so SDK discovery falls through to `PATH`, and fixtures for the three rows.
- `test/infrastructure/correction/claude_agent_sdk/sidecar_fake_cli_test.dart` -- new; the two branch rows, the streaming control row, the stub-was-really-spawned assertion and the skip-banner row.
- `test/architecture/desktop_entries_test.dart` -- new; desktop-file-validate-style checks over both files plus the three-site id agreement, the AD-14 `Exec` pairing, and a behavioural run of the installer into a temp XDG tree.
- `test/architecture/sidecar_pin_drift_test.dart` -- new; a pure parser for each side's pin (unit-tested on synthetic text for found and not-found) and the row comparing the two real files.
- `test/infrastructure/correction/claude_agent_sdk/sidecar_asset_path_test.dart` -- new; the derivation's two rows.
- `test/infrastructure/config/default_app_config_test.dart` -- update the sidecar-path row for the derived value.
- `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart` -- print the loud banner (row, reason, `dart test --tags=live --run-skipped …`) for each skipped row.
- `.github/workflows/ci.yml` -- new; checkout, Flutter 3.44.8, `flutter pub get`, `dart analyze`, the scoped `dart test`. Nothing else. Comment it as never-executed-here and note DW-46's flakes.
- `README.md` -- a Developing section: provision, install entries, run the harness, run the live smoke.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- retain the two `spec-claude-agent-sdk-provider.md` headings and historical text; set each `status: done <date>` and add a `resolution:` citing the closing evidence. Append new `### DW-…` entries for what this story leaves open.

**Acceptance Criteria:**
- Given a fresh checkout, when `tool/provision_sidecar.sh` runs twice, then both runs exit 0 and print the interpreter path and the resolved `claude_agent_sdk` version equal to the `requirements.txt` pin.
- Given the provisioned venv, when the scoped `dart test` runs, then the fake-CLI rows **pass** (not skip) and the run output shows no new skips against the 690 passed / 2 skipped baseline.
- Given a fake-CLI row has run, when it asserts which binary the SDK spawned, then the stub's own log file exists and is non-empty — proving no real `claude` was reached.
- Given `WaylandPortalGlobalHotkey.applicationId`, when the desktop-entry test reads the packaging file's basename and `APPLICATION_ID` from `linux/CMakeLists.txt`, then all three are the identical reverse-DNS string.
- Given both `.desktop` files, when the validity checks run, then each has `[Desktop Entry]` as its first non-comment line, `Type=Application`, a non-empty `Name` and `Exec`, no duplicate keys, no whitespace around `=`, a boolean `Terminal`, and a `;`-terminated `Categories`.
- Given `tool/install_desktop_entries.sh` run against a temp `XDG_DATA_HOME`/`XDG_CONFIG_HOME` with `--exec /tmp/x/bin`, when it exits, then `applications/com.divertedriver.HotkeyGrammarCorrector.desktop` and `autostart/com.divertedriver.HotkeyGrammarCorrector.desktop` both exist with `Exec=/tmp/x/bin`, and a second run leaves the same state and exits 0.
- Given the ledger, when the story completes, then the two `spec-claude-agent-sdk-provider.md` headings remain, each entry has `status: done <date>` and a `resolution:` citing the closing evidence, and every other entry is unchanged.
- Given the completion notes, when they are read, then they state the packaging format is still undecided and that a Flatpak build must not call `Registry.Register`.

## Spec Change Log

## Review Triage Log

### 2026-08-11 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 17: (high 0, medium 7, low 10)
- defer: 2: (high 0, medium 1, low 1)
- reject: 2: (high 0, medium 0, low 2)
- addressed_findings:
  - `[medium]` `[patch]` The shipped `interpreterPath` stayed the bare `python3` while the story provisioned a venv nothing pointed at — a developer who completed README step 1 still got `providerUnavailable` on every correction. Interpreter derivation added alongside the script derivation, with the same injected-probe shape; README and the provisioning script's closing output now state the relationship.
  - `[medium]` `[patch]` The new `finally: await messages.aclose()` could replace the in-flight `SidecarFailure` with the close error — reporting `providerError: RuntimeError: aclose()…` while the empty-stderr row still passed. Replaced with a `close_quietly()` that tolerates a missing `aclose` and suppresses anything it raises.
  - `[medium]` `[patch]` `DefaultAppConfig.sidecarPath()` hard-wired `Platform.resolvedExecutable` and `File.existsSync`, so the installed-bundle branch was unreachable from any row and the root-path row asserted against the constant under test. Injectable seams with host defaults added, plus a row that builds a real bundle tree on disk and drives the real `existsSync`; the third arm now returns the absolute bundle candidate rather than a CWD-relative path.
  - `[medium]` `[patch]` Nothing pinned `- assets/sidecar/` under `flutter: assets:`, so deleting it would silently un-bundle the sidecar with the suite green. The tray side's declared-assets helper lifted into `test/support` and a row added for the sidecar directory.
  - `[medium]` `[patch]` The CI gate skipped the verification the story exists to add (no `.venv-sidecar` on a runner) and was weaker than AGENTS.md §6's rule. Provisioning step added before `dart test`, `--fatal-infos`, `timeout-minutes`, a cancel-in-progress concurrency group, `push` restricted to `main`, `test/composition/` named in the exclusions comment, and the workflow's Flutter version brought under the drift test.
  - `[medium]` `[patch]` The live smoke's "loud" banners were `skip:` strings on a `live`-tagged file and reached no run output: the routine command excludes the tag, `--tags=live` prints only the suite reason, and `--run-skipped` suppresses the dependency skips. Banners now also print from `main()`, and an untagged always-running status row inside the scoped set reports the exclusion, the live chain's current state, and the opt-in command.
  - `[medium]` `[patch]` The invocation's container clause asked for desktop-dependent rows skipped with an explicit reason and none were written — the unobserved half lived only in the ledger. `test/platform/desktop_entries_live_test.dart` added, body-less and skipped, naming the four observations owed on a real session.
  - `[low]` `[patch]` The AD-14 row justified itself with a claim about the singleton lock that `SingleInstanceLock` does not implement (its address comes from `XDG_RUNTIME_DIR`, never from `Exec`); reworded to what `Exec` equality actually protects.
  - `[low]` `[patch]` `Categories=Utility;TextTools;` is what a real `desktop-file-validate` would flag; reduced to `Categories=Utility;`.
  - `[low]` `[patch]` The installer accepted `--exec ''` and silently installed the bare name, mangled backslashes through `awk -v`, left a whitespace-carrying path unquoted, and printed "refreshed the desktop database" whether or not that succeeded; all four fixed, and the README now names the third file it writes.
  - `[low]` `[patch]` `provision_sidecar.sh`'s `read_pin` was a third parser of the pin that disagreed with the two under test (a trailing comment or a second match made a correct environment fail its own verification); aligned to the Dart rule and covered by a new script-level test with no network.
  - `[low]` `[patch]` Harness robustness: `jsonEncode` for the request line, an existence check on fixtures, `PYTHONPATH` prepended rather than replaced, group-level skip so `--run-skipped` prints the banner instead of a `LateInitializationError`, and a stub that exits non-zero naming the message types it saw when the prompt never arrives.
  - `[low]` `[patch]` The desktop-entry parser flattened every group into one namespace, so a `[Desktop Action …]` group would break the duplicate check and hand the AD-14 comparison an action's command; parsing and lookups scoped to `[Desktop Entry]`.
  - `[low]` `[patch]` `pinnedInStackTable` scanned the whole spine in document order despite its name; sliced to the `## Stack` section first.
  - `[low]` `[patch]` The seeded-path row asserted an environment fact without asserting it; the precondition is now explicit.
  - `[low]` `[patch]` Ledger accuracy: DW-93 miscounted the sidecar's `fail()` call sites, and story 8's entry still asserted the `APPLICATION_ID` mismatch this story removed; both corrected, the latter closed with a resolution.
  - `[low]` `[patch]` `sidecarPath()`'s doc claimed the path was a property of the running process when the store persists it at seed time; corrected (the self-repair question deferred).

### 2026-08-11 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 33: (high 1, medium 7, low 25)
- defer: 2: (high 0, medium 1, low 1)
- reject: 8: (high 0, medium 1, low 7)
- addressed_findings:
  - `[high]` `[patch]` Both derivations returned a **CWD-relative** middle arm, and what they return is persisted at seed time and never re-derived — so the story's own happy path was broken by the story's other half: provision and seed from a checkout, install the autostart entry this story ships, log in, and the daemon resolves `assets/sidecar/…` and `.venv-sidecar/bin/python3` against `$HOME`. `SidecarHostPaths` now takes the working directory as a third injected input and every arm is absolute except the deliberate bare-command fallback; `_directoryOf` throws on a separator-less path instead of answering `.` and quietly reinstating the dependency. Pinned by a two-different-working-directories row (a derivation returning the constant answers both identically) and by the seeded-value rows.
  - `[medium]` `[patch]` `provision_sidecar.sh` verified the pin from `importlib.metadata` alone, which reads `dist-info` and outlives the code it describes — a half-installed venv reported "already provisioned", the fake-CLI rows then skipped on their own *import* probe, and `dart test` was green having executed neither branch this story exists to close. The probe now imports the module, with a distinct error when the install succeeded and the import still fails. The stub's metadata arm deliberately always succeeds, so removing the import is a mutation that kills a row rather than one the stub absorbs.
  - `[medium]` `[patch]` `create_venv` — the fresh-machine branch, the reason the script exists, and the one this devcontainer and a CI runner both take — was reachable from no row, because every row pre-created an executable stub venv. Two rows added that omit it and put a stub `python3` first on `PATH`, covering the ensurepip and the `--without-pip` bootstrap paths.
  - `[medium]` `[patch]` The fake-CLI group's `skip:` meant an unprovisioned host reported success having run none of the sidecar, with nothing failing anywhere. The story's "the skip count must stay 2" is now an assertion rather than something a human reads out of a log: an untagged row requires the harness to be available when `CI=true`, which is the one host where provisioning is mandatory.
  - `[medium]` `[patch]` The only evidence that the harness's `_bundled` omission worked was the stub's log file, read *after* the spawn — by which time a real 282 MB `claude` had already run, which is the process the intent forbids outright. `FakeClaudeCli.create` now asks the SDK's own discovery function whether it still sees a bundled CLI and refuses before starting anything; symlinking `_bundled` back into the view kills five rows without spawning.
  - `[medium]` `[patch]` The installer's `--exec` guard rejected a backslash and a quote but not a newline, a control character, `%`, `$`, a backtick, a leading dash, or a relative path — each of which installs a broken entry and exits 0, which the script's own comment calls the worst outcome available. All refused now, each with a row; `--exec --help` no longer installs `Exec=--help`.
  - `[medium]` `[patch]` The Exec rewrite was an unverified substitution written straight over the destination: a source that lost its `Exec=` line was a silent no-op still reporting `wrote …`, and a failure mid-write left a zero-length `.desktop` in the user's real applications directory. Now staged, checked for an `Exec=` line, and renamed; the awk match is scoped to `[Desktop Entry]`, matching the reader on the test side.
  - `[medium]` `[patch]` Nothing pinned that `my_application.cc` still feeds `APPLICATION_ID` to `g_set_prgname` and to the GApplication id — the link that makes the three-site agreement mean anything. A literal there (the snake_case `BINARY_NAME` being the obvious slip) left every other row green while the process announced an id no installed entry is named for. Source-text row added over both call sites and the macro definition.
  - `[low]` `[patch]` `read_pin`'s `sed` had no failure branch, so `claude-agent-sdk==` with no version made the pin the whole requirement line and the script blamed the environment for its own parse — the exact outcome the function's comment says it exists to avoid. Fixed with `-n`/`/p` plus an explicit error, and pinned (the guard killed zero rows on the first gate run, which is how the missing row was found).
  - `[low]` `[patch]` The drift readers used `firstMatch`: two conflicting `claude-agent-sdk==` lines passed the gate on the first one while `provision_sidecar.sh` refused the same file, and `flutter-version: "3.44.8"` — the ordinary way to keep YAML from reading a version as a number — reported a drift that did not exist. Both readers now require exactly one match, and the workflow reader strips quotes.
  - `[low]` `[patch]` `.venv-sidecar` and the script path had six independent spellings, and a rename fails *silently*: every dependent row skips rather than failing. The Dart-side copies now read `SidecarHostPaths`, and the one consumer that cannot import Dart — the provisioning script — got a drift row of its own.
  - `[low]` `[patch]` A relative `XDG_DATA_HOME`/`XDG_CONFIG_HOME` was used verbatim, installing the entries under the caller's working directory where no compositor looks, exit 0. The XDG base-directory spec requires ignoring it; it now warns and uses the default.
  - `[low]` `[patch]` The installer's bare invocation — the one the README teaches first — was exercised by nothing, because the helper always passed `--exec` (even the "empty" row passed `--exec ''`). A row now covers it and asserts the two destinations receive the two *different* sources.
  - `[low]` `[patch]` `close_quietly` caught `Exception`, so a `CancelledError` from `aclose()` escaped the `finally`, missed every handler in `main()`, and left a traceback with no protocol line at all; and the close was unbounded, so on the happy path it could withhold `done` until the adapter's 60 s deadline turned a success into a reported timeout. Now `BaseException` and a 5 s bound.
  - `[low]` `[patch]` `emit()` could raise `BrokenPipeError` — the adapter spawns through `setsid`, so the sidecar outlives a daemon that exits mid-correction — and `main()`'s handler then called `emit` again, producing an uncaught traceback plus Python's own "Exception ignored in `<_io.TextIOWrapper>`" at shutdown: the stderr pollution this story removed, by another route. Guarded with `os._exit(1)`; hand-verified against an unguarded copy (exit 1 / empty stderr versus exit 120 / traceback) on a path that never reaches the SDK.
  - `[low]` `[patch]` `build()` had dropped the deep immutability the `static const` field enforced — neither `AppConfig` nor `ProviderConfig` copies or wraps, so a write that used to throw silently rewrote the one defaults instance the daemon keeps for its whole lifetime. `Map.unmodifiable` on both maps, with a row.
  - `[low]` `[patch]` The desktop-entry reader stored values trimmed while only checking the leading side, so `Exec=/opt/hgc ` passed every row in the file while the installed byte differed; and a line inside the group with no `=` was skipped with no record, making a typo read as an absent key. Both reported now.
  - `[low]` `[patch]` `live_smoke_status_test.dart` carried two assertions true by construction (`_enablingCommand` is built by interpolating the things it was checked to contain) and printed "this command passes `--exclude-tags=live`" unconditionally, which is false under `flutter test`. Tautologies dropped, claim corrected.
  - `[low]` `[patch]` The unobserved-AD-11/AD-14 row lived in `test/platform`, which `dart test` cannot load and CI does not include — so the visibility device the story built for the live smoke was never applied to the desktop gap it was written for. The four owed observations now print from an untagged row inside the scoped set.
  - `[low]` `[patch]` `runSidecar` had no deadline: DW-92's failure mode is "like a hang", which spent itself as an anonymous 30 s framework timeout and let `dispose()` delete the stub launcher and package view out from under a live process. Bounded at 20 s with a SIGKILL and a message naming DW-92.
  - `[low]` `[patch]` The new `APPLICATION_ID` comment and the test's reason asserted a causal chain — prgname → compositor association → AD-11 precondition — that the adapter's own docs contradict (`Registry.Register` is documented as advisory and tolerant of absence) and that DW-87 concedes was never observed. Reworded to pin the agreement as a requirement rather than a verified mechanism; the assertion is unchanged.
  - `[low]` `[patch]` `fail()` was annotated `-> None` though it never returns, so at the module-level import guard a checker sees execution continue into a module where every SDK symbol is unbound. `NoReturn`.
  - `[low]` `[patch]` `.github/workflows/ci.yml`: no `permissions:` block on a `pull_request` trigger whose job resolves the branch's own `pubspec.yaml` and pip-installs its own `requirements.txt`; `cancel-in-progress` applied to `main`, discarding the gate's verdict for intermediate commits on the one branch its green history is for; and no `workflow_dispatch`, so a never-executed gate's first run could only be a merge check. All three fixed.
  - `[low]` `[patch]` `wayland_portal_global_hotkey.dart` named "story 11, packaging" as the story that changes `_registerApplicationIdOnce` under a sandbox — a story that has now run and deliberately picked no format. It names DW-89.
  - `[low]` `[patch]` README: the provisioning script's verification is described as an import plus a version check rather than "the version that actually resolved", and the installer's refusal set and staged-write behaviour are stated.

## Design Notes

**The harness mechanism, verified end-to-end during planning** (`0.2.132`, this container). Three facts decide its shape:

1. The linux wheel **bundles its own 282 MB `claude`** at `claude_agent_sdk/_bundled/claude`, and `_find_bundled_cli()` is consulted *before* `shutil.which("claude")`. A stub on `PATH` alone is therefore never spawned. The harness builds a temp directory holding `claude_agent_sdk/` symlinks to every entry of the installed package **except `_bundled`**, and puts it first on `PYTHONPATH`: discovery then falls through to `PATH`. Nothing in the venv is mutated.
2. The SDK opens with a control handshake before any prompt: it writes `{"type":"control_request","request_id":…,"request":{"subtype":"initialize",…}}` and blocks up to 60 s for `{"type":"control_response","response":{"subtype":"success","request_id":<same>,…}}`, then sends `{"type":"user",…}`. The stub answers the handshake, replays its fixture, exits. `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK=1` avoids the `[cli, "-v"]` probe; the stub answers `-v` regardless.
3. The subject is the **sidecar script**, not the Dart adapter — the adapter exposes no environment seam, so the row spawns `<venv>/bin/python assets/sidecar/claude_agent_sdk_sidecar.py` directly with `Process.start(..., environment: …)` and asserts the NDJSON on stdout.

Observed outputs from the prototype, which the rows should reproduce:

```text
is_error fixture      -> {"type":"error","kind":"providerError","message":"result error_during_execution: the model refused"}   exit 1
assistant-only        -> {"type":"text","text":"FORMAL: …\nEND"}  {"type":"done"}                                              exit 0
two stream_event deltas + same assistant text
                      -> {"type":"text","text":"FORMAL: I went"}  {"type":"text","text":" to the store.…"}  {"type":"done"}    exit 0
```

The first of those also **surfaced a defect**: the correct error line is emitted, but `fail()` calls `sys.exit(1)` from inside `async for`, so the interpreter additionally prints a `SystemExit` traceback and `RuntimeError: aclose(): asynchronous generator is already running`. The adapter forwards sidecar stderr to the daemon log, so today every provider error writes a traceback into an all-day daemon's log. That is what the sidecar edit fixes, and the harness is what can hold it fixed.

**CI decision.** A workflow is added because a GitHub remote exists and the ledger has wanted the gate enforced since story 2 — but strictly `dart analyze` plus the scoped `dart test`, per the spine's "no CI deployment target". It has never been executed (no runner here) and must be reported as unverified. `flutter test`, which carries every `test/ui` and `test/platform` row, stays outside it, as does the live smoke; both, plus DW-46's known full-suite flakes producing false reds, belong in a new ledger entry rather than in a workflow nobody can watch.

**Why the app-id change is in scope.** `my_application.cc`'s own comment says prgname exists to "map this running application to its corresponding .desktop file". Shipping the file while the running app announces a different id would satisfy AD-11 on paper and still lose the bind.

## Verification

**Commands:** (the toolchain is not on the default `PATH` here — `export PATH="$PATH:/home/vscode/flutter/bin"` first)
- `tool/provision_sidecar.sh` -- expected: exit 0, prints `.venv-sidecar/bin/python3` and `claude_agent_sdk 0.2.132`; a second run also exits 0.
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass. Baseline on `ec36968`: **690 passed / 2 skipped**. New rows must **pass**, not skip; the skip count must stay 2.
- `flutter test` -- expected: all pass. Baseline: **862 passed / 9 skipped**; unchanged skip count.
- `flutter build linux --debug` -- expected: builds with the new `APPLICATION_ID`.
- `git diff _bmad-output/implementation-artifacts/deferred-work.md` -- expected: both closed headings remain, each gains `status: done <date>` and a `resolution:` citing evidence, and newly filed entries are appended; no heading is deleted.

**Mutation gates** — apply each alone against a green tree, run the suite, record how many rows fail, revert. Back the working tree up to the scratchpad first; `git checkout --` is not a safe revert while an uncommitted patch is under review. **A gate that fails zero rows means the property is unpinned and the test is what needs fixing.**
1. Change `requirements.txt` to `claude-agent-sdk==0.2.131` -- the drift row must fail.
2. Feed the pin parser a Stack table with the row deleted (its own synthetic-input row) -- it must fail with "row not found", never pass.
3. Change the autostart entry's `Exec` -- the AD-14 pairing row must fail.
4. Rename the packaging file's basename -- the AD-11 basename row must fail.
5. Restore `APPLICATION_ID` to `com.divertedriver.hotkey_grammar_corrector` -- the three-site agreement row must fail.
6. Restore the sidecar's `fail()` call inside the `async for` -- the no-traceback row must fail.
7. Make the sidecar replay `fallback_text` unconditionally -- the streaming control row must fail on the duplicated text.
8. Make the path derivation always return the repo-relative path -- the installed-bundle row must fail.

**Manual checks (if no CLI):**
- **Not observable here, and must be reported as such.** This container has no compositor, no `xdg-desktop-portal`, no session bus and no `desktop-file-validate`. Nothing is observed about the entries *on a desktop*: not that GNOME associates the app id with the installed file, not that the bind survives because of it, not that the autostart entry starts the daemon at login, and not that an autostarted daemon plus a manual launch resolve to one instance. The tests read file contents and run an installer into a temp tree; that is a check of bytes and paths, not a desktop observation.
- Read the scoped `dart test` output and confirm each skipped row printed its reason and its enabling command.
- Confirm `.github/workflows/ci.yml` is stated as never-executed rather than as a passing gate.


## Auto Run Result

Status: done
Blocking condition: none

### Summary of implemented change

This was a **second review pass** over the story-11 diff (`ec36968..HEAD`), run because the first pass recommended one. The shipped feature set is unchanged: AD-11's app-id entry, AD-14's autostart entry, the three-site id agreement, the installer, the provisioning script, the derived AD-19 paths, the sidecar's failure exit, the fake-CLI harness, the CI workflow. What changed is that several of those turned out to be **correct in the direction they were tested and wrong in the direction they were not**, and one of them was wrong on the story's own happy path.

The high finding is the interaction between this story's two halves. Both AD-19 derivations resolved their middle arm to a **CWD-relative** string, and that string is persisted at seed time and never re-derived. So: provision from a checkout, seed a config, install the autostart entry *this story ships*, log in — and the daemon resolves `assets/sidecar/…` and `.venv-sidecar/bin/python3` against `$HOME`. Every correction fails `providerUnavailable`. The already-filed deferred item covers "seeded once, never re-derived" for a *moved install*; the autostart entry made it the documented first-run path. `SidecarHostPaths` now takes the working directory as a third injected input and every arm is absolute except the deliberate bare-command fallback. That the fix is real is pinned by a row that derives from two different working directories: a derivation answering the bare constant returns the same string for both, which is exactly the defect.

Three more findings were about gates that could not fail. `provision_sidecar.sh` verified its pin from `importlib.metadata` alone — which reads `dist-info`, and `dist-info` outlives the code it describes — so a half-installed venv reported "already provisioned", the fake-CLI rows then skipped on their own *import* probe, and `dart test` was green having run neither branch the story exists to close. `create_venv`, the fresh-machine branch and the one this container and a CI runner both take, was reachable from no row at all. And the fake-CLI group's `skip:` meant an unprovisioned host reported success silently; the story's "the skip count must stay 2" is now an assertion on the one host where provisioning is mandatory rather than something a person has to notice in a log.

The harness got the change with the largest downside avoided. The only evidence that its `_bundled` omission worked was the stub's log file, read *after* the spawn — so the first thing to notice a discovery change would have been a real 282 MB `claude` already running, which is the process the intent forbids outright and which has been observed terminating a session. It now asks the SDK's own discovery function whether it still sees a bundled CLI and refuses before starting anything.

The installer's `--exec` guard rejected a backslash and a quote and let through a newline, a control character, `%`, `$`, a backtick, a leading dash and a relative path — each of which installs a broken entry and exits 0, which the script's own comment names as the worst outcome available. The rewrite was also a substitution written straight over the destination: a source that lost its `Exec=` line was a silent no-op still printing `wrote …`, and a failure mid-write left a zero-length `.desktop` in a real applications directory. Both closed, each with a row.

Nothing was re-derived: **no intent gaps and no spec defects.** Every finding was either a patch or filed.

### Files changed

**Shipped code**
- `lib/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart` — working directory injected; every arm absolute; `_directoryOf` throws on a separator-less path rather than answering `.`.
- `lib/src/infrastructure/config/default_app_config.dart` — the working-directory seam with a host default; `Map.unmodifiable` on both maps, restoring the guarantee the `static const` field used to enforce.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — the sandbox `Registry.Register` rule points at DW-89, not at a story that has run.
- `assets/sidecar/claude_agent_sdk_sidecar.py` — `close_quietly` catches `BaseException` and is bounded; `emit` survives a broken stdout without a traceback; `fail` is `NoReturn`.
- `linux/CMakeLists.txt` — the id-agreement comment states a requirement rather than an unobserved mechanism.

**Tooling**
- `tool/install_desktop_entries.sh` — the full `--exec` refusal set, flag lookahead, absolute-or-bare-name rule, staged-and-renamed writes with an `Exec=` check, group-scoped rewrite, relative XDG roots ignored.
- `tool/provision_sidecar.sh` — the verification imports the module; `read_pin` fails on a version-less pin instead of returning the whole line.
- `.github/workflows/ci.yml` — `permissions: contents: read`, `cancel-in-progress` off on `main`, `workflow_dispatch`.

**Tests**
- `test/support/fake_claude_cli.dart` — pre-spawn bundled-CLI refusal, a 20 s deadline with a SIGKILL, both path constants taken from `SidecarHostPaths`.
- `test/architecture/provision_sidecar_test.dart` — the version-less pin row, the broken-install row, and two rows that reach `create_venv` by omitting the stub venv and stubbing the host `python3`.
- `test/architecture/desktop_entries_test.dart` — the bare invocation, the quote/newline/relative `--exec` refusals, the missing-`Exec=` guard, the relative-XDG rule, the `my_application.cc` link, the two reader gaps, and the printed AD-11/AD-14 owed observations.
- `test/architecture/sidecar_pin_drift_test.dart` — exactly-one-match readers, quote stripping, and a third pair: the script's `venv_dir` against the shipped constant.
- `test/infrastructure/correction/claude_agent_sdk/sidecar_host_paths_test.dart` — the working directory threaded through, plus the two-directories row, the root-directory row and the separator-less refusal.
- `test/infrastructure/config/default_app_config_test.dart` — absolute seeded paths, the interpreter row split out and checked by *importing* rather than by existence, and the immutability row.
- `test/infrastructure/correction/claude_agent_sdk/sidecar_fake_cli_test.dart` — the CI-must-be-provisioned row.
- `test/infrastructure/correction/claude_agent_sdk/live_smoke_status_test.dart` — tautologies removed, the exclusion claim corrected.

**Docs**
- `README.md` — what the provisioning verification actually checks, and the installer's refusal set and staged writes.
- `_bmad-output/implementation-artifacts/deferred-work.md` — two new entries appended; no existing entry touched.

### Review findings breakdown

Four layers ran in parallel with no prior conversation context — adversarial, edge-case, verification-gap, intent-alignment. **33 patched** (high 1, medium 7, low 25), **2 deferred**, **8 rejected**. No intent gaps, no spec defects.

**Deferred 2.** (medium) An installed build has no provisioning route at all: `provision_sidecar.sh` always builds under the repository root, so `resolveInterpreter`'s beside-the-executable arm — the one the tests call "the branch every user of a packaged build takes" — cannot be satisfied by anything shipped, and a packaged daemon always falls back to the bare `python3`. Left open on the intent's own authority: a `--prefix`, or installing beside a binary, is a decision about where an installed build lives, i.e. the packaging format the Never list defers to DW-89. (low) Ledger bookkeeping this review was instructed not to perform — the two resolved entries were deleted rather than closed, the story-8 basename entry is satisfied but still open, and DW-89 restates a still-open story-8 entry. Filed for the owner; the one adjacent item in scope (the adapter's stale story reference) was fixed.

**Rejected 8.** The intent's own rationale that identical `Exec` is what makes two launches collide on the singleton lock — false (the lock's address comes from `XDG_RUNTIME_DIR`), but the requirement is unambiguous and already implemented, and every actionable restatement was corrected in the first pass. That CI provisioning "violates" the never-install rule — the rule names *tests*, and a gate that skipped its own subject would breach the stronger "never fake a pass"; the diff resolved a genuine collision between two Nevers in the coherent direction. `resolveScript`'s third arm and the interpreter derivation's absence from the I/O matrix — both deliberate and logged last pass. The `flutter test` skip-count deviation — already disclosed. A Python-version probe in the provisioning script, more of `desktop-file-validate`'s rule surface, and `--require-hashes` pip pinning in CI — a cosmetic message, a validator that does not exist here (DW-87 owns it), and a supply-chain policy decision respectively.

**Follow-up review recommended: true.** Patched severities: high 1, medium 7, low 25 — the rule makes any patched `high` sufficient on its own (score `3×7 + 1×25 = 46`, threshold 5). The honest read is narrower than that number suggests: this pass found one real user-visible defect and a cluster of gates that could not fail, which is the expected shape of a second pass over a 3,000-line three-goal story. A third pass is warranted mainly because 33 patches is itself a large edit, and because two of them — the working-directory seam and the harness's pre-spawn refusal — changed shipped behaviour rather than only tests.

### Verification performed

All commands from `## Verification`, re-run after the patch pass (`export PATH="$PATH:/home/vscode/flutter/bin"`):
- `tool/provision_sidecar.sh` — exit 0, twice; prints the interpreter path and `claude_agent_sdk 0.2.132`.
- `dart analyze --fatal-infos` — no issues.
- `dart format --output=none --set-exit-if-changed lib test` — 0 changed of 172.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — **779 passed / 2 skipped** (previous pass 751/2; +28 rows, **skip count unchanged at 2**).
- `flutter test` — **951 passed / 10 skipped** (previous pass 923/10; skip count unchanged).
- `flutter build linux --debug` — builds.
- `.venv-sidecar/bin/python3 -m py_compile assets/sidecar/…` and `bash -n` on both scripts — clean.
- `git diff` on the ledger — two appended entries, nothing else.

**Mutation gates.** Backed the working tree up to the scratchpad first, per this spec's own instruction. Every gate below was applied alone against a green tree and reverted; each figure is rows failed:

| Gate | Rows |
|---|---|
| `create_venv` builds the wrong directory | 1 |
| ensurepip probe inverted | 2 |
| `read_pin`'s `sed` loses `-n`/`/p` | 1 |
| `installed_version` drops the import probe | 1 |
| script arm reverts to the bare relative constant | 4 |
| host default reverts to a relative working directory | 2 |
| `_directoryOf` answers `.` for a separator-less path | 1 |
| `build()` drops `Map.unmodifiable` | 1 |
| `--exec` control-character arm removed | 1 |
| `--exec` double-quote arm removed | 1 |
| `--exec` absolute-path arm removed | 1 |
| staged-write `Exec=` verification removed | 1 |
| relative XDG root honoured | 1 |
| `prgname` takes a literal instead of the macro | 1 |
| reader reverts to `trimLeft` only | 1 |
| reader stops recording malformed lines | 1 |
| requirements reader reverts to `firstMatch` | 1 |
| workflow reader stops stripping quotes | 1 |
| provisioning script renames the venv directory | 1 |
| package view stops omitting `_bundled` | 5 (all **before** any spawn) |

Two gates found their own missing rows rather than passing: the `read_pin` guard killed **zero** rows on its first run, and the import-probe gate killed zero until the stub's metadata arm was decoupled from its import arm — both were fixed and now kill one each. The eight gates from the first pass were not re-run; they cover properties this pass did not touch.

**Hand-verified, unpinned by any row** (stated rather than implied): the broken-stdout guard in `emit`. Driven against an unguarded copy of the sidecar on a path that never reaches the SDK — guarded gives exit 1 and empty stderr, unguarded gives exit 120 and a traceback. A row would need to break the pipe on a live sidecar, which the harness has no seam for; this is the same class DW-91 already records for `close_quietly`'s two guards, and `CancelledError` and the 5 s close bound join it.

### Residual risks

**Nothing here was observed on a desktop.** No compositor, no `xdg-desktop-portal`, no session bus, no `desktop-file-validate`. All four AD-11/AD-14 runtime claims remain owed (DW-87) — and they are now printed by an untagged row inside the routine command, which is the one thing this pass changed about them.

`.github/workflows/ci.yml` has still **never executed** (DW-88); the three edits to it are claims about what the file says. It now has `workflow_dispatch`, so its first run no longer has to be a merge check. DW-46's cross-suite flakes can still produce a false red on that first run.

The `live` smoke was not run, deliberately. Note one thing this pass learned about that boundary: driving the sidecar's broken-pipe path through `query()` *does* reach real CLI discovery, so an experiment aimed at the sidecar can spawn a real `claude` by accident — which is why the hand-verification above was moved to a request that fails validation before the SDK is touched, and why the harness's refusal is now pre-spawn.

Still open and unchanged by this pass: the packaging format (DW-89, and now the installed-build provisioning gap that follows from it), the pin's two writable homes (DW-90), the SDK-internals dependency the pin keeps honest (DW-92), the `providerUnavailable` import guard reachable only through the live file (DW-93), the seed-time-only path derivation as a `ConfigStore` contract question — narrowed but not eliminated, since the values are now absolute rather than shell-dependent — and the AD-19 chain still verified as two halves that meet only in the live row.
