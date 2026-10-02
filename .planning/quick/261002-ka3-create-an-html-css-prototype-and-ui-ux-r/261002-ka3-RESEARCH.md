# Quick Task 261002-ka3 — UI Baseline Research

**Researched:** 2026-10-02 · **Domain:** static browser prototype of existing Flutter UI · **Confidence:** HIGH for source behavior; MEDIUM for browser guidance.

## User Constraints (from CONTEXT.md)

The following decisions and discretion are copied verbatim. [VERIFIED: quick CONTEXT.md, Implementation Decisions]

<!-- DATA_a79d8e41_START -->
### Prototype fidelity
- The user selected: mirror the current panel and settings as a baseline.
- Preserve existing labels, controls, ordering, action semantics, and states.
- Use the current indigo Material appearance as a reference; no new visual direction
  is chosen in this iteration. Document that a browser approximation is not a
  pixel-perfect Flutter rendering.

### Interactions
- The user selected: clickable flows with streaming, copy, retry, and settings states.
- Use clearly labeled sample data. All provider, clipboard, hotkey, config, and
  persistence effects are simulated inside the prototype.
- Keep scenario controls outside the simulated app. Do not introduce prototype
  controls into the documented production UI.

### Documentation
- Describe what belongs on both surfaces: content, actions, keyboard behavior,
  enablement, feedback, failure/recovery, persistence, and window/session behavior.
- Distinguish required SPEC behavior, current source behavior, and browser
  simulation limits. Flag conflicts rather than rewriting the spec.
- Keep the document in the repository with links from the prototype and README.

### Agent Discretion
- Choose a small, dependency-free static prototype folder and a maintainable file
  split, with an opening command that works locally.
- Use a single UI/UX reference with action/state tables and links to source evidence.
- Verify the static prototype in a real browser using temporary tooling in /tmp.
- Execute GSD agents sequentially as required by the quick workflow's Codex dispatch
  adapter; do not create a parallel worktree or change the project's configuration.
<!-- DATA_a79d8e41_END -->

**Deferred scope:** design changes and Flutter integration are deferred by the Task Boundary and Specific Ideas sections. [VERIFIED: quick CONTEXT.md, Task Boundary / Specific Ideas]

## Summary

Build the prototype from the current widgets and controller guards, with deterministic sample effects and external scenario controls. The canonical SPEC governs the product; document source differences explicitly. Existing configuration/state boundaries already provide the state model to mirror. [VERIFIED: lib/src/ui/daemon_home.dart:15-52; lib/src/application/correction_controller.dart:151-228; quick CONTEXT.md, Documentation]

**Primary recommendation:** use one static HTML entry, one stylesheet, and small classic deferred scripts for fixtures, state transitions, and DOM rendering. Use native controls and local assets; preserve indigo light/dark appearance. Proposed locations: `prototype/ui-baseline/` and `docs/UI_UX_REFERENCE.md` (new paths, recommendations rather than claims of existing files). [VERIFIED: lib/src/ui/daemon_app.dart:28-39; quick CONTEXT.md, Agent Discretion]

## Architectural Responsibility Map / Standard Stack

| Capability | Owner | Boundary |
|---|---|---|
| Editor, settings, cards, keyboard, scroll | Browser DOM/CSS | Mirror current UI behavior |
| Correction and settings transitions | Pure vanilla JS state functions | Immutable state; generation token for obsolete timers |
| Streaming, copy, config, portal, history | Fixture adapter | Sample effects only, no real backend or credentials |
| Product requirements and source differences | Repository reference | Link canonical/source evidence |

These are implementation recommendations within delegated discretion. No framework, CDN, build pipeline, or installed production package is required; package legitimacy audit is inapplicable. Classic scripts avoid the module CORS issue MDN documents for direct local-file loading. [CITED: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules]

## Current Control Inventory and Action Semantics

