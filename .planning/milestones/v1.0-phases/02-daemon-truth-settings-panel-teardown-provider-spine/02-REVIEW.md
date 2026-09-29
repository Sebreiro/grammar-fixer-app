---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
reviewed: 2026-09-26T10:28:45Z
depth: deep
files_reviewed: 62
files_reviewed_list:
  - lib/main.dart
  - lib/src/application/composition/controller_providers.dart
  - lib/src/application/composition/daemon_graph.dart
  - lib/src/application/correction_controller.dart
  - lib/src/application/correction_state.dart
  - lib/src/application/panel_controller.dart
  - lib/src/application/settings_controller.dart
  - lib/src/application/settings_state.dart
  - lib/src/domain/config/config_load_result.dart
  - lib/src/domain/config/config_write_conflict.dart
  - lib/src/domain/config/provider_config.dart
  - lib/src/domain/config/secret_store.dart
  - lib/src/domain/hotkey/hotkey_bind_outcome.dart
  - lib/src/domain/panel/panel_visibility.dart
  - lib/src/domain/tray/hotkey_tray_status.dart
  - lib/src/domain/tray/tray_port.dart
  - lib/src/infrastructure/config/default_app_config.dart
  - lib/src/infrastructure/config/json_config_store.dart
  - lib/src/infrastructure/config/provider_secret_fields.dart
  - lib/src/infrastructure/correction/active_correction.dart
  - lib/src/infrastructure/correction/api_key_resolver.dart
  - lib/src/infrastructure/correction/api_key_source.dart
  - lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart
  - lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart
  - lib/src/infrastructure/correction/openai_compatible/chat_completion_sse_decoder.dart
  - lib/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart
  - lib/src/infrastructure/correction/provider_registry.dart
  - lib/src/infrastructure/correction/secret_service_secret_store.dart
  - lib/src/infrastructure/correction/shared/register_tagged_stream_parser.dart
  - lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart
  - lib/src/infrastructure/panel/panel_window.dart
  - lib/src/infrastructure/panel/window_manager_panel_visibility.dart
  - lib/src/infrastructure/panel/window_manager_panel_window.dart
  - lib/src/infrastructure/system/daemon_lifecycle.dart
  - lib/src/infrastructure/system/daemon_startup.dart
  - lib/src/infrastructure/tray/tray_manager_tray.dart
  - lib/src/ui/daemon_home.dart
  - lib/src/ui/panel/correction_panel.dart
  - lib/src/ui/panel/suggestion_card.dart
  - lib/src/ui/panel/suggestion_list.dart
  - lib/src/ui/settings/hotkey_status_view.dart
  - lib/src/ui/settings/preset_choice_list.dart
  - lib/src/ui/settings/settings_screen.dart
  - pubspec.yaml
  - test/application/correction_controller_test.dart
  - test/application/settings_controller_test.dart
  - test/architecture/hidden_window_test.dart
  - test/architecture/hotkey_confinement_test.dart
  - test/architecture/panel_event_forwarding_test.dart
  - test/composition/daemon_graph_test.dart
  - test/fakes/fake_panel_window.dart
  - test/fakes/fake_tray_port.dart
  - test/infrastructure/config/json_config_store_test.dart
  - test/infrastructure/correction/active_correction_test.dart
  - test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart
  - test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart
  - test/infrastructure/panel/window_manager_panel_visibility_test.dart
  - test/infrastructure/system/daemon_startup_test.dart
  - test/ui/panel/correction_panel_layout_test.dart
  - test/ui/panel/correction_panel_selection_and_copy_test.dart
  - test/ui/settings/settings_screen_config_test.dart
  - test/ui/settings/settings_screen_hotkey_test.dart
findings:
  critical: 4
  warning: 0
  info: 0
  total: 4
status: resolved
original_status: issues_found
resolved: 2026-09-26T10:51:54Z
findings_resolved: 4
---

# Phase 02: Code Review Report

**Reviewed:** 2026-09-26T10:28:45Z  
**Depth:** deep  
**Files Reviewed:** 62  
**Status at review:** issues_found; all four findings resolved on 2026-09-26.

## Summary

Reviewed the Phase 02 code changes from `afb7a6c` through HEAD and cross-checked the `02-*-SUMMARY.md` key-file lists. Four source-proven defects affect clipboard ordering, startup hotkey truth, unsaved provider settings, and config-file credential permissions. The existing tests cover ordinary overlapping clipboard writes but do not establish what happens when an earlier platform write times out and later completes. No new test, gate, CI, native-session, or live-endpoint work was performed. The D-16 placement waiver and D-17 preservation of a user-authored config key were treated as approved constraints, not findings.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 — BLOCKER: A stale startup bind can overwrite a newer tray status

**File:** `lib/src/infrastructure/system/daemon_startup.dart:229-253`  
**Related:** `lib/src/application/settings_controller.dart:499-520`, `lib/src/application/settings_controller.dart:543-558`, `lib/src/application/composition/daemon_graph.dart:69-73`, `lib/src/application/composition/daemon_graph.dart:119-137`, `lib/src/infrastructure/tray/tray_manager_tray.dart:134-156`, `lib/main.dart:425-431`  
**Issue:** `SettingsController` explicitly accepts a compositor `bindingChanges` event before the startup `bind()` answer and declines that older answer later. The graph publishes the newer event to the tray. `DaemonStartup.bindHotkey`, however, independently calls `setHotkeyUnavailable` with its older answer before handing it to Settings. That call sets `_status = null` and may replace the tray's newer icon and cause-specific line. The subsequent `applyStartupOutcome` is a no-op, so there is no correcting emission. For example, a revocation emitted during the portal bind can leave Settings showing *revoked* while the tray shows an available hotkey. This violates SETTINGS-03's every-transition truth requirement. This is a source-ordering finding; it does not claim a native session was observed.

