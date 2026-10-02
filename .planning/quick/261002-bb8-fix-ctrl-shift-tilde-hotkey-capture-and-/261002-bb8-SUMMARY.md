---
quick_id: 261002-bb8
status: complete
date: 2026-10-02
source_fix_commit: d27914d
verification_status: passed
---

# Ctrl+Shift+tilde and punctuation hotkeys supported

The shared key catalogue omitted the physical backquote key, so Settings refused Ctrl+Shift+~ before contacting either backend. Following the user's question about supporting all keys, the fix adds all 11 standard punctuation keys to the existing physical-usage and base-keysym tables. The catalogue now has 74 distinct keys. Ctrl+Shift+~ is stored and displayed as Ctrl+Shift+Backquote.

The existing physical-key model handles shifted characters without creating duplicate labels. Settings Apply still binds through the selected adapter and writes through to config. Unsupported keys, modifier-only presses, bare-key and AltGr capture guards stay in place. Keypad, media and extra international keys need separate support beyond this punctuation expansion.

## Validation

- Baseline CAP-12 regressions failed with missing Backquote usage/keysym; the existing X11 probe reported `catalogue=UNRESOLVED`.
- 389 pure Dart hotkey/architecture tests passed; one existing desktop-observation placeholder remains skipped.
- 93 Flutter Settings tests passed, including 22 capture/save cases for base and shifted punctuation.
- `dart analyze --fatal-infos`, formatting and `git diff --check` passed.
- The actual X11 registrar delivered all 33 injected Ctrl+Shift+punctuation presses under Xvfb.
- Linux release build succeeded.
- The actual rebuilt AppImage showed and focused its panel on Ctrl+Shift+grave, and hid it on a second press, under Xvfb/openbox with temporary config. The direct release bundle and extracted AppRun also passed.
- Code review completed inline with no unresolved findings. Wayland serialization and adapter suites passed; no real Wayland compositor grant was observed.

## Delivered build

Updated local artifact:

`build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage`

SHA256: `b63720621bb5b7667e5bc387e24b1321cdb777f95c20d17253a9bdddecd67d7d`.

The candidate was smoke-tested before atomically replacing the existing release and checksum. Its AOT library matches the current release bundle. Packaging preserved the prior dependency payload and executable launcher mode. Temporary test configuration was separate from user configuration; no correction/provider request was made and no release was published. Fully quit the old tray daemon before launching the replacement.

The first packaged probe revealed a generated launcher permission error, fixed by preserving mode 0755. A later probe restart during AppImage initialization was inconclusive; preseeded temporary configuration and a single launch produced the successful actual-package observation. GTK's helper window was excluded from the observed panel.
