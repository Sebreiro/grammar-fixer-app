---
title: 'Bootstrap project skeleton and pure-Dart domain ring'
type: 'feature'
created: '2026-08-06'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'febdd4016bfb7690fda4b35fdeb8f44ae337bfd5'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The repo has planning artifacts but no code. Every future slice (adapters, controllers, UI) depends on the domain ring's port interfaces and value types existing first, with AD-1's import discipline mechanically enforced from day one.

**Approach:** Create a Linux-desktop-only Flutter project at the repo root pinned to the spine's Stack table, wire `analysis_options.yaml` (flutter_lints + strict-casts + strict-raw-types + AD-1 import lint), build the complete `lib/src/domain/` ring per the Structural Seed, and provide one fake per port in `test/fakes/`.

## Boundaries & Constraints

**Always:**
- AD-2 declarations verbatim — names and fields fixed; do not redesign.
- Everything under `lib/src/domain/` imports only `dart:` core libraries (AD-1).
- One public type per file; filename is snake_case of the type (AGENTS.md §3). Fakes named `Fake<Port>` in `test/fakes/` (spine Consistency Conventions).
- pubspec pins the spine Stack versions: flutter_riverpod 3.4.2, drift 2.34.3, drift_flutter 0.3.1, sqlite3 3.5.1, dbus 0.7.14, window_manager 0.5.2, tray_manager 0.5.3, hotkey_manager 0.2.3, drift_dev 2.34.0, build_runner 2.15.1, flutter_lints 6.0.0; SDK constraint matches Dart 3.12.2 / Flutter 3.44.8. `test 1.31.0` as a direct dev dependency is human-approved. <!-- drift_dev/build_runner renegotiated down and `test` approved by the human, 2026-08-06 review checkpoint -->
- Demonstrate the AD-1 rule works: add a deliberate flutter import under domain/, show the enforcing check `dart test test/architecture/` fail, remove it. <!-- amended from "dart analyze fail" with human ratification, 2026-08-06: the Dart 3.12 analyzer has no options-native import ban and analyzer plugins would need out-of-Stack dependencies -->
- Ports designed but not spelled out in the spine (clipboard, tray, repository, config store, clock, logger) follow the spine's conventions: role-noun names, no `I` prefix, expected failures as modelled values, unix-millis UTC via Clock.

**Ask First:**
- Any deviation from an AD-2 name or field.
- Adding a dependency not in the Stack table.

