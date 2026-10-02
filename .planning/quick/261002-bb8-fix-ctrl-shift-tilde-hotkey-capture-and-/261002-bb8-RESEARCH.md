# Ctrl+Shift+tilde hotkey research

## Cause and integration points

The capture control sends `event.physicalKey.usbHidUsage` to the injected registrable vocabulary. `HotkeyKeyCatalogue` currently lists letters, digits, F1-F12 and navigation keys, but omits usage `0x00070035`. The existing X11 probe reproduces `RESULT Backquote catalogue=UNRESOLVED`.

Add canonical label `Backquote` with that usage to the named-key table. Following the user's scope question, also add Minus, Equal, BracketLeft, BracketRight, Backslash, Semicolon, Quote, Comma, Period and Slash. Both the reverse lookup and injected vocabulary derive from this table. Add their base keysym names to `XdgShortcutTrigger`: the X11 registrar also reads that same mapping, so no platform branches or new abstraction are needed. No dependency changes.

## Source evidence

- [Flutter backquote constant](https://api.flutter.dev/flutter/services/PhysicalKeyboardKey/backquote-constant.html) identifies physical usage `0x00070035`; the installed pinned SDK agrees in `keyboard_key.g.dart`.
- [Freedesktop Shortcuts Specification](https://specifications.freedesktop.org/shortcuts/latest/) requires modifier keywords joined to an xkbcommon keysym name, using the base layer. Serialize Ctrl+Shift+Backquote as `CTRL+SHIFT+grave`.
- Installed X11 and xkbcommon headers both define `grave = 0x0060` and `asciitilde = 0x007e`. Use `grave` with Shift preserved rather than storing the shifted character as a different physical key.

## Verification and pitfalls

Pin the physical usage explicitly, preserve catalogue/serializer parity, and drive Settings with both logical `backquote` and logical `tilde` on physical `backquote`. Assert Apply reaches the hotkey port and writes the same binding to config. Exercise a real X11 grab under Xvfb with injected Ctrl+Shift+grave presses. Wayland preferred-trigger serialization is testable here; a real Wayland portal/compositor grant remains unobserved.

Keep unsupported-key and AltGr refusals intact. The 11 new labels increase the catalogue count from 63 to 74. Their usages and base keysym names were checked against the installed pinned Flutter SDK and xkbcommon headers. Do not add aliases that cause multiple canonical labels to share one physical usage. The international extra key and keypad/media keys have separate semantics and are outside this punctuation expansion.