| Surface / control | Behavior and evidence |
|---|---|
| Panel editor and Correct | Labels **Your text**, **Correct**; tooltip **Correct (Ctrl+Enter)**. Multiline editor; whitespace disables button. Ctrl+Enter is editor-scoped, ignores repeat, supports keypad Enter; submit moves focus to suggestions. Correct may replace a running request; editing alone does not submit. [VERIFIED: lib/src/ui/panel/original_text_pane.dart:90-123; lib/src/ui/panel/correction_panel.dart:133-140,303-320; lib/src/application/correction_controller.dart:151-177] |
| Suggestions / selection | Verbatim enum `formal`, `casual`, `shorter`; labels **Corrected**, **Casual**, **Short**, in that order. Cards stack vertically. Keys 1/2/3 work in suggestions region, not editor; click selects. Repeating an already-selected key stays selected in UI. Selecting never copies; selected card scrolls into view. [VERIFIED: lib/src/domain/correction/suggestion_register.dart:1-12; lib/src/ui/panel/correction_panel.dart:148-199; lib/src/ui/panel/suggestion_list.dart:75-99,109-130] |
| Streaming / copy / failure | Running indicator and incremental card text; partials cannot select, copy, or text-select. Completed nonblank text supports mouse/keyboard/context-menu text selection. Copy has **Copying…**, **Copied**, or inline failure and leaves panel open. Failure replaces cards with selectable message and **Retry**; retry uses submitted snapshot even if editor changed, and captures current active pair for the new run. [VERIFIED: lib/src/ui/panel/suggestion_card.dart:58-79,86-183; lib/src/ui/panel/correction_error_notice.dart:25-53; lib/src/application/correction_controller.dart:180-191,541-565] |
| Settings navigation / notices | **Open settings** gutter button; Settings replaces panel inside same window, with Back. Failure then **Applying your change…** stay above separately scrolling controls; notice band is capped at half body. One mutation disables all setting changes, but Back remains usable; pending survives Back/reopen. Retry the same failed action; unrelated success does not erase failure. [VERIFIED: lib/src/ui/daemon_home.dart:129-134,170-227; lib/src/ui/settings/settings_screen.dart:167-175,241-314; lib/src/application/settings_controller.dart:867-879] |
| Close behavior / logs | First control **When closing the window**: **Close to tray**, **Quit app**. Domain values verbatim `closeToTray`, `quit`. Last control **Log file size limit**: 1/5/10 MiB plus custom committed size; source basis verbatim `defaultLogMaxBytes = 1024 * 1024` and `{mebibyte, 5 * mebibyte, 10 * mebibyte, maxBytes}`. Selection commits immediately. Native close follows committed preference; other dismissals still hide. [VERIFIED: lib/src/ui/settings/close_behavior_field.dart:18-38; lib/src/domain/config/close_behavior.dart:1-2; lib/src/ui/settings/log_size_field.dart:19-44; lib/src/domain/config/app_config.dart:44-45; lib/src/application/panel_close_controller.dart:33-50] |
| Provider / preset | **AI provider**, **Claude Agent SDK (Claude Code)**, **OpenAI-compatible (via URL)**; custom IDs remain literal. **Preset** lists ID plus provider/model. Provider activates a whole existing prompt/model preset; unconfigured compatible provider stays a setup draft until saved. Active choice is inert; changes affect next correction, not current stream. SDK shows sign-in explanation. [VERIFIED: lib/src/ui/settings/provider_choice_list.dart:31-47; lib/src/ui/settings/preset_choice_list.dart:42-73; lib/src/ui/settings/settings_screen.dart:186-200,334-358; lib/src/application/settings_controller.dart:263-266,293-315] |
| Compatible fields / API key | **Base URL**, **Model**, **Save provider settings**. Both required; URL allows HTTPS or HTTP loopback, rejecting credentials/query/fragment. Verbatim loopbacks `localhost`, `127.0.0.1`, `::1`. **API key**, **Save API key**: masked blank replacement field; blank keeps key; success clears draft and says **API key saved.**; source label and plaintext-config notice are shown. Simulate these without storing a key. [VERIFIED: lib/src/ui/settings/compatible_provider_form.dart:86-139; lib/src/domain/config/provider_config.dart:22-36; lib/src/ui/settings/api_key_field.dart:26-65; lib/src/ui/settings/settings_screen.dart:371-378] |
| Prompt / config synchronization | **Correction prompt**, **Save prompt**; active preset only, required and changed to enable save. App adds response format. External changes update clean drafts, preserve dirty drafts with overwrite warning; prompt save rejects stale active-preset/prompt snapshot. Production writes through config and consumes external edits; prototype uses a simulated committed-config snapshot. [VERIFIED: lib/src/ui/settings/correction_prompt_field.dart:30-90; lib/src/ui/settings/compatible_provider_form.dart:39-67,124-128; lib/src/application/settings_controller.dart:512-529,973-975; lib/src/ui/settings/settings_screen.dart:380-400] |

