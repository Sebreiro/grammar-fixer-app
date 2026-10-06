---
quick_id: 261006-jbt
status: complete
version: 1.1.0+2
scope: local-only
source_commit: a5789fec07b292fc2be6303745063aba75a6299b
---

# Compact focused UI integrated and released locally as 1.1

## Delivered

- `d3c940c`: squash of the complete committed compact-focused feature into dev.
  Its tree matches `57fe4a4` exactly and it has the former dev tip as sole parent.
- `a5789fe`: manifest version `1.1.0+2`, CI triggers for existing main/dev, and
  formatter-only cleanup of the existing hotkey probe.
- Main fast-forwarded to the tested dev release; completion documentation is
  committed afterward and carried to both branches through the same method.
- All work remains local, following the user's later no-push instruction. An
  earlier authentication dry-run changed no remote refs and was terminated.
- The untracked design brief, feature branch, generated SPEC, and older 1.0
  AppImage are preserved.

## Validation

- Fatal-info Dart analysis and Dart formatting: passed.
- Binding-free Dart suite: 1,118 passed, two existing skips.
- Full non-live Flutter suite: 1,474 passed, nine existing skips.
- Coverage: 5,145/5,354 lines (96.10%) and 2,079/2,310 branches (90.00%); gate passed.
- Native activation: both compiled C++ executables and ten Node tests passed.
- Changed CI workflow actionlint, prototype JavaScript syntax, release metadata,
  and source diff checks: passed.
- Linux release build: passed.
- Extracted AppImage: application code sections match the fresh release bundle;
  13 bundle resources match; 75 native dependency checks, pinned SDK/bundled CLI,
  launchers, and isolated desktop installation pass.
- Actual final-named AppImage: hidden startup, global-hotkey summon/focus, and
  second-hotkey dismissal pass on Xvfb/openbox with a private session bus and
  private XDG environment. The runtime uses extract-and-run because this
  container has no FUSE device.

## Local artifact

`build/releases/hotkey_grammar_corrector-1.1.0-linux-x86_64.AppImage`

Size: 111,954,424 bytes. SHA256:
`52216c81e4f47e65fa4cfc2bec3d34e03ceac83988705576da78034950dff3c2`.
The adjacent `.sha256` file validates the final artifact.

Quit an existing tray daemon before launching the new image so the single-instance
handoff does not reopen the older running app.

## Evidence and limits

Logs and artifact metadata are under `build/verification/261006-jbt/` and coverage
is `coverage/lcov.info`. Workflow roles were performed inline. No real provider
request, desktop installation into the user's directories, remote release, or
push was performed. Native Wayland, physical-desktop appearance, and resident
performance remain manual checks; the prior feature verification retains its
more detailed UI behavior checks. The optional lint of unchanged release.yml
is limited by installed actionlint rejecting its existing `concurrency.queue`
key; the changed CI workflow passes lint independently.
