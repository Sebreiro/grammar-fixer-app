---
phase: "02"
slug: "daemon-truth-settings-panel-teardown-provider-spine"
status: approved
shadcn_initialized: false
preset: none
created: "2026-09-24"
reviewed_at: "2026-09-24"
---

# Phase 02 — UI Design Contract

> Visual and interaction contract for the existing Flutter desktop daemon. The locked Phase 02 SPEC and D-01–D-15 decisions take precedence over this contract. Wave D and Wave F have no new screen.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | Flutter Material 3; shadcn is not applicable to this Flutter project |
| Preset | Existing `ThemeData` and `ColorScheme.fromSeed(seedColor: Colors.indigo)` in `daemon_app.dart`; `ThemeMode.system` |
| Component library | `package:flutter/material.dart`; retain existing `Scaffold`, `Card`, `TextField`, `ListTile`, and button patterns |
| Icon library | Flutter Material `Icons`; retain the shipped tray icons |
| Font | Flutter's platform Material font; no bundled or new font |

Source: `lib/src/ui/daemon_app.dart` and current UI widgets. Keep the single warm Flutter window and its light/dark behavior. No web or registry components are introduced.

---

## Component Inventory

Enumerated by `rg '^class [A-Z][A-Za-z0-9_]* extends (StatelessWidget|StatefulWidget)' /home/vscode/flutter/packages/flutter/lib/src/material -g '*.dart' | wc -l` — 109 components — flutter@3.44.8 — 2026-09-24.

This is a non-exhaustive list of known-good Material widgets, not an allowlist. The count is of public widget classes directly extending `StatelessWidget` or `StatefulWidget` in the installed Material source; other exported components remain available. `flutter --version --machine` supplied the resolved version.

| Component | Import path | Phase use |
|-----------|-------------|-----------|
| `Scaffold`, `AppBar` | `package:flutter/material.dart` | Existing panel and Settings shells |
| `TextField`, `InputDecoration` | `package:flutter/material.dart` | Editor, Base URL and Model fields |
| `Card`, `ListTile` | `package:flutter/material.dart` | Suggestion variants and preset choices |
| `ElevatedButton`, `TextButton`, `IconButton` | `package:flutter/material.dart` | Correct, Retry, Copy, Back and Settings |
| `CircularProgressIndicator`, `LinearProgressIndicator` | `package:flutter/material.dart` | Real copy and correction progress only |
| `Tooltip`, `Semantics` | `package:flutter/material.dart` | Shortcut and action names, live feedback |
| `SingleChildScrollView` | `package:flutter/material.dart` | Existing bounded panel and Settings overflow |

---

## Spacing Scale

The design scale uses only the tokens below, in logical pixels. Preserve the shipped 12 px panel, Settings and notice insets as a legacy layout exception; do not use 12 px as a token for new spacing.

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4 px | Label to field, compact status gap |
| sm | 8 px | Card inset, editor to suggestions gap, status to Copy gap |
| md | 16 px | Provider form field gap |
| lg | 24 px | Settings section divider and group break |
| xl | 32 px | Major section break when space permits |
| 2xl | 48 px | Large screen separation only |
| 3xl | 64 px | Reserved; do not add empty space inside the 640 × 520 panel |

Exception: the existing panel and Settings outer insets and notice inset remain 12 px to preserve the shipped layout. New spacing uses only the scale above. Interactive icon hit areas are at least 40 × 40 logical px; the shipped 18 px Copy glyph remains inside its button hit area. Source: existing 4/8/12/24 px UI spacing; 16/32/48/64 are defaults for the added form.

---

## Typography

Use the existing Material font and text theme roles. These are the four target sizes and two weights for any new text; preserve platform text scaling and do not force a fixed scale.

| Role | Size | Weight | Line height | Use |
|------|------|--------|-------------|-----|
| Caption | 12 px | 400 | 1.33 | Key-source detail, validation and copy status |
| Label | 14 px | 500 | 1.4 | Field labels, card register and button labels |
| Body | 16 px | 400 | 1.5 | Editor text, suggestions, status and errors |
| Heading | 20 px | 500 | 1.2 | Settings section heading where needed |

Use `Theme.of(context).textTheme` and the closest existing role; do not replace `ThemeData` to force exact pixels. Source: current `bodySmall`/`bodyMedium`/`bodyLarge`, `labelMedium`, and `titleSmall` use; numeric sizes and line heights are design defaults.

---

## Color

Flutter generates actual light and dark colors from the existing indigo seed `#3F51B5`. Bind widgets to semantic `ColorScheme` roles so the same contract adapts to the system theme; do not hardcode a light-only surface hex.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `colorScheme.surface` | Panel, Settings and editor surroundings |
| Secondary (30%) | `colorScheme.surfaceContainerLow` / default `Card` surface | Suggestion cards, form group and notices |
| Accent (10%) | `colorScheme.primary` and `primaryContainer`, derived from `#3F51B5` | Correct action, selected suggestion highlight and check, focused field and active preset |
| Destructive / error | `colorScheme.error` | Failed copy, provider/Settings error and Required validation only |

