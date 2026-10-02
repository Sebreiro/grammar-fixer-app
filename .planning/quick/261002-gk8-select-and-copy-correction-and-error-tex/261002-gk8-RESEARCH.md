# Quick Task 261002-gk8 — Research

## Recommendation

Use Flutter's built-in `SelectableText` for completed suggestion bodies and inline errors. It renders read-only text, manages its own focus/controller lifecycle, supports mouse selection, and exposes the standard desktop keyboard actions and adaptive selection toolbar. No package or custom selection system is needed.

Sources: [SelectableText](https://api.flutter.dev/flutter/material/SelectableText-class.html), [contextMenuBuilder](https://api.flutter.dev/flutter/material/SelectableText/contextMenuBuilder.html), and the installed Flutter implementation at `/home/vscode/flutter/packages/flutter/lib/src/material/selectable_text.dart`.

## Integration

- `SuggestionCard` renders correction text with `Text` inside an `InkWell`. Replace only authoritative nonblank suggestion bodies with `SelectableText`; forward a simple tap to the existing register-selection callback so mouse selection does not remove the current card-selection interaction.
- Preserve plain `Text` for streamed partials and blank results. Existing AD-3 tests forbid copying an unauthoritative partial.
- `CorrectionErrorNotice` renders the provider failure inside a live-region `Semantics` and an unbounded-safe scroll view. Retain both wrappers and the Retry action when replacing its `Text`.
- Copy failures are shown in `SuggestionCard`; make those selectable as well, retaining plain progress/success status text.
- The original editor already delegates native selection/copy to Flutter's text-control infrastructure. Follow that pattern without adding direct clipboard calls to widgets; whole-suggestion copy continues through `CorrectionController` and `ClipboardPort`.

## Verification Pitfalls

- Test Linux pointer behavior explicitly: framework widget tests otherwise default to a mobile target.
- Drag actual mouse gestures and capture the framework platform clipboard channel to assert the copied substring. Do not prove copying by assigning a text controller's selection directly.
- Check right-click preserves an existing selection, Ctrl+A/C copies the entire message, and typed keys cannot alter result/error text.
- Existing panel tests cover long-text/narrow-window layout, register shortcuts, streaming, retry, copying, and live-region semantics. Run them after replacement to expose framework semantics or focus differences.
- X11/Wayland compositor observations cannot be inferred from widget tests; native framework interaction is covered, and live desktop checks remain unobserved.
