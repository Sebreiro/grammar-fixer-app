---
quick_id: 261002-cdz
status: human_needed
verified: 2026-10-02
---

# Verification

Source checks and automated behavioral/native/platform tests pass. The actual
AppImage was rebuilt and exercised successfully on X11 under Xvfb/openbox.
Its native executable and AOT payload match the release bundle.

Final package integrity was rechecked after the concurrent local repack:
SHA256 `a9fe8301bbb7b54118232fff84cfa235e9184a6bfd93376fbc51b6dab27cb1e2`.
The extracted native runner and AOT library still match the tested build.

| Must-have | Evidence | Result |
|---|---|---|
| Visible panel stays above ordinary windows | GTK setup + actual X11 competitor check; KWin script behavioral tests and real bus lifecycle | Implemented; real KDE pending |
| Denied activation focuses the app and clears attention | Plasma 5/6 script behavioral tests | Model verified; real KDE pending |
| Hidden startup, taskbar and dismissal preserved | Actual AppImage and bundle smoke; existing panel/controller suites | Passed on X11; real KDE pending |
| Startup/setup I/O stays off the hotkey path | Native worker setup, warm show/focus pipeline, bounded bus test | Passed |
| Owned resources are cleaned up | Native rollback/disposal/private-file tests and Flutter teardown-once test | Passed |

## Desktop observation still needed

On the affected KDE Wayland desktop, quit the old tray daemon and launch the
replacement AppImage. With another app focused, summon via both hotkey and
tray, including repeated summons and returning from minimize. Confirm the
panel appears above, accepts typing, and does not merely flash in the taskbar.
Confirm clicking away still hides it and a second hotkey press hides it.

The container has no KWin executable, so these observations and the real KDE
100 ms target are not claimed as measured. KWin's scripting service must be
accessible; this task validated the AppImage/host mechanism rather than
Flatpak's scripting-service permissions or host path mapping.
