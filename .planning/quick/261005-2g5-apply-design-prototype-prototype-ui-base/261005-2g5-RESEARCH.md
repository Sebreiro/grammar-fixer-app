# Quick 261005-2g5: Apply focused command panel — Research

**Researched:** 2026-10-05 · **Domain:** Existing Flutter desktop presentation · **Confidence:** MEDIUM (official API documentation plus source inspection; no runtime validation).

## User Constraints (from CONTEXT.md)

<!-- DATA_R7k2N9q4_START -->
### Locked user decision

The user explicitly chose: “suggestions should be one below another - same as in prototype”. Implement stacked suggestions. This instruction overrides CAP-4's side-by-side layout wording for this task. Preserve CAP-4's three variants and scoped selection shortcuts. Record the discrepancy; never hand-edit the generated SPEC.

### Established design

- Match the prototype's neutral light/dark surfaces, restrained blue accents, compact header/editor, explicit Copy actions, five-line previews and full-text expansion.
- Apply General / AI / Advanced settings navigation, with a compact selector at narrow widths.
- Follow the system theme. Preview-only scenario and appearance controls do not belong in production.
- Preserve true streaming, original/variant concurrent readability, explicit exact-text copy, retry input snapshots, config write-through, hotkey authority, and pending/failure recovery.
- Preserve unsaved provider and prompt drafts across category navigation and Back/reopen; unsaved API key input clears on leaving, as disclosed in the prototype.

### Agent discretion

Flutter widget composition, responsive sizing, keyboard/accessibility details, and test updates can follow existing project conventions and the prototype. Keep platform work behind current seams; perform no native resizing or I/O in build methods or hotkey show paths.
<!-- DATA_R7k2N9q4_END -->

No deferred-ideas section exists in the task context. [VERIFIED: task CONTEXT source, lines 1–36]

## Summary

Restyle the existing presentation and extend its draft lifetime; retain the correction/configuration controllers. The editor already sits above a stacked suggestion list, with independently bounded regions and scoped shortcuts. [VERIFIED: lib/src/ui/panel/correction_panel.dart:349–451; lib/src/ui/panel/suggestion_list.dart:109–131] The significant behavior change is preserving non-secret Settings drafts across screen unmounts: the current home swaps screens and each form disposes its editing controllers. [VERIFIED: lib/src/ui/daemon_home.dart:170–174; lib/src/ui/settings/compatible_provider_form.dart:70–74; lib/src/ui/settings/correction_prompt_field.dart:40–43]

**Primary recommendation:** Implement theme/header/compact rows first, then categorized Settings with an explicit persistent presentation draft owner above the home view swap, and finally behavioral verification.

## Project Constraints (from AGENTS.md)

Use the existing Flutter/Linux architecture and Riverpod approach; constructor injection and inward dependencies; one public type per file; readable names, small functions, guard clauses, pure decisions separated from I/O. Keep widget builds pure and dispose owned resources. Use immutable values, sound null safety, exhaustive state handling, awaited or visibly discarded futures, no broad swallowed failures, and no new service locator. Preserve provider stream/failure/cancellation seams, one active provider, prompt/model pairing, stateless requests and the shared history suggestion shape. Preserve write-through Settings and prebuilt hidden-window startup. No fallback providers, fake suggestions, webview, remote history, non-goal features or generated SPEC edits. Run formatter and clean analysis; test capability behavior through current fakes with CAP IDs. [VERIFIED: AGENTS.md, sections 1–9]

## Architectural Responsibility Map

| Capability | Owner | Boundary |
|---|---|---|
| Theme, categories, previews, expansion, drafts | Flutter presentation | Forward commands; perform no persistence |
| Correction, exact copy, Retry snapshot | Existing application controller | Preserve state/event semantics |
| Settings mutation slot, config/key writes | Existing Settings controller | Navigation never creates another mutation slot |
| Initial native bounds | Existing startup composition | Hidden-window setup only |

These assignments follow current controller/UI separation. [VERIFIED: lib/src/ui/panel/correction_panel.dart:310–327, 424–442; lib/src/ui/settings/settings_screen.dart:167–207; lib/main.dart:728–744]

## Standard Stack / Don't Hand-Roll

