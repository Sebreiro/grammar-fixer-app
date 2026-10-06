# Focused prototype research

## Existing implementation

`index.html` loads local classic scripts in fixtures → state → app order, so direct file opening works. `state.js` owns immutable transitions; `fixtures.js` owns sample adapters; `app.js` owns rendering and wiring. Preserve these seams and do not install dependencies.

The previous vertically stacked results violate the production layout wording recorded in the brief. Replace them with an adjacent three-column grid. Each card needs its own scrollable text region, stable footer and disabled partial-copy button. The editor must scroll independently. Below the minimum readable card width, horizontal overflow preserves adjacency instead of stacking.

## Settings integration

Keep existing element IDs and handlers. Add category containers and presentation-only navigation outside the pending-disabled fieldset. Associate mutation status with its affected group. Navigation should only change visibility, never call draft synchronization. Preserve blank-key semantics, URL validation, expected-prompt guards, requested/effective shortcut distinction and next-correction preset snapshots.

Draft synchronization on reopening currently overwrites unsaved fields. Preserve drafts across category navigation and Back/reopen; clear transient key input on leaving as before. Provider/preset commits remain existing draft synchronization boundaries.

## Verification approach

Existing Playwright and Chromium are available under `/tmp/grammar-ui-browser`; use that temporary tooling without adding repo dependencies. Exercise direct-file load, edited input/streaming/selection/copy/retry, pending and failed mutations, dirty drafts and external edits, responsive preferences navigation, long text, both themes and enlarged text. Capture screenshots and inspect them. Check protected Flutter/spec/config paths remain untouched.

## Pitfalls

- Cards must exist before the first partial without rendering canned placeholder suggestions.
- Do not re-create cards during streaming: preserve focus, scroll and button positions.
- Digit shortcuts belong only to the suggestions region; Ctrl+Enter belongs only to the editor.
- Failure replaces partial text; Retry uses submitted input rather than the later editor draft.
- Preserve literal text with `textContent`, transient credentials and sample-only effects.
- Responsive category navigation must not disable Back or discard drafts during pending saves.

No external API, library selection, production platform implementation, or unstable external facts are required; research is grounded in the local source and binding brief.
