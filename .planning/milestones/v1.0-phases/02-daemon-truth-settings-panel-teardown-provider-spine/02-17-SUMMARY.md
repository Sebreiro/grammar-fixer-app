---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 17
subsystem: provider-settings
tags: [dart, flutter, settings, config, provider, privacy]
requires:
  - phase: 02-16
    provides: read-only key-source resolver and D-17 preservation of a hand-placed config key
  - phase: 02-15
    provides: OpenAI-compatible adapter and destination validation rules
  - phase: 02-11
    provides: warm Settings view and stable controller state
provides:
  - Selected compatible provider Base URL and paired preset model write-through
  - Provider form with immediate required and destination validation
  - Source-only Settings display seam and conditional plaintext warning
affects: [02-18, PROVIDER-02, D-17]
actuals:
  tokens: 4515
  tasks: 2
  commits: 4
commits: 4
plan_head_before: 12d8a0cde9a98a30fcaaca0c84a8ae8e215cd12c
tech-stack:
  added: []
  patterns: [selected-preset write-through, provider-only save guard, source-only credential callback]
key-files:
  created: []
  modified:
    - lib/src/application/settings_controller.dart
    - lib/src/application/settings_state.dart
    - lib/src/domain/config/provider_config.dart
    - lib/src/ui/settings/settings_screen.dart
    - test/infrastructure/config/json_config_store_test.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
key-decisions:
  - Save the selected compatible provider Base URL and model through one existing Settings mutation, preserving the preset prompt.
  - Accept remote HTTPS and explicit loopback HTTP only; reject userinfo, query, and fragment in the in-app Base URL.
  - Keep API key lookup at the composition edge; the 02-18 plan will inject the source-only resolver into Settings.
requirements-completed: []
requirements-pending-global: [PROVIDER-02]
coverage:
  - id: PROVIDER-02-settings
    description: A selected compatible preset can save its Base URL and model without changing its prompt, while an incomplete form disables only provider save.
    requirement: PROVIDER-02
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos and source inspection
        status: pass
      - kind: automated_ui
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: true
    rationale: No new behavior-specific test or live endpoint observation is in this milestone's scope; full provider selection and source injection are due in 02-18.
  - id: PROVIDER-02-source
    description: Settings renders a source-only label and the config plaintext warning, with the live resolver injection pending in 02-18.
    requirement: PROVIDER-02
    verification:
      - kind: other
        ref: source inspection of settings_controller.dart and settings_screen.dart
        status: unknown
    human_judgment: true
    rationale: The 02-18 composition root has not injected ApiKeyResolver, so source precedence is not yet observed on screen.
duration: 12min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 17: Provider Settings Summary

**Settings now saves a validated compatible endpoint and the selected preset's model together, with a source-only credential display ready for composition injection.**

## Performance

- **Started:** 2026-09-24T18:27:27Z
- **Completed:** 2026-09-24T18:39:05Z
- **Duration:** 12 minutes
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added a serialized provider-settings mutation that keeps the selected preset's prompt and writes its model with the compatible provider's Base URL. The existing config store still preserves only an already hand-placed API key under D-17; Settings never creates a key field or copies a keyring or environment value.
- Added Base URL and Model fields with immediate `Required` messages, URL safety feedback, and a provider-only Save guard. Hotkey and preset controls remain usable when the provider form is incomplete.
- Added a source-only Settings callback and the exact plaintext warning directly below a Config file source label. Plan 02-18 owns the resolver injection and compatible preset composition; until then, the callback is absent and the label defaults to `None configured`.

## Task Commits

1. **Task 1: Persist a validated endpoint and paired preset model** — `42e0d31` (`feat`).
2. **Task 2: Render provider form and source-only warning** — `12bdaf4` (`feat`).
3. **Rule 3 assertion compatibility: config filename display copy** — `adbf2c1` (`test`).
4. **Rule 3 assertion compatibility: hotkey-only text field check** — `fa7a99a` (`test`).

## Verification

- `dart analyze --fatal-infos` passed after each task and both assertion corrections.
- Existing Dart phase suite: 982 passed, 2 pre-existing skips.
- Existing Flutter phase suite: 165 passed, 7 pre-existing skips.
- Source inspection confirms provider selection is still singular, the model remains on `Preset` with its prompt, and the HTTP adapter owns validated destination, no redirects, bounded request and stream, and cancellation. The adapter and source resolver are not yet wired to the active compatible provider; plan 02-18 owns that composition.
- No live OpenAI, Ollama, or Secret Service outcome was observed. PROVIDER-02 remains pending until 02-18.
- D-17 preserves a user-authored config key in a whole-file rewrite. That is an owner-approved exception to the Phase 2 SPEC's literal no-write criterion; strict compliance is not claimed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Config-reader assertion matched required display copy**
- **Found during:** Phase-gate Dart suite.
- **Issue:** The source scan treated the UI-SPEC's literal `config.json` warning as another config-file reader.
- **Fix:** Removed only that exact display sentence before applying the existing scan, preserving detection for actual path access.
- **Files modified:** `test/infrastructure/config/json_config_store_test.dart`.
- **Commit:** `adbf2c1`.

**2. [Rule 3 - Blocking issue] Hotkey assertion covered unrelated provider fields**
- **Found during:** Phase-gate Flutter suite.
- **Issue:** The old assertion expected no TextField anywhere in Settings, while D-14 now requires two provider fields.
- **Fix:** Scoped the check to descendants of `HotkeyCaptureField`, where free-text hotkey entry remains prohibited.
- **Files modified:** `test/ui/settings/settings_screen_hotkey_test.dart`.
- **Commit:** `fa7a99a`.

## Known Stubs

| File | Line | Reason |
|------|------|--------|
| `lib/src/application/settings_controller.dart` | 179 | Without composition's source resolver, the display reports `None configured`; plan 02-18 injects `ApiKeyResolver.sourceForSettings` and makes keyring, environment, and config labels authoritative. |

## Next Plan

02-18 must inject the source resolver, add the compatible provider factory and selectable preset, then verify that a hand-placed key displays Config file with the warning while keyring and environment take precedence when present.

## Self-Check: PASSED

The six changed files exist and all four task/deviation commits are present in git history.