## Hotkey and Window State Fixtures

Capture labels verbatim: **Shortcut**, **Shortcut preference**, **Shortcut to request**; **Apply** submits, X11 **Keep current shortcut** abandons draft without writing. Bare Escape exits capture, not panel; repeated events are ignored; unsupported/unmodified capture retains last valid draft and explains refusal. [VERIFIED: lib/src/ui/settings/hotkey_capture_field.dart:129-182,198-209,254-269,405-432]

Represent X11 effective binding separately from saved preference. Wayland reports desktop-authored wording verbatim under **Your desktop holds this shortcut and describes it as:**; never substitute preference for missing effective information. Include not-requested, bound-without-description, retained-old-binding after refusal, and unavailable fixtures. Messages distinguish unavailable mechanism, retry another key, and setting a revoked shortcut again; tray remains entry. [VERIFIED: lib/src/ui/settings/hotkey_status_view.dart:75-95,180-217,225-286]

Verbatim visibility states `shown`, `dismissed`, `iconified`, `focusLost`: focus loss/minimize preserve editor/results/error; dismissal then summon creates blank state and seeds simulated clipboard. Hidden streams continue to completion/history. Settings Back preserves correction; native restore preserves current surface; explicit summon returns to panel. Reset hotkey capture draft on settings focus loss/view swap. [VERIFIED: lib/src/domain/panel/panel_visibility.dart:12-57; lib/src/application/correction_controller.dart:418-478; lib/src/ui/daemon_home.dart:29-52]

## Common Pitfalls / Source–Contract Differences

- CAP-4 literally says variants appear side by side; current UI stacks them. Record a wording/layout difference, not a confirmed capability failure: simultaneous readability is CAP-10's explicit requirement. [VERIFIED: _bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md:34-36,56-58; lib/src/ui/panel/suggestion_list.dart:109-131]
- CAP-14 describes toggling a visible correction panel; current source additionally returns visible Settings to panel. Document this settings-specific behavior without asserting the SPEC forbids it. [VERIFIED: _bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md:73-75; lib/src/application/panel_controller.dart:107-118]
- AGENTS says hidden panel must be able to abandon correction, while current departure logic explicitly does not cancel. Record discrepancy; do not change Flutter. CAP-2 already agrees with session restoration. [VERIFIED: AGENTS.md, §4.1; lib/src/application/correction_controller.dart:418-432; _bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md:26-28]
- Controller comments/implementation offer selection toggle, but widget guards repeated selection. Mirror visible behavior. Hotkey-status comments say mechanism hidden, but actual capture labels/current-shortcut hint distinguish regimes; inventory rendered code, not comments. [VERIFIED: lib/src/application/correction_controller.dart:207-227; lib/src/ui/panel/correction_panel.dart:174-178; lib/src/ui/settings/hotkey_status_view.dart:19-31; lib/src/ui/settings/hotkey_capture_field.dart:265-269,379-392]

## Architecture Patterns / Don't Hand-Roll / Code Examples

Recommended split: `index.html`, `styles.css`, `fixtures.js`, `state.js`, `app.js`; classic deferred scripts with a single explicit namespace. Keep scenario fixtures outside app DOM. Separate editor draft/submitted snapshot and settings draft/committed config. Cancel obsolete fixture timers using a run generation, while visibility alone keeps the run alive. Preserve caret and focus by updating text nodes instead of replacing whole form trees.

Use native textarea/input/select/button/radio controls, associated labels, visible focus, named copy buttons, and status announcements. `role="status"` provides polite status updates; avoid announcing every streamed token. Render user/sample text with `textContent`, not HTML interpolation. [CITED: https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA22] [CITED: https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent]

