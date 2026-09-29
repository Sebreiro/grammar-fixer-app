# Deferred items observed during 02-06

- 2026-09-24, commit `aa2b21e`: the existing Dart phase-gate suite failed in `test/application/settings_controller_test.dart` (18 failures in the full run; a focused rerun reported six). The existing Flutter phase-gate suite failed in two `test/ui/settings/settings_screen_hotkey_test.dart` cases: A1 AD-10 effective X11 binding and A4 AD-10 requested-versus-effective wording. These are Settings paths from 02-02; no Settings source was changed by 02-06. The 02-06 panel layout regression seen in the first Flutter run was fixed in `aa2b21e`; the focused panel layout and DaemonHome tests pass.
  status: resolved
  resolution: Later Settings repairs and the final Phase 02 suite cleared these failures. The final tree passed 982 Dart tests with 2 skipped, 165 Flutter tests with 7 skipped, and `dart analyze --fatal-infos`; see `02-VALIDATION.md`. The original 02-06 failure remains recorded above.