Keep the installed SDK and dependencies; no installation or package audit is needed. Verbatim manifest values: `sdk: ^3.12.2`, `flutter: '>=3.44.8'`, `flutter_riverpod: 3.4.2`, `window_manager: 0.5.2`, `test: 1.31.0`; widget tests use `flutter_test` from the SDK. [VERIFIED: pubspec.yaml:8–9, 35–46] The local version probe reports Flutter 3.44.8 / Dart 3.12.2. [VERIFIED: flutter --version, this session]

Use Flutter text layout and an in-window overlay; reuse config validators, controller copy, hotkey capture/status and failure notices. Do not reproduce the prototype's simulated provider/configuration effects. [VERIFIED: prototype/ui-baseline/README.md:37–43; lib/src/ui/settings/compatible_provider_form.dart:86–90]

## Architecture Patterns / Code Examples

**Tokens and structure.** Use explicit light/dark schemes rather than seed-derived colors. Verbatim light tokens: `--surface: #ffffff; --editor: #f6f7f9; --foreground: #252a34; --muted: #626b7a; --primary: #3458c9; --outline: #e0e4eb; --selected: #f3f6ff;`. Dark counterparts: `--surface: #1e222a; --editor: #252a33; --foreground: #edf0f6; --muted: #abb4c4; --primary: #a9beff; --outline: #373e4a; --selected: #2a3349;`. [VERIFIED: prototype/ui-baseline/styles.css:4–12, 22–30] Keep system theme mode, already `themeMode: ThemeMode.system`. [VERIFIED: lib/src/ui/daemon_app.dart:28–39]

Move Settings into the compact header, eliminate its editor gutter, integrate Correct and its shortcut hint into the editor surface, and give results a compact heading/status. Prototype literals: header `padding: 6px 10px;`, content `gap: 10px; padding: 10px;`, editor `padding: 6px 8px;`, row `padding: 6px 8px; border-radius: 6px;`, results `gap: 4px;`. [VERIFIED: prototype/ui-baseline/styles.css:321–327, 357–364, 390–400, 461–483]

**Rows and expansion.** Layout label/shortcut, preview and visible Copy action together; put Copying/Copied in the button and retain inline selectable failures. Preserve actual register identities: `formal, casual, shorter;` and labels `formal => 'Corrected', casual => 'Casual', shorter => 'Short'`. [VERIFIED: lib/src/domain/correction/suggestion_register.dart:2–12] Five-line clamp is literally `-webkit-line-clamp: 5;`; narrow rows switch at `@container (max-width: 460px)`. [VERIFIED: prototype/ui-baseline/styles.css:514–529, 1062–1081]

