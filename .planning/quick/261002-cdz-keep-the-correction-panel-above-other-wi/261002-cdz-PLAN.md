---
quick_id: 261002-cdz
mode: quick-full
must_haves:
  truths:
    - The visible panel requests keep-above on X11 and uses KWin stacking on KDE Wayland.
    - Denied activation brings only this app forward and clears attention without defeating focus-loss hide.
    - Startup remains hidden, the taskbar entry remains enabled, and teardown unloads the owned runtime script.
    - KWin setup performs bounded startup I/O outside GTK's thread and the hotkey path.
---

# Keep the correction panel above other windows

## Task 1 — Implement native stacking and lifecycle

**Files:** `lib/main.dart`, `lib/src/infrastructure/panel/gtk_panel_activation_presenter.dart`,
`linux/runner/panel_activation.cc`, `linux/runner/kwin_panel_stacking.{h,cc}`,
`linux/runner/kwin_panel_stacking_script.h`, `linux/runner/CMakeLists.txt`.

**Action:** Prepare GTK keep-above once. Install the app-scoped runtime KWin script
only when using Wayland and KWin's bus service is present. Use bounded worker
calls, private temporary storage, supported Plasma paths, and explicit cleanup.
Preserve the token presenter and panel event/lifecycle policy.

**Verify:** Behavioral script and private-bus tests, hidden-startup/lifecycle tests,
analyzer and Linux release build.

**Done:** The supported mechanisms apply without changing desktop config or
introducing I/O on the hotkey path. Commit source and regressions atomically.

## Task 2 — Verify and deliver the local build

**Files:** `test/native/kwin_panel_stacking_test.cc`,
`test/native/kwin_panel_stacking_script_test.cjs`, `tool/test_native_panel_activation.sh`,
`test/platform/gtk_panel_activation_presenter_test.dart`,
`test/architecture/hidden_window_test.dart`; quick-task artifacts and STATE.md.

**Action:** Test app identity isolation, denied activation, hide/unminimize,
Plasma path compatibility, teardown, absent service and setup failures. Smoke-test
the actual release and rebuilt local AppImage on an isolated X11 display.
Record the real KDE evidence limit, inline plan check/review, and state entry.

**Verify:** Relevant Dart/Flutter suites, native tests, `dart analyze --fatal-infos`,
`flutter build linux --release`, actual package smoke, `git diff --check`.

**Done:** Local AppImage contains the fixed native runner; artifacts accurately
distinguish measured results from the pending KDE desktop observation.

## Inline plan check

Passed: requirements covered, 2 focused tasks, files and seams grounded in the
live working tree, scope excludes providers/config/history. Real KDE acceptance
is explicitly pending rather than inferred from GTK's ignored Wayland setter.

<threat_model>
Only fixed packaged JavaScript is passed to KWin; its temporary directory is
private to the current user. Identity matching is exact and restricted to this
app's normal windows. Cleanup addresses only this app's named runtime script.
No credentials, clipboard contents, other applications, or KWin config files
enter this integration. Native startup/teardown is serialized on workers and
D-Bus calls are bounded. No unresolved high-severity threat was identified.
</threat_model>