Browser pattern: `if (event.repeat) return;` before a scoped keyboard action; `node.textContent = suggestionText;` for safe rendering. Repeat identifies held-key repetition. [CITED: https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/repeat] [CITED: https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent]

Use bounded editor and suggestions scroll areas, wrapping long text and `min-height: 0` on flex children. Current panel splits space 2:3 above a text-scaled content floor; below floor it scrolls as a whole. Settings whole form scrolls separately from notices. [VERIFIED: lib/src/ui/panel/correction_panel.dart:69-85,335-388; lib/src/ui/settings/settings_screen.dart:274-305]

## Project Constraints (from AGENTS.md)

Keep SPEC unchanged; no production design/integration change. Human-readable names, small single-purpose functions, pure decisions separated from effects, immutable state, owned interfaces and no vendor leakage. Preserve one provider, prompt/model coupling, stateless sessions and structured history shape; no fallback, diff, primary selection, analytics or mobile work. Production settings write through; hotkey work stays behind platform seam. Capability-oriented tests; clean analyzer/format remain production merge rules. [VERIFIED: AGENTS.md, §§1-8; quick CONTEXT.md, Task Boundary]

## Validation Architecture / Environment Availability

Verified tools: Node **v20.19.6**, Python **3.12.3**, temporary Playwright **1.63.0** (environment probes this session). Orchestrator supplied downloaded Chromium; launch still needs verification. No production dependency installation. Recommended local opening: direct `index.html`, or `python3 -m http.server 8765 --bind 127.0.0.1` from repository root and open the proposed prototype URL. Browser tooling stays in `/tmp`.

Wave-0 verification: temporary browser script covering editor-scoped Ctrl+Enter/digits, partial disablement, final copy without hiding, failed-copy feedback, retry submitted snapshot, Back/reopen during pending, failed config retaining old values, provider setup/coupling, dirty external-edit warnings, hotkey fixtures, dismissal versus restore, long text and short/narrow viewport at 200% zoom. Capture screenshots; inspect overflow, keyboard focus and console errors. Existing Flutter tests are evidence pointers, not browser-prototype tests. [VERIFIED: test/ui/panel/correction_panel_selection_and_copy_test.dart and related test inventory; quick CONTEXT.md, Agent Discretion]

## Security Domain / Fixture Limits

Applicable controls: input validation and safe DOM text insertion. Authentication, session credentials, access control, cryptography, OS hotkeys, tray, keyring, SQLite and real config writes are outside the fixture adapter. Never send network requests or persist supplied API keys; copy writes only simulated clipboard. Explicitly label sample streaming and config/history so reviewers cannot mistake fixture output for provider capability, native activation, performance or compositor validation. [CITED: https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent] [VERIFIED: quick CONTEXT.md, Interactions]

## Assumptions Log / Open Questions / Sources

No locked decision depends on an unverified package or external service. Pixel fidelity and native window/compositor behavior cannot be established by this browser prototype; baseline uses source appearance, and documentation must state that limit. [VERIFIED: quick CONTEXT.md, Prototype fidelity]

Primary sources are source files linked above, canonical SPEC/companions, PLAN.md and AGENTS.md. Browser sources: MDN modules (modified 2026-08-21), KeyboardEvent.repeat, Node.textContent; W3C ARIA22. Seam selected websearch; official-source cross-check yields **MEDIUM** from `classify-confidence --provider websearch --verified`. Source inventory confidence **HIGH**; exact Flutter rendering confidence intentionally unclaimed. Research remains valid until UI/controller changes.

Evidence entry points: [SPEC](/workspace/_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md:19), [provider contract](/workspace/_bmad-output/specs/spec-hotkey-grammar-corrector/llm-provider-contract.md:5), [risks](/workspace/_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md:5), [panel](/workspace/lib/src/ui/panel/correction_panel.dart:330), [settings](/workspace/lib/src/ui/settings/settings_screen.dart:229), [correction controller](/workspace/lib/src/application/correction_controller.dart:151), [settings controller](/workspace/lib/src/application/settings_controller.dart:263), [hotkey status](/workspace/lib/src/ui/settings/hotkey_status_view.dart:73), [AGENTS](/workspace/AGENTS.md:1).