Accent is reserved for the selected variant, active preset, primary Correct action and keyboard focus. Neutral controls remain neutral. The existing tray warning asset signals unavailable shortcuts; do not recolor it at runtime. Selection must remain recognizable without color via a check mark. Source: `daemon_app.dart`, `suggestion_card.dart`, existing error notices; 60/30/10 distribution is a visual default.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Panel primary CTA | `Correct` (retain shipped label and `Correct (Ctrl+Enter)` tooltip) |
| Provider form CTA | `Save provider settings` |
| Empty panel heading | `No suggestions yet` |
| Empty panel body | `Type or paste text, then press Correct.` |
| Provider validation | `Required` immediately below an empty Base URL or Model field |
| Copy pending | `Copying…` beside the affected card's Copy button, with a spinner |
| Copy success | `Copied` beside the affected card's Copy button |
| Copy failure | `Couldn't copy this suggestion. Try again.` beside the affected card's Copy button |
| Empty copy refusal | `There is no suggestion text to copy.` on the affected card if a stale action reaches the controller |
| Provider error | `This provider is unavailable. Add a Base URL and Model in Settings, then retry.` when those values are missing; other provider errors retain an actionable adapter-authored message and the existing `Retry` action |
| API key source | `API key source: System keyring`, `API key source: Environment variable`, `API key source: Config file`, or `API key source: None configured` |
| Config key warning | `This API key is stored as plaintext in config.json. Move it to your system keyring or environment.` |
| Tray action | `Open the panel` (always enabled), followed by one status line when needed, then `Quit` |
| Tray: no backend | `This desktop has no global shortcuts. Open the panel from this menu.` |
| Tray: refused, no working shortcut | `That shortcut was refused. Open the panel from this menu.` |
| Tray: revoked | `Your desktop removed the shortcut. Open the panel from this menu.` |
| Tray: refused rebind, old shortcut works | `The new shortcut was refused; the previous shortcut still works.` Show only while Settings shows the same refusal; keep normal icon |
| Destructive confirmation | `Quit`: no confirmation, as shipped. An unapplied hotkey draft is discarded on view swap; reopening Settings shows the effective shortcut, with no confirmation dialog. |

The copy strings above come from D-04–D-15 where specified; the remaining wording is a design default. Never show an API key value or raw exception text. Do not add a restart caveat after a preset selection: SETTINGS-01 makes the next correction use it.

`Correct` is an intentional exception to the verb-plus-noun CTA convention: retain the shipped one-word button label and its `Correct (Ctrl+Enter)` tooltip so the existing panel action stays recognizable.

---

## Screen and Interaction Contract

### Panel and window

- The editable original text is the panel's primary visual anchor and first point of attention: place its outlined field in the upper 40% of the normal-size panel. The primary `Correct` action follows the editor; the suggestion cards occupy the lower 60%, with the selected card's highlight and check guiding attention to the active result. Keep Settings visually secondary in its separate header or gutter.
- Open at approximately 640 × 520 logical px. Prefer a 480 × 360 logical px minimum at text scale 1.0; at larger text scales, preserve `CorrectionPanel.minimumPanelHeightFor` as the readability floor. On a smaller display, shrink to fit and allow whole-panel scrolling below the readability floor. If display geometry is unreadable, use the chosen default geometry and complete startup. Under D-16's owner-approved waiver, prepare best-effort centering from startup or cached geometry while hidden; ordinary Wayland toplevel placement remains compositor-controlled. The hotkey path only toggles visibility and does no placement I/O. Verification must label exact current-pointer placement unproven.
- Keep the existing 2:3 vertical editor/suggestions split at the normal size (40%/60%). The original editor and at least one correction remain readable together at or above the effective minimum. Long editor text scrolls within the editor; suggestions scroll within their own region. At smaller sizes, scroll the panel as a whole rather than clip text or actions.
- Put the Settings `IconButton` outside the editor's hit bounds, in a separate header or aligned gutter. Every pixel inside the outlined editor reaches its text field. Preserve the editor text byte-for-byte across summon, focus loss, click-away and minimize/restore orderings. Do not take focus back after the user has clicked another app.
- Pressing the hotkey while Settings is visible leaves the window visible and returns to the panel. If no panel session exists, show the empty panel state. The next hotkey on the panel retains the normal visibility toggle. A view swap discards an unapplied hotkey draft; reopening Settings shows the effective binding.

### Suggestion variants and copying

