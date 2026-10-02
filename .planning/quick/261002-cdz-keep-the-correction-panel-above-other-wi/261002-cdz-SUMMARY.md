---
quick_id: 261002-cdz
status: complete
date: 2026-10-02
source_fix_commit: 36d91b9
verification_status: human_needed
---

# Panel stacking implemented for KDE Wayland

The user confirmed the affected session is KDE Wayland and requested the panel
always appear above other windows. GTK ignores its keep-above hint on Wayland,
so the change adds an app-scoped KWin runtime script behind the existing native
presenter. It keeps the visible panel above ordinary windows, activates it on
mapping/returning from minimize/denied activation, and clears taskbar attention.
It preserves focus-loss dismissal and hotkey toggle, the existing activation
tokens, hidden startup, and the taskbar entry previously requested by the user.

KWin setup uses bounded worker-thread D-Bus calls, supports Plasma 5 and 6,
stages fixed code privately until KWin reads it, and unloads on teardown.
Startup removes the same owned script left by a prior crash. No persistent
desktop rules or settings are modified. On X11 the warm window prepares GTK's
keep-above property at startup.

## Validation

- 360 relevant pure Dart panel/application/architecture tests passed; one
  existing live-desktop placeholder remains skipped.
- 10 platform Flutter tests passed, including native-resource disposal once.
- 12 native private-bus tests passed (6 existing tray-token + 6 KWin), including
  modern/legacy paths, absent service, failure rollback, timeout and cleanup.
- 10 behavioral JavaScript tests passed for Plasma 5/6 focus, visibility,
  attention, minimizing, app identity isolation and retained taskbar eligibility.
- Analyzer, Dart formatting, diff checks and Linux release compilation passed.
- Actual release bundle and rebuilt AppImage passed Xvfb/openbox smoke checks:
  startup hidden; existing warm window above a competing raised window; keyboard
  focus; taskbar enabled without attention flag; click-away hide; three subsequent
  show/hide cycles using the same window.
- Source reviewed inline; no unresolved findings. Real KDE foreground behavior,
  taskbar animation, and CAP-1's 100 ms target still require a desktop check.

## Local delivery

Updated `build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage`
and its checksum after the candidate passed the actual-package smoke check.

Final SHA256: `a9fe8301bbb7b54118232fff84cfa235e9184a6bfd93376fbc51b6dab27cb1e2`.

A concurrent correction-variants task repackaged the same local release after
the tested candidate was installed. The final image was independently extracted
and its native runner and AOT library both match the verified build. The tested
candidate's SHA256 was `4ca00b358f32e2e687e7a4c3ad5f1ff878060671652e6b100e68197d92befa82`.

Both the native runner and AOT library match the verified release bundle.
Packaging retains the previous dependency payload and executable launcher.
Tests used private config/data directories and a private display/session bus;
no provider request was made, no existing daemon was stopped and no release was
published. Fully quit the old tray daemon before starting the replacement.

The workflow ran inline under the skill's Codex spawn restriction. The pending
real KDE observation is recorded as `human_needed`, not inferred from X11 or
the private-bus fake.