**Never:**
- Adapters, UI widgets, Python sidecar, drift tables, main.dart wiring, Riverpod providers — out of this slice.
- Behaviour tests — fakes only (a minimal smoke test may exist solely so `dart test` has something to run).
- Flutter/drift/dbus/plugin imports anywhere under `lib/src/domain/`.
- Platform directories other than `linux/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| AD-1 violation | `package:flutter/…` import in domain file | `dart test test/architecture/` exits non-zero naming the banned import | N/A |
| Clean tree | Final state | `dart analyze` clean, `dart test` passes | N/A |

</frozen-after-approval>

## Code Map

- `pubspec.yaml` -- Flutter project manifest, pinned Stack versions
- `analysis_options.yaml` -- flutter_lints + strict modes + AD-1 import ban
- `lib/src/domain/correction/suggestion_register.dart` -- enum, AD-2 verbatim
- `lib/src/domain/correction/suggestion.dart` -- value type, AD-2 verbatim
- `lib/src/domain/correction/preset.dart` -- value type, AD-2 verbatim
- `lib/src/domain/correction/correction_event.dart` -- sealed hierarchy + CorrectionFailureKind, AD-2 verbatim
- `lib/src/domain/correction/correction_provider.dart` -- port, AD-2 verbatim
- `lib/src/domain/correction/correction_record.dart` -- AD-7 shape: input + suggestions + provenance
- `lib/src/domain/correction/correction_outcome.dart` -- CorrectionOutcome enum (own file per AGENTS.md §3)
- `lib/src/domain/config/provider_config.dart` -- opaque provider settings value (AD-15 keeps transport adapter-private)
- `lib/src/domain/config/config_load_result.dart` -- AppConfig + optional malformed-file warning (AD-13)
- `test/architecture/ad1_import_rule_test.dart` -- the AD-1 merge gate (analyzer has no options-native import ban)
- `lib/src/domain/hotkey/hotkey_binding.dart` -- HotkeyModifier + HotkeyBinding, AD-9 verbatim
- `lib/src/domain/hotkey/global_hotkey.dart` -- port + HotkeyRegistration + BindingAuthority, AD-9 verbatim
- `lib/src/domain/panel/panel_visibility.dart` -- port, AD-8 verbatim
- `lib/src/domain/clipboard/clipboard_port.dart` -- port: read + write plain text
- `lib/src/domain/tray/tray_port.dart` -- port: tray icon + menu surface
- `lib/src/domain/history/correction_repository.dart` -- port: save + query CorrectionRecord
- `lib/src/domain/config/app_config.dart` -- immutable config value (providers, presets, activePreset, hotkey, sidecar paths)
- `lib/src/domain/config/config_store.dart` -- port: load/watch/write AppConfig (AD-13)
- `lib/src/domain/clock.dart` -- port: unix-millis UTC now
- `lib/src/domain/logger.dart` -- port: structured stderr lines
- `test/fakes/` -- one `Fake<Port>` per port above

## Tasks & Acceptance

**Execution:**
- [x] repo root -- `flutter create` Linux-only project (org `com.divertedriver`), delete unused boilerplate, write pinned `pubspec.yaml` -- skeleton per spine Stack (build_runner/drift_dev pins unsatisfiable — see Spec Change Log)
- [x] `analysis_options.yaml` -- flutter_lints, strict-casts, strict-raw-types, AD-1 import rule -- merge gate per AGENTS.md §6 (AD-1 via the Design-Notes-authorized architecture test — see Spec Change Log)
- [x] `lib/src/domain/correction/*` -- five AD-2 files verbatim + `correction_record.dart` -- the provider contract
- [x] `lib/src/domain/hotkey/*`, `panel/`, `clipboard/`, `tray/`, `history/`, `config/`, `clock.dart`, `logger.dart` -- remaining value types and ports -- Structural Seed completion
- [x] AD-1 proof -- add bad import in domain/, run the enforcing check (must fail), remove it, re-run (must pass) -- demonstrated via `dart test test/architecture/` (exit 1 with violation, exit 0 clean)
- [x] `test/fakes/*` -- one fake per port (FakeCorrectionProvider, FakeGlobalHotkey, FakePanelVisibility, FakeClipboard, FakeTray, FakeCorrectionRepository, FakeConfigStore, FakeClock, FakeLogger) + minimal smoke test -- AGENTS.md §4.1
- [x] `.devcontainer/Dockerfile` -- already patched with Flutter 3.44.8 + GTK toolchain (done during env setup) -- reproducible builds

**Acceptance Criteria:**
- Given the final tree, when `dart analyze` runs, then it reports zero issues.
- Given the final tree, when `dart test` runs, then all tests pass.
- Given any file under `lib/src/domain/`, when its imports are inspected, then only `dart:` URIs (and domain-relative imports) appear.
- Given a deliberate `package:flutter` import added under `lib/src/domain/`, when `dart test test/architecture/` runs, then it fails naming the violating file.
- Given `pubspec.yaml`, when versions are compared to the spine Stack table (as renegotiated 2026-08-06), then every listed package matches exactly.
- Given the repo root, when platform folders are listed, then only `linux/` exists (no android/ios/web/macos/windows).

## Spec Change Log

- 2026-08-06 (implementation): **Stack-table pins `build_runner 2.16.0` and `drift_dev 2.34.5` are unsatisfiable on Flutter 3.44.8 and were omitted from `pubspec.yaml`, not repinned** — needs human renegotiation of the spine Stack table. Empirically verified with `flutter pub get`: (a) build_runner ≥2.15.2 needs analyzer ≥13.3.0 which needs meta ^1.18.3, but the Flutter 3.44.8 SDK pins meta 1.18.0 (newest resolvable: build_runner 2.15.1); (b) drift_dev ≥2.34.1+1 needs analyzer ^13.0.0, which is jointly unsatisfiable with flutter_riverpod 3.4.2 — riverpod 3.4.2 needs `test ^1.0.0` and every `test` version compatible with flutter_test's test_api 0.7.11 pin needs analyzer <13.0.0 (newest resolvable: drift_dev 2.34.0 — 2.34.1 was never published; the 2.34.1+1..2.34.4 line needs analyzer ^13.0.0). Neither tool is used in this slice (no drift codegen). All other Stack pins resolve exactly and are pinned without carets.
- 2026-08-06 (review, human-ratified): AD-1 stays enforced via the architecture test under `dart test`; `test 1.31.0` direct dev dep approved; build_runner and drift_dev re-added at the newest resolvable exact pins — build_runner 2.15.1 and drift_dev 2.34.0 (the ratification note said 2.34.1, but that version was never published; 2.34.0 is the newest that resolves). The spine Stack table is being updated to match.
- 2026-08-06 (implementation): AD-1 enforced via `test/architecture/ad1_import_rule_test.dart` (the Design-Notes fallback). Verified empirically that the Dart 3.12 analyzer has no analysis_options-native import ban: candidate options under `analyzer:` are rejected with `unsupported_option` (supported keys: cannot-ignore, enable-experiment, errors, exclude, language, optional-checks, plugins, strong-mode), and `plugins` would require a dependency outside the Stack table.
- 2026-08-06 (implementation): `test 1.31.0` added as a direct dev dependency — not in the Stack table, but already in the dependency graph at exactly that version (riverpod 3.4.2 depends on it) and required for the spec's own `dart test` verification command to run pure-Dart tests without a Flutter binding (AGENTS.md §7).
- 2026-08-06 (implementation): clipboard and tray port types are named `ClipboardPort`/`TrayPort` (so their fakes are `FakeClipboardPort`/`FakeTrayPort`, not the task list's `FakeClipboard`/`FakeTray`): the Structural Seed fixes the filenames `clipboard_port.dart`/`tray_port.dart`, and the frozen §3 rule (filename = snake_case of the type) then fixes the type names.
- 2026-08-06 (review, human-ratified): three escalations resolved by the human at the review checkpoint. (1) Frozen AD-1 wording amended from "`dart analyze` fail" to "`dart test test/architecture/` fail" — a live probe proved `dart analyze` passes with a flutter import under domain/, and the analyzer offers no in-Stack alternative; the architecture-test mechanism is ratified. (2) `test 1.31.0` direct dev dependency retroactively approved (Ask-First gate satisfied). (3) Stack pins renegotiated: build_runner 2.15.1 and drift_dev 2.34.0 re-added to pubspec (newest resolvable — 2.34.1 was never published upstream), spine Stack table updated to match. KEEP: the AD-1 architecture test, the verbatim AD-2/8/9 declarations, the pinned-exact pubspec discipline, and the fail/pass demonstration practice must survive any re-derivation.
- 2026-08-06 (review): confirmed review findings patched — AD-1 test hardened against conditional-import alternate URIs, `part` directives, and comment false-positives (with fixture self-tests); Dockerfile curl `-fsSL` + SHA-256 verification + `libkeybinder-3.0-dev`/`libayatana-appindicator3-dev` (a live `flutter build linux` failed at CMake without keybinder); `ConfigStore.load()` now returns `ConfigLoadResult` so AD-13's malformed-file warning has a port surface, and pre-load `current` is documented programmer error; `FakeGlobalHotkey.bind` configurable for AD-10 compositor-authority scenarios; fakes close their stream controllers via `dispose()`; `CorrectionRepository.recent` documents non-negative `limit`; `CorrectionRecord` constructor asserts its documented invariants; pubspec gained a Flutter `environment:` constraint so the toolchain pin is enforced, not aspirational.

## Design Notes

- AD-1 enforcement: no first-party "import-lint" exists in `flutter_lints`. Verify what the pinned toolchain supports; if no analyzer-native mechanism covers "domain may import only dart:", the fallback is a tiny pure-Dart test (`test/architecture/ad1_import_rule_test.dart`) that scans `lib/src/domain/**` import directives — runs under `dart test`, cites AD-1. Choose whichever mechanism actually fails the build, and record the choice in the implementation notes.
- `CorrectionRecord` (AD-7 shape): `createdAtMillis`, `inputText`, `presetId`, `providerId`, `model`, `latencyMs`, `outcome` (enum `CorrectionOutcome { completed, failed }`), `failureKind` (nullable `CorrectionFailureKind`), `suggestions` (empty when failed). DB ids never leave the repository, so the record has no id field.
- Fakes are hand-written, constructor-configurable, no mocking framework. `FakeCorrectionProvider` replays a scripted `List<CorrectionEvent>`; `FakeClock` returns a settable millis value.

## Verification

**Commands:**
- `flutter pub get` -- expected: resolves with pinned versions, no downgrades
- `dart analyze` -- expected: No issues found
- `dart test` -- expected: all tests pass
- `dart test test/architecture/` -- expected: passes on a clean tree; fails naming the file when any non-`dart:` URI (import/export/part, including conditional-import alternatives) appears under `lib/src/domain/`
- `grep -rn "'package:" lib/src/domain --include='*.dart'` -- expected: no matches (secondary spot check for package: URIs only; the architecture test is the authoritative gate and also covers conditional imports, exports, and parts)
- `flutter build linux --debug` -- expected: builds; proves the devcontainer toolchain end to end

## Suggested Review Order

**The contract: domain ports and value types**

- The load-bearing port — text in, stream out, AD-2 verbatim.
  [`correction_provider.dart:4`](../../lib/src/domain/correction/correction_provider.dart#L4)

- Sealed event hierarchy: deltas, one terminal completed/failed event (AD-2/AD-3).
  [`correction_event.dart:4`](../../lib/src/domain/correction/correction_event.dart#L4)

- AD-7 persistence shape; constructor asserts enforce the documented invariants.
  [`correction_record.dart:21`](../../lib/src/domain/correction/correction_record.dart#L21)

- Hotkey port reports effective binding + authority — the AD-10 Wayland split.
  [`global_hotkey.dart:5`](../../lib/src/domain/hotkey/global_hotkey.dart#L5)

- Immutable config value; collection-ownership and cross-field validation conventions documented.
  [`app_config.dart:16`](../../lib/src/domain/config/app_config.dart#L16)

- AD-13's malformed-file warning gets a port surface instead of an exception.
  [`config_load_result.dart:6`](../../lib/src/domain/config/config_load_result.dart#L6)
  [`config_store.dart:15`](../../lib/src/domain/config/config_store.dart#L15)

**AD-1 enforcement (the mechanical gate)**

- The gate itself: scans import/export/part incl. conditional-import alternatives, strips comments.
  [`ad1_import_rule_test.dart:7`](../../test/architecture/ad1_import_rule_test.dart#L7)

- Fixture self-tests prove each evasion form is caught (review probe found the bypasses).
  [`ad1_import_rule_test.dart:75`](../../test/architecture/ad1_import_rule_test.dart#L75)

- Strict analyzer settings; comment records why AD-1 lives in a test, not here.
  [`analysis_options.yaml:6`](../../analysis_options.yaml#L6)

**Toolchain pins**

- Flutter environment constraint makes the spine's 3.44.8 pin enforced, not aspirational.
  [`pubspec.yaml:7`](../../pubspec.yaml#L7)

- Renegotiated dev pins (2.34.0/2.15.1) with the resolver evidence in comments.
  [`pubspec.yaml:40`](../../pubspec.yaml#L40)

- SHA-256-verified Flutter install + keybinder/appindicator so `flutter build linux` works.
  [`Dockerfile:101`](../../.devcontainer/Dockerfile#L101)

**Fakes (peripheral)**

- Scriptable bind response makes AD-10 compositor-authority scenarios testable.
  [`fake_global_hotkey.dart:7`](../../test/fakes/fake_global_hotkey.dart#L7)

- Replays a scripted event list as the single-subscription stream AD-4 requires.
  [`fake_correction_provider.dart:8`](../../test/fakes/fake_correction_provider.dart#L8)
