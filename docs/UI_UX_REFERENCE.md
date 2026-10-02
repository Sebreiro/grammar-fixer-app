# Current correction panel and settings UI and UX reference

This reference records the existing Flutter baseline so a later design can preserve its actions and state behavior. Open the [clickable sample](../prototype/ui-baseline/index.html) and [review guide](../prototype/ui-baseline/README.md). The sample uses in-memory effects; its external scenario controls are not production UI.

The [SPEC](../_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md#capabilities) defines required behavior. The [provider contract](../_bmad-output/specs/spec-hotkey-grammar-corrector/llm-provider-contract.md), [risks](../_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md), [roadmap](../PLAN.md) and [coding rules](../AGENTS.md) remain authoritative. The tables below describe observed source behavior, not changes to those documents.

## Appearance and layout

The [app theme](../lib/src/ui/daemon_app.dart#L28) derives both system light and dark palettes from indigo. The sample approximates Material colors, rounded cards, outlined fields and filled actions with local CSS and system fonts; it is not a pixel-perfect Flutter rendering.

The [panel layout](../lib/src/ui/panel/correction_panel.dart#L335) reserves a top-right settings gutter and divides the editor/results region 2:3, with 12 px content padding. Above a text-scaled minimum height, both panes remain concurrently readable and scroll independently (CAP-10). Below that floor the entire panel scrolls. Cards stack vertically. Settings replaces the panel in the same native window. Its [notice band](../lib/src/ui/settings/settings_screen.dart#L274) stays above separately scrolling controls, capped at half the body; failure precedes pending.

## Correction panel actions

| Content or action | Enablement and effect | Feedback and recovery | Source / requirement |
| --- | --- | --- | --- |
| **Your text** | Multiline editable original, seeded on a fresh session. Edits alone never submit. | Preserves the draft while reading results and after Back. | [Editor](../lib/src/ui/panel/original_text_pane.dart#L90), CAP-2/3 |
| **Correct**, tooltip **Correct (Ctrl+Enter)** | Enabled for non-whitespace text, including while running. Submits the editor snapshot, supersedes the prior run and moves focus to suggestions. | Running state and partial text; completion or inline error. | [Submission](../lib/src/ui/panel/correction_panel.dart#L303), CAP-3/5 |
| **Corrected**, **Casual**, **Short** | Ordered cards map to `formal`, `casual`, `shorter`. Partial or blank cards cannot select/copy; partial text cannot be text-selected. | Click or scoped digit selects a completed card and scrolls it into view. Selection never copies. | [Labels](../lib/src/domain/correction/suggestion_register.dart#L1), [cards](../lib/src/ui/panel/suggestion_card.dart#L58), CAP-4/11 |
| **Copy** on each card | Copies exact final text, leaves the window and other variants available. Final text supports ordinary selection/context menu. | **Copying…**, **Copied**, or **Couldn't copy this suggestion. Try again.** Retry by clicking Copy. | [Copy card](../lib/src/ui/panel/suggestion_card.dart#L71), CAP-11/14 |
| Inline failure and **Retry** | Failure replaces cards. Error text remains selectable. Retry uses the submitted text, even if the editor changed, and the current active prompt/model/provider pair. | New run clears the error; no provider fallback/cascade. | [Error notice](../lib/src/ui/panel/correction_error_notice.dart#L25), [retry](../lib/src/application/correction_controller.dart#L180), CAP-13 |
| **Open settings** | Gear in the editor gutter replaces panel with Settings. | Back preserves the correction session. | [Navigation](../lib/src/ui/daemon_home.dart#L129), CAP-12 |

## Settings actions in rendered order

| Content or action | Draft and committed behavior | Feedback / guard | Source |
| --- | --- | --- | --- |
| **Back** | Returns to correction; a pending controller mutation survives navigation. | Remains enabled during pending. | [Settings](../lib/src/ui/settings/settings_screen.dart#L241) |
| **When closing the window** | **Close to tray** / **Quit app** commit immediately. Native close uses the committed preference. | Failure keeps the old preference; other dismissals still hide. | [Field](../lib/src/ui/settings/close_behavior_field.dart#L18), [close](../lib/src/application/panel_close_controller.dart#L33) |
| Effective shortcut status | Reports backend outcome, separately from saved restart preference. X11 may report an effective binding that differs. Wayland displays desktop wording verbatim under **Your desktop holds this shortcut and describes it as:** | Missing desktop description explicitly says the combination is unknown. Refusal may retain the old binding; unavailable/revoked states explain recovery and tray access. | [Status](../lib/src/ui/settings/hotkey_status_view.dart#L180) |
| **Shortcut** / **Shortcut preference** / **Shortcut to request** | Capture label follows application / compositor / unknown authority. **Apply** requests a bind and saves according to its outcome. X11 **Keep current** discards the draft; the registered shortcut summons the panel instead of being recaptured. | Unsupported/unmodified keys preserve the last valid draft with refusal feedback. Capture resets on view swap or settings focus loss. | [Capture](../lib/src/ui/settings/hotkey_capture_field.dart#L129), [labels](../lib/src/ui/settings/hotkey_capture_field.dart#L265) |
| **AI provider** | **Claude Agent SDK (Claude Code)**, **OpenAI-compatible (via URL)**, then literal configured IDs. Existing provider choices activate a whole preset; active choice is inert. | An unconfigured compatible provider remains a setup draft until saved; current provider continues meanwhile. | [Choices](../lib/src/ui/settings/provider_choice_list.dart#L31), [controller](../lib/src/application/settings_controller.dart#L293) |
| **Preset** | Lists matching preset IDs with provider/model. Activates a complete prompt/model pair for the next correction. | Current stream keeps its captured pair. SDK explains **Uses your Claude Code sign-in on this computer.** | [Presets](../lib/src/ui/settings/preset_choice_list.dart#L42), [screen](../lib/src/ui/settings/settings_screen.dart#L334) |
| Compatible **Base URL**, **Model**, **Save provider settings** | Both required. Save activates/configures the paired model/prompt/provider. | URL accepts HTTPS or HTTP loopback (`localhost`, `127.0.0.1`, `::1`), without credentials/query/fragment. Dirty fields survive external edits with overwrite warning. | [Form](../lib/src/ui/settings/compatible_provider_form.dart#L86), [validation](../lib/src/domain/config/provider_config.dart#L22) |
| **API key**, **Save API key** | Masked blank replacement field; no stored value is prefilled. Blank preserves the existing key and disables save. Success clears the submitted draft. | **API key saved.**, source label; **Config file** source also shows the plaintext notice. | [Key field](../lib/src/ui/settings/api_key_field.dart#L26), [source notice](../lib/src/ui/settings/settings_screen.dart#L371) |
| **Correction prompt**, **Save prompt** | Active preset only. Nonempty changed draft enables save. The app adds the required response format. | Clean fields follow external edits; dirty drafts retain text with overwrite warning. Saving rejects a stale preset/prompt snapshot. | [Prompt](../lib/src/ui/settings/correction_prompt_field.dart#L30), [stale guard](../lib/src/application/settings_controller.dart#L512) |
| **Log file size limit** | 1/5/10 MiB plus the current custom size, sorted; choice commits immediately. | Pending disables changes; failure keeps the previous size. | [Sizes](../lib/src/ui/settings/log_size_field.dart#L19) |

One mutation owns the pending slot. It disables all settings edits, including explicit saves and immediate choices. **Applying your change…** remains visible across Back/reopen. Failures retain committed values; retry by repeating the original setting action. Settings has no dedicated Retry button. Unrelated successful changes do not erase that failure. See [mutation handling](../lib/src/application/settings_controller.dart#L867) and [notices](../lib/src/ui/settings/settings_screen.dart#L274).

## Keyboard and focus

| Context | Behavior to preserve |
| --- | --- |
| Editor | Ctrl+Enter, including keypad Enter, submits only here. Repeated events do not resubmit. Digits are ordinary input. |
| Suggestions | 1/2/3 select corresponding completed cards; selecting an already-selected card keeps it selected. Ctrl+Enter does not submit from this region. |
| Shortcut capture | Bare Escape exits capture without dismissing Settings; held/repeated keys are ignored. Unsupported input retains the valid draft. |
| General controls | Native focus traversal, visible focus indication and labeled fields/buttons. No panel Escape-dismiss shortcut is added. Copy feedback and terminal status are announced without announcing every streamed token. |

Evidence: [editor and suggestion scopes](../lib/src/ui/panel/correction_panel.dart#L133), [selection guard](../lib/src/ui/panel/correction_panel.dart#L174), [capture](../lib/src/ui/settings/hotkey_capture_field.dart#L198). Browser Tab order approximates Flutter focus traversal; it does not prove native focus acquisition.

## Sessions and persistence

| State or transition | Current source behavior | Sample representation |
| --- | --- | --- |
| Dismissed → summon | Fresh editor seeded from current clipboard; prior cards/error clear (CAP-2). Empty/non-text/read failure leaves a usable empty editor. | Clipboard fixture and explicit Dismiss/Summon/Tray buttons. |
| Focus loss or minimize → restore | Editor/results/error survive. Native restore preserves the current view; explicit summon returns to panel. | Separate `focusLost` and `iconified` fixtures; browser blur itself does not dismiss. |
| Visible panel → summon | Hides the panel (CAP-14). | Summon/toggle button. |
| Visible Settings → summon | Returns to panel in the same visible window. | Same external summon action. |
| Hidden correction | Continues to terminal event and local history. New submission/session can supersede it. | Timers continue while hidden; sample history records input and structured `{register, text}[]`. |
| Native close / Quit | Committed close preference hides or quits. Production Quit drains writes and disposes daemon resources. | Displays simulated quit externally; Reset sample restarts. No actual process exit/resource test. |
| Config, prompt and key | Production settings write through to config/prompt files and ingest external changes (CAP-8/12). Keyring/environment/config source rules still apply. | Separate drafts and committed in-memory values; explicit external-edit/source fixtures. No file/keyring access. |
| History | Production stores structured suggestions locally, matching the domain/provider shape (CAP-7). | Completion count outside app only, no production history/analytics UI or durable storage. |

Evidence: [visibility states](../lib/src/domain/panel/panel_visibility.dart#L12), [session departures](../lib/src/application/correction_controller.dart#L418), [summon](../lib/src/application/panel_controller.dart#L107), [history shape](../lib/src/domain/correction/suggestion.dart#L1), [prompt files](../README.md#correction-prompts).

## Source and contract differences

| Difference | Treatment in this baseline |
| --- | --- |
| CAP-4 literally describes side-by-side variants; [current list](../lib/src/ui/panel/suggestion_list.dart#L109) stacks cards. | Preserve the source layout and record the wording difference. This alone does not establish failure of CAP-10's concurrent readability requirement. |
| CAP-14 defines visible-panel toggle; [visible Settings summon](../lib/src/application/panel_controller.dart#L107) additionally returns to panel. | Include that settings-specific behavior; the SPEC does not explicitly forbid it. |
| AGENTS §4.1 says hiding must be able to abandon a correction; [departure logic](../lib/src/application/correction_controller.dart#L429) says no departure cancels. | Mirror hidden completion for review and flag the tension. No Flutter or canonical document is changed. |
| [Controller](../lib/src/application/correction_controller.dart#L207) describes a selection toggle; [widget](../lib/src/ui/panel/correction_panel.dart#L174) guards repeated selection. | Mirror visible repeated-selection behavior. |
| [Hotkey comments](../lib/src/ui/settings/hotkey_status_view.dart#L19) say mechanism is hidden; actual capture labels and current-shortcut hints distinguish regimes. | Document rendered labels and effective facts rather than treating the comment as the whole UI contract. |

## Review fixtures and limits

Outside the app, the sample exposes light/dark/system appearance, completion/mid-stream failure/timeout, copy success/failure, settings success/failure/held pending, readable/empty/non-text/failed clipboard, external config edits, custom provider/log size, key sources, X11 effective/preferred differences and Wayland desktop wording/unknown/refused/unavailable/revoked states. These review controls do not belong in the production Settings inventory.

The initial sentence has authored variants. Arbitrary input is echoed with a few deterministic substitutions and can produce identical variants. This demonstrates interaction states, not correction quality, live provider authentication or backend response mapping. Enter dummy keys only: saving clears the field and retains presence/source status rather than any key value. Shortcut capture in the browser covers modified letters and digits; the Flutter app's wider key catalogue is represented by desktop fixtures. The external **Repeat failed action (sample)** convenience is separate from the Settings action inventory.

Browser smoke evidence establishes sample click/keyboard flows, literal text rendering, constrained layouts and the absence of outgoing requests, native clipboard calls and browser-storage writes. It does not validate native hotkeys, portals/compositors, OS focus/selection, actual config/history persistence, exact Flutter pixels, CAP-1's 100 ms summon budget, CAP-9's correction quality, daemon autostart/residency, or RAM. Those need the Flutter app and desktop checks described in [risks](../_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md).

No diff, primary selection, invisible replacement, personalization, provider fallback/racing, mobile UI or analytics UI is introduced. Later redesign work should preserve the actions above and resolve any contract changes explicitly.