- Keep three register cards in stable register order. During a real correction stream, show the existing linear progress indicator and only actual received text; do not render canned suggestions or skeleton text. Copy and selection stay disabled until a completed, nonblank suggestion is present.
- A click anywhere on a card outside its Copy action selects the same variant as the card's displayed key hint. Clicking the selected card does nothing. Selection adds the existing `primaryContainer` highlight and a visible check mark; it never writes to the clipboard. Scope digit keys to the suggestions region so typing digits in the editor remains text. The rendered key hint must name the key actually accepted on non-QWERTY layouts.
- The Copy button remains a separate, named action on each card. Show a spinner and `Copying…` adjacent to the requesting card's button while its write is pending. Keep Copy buttons operable during a write; a later request supersedes earlier feedback, including an earlier request for identical text. Only the latest request may show `Copied` after its write completes. Keep `Copied` until the next copy request or correction. A failed or hung write never shows success; show card-local failure. The panel remains open after copying.
- Card status is a polite semantics live region that names its register, such as `Formal suggestion copied`; the Copy button tooltip continues to name the register. Preserve visible focus and the selected check for keyboard and assistive technology users.

### Settings, provider and tray

- Keep Settings as the existing scrolling view inside the warm window. Keep failure and pending notices visible above the scrolling controls, with their current half-height cap and failure-first order. Retain the existing effective-shortcut read-out, desktop-authored Wayland wording, and cause-specific Settings explanations. A refused rebind must show the shortcut still in effect; do not claim the requested one is active. Under D-18, once Wayland reports an effective binding, the persisted value replaces the requested preference rather than keeping both.
- Preset choices remain the way to select a provider: each row shows preset id, provider id and model. A selection writes through to config and serves the next correction. An in-flight correction keeps its captured preset. Remove the shipped sentence that says a restart is required.
- In the OpenAI-compatible provider flow, label editable fields `Base URL` and `Model`. The Model field edits the model member of the selected prompt-and-model preset; do not invent a provider-only model value or separate provider-specific selection branch. Show `Required` immediately under either empty field and disable only `Save provider settings` until both are filled. Hotkey editing and preset selection remain usable. For a hand-edited incomplete config, startup continues and the first correction reports the actionable inline provider-unavailable message with `Retry`.
- Directly under the provider controls, always show the winning API-key source in the order keyring → environment → config, or `None configured`. If config wins, show the plaintext warning directly beneath that line. Never render the key value or offer an in-app action to create one in config. Under D-17, a later Settings save preserves a key the user hand-placed there; this is an owner-approved exception to the phase spec's literal no-write wording.
- In the tray, show the existing warning icon and exactly one disabled, plain-language cause line immediately below `Open the panel` when the shortcut is unavailable. Keep `Open the panel` and `Quit` enabled. A refused new binding with an old working shortcut keeps the normal icon and shows its temporary refusal line only while Settings shows that refusal. On restoration, remove the line and warning icon immediately, without a toast or desktop notification.

---

## UI Considerations

Applicable state considerations resolved: 8 covered, 0 backstop, 0 unresolved. This is an interaction-state contract, not a request for new tests, gates or CI work; Phase 02 explicitly excludes those.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| Empty | Panel editor and suggestion list | ✅ covered | Empty editor disables Correct and renders the Copywriting Contract's empty state; the three register slots stay stable and nonactionable. |
| Loading | Correction and per-card Copy | ✅ covered | The existing linear indicator marks real correction work; the latest copy request alone gets a card-local spinner and `Copying…`. |
| Error | Provider correction, copy and Settings mutation | ✅ covered | Provider failure replaces suggestions with an inline message and Retry; copy failure stays on its card; Settings failure remains visible above scrolling controls. |
| Populated | Three suggestion cards and preset choices | ✅ covered | Show variants in register order; selected card has highlight plus check; preset rows show id, provider and model. |
| Partial | Streamed variants and incomplete provider form | ✅ covered | Stream only received text and disable actions until authoritative completion; empty Base URL or Model gets immediate `Required` and guards only provider save. |
| Overflow | Panel, suggestions, Settings, notices and tray copy | ✅ covered | Editor and suggestion regions scroll independently; undersized panel and Settings scroll; notices retain a half-height cap; tray uses one compact cause line. |
| Zero / one / many | Suggestion text and provider presets | ✅ covered | Zero suggestions uses the empty copy; one or more real variants keep stable card order and individual actions; preset list renders each configured option without inventing choices. |
| Long text | Editor, suggestion bodies, provider URL, status and errors | ✅ covered | Preserve and scroll complete user text; wrap card/status/error copy, scroll small regions as needed, and keep Copy, Retry and form controls reachable. |

D-01's exact current-pointer placement conflicts with CAP-1's I/O-free hotkey path and ordinary Wayland toplevel positioning. The owner accepted the D-16 best-effort waiver on 2026-09-24. The planner must preserve that limit and avoid claiming exact placement.

---

## Registry Safety

| Registry | Blocks used | Safety gate |
|----------|-------------|-------------|
| Not applicable — Flutter Material SDK | None | No shadcn or third-party registry blocks are used |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: FLAG — shipped `Correct` label retained intentionally
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS
- [x] Dimension 7 Inventory Provenance: PASS

**Approval:** approved with one non-blocking copywriting flag