**Fix:** Make the Settings outcome the single authoritative startup fan-out. Apply the startup bind result as a seed, then publish `settings.trayStatus`; if a backend event already seeded Settings, publish that newer value. Remove the independent stale-result tray write from `DaemonStartup`, or generation-gate it against the same backend event counter. Keep tray writes serialized through one path.

### CR-02 — BLOCKER: Clipboard timeout breaks last-request-wins ordering

**File:** `lib/src/application/correction_controller.dart:258-272`  
**Related:** `lib/src/application/correction_controller.dart:273-305`, `lib/src/domain/clipboard/clipboard_port.dart:5-10`, `lib/src/infrastructure/clipboard/system_clipboard.dart:29-31`  
**Issue:** `_copyTail` sequences the futures returned by `_writeCopy`, but `_writeCopy` waits on `writeText(text).timeout(...)`. A timeout completes that wrapper without cancelling the platform clipboard write; the port exposes no cancellation. A later request then starts and can successfully write variant 2, after which the original platform call can finish and overwrite it with variant 1. The token only controls feedback, so the panel can say “Copied” for variant 2 while the clipboard holds variant 1. Existing slow-write tests release the first write before the second begins and do not cover a timed-out write that later lands. This violates PANEL-03 and risks replacing clipboard content with an unintended variant.

**Fix:** Keep physical writes serialized until the underlying write settles, including after the UI timeout, and report the timed-out request separately. If a platform write cannot be cancelled or guaranteed to settle, the controller cannot promise a later successful copy while that write remains outstanding; expose that limitation and suppress/queue later writes until ordering can be guaranteed. Do not let the timed-out wrapper become the queue tail.

### CR-03 — BLOCKER: Unrelated config changes erase unsaved provider fields

**File:** `lib/src/ui/settings/settings_screen.dart:112-121`  
**Related:** `lib/src/ui/settings/settings_screen.dart:319-349`, `lib/src/application/settings_controller.dart:543-558`, `lib/src/application/settings_controller.dart:561-603`  
**Issue:** A user can type a new Base URL or Model without saving. `_onStateChanged` rewrites *both* text controllers whenever any config field changes. A hotkey change (including a compositor-originated effective binding persisted to config) changes `state.config`, so it silently restores the prior URL and model even though neither provider field changed. The Save button then has no access to the user's draft. This is reachable without leaving Settings and is user-entered data loss. D-14 expressly keeps unrelated Settings changes usable; it does not authorize discarding the provider draft.

**Fix:** Re-seed each text controller only when its corresponding committed provider value or active compatible preset actually changes, and account for dirty fields before applying an external provider edit. A hotkey-only config update must leave both draft strings and cursor positions intact.

### CR-04 — BLOCKER: A Settings rewrite can widen a hand-protected API-key file's permissions

**File:** `lib/src/infrastructure/config/json_config_store.dart:302-308`  
**Related:** `lib/src/infrastructure/config/json_config_store.dart:97-104`, `lib/src/infrastructure/config/json_config_store.dart:108-133`  
**Issue:** D-17 requires preserving a hand-placed plaintext API key when Settings rewrites `config.json`. The rewrite creates a fresh scratch file with `File.writeAsString` and renames it over the original, without setting restrictive permissions or carrying over the original mode. Under a normal permissive Linux umask such as `022`, a user who protected the original config with mode `0600` can have it replaced by a `0644` file containing the preserved key. Other local accounts can then read that credential. The approved D-17 key-preservation exception does not approve widening access to it.

**Fix:** Create the scratch file with owner-only permissions atomically (`0600`) before writing sensitive content, then rename it. Preserve stricter existing permissions if applicable. Do not rely on a chmod after writing, which leaves a readable interval before the chmod completes.

---

_Reviewed: 2026-09-26T10:28:45Z_  
_Reviewer: the agent (gsd-code-reviewer)_  
_Depth: deep_

## Resolution — 2026-09-26

The original findings above remain as the historical review record. The fixes
were re-reviewed against the source and the existing regression cases after
commit `cc8bc32`; each finding passed.

| Finding | Resolution | Evidence |
|---------|------------|----------|
| CR-01 | Resolved | `9eb91a1` keeps a typed status authoritative over the startup boolean. `cc8bc32` serializes native icon/menu pushes and reconciles the latest status after an in-flight push. The existing AD-12 tray case holds a stale menu update while a revoked status arrives and checks the final menu. |
| CR-02 | Resolved | `323e807` keeps the queue tail on the underlying clipboard write after UI timeout, skips expired queued copies, and cancels feedback timers on disposal. The existing PANEL-03 case covers a late first write followed by a successful second write. A platform write that never settles leaves later copies visibly timed out; the port offers no cancellation. |
| CR-03 | Resolved | `8410afb` synchronizes Base URL and Model drafts independently, preserves dirty text and cursor positions across unrelated updates, and warns before a same-field external edit is overwritten. Existing A18 widget cases cover those paths. |
| CR-04 | Resolved | `f3caf02` creates a Linux scratch file with mode `0600` before config bytes are written and keeps stricter owner permissions on replacement. The existing CAP-12 case checks a hand-placed key and retained `0400` mode. |

Final local checks after all fixes: `dart analyze --fatal-infos` clean; existing
Dart suite 982 passed, 2 skipped; existing Flutter suite 165 passed, 7 skipped.
These checks do not establish native compositor or live provider behavior.