Measure overflow using `TextPainter` after `layout`, with matching width/style/direction/scaler and `maxLines`, then read `didExceedMaxLines`; never truncate the authoritative string supplied to copy. The API reports omitted lines only after layout. [CITED: https://api.flutter.dev/flutter/painting/TextPainter/didExceedMaxLines.html] Render full selectable text in an overlay above existing rows, bounded to the application viewport, with Show less, outside-click and Escape dismissal plus focus restoration. `OverlayPortal` inherits its owner's theme and cannot outlive it. [CITED: https://api.flutter.dev/flutter/widgets/OverlayPortal-class.html] Close expansion on submit, screen swap and source replacement. Prototype opens expansion only after completion and retains full text in both views. [VERIFIED: prototype/ui-baseline/app.js:146–180, 386–390]

**Settings lifetime.** General owns close behavior and shortcut; AI owns provider/preset, URL/model and credential controls; Advanced owns the active-preset prompt and log size. Navigation switches to a selector at literal `@container (max-width: 680px)`. [VERIFIED: prototype/ui-baseline/index.html:223–396; prototype/ui-baseline/styles.css:1043–1060] Hold non-secret drafts in a small UI value owner above the screen swap; pass draft values/change callbacks into fields. Preserve existing clean/dirty external-update rules and prompt preset identity, including stale-save protection. [VERIFIED: lib/src/ui/settings/compatible_provider_form.dart:39–68; lib/src/ui/settings/correction_prompt_field.dart:30–37; lib/src/ui/settings/settings_screen.dart:380–392] Keep API-key controller local and recreate/clear it on leaving Settings; category changes alone should preserve it, matching prototype behavior. Prototype disclosure: “Unsaved key input is cleared when you leave Settings.” Back literally executes `byId("api-key").value = ""`. [VERIFIED: prototype/ui-baseline/index.html:339–341; prototype/ui-baseline/app.js:414–416]

**Feedback.** Reuse the controller's global mutation guard and committed values. Current failures contain only `kind`, `message`, `previousShortcutWorks`; no group identity is present, so do not guess the affected group from error text. Keep a visible global recovery notice alongside optional presentation-owned group attribution. Never disable category navigation or Back while pending. [VERIFIED: lib/src/application/settings_state.dart:27–36, 126–154; lib/src/ui/settings/settings_screen.dart:229–299]

**Native size.** Change the startup preferred size to the prototype standard while retaining display clamping and scaled content minimum. Current verbatim expressions: `Size(480, minimumHeight)` and `Size(640, math.max(520.0, minimumHeight))`; startup calls `setMinimumSize`, `setSize`, `setPosition` before showing. [VERIFIED: lib/main.dart:737–744, 776–807] Prototype standard literals are `width: 840px; height: 650px;`. [VERIFIED: prototype/ui-baseline/styles.css:276–279] The runner's `gtk_window_set_default_size(window, 1280, 720);` is subsequently overridden; changing that alone has no lasting effect. [VERIFIED: linux/runner/my_application.cc:51; lib/main.dart:743] Keep manual user resizing; preview size presets are review controls, not production features.

## Common Pitfalls / Validation Architecture

Preserve the original editor's caret echo guard; completed selectable text, genuine partial streaming, disabled partial copy/selection, digit scoping, exact-copy stay-open behavior and Retry submitted-input snapshot. Keep independent result scrolling; selected-row reveal must scroll only the result viewport. [VERIFIED: lib/src/ui/panel/original_text_pane.dart:63–74; lib/src/ui/panel/suggestion_card.dart:179–183; lib/src/ui/panel/suggestion_list.dart:94–99; prototype/ui-baseline/README.md:29–31]

Use existing widget harnesses and update tests to navigate the correct category before interacting. Existing tests assume specific button types and flat Settings; preserve their behavior claims when changing finders. [VERIFIED: test/ui/panel/correction_panel_layout_test.dart:44–64; test/ui/settings_harness.dart:27–43] Add behavior coverage for stacked compact rows, measured five-line expansion without moving siblings, full copy from both views, Escape/outside close and focus return, narrow/large-text layouts, category and Back/reopen draft preservation, clean/dirty config edits while away, API-key clearing, and pending/failure surviving navigation. Re-measure the panel floor after adding the header; its current literal is `minimumPanelHeight = 300`. [VERIFIED: lib/src/ui/panel/correction_panel.dart:58–85]

Quick command: `flutter test --exclude-tags=live test/ui`. Broader gate: run existing application/controller and UI/platform/composition suites, `dart format`, `dart analyze --fatal-infos`, and a Linux build when native startup geometry changes. Preserve CAP-3/4/5/10/11/13/14 behavior tests and CAP-8/12 write-through/hotkey tests. These are verification recommendations; runtime checks were not executed by this researcher.

## Security Domain / Runtime State Inventory

Keep credentials outside persistent presentation drafts, masked and never prefilled from storage; preserve HTTPS/loopback endpoint validation and current plaintext-fallback disclosure. [VERIFIED: lib/src/ui/settings/api_key_field.dart:5–6, 40–51; lib/src/ui/settings/compatible_provider_form.dart:86–90; lib/src/ui/settings/settings_screen.dart:371–378] Applicable control review: input validation and secret handling; this presentation task introduces no authentication/session/authorization or cryptographic mechanism.

Stored data, live service config, OS registrations, secrets/environment names and installed artifacts: no rename/migration is planned in any category. Existing clipboard/history/config/keyring/hotkey identifiers remain unchanged; this inventory is scope classification, not a live external-state audit.

## Assumptions Log / Open Questions / Sources

No new load-bearing product assumptions. Retain the existing test that discards a prompt draft when changing preset; category/Back preservation does not authorize changing preset-switch behavior. [VERIFIED: test/ui/settings/correction_prompt_settings_test.dart:111–125] The current architecture allows hidden correction streams to continue, while AGENTS requests cancellation on hide; preserve existing behavior for this UI task and report the existing discrepancy rather than changing lifecycle policy. [VERIFIED: lib/src/ui/panel/correction_panel.dart:27–30; AGENTS.md section 4.1]

Primary evidence is the opened repository sources cited above; the two official Flutter API links establish layout/overlay patterns. Documentation lookup seam requested Context7; unavailable provider tools were replaced by official Flutter documentation. No new package, environment setup, database migration or broad ecosystem research is required. Installed Flutter was probed; real-compositor visual behavior remains executor/manual verification.
