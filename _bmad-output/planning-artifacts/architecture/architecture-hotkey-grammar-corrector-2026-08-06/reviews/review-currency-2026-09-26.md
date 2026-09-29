# Currency and repository reality review — plan 02-21

**Target:** `ARCHITECTURE-SPINE.md`, working-tree update of 2026-09-26  
**Lens:** checked-in technology, version, dependency, and runtime claims against `pubspec.yaml`, `pubspec.lock`, relevant `lib/src` and sidecar sources, the product SPEC, and D-19.  
**Verdict:** **CONDITIONAL — one high-severity contract mismatch and one medium-severity runtime claim remain.** The newly reconciled pub pins, removed packages, D-19 constructor, portal regime, and complete Structural Seed are grounded in the tree. No new host observation was established by this review.

## Findings

### HIGH — AD-16 describes the wrong success grammar

`ARCHITECTURE-SPINE.md:382` says the **shipped** preset requires *exactly three lines* and that the parser completes after the three tagged registers. The shipped prompt in `lib/src/infrastructure/config/default_app_config.dart:29-38` requires **four** lines: `FORMAL`, `CASUAL`, `SHORTER`, then `END`. The actual parser in `lib/src/infrastructure/correction/shared/register_tagged_stream_parser.dart:10-23,181-196` requires that end sentinel before `CorrectionCompleted`; three correct register lines without it produce `malformedResponse`. This is a normative parser contract, so a future adapter following the spine can mishandle truncated output. The update changed this AD's parser-location claim but left the pre-existing grammar error. Regenerate AD-16 to name the fourth sentinel line and its truncation role; retain AD-16 and the actual parser path.

### MEDIUM — operational diagnostics promise stderr text that is deliberately suppressed

`ARCHITECTURE-SPINE.md:651` says sidecar stderr is forwarded to the daemon log so an import failure is visible there. `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart:260-274` consumes each stderr line but logs only `sidecar reported an error`, specifically because stderr can quote draft text. The Python import guard in `assets/sidecar/claude_agent_sdk_sidecar.py:70-84` sends an actionable `providerUnavailable` error on **stdout** as protocol JSON. The spine's existing diagnostic claim is false and could lead a maintainer to log sensitive stderr to make the documentation true. Say that stderr *occurrence* is logged without content and the structured stdout error supplies the panel diagnosis.

### MEDIUM — manifest comments still contradict the reconciled Stack table

The table at `ARCHITECTURE-SPINE.md:449-475` now correctly omits `drift_flutter` and `hotkey_manager` and includes `ffi 2.2.0` and `test 1.31.0`. But `pubspec.yaml:11-37,58-62` still says the spine lists both removed packages and omits `test`, and calls them live divergences. The manifest and lock contain neither removed package (`pubspec.yaml:38-71`; no matching entries in `pubspec.lock`), while `test` is a direct dev dependency. This is stale source commentary, not a bad Stack pin, but it undercuts the statement that the checked-in manifests are reconciled. Update the comments in a permitted source pass; do not restore the deleted dependencies.

### LOW — Python 3.11+ is a stated floor without a repository version gate

`ARCHITECTURE-SPINE.md:466,649` lists Python 3.11+ as a runtime dependency. `tool/provision_sidecar.sh:89-105` checks only that `python3` exists and can create a virtual environment; it does not inspect its version. Local installed metadata for the pinned `claude-agent-sdk 0.2.132` reports `Requires-Python: >=3.10`, so the 3.11 floor is a project choice, not a fact established by that dependency. Either enforce/document the stricter project floor or describe the SDK's actual minimum separately. No Python-version compatibility run was performed here.

### LOW — clarify the Flutter row's historical meaning

`ARCHITECTURE-SPINE.md:453` labels the CI pin `Flutter (stable)`. `.github/workflows/ci.yml:75-88` and `.devcontainer/Dockerfile:111-115` pin **3.44.8**; `pubspec.yaml:9` declares it as a floor. Official [Flutter release notes](https://docs.flutter.dev/release/release-notes) list **3.47.0** as a later stable release as of this review. The paragraph at spine line 449 correctly disclaims upstream latest, so this is wording only: `Flutter (stable-channel CI pin)` would prevent readers from mistaking the row for the current stable release. The workflow itself says it has never executed (`.github/workflows/ci.yml:1-6`), so this review confirms a configured pin, not a verified CI run.

## Confirmed claims and limits

- **Pub dependency inventory:** Every numeric pub package row at spine lines 455-465 matches `pubspec.yaml:42-71` and the resolved `pubspec.lock` entries. The Dart `^3.12.2` constraint matches `pubspec.yaml:8` and the lock's `>=3.12.2 <4.0.0` SDK range (`pubspec.lock:827-829`). `drift_flutter`, `hotkey_manager`, and the earlier native SQLite plugin packages are absent from the lock. `sqlite3 3.5.1` has a local cached `hook/build.dart`, supporting the build-hooks statement at spine line 475. The sidecar pin resolves to `claude-agent-sdk==0.2.132` in `assets/sidecar/requirements.txt:1`; `tool/provision_sidecar.sh:24-39,124-130` reads and installs that file.
- **D-19 and Phase 1 hotkey facts:** `02-AD9-RATIFICATION.md:5-17,19-45` distinguishes the owner's 2026-09-24 ratification from the earlier unattended choice. Spine lines 251-254 and 317 reproduce the non-`const`, unmodifiable-set constructor in `lib/src/domain/hotkey/hotkey_binding.dart:5-7`. The current-status accessor, unavailable cause, and conditional host portal registration are present in the corresponding domain and infrastructure files; these are not newly attributed to D-19.
- **X11 and tray dependency claims:** `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart:1-11,119-139` uses libX11 FFI and opens the worker on a grab request; the old plugin is absent from the manifest and lock. Local cached `tray_manager-0.5.3/linux/tray_manager_plugin.cc:109-129` returns success from `set_icon` without proving a StatusNotifier host displayed it. Spine line 650 properly labels the absent-host consequence as source inspection rather than a new host observation. No live X11, Wayland, or tray-host behavior was measured in this review.
- **Structural Seed:** The file map at spine lines 479-575 includes all 96 present `lib/**/*.dart` files and the present `history.drift`, sidecar, requirements, and desktop-entry paths. The shared parser's old `claude_agent_sdk/` import path remains as a compatibility export (`lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart:1-2`), while the implementation lives under `shared/`, as the updated AD-16 says.
- **Scope:** This is a source and manifest review. It did not run the app, tests, CI, a display-server session, or a host with and without a tray service. The plan's claim of no newly observed runtime behavior should be preserved.
