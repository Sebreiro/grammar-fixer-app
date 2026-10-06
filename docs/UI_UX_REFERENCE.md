# Current correction panel and settings UI and UX reference

The Flutter app now applies the focused command panel and General / AI / Advanced Settings interior from the [HTML prototype](../prototype/ui-baseline/index.html). Its [review guide](../prototype/ui-baseline/README.md) retains simulated scenarios for comparison; external appearance, size and sample-effect controls are excluded from production.

The [SPEC](../_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md#capabilities) defines required behavior. The [provider contract](../_bmad-output/specs/spec-hotkey-grammar-corrector/llm-provider-contract.md), [risks](../_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md), [roadmap](../PLAN.md) and [coding rules](../AGENTS.md) remain authoritative. The tables below describe observed source behavior, not changes to those documents.

## Appearance and layout

The [explicit theme](../lib/src/ui/daemon_theme.dart) follows the system in light and dark modes. Surfaces, typography and blue accents use the prototype palettes:

| Token | Light | Dark |
| --- | --- | --- |
| Surface / editor | `#ffffff` / `#f6f7f9` | `#1e222a` / `#252a33` |
| Text / muted | `#252a34` / `#626b7a` | `#edf0f6` / `#abb4c4` |
| Accent / outline / selection | `#3458c9` / `#e0e4eb` / `#f3f6ff` | `#a9beff` / `#373e4a` / `#2a3349` |

The compact header holds Settings above the editor. Content uses 10 px padding/gaps; editor and rows use 6×8 px padding and 6–7 px corner radii. Correct and Ctrl+Enter appear inside the neutral editor surface. Editor/results retain independent scroll regions, with a text-scaled 420 px content floor; below it the whole panel also scrolls. Startup prepares a preferred 840×650 hidden window, enlarged when scaled controls require it and clamped to the available display. Show and Settings swaps do not resize it.

Stacked rows place shortcut/label, preview and explicit Copy actions in adjacent columns. At 460 px they place the label above the preview; very narrow surfaces keep actions before preview text. Completed answers exceeding five measured lines expose Show more. Full selectable text expands inside the existing window without moving sibling rows; Show less, outside click and Escape close it and return focus. Copy preserves the original full string from either view. Streaming partials remain genuine and cannot select, copy or expand.

Settings uses a General / AI / Advanced rail above 680 px and a labeled selector below it or at enlarged text. General holds close behavior and shortcut authority/capture; AI holds provider/preset, connection and credentials; Advanced holds the active preset prompt and log limit. Categories and Back remain available during pending writes. The failure/pending band remains bounded above scrolling content; short windows also scroll their category selector to preserve usable control space.

## Correction panel actions

| Content or action | Enablement and effect | Feedback and recovery | Source / requirement |
| --- | --- | --- | --- |
| **Your text** | Multiline editable original, seeded on a fresh session. Edits alone never submit. | Preserves the draft while reading results and after Back. | [Editor](../lib/src/ui/panel/original_text_pane.dart), CAP-2/3 |
| **Correct**, tooltip **Correct (Ctrl+Enter)** | Enabled for non-whitespace text, including while running. Submits the editor snapshot, supersedes the prior run and moves focus to suggestions. | Running state and partial text; completion or inline error. | [Submission](../lib/src/ui/panel/correction_panel.dart), CAP-3/5 |
| **Corrected**, **Casual**, **Short** | Ordered cards map to `formal`, `casual`, `shorter`. Partial or blank cards cannot select/copy; partial text cannot be text-selected. | Click or scoped digit selects a completed card and scrolls it into view. Selection never copies. | [Labels](../lib/src/domain/correction/suggestion_register.dart), [cards](../lib/src/ui/panel/suggestion_card.dart), CAP-4/11 |
| **Copy** on each card | Copies exact final text, leaves the window and other variants available. Final text supports ordinary selection/context menu. | **Copying…**, **Copied**, or **Couldn't copy this suggestion. Try again.** Retry by clicking Copy. | [Copy card](../lib/src/ui/panel/suggestion_card.dart), CAP-11/14 |
| Inline failure and **Retry** | Failure replaces cards. Error text remains selectable. Retry uses the submitted text, even if the editor changed, and the current active prompt/model/provider pair. | New run clears the error; no provider fallback/cascade. | [Error notice](../lib/src/ui/panel/correction_error_notice.dart), [retry](../lib/src/application/correction_controller.dart), CAP-13 |
| **Open settings** | Labeled header action, with an icon at narrow widths, replaces panel with Settings. | Back preserves the correction session. | [Navigation](../lib/src/ui/daemon_home.dart), CAP-12 |

## Settings actions

| Content or action | Draft and committed behavior | Feedback / guard | Source |
| --- | --- | --- | --- |
| **Back** | Returns to correction; a pending controller mutation survives navigation. | Remains enabled during pending. | [Settings](../lib/src/ui/settings/settings_screen.dart) |
| **When closing the window** | **Close to tray** / **Quit app** commit immediately. Native close uses the committed preference. | Failure keeps the old preference; other dismissals still hide. | [Field](../lib/src/ui/settings/close_behavior_field.dart), [close](../lib/src/application/panel_close_controller.dart) |
| Effective shortcut status | Reports backend outcome, separately from saved restart preference. X11 may report an effective binding that differs. Wayland displays desktop wording verbatim under **Your desktop holds this shortcut and describes it as:** | Missing desktop description explicitly says the combination is unknown. Refusal may retain the old binding; unavailable/revoked states explain recovery and tray access. | [Status](../lib/src/ui/settings/hotkey_status_view.dart) |
| **Shortcut** / **Shortcut preference** / **Shortcut to request** | Capture label follows application / compositor / unknown authority. **Apply** requests a bind and saves according to its outcome. X11 **Keep current** discards the draft; the registered shortcut summons the panel instead of being recaptured. | Unsupported/unmodified keys preserve the last valid draft with refusal feedback. Capture resets on view swap or settings focus loss. | [Capture](../lib/src/ui/settings/hotkey_capture_field.dart), [labels](../lib/src/ui/settings/hotkey_capture_field.dart) |
| **AI provider** | **Claude Agent SDK (Claude Code)**, **OpenAI-compatible (via URL)**, then literal configured IDs. Existing provider choices activate a whole preset; active choice is inert. | An unconfigured compatible provider remains a setup draft until saved; current provider continues meanwhile. | [Choices](../lib/src/ui/settings/provider_choice_list.dart), [controller](../lib/src/application/settings_controller.dart) |
| **Preset** | Lists matching preset IDs with provider/model. Activates a complete prompt/model pair for the next correction. | Current stream keeps its captured pair. SDK explains **Uses your Claude Code sign-in on this computer.** | [Presets](../lib/src/ui/settings/preset_choice_list.dart), [screen](../lib/src/ui/settings/settings_screen.dart) |
| Compatible **Base URL**, **Model**, **Save provider settings** | Both required. Save activates/configures the paired model/prompt/provider. | URL accepts HTTPS or HTTP loopback (`localhost`, `127.0.0.1`, `::1`), without credentials/query/fragment. Provider drafts survive categories and Back/reopen. Clean drafts follow external edits even while Settings is absent; dirty fields retain their text and show an overwrite warning. | [Form](../lib/src/ui/settings/compatible_provider_form.dart), [validation](../lib/src/domain/config/provider_config.dart) |
| **API key**, **Save API key** | Masked blank replacement field; no stored value is prefilled. Blank preserves the existing key and disables save. Success clears the matching submitted draft, including after category navigation. Unsaved key input survives categories but clears on Back, explicit summon or other Settings departure. | **API key saved.**, source label; **Config file** source also shows the plaintext notice. | [Key field](../lib/src/ui/settings/api_key_field.dart), [source notice](../lib/src/ui/settings/settings_screen.dart) |
| **Correction prompt**, **Save prompt** | Active preset only. Nonempty changed draft enables save. The app adds the required response format. | Prompt drafts survive categories and Back/reopen. A preset identity change resets the prompt. Clean fields follow external edits while away; dirty drafts retain text and baseline with an overwrite warning. Deliberate Save uses the rendered preset snapshot; changes racing that save are rejected. Saving rejects a stale preset/prompt snapshot. | [Prompt](../lib/src/ui/settings/correction_prompt_field.dart), [stale guard](../lib/src/application/settings_controller.dart) |
| **Log file size limit** | 1/5/10 MiB plus the current custom size, sorted; choice commits immediately. | Pending disables changes; failure keeps the previous size. | [Sizes](../lib/src/ui/settings/log_size_field.dart) |

One mutation owns the pending slot. It disables all settings edits, including explicit saves and immediate choices. **Applying your change…** remains visible across Back/reopen. Failures retain committed values; retry by repeating the original setting action. Settings has no dedicated Retry button. Unrelated successful changes do not erase that failure. See [mutation handling](../lib/src/application/settings_controller.dart) and [notices](../lib/src/ui/settings/settings_screen.dart).

## Keyboard and focus

| Context | Behavior to preserve |
| --- | --- |
| Editor | Ctrl+Enter, including keypad Enter, submits only here. Repeated events do not resubmit. Digits are ordinary input. |
| Suggestions | 1/2/3 select corresponding completed cards; selecting an already-selected card keeps it selected. Ctrl+Enter does not submit from this region. |
| Shortcut capture | Bare Escape exits capture without dismissing Settings; held/repeated keys are ignored. Unsupported input retains the valid draft. |
| Settings categories | Arrow keys and Home/End change the focused category and transfer focus to content; Tab continues normal traversal. |
| Expansion | Escape closes only the open full-text expansion, with focus restored to Show more. |
| General controls | Native focus traversal, visible focus indication and labeled fields/buttons. No panel Escape-dismiss shortcut is added. Copy feedback and terminal status are announced without announcing every streamed token. |

Evidence: [editor and suggestion scopes](../lib/src/ui/panel/correction_panel.dart), [selection guard](../lib/src/ui/panel/correction_panel.dart), [capture](../lib/src/ui/settings/hotkey_capture_field.dart). Browser Tab order approximates Flutter focus traversal; it does not prove native focus acquisition.

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

Evidence: [visibility states](../lib/src/domain/panel/panel_visibility.dart), [session departures](../lib/src/application/correction_controller.dart), [summon](../lib/src/application/panel_controller.dart), [history shape](../lib/src/domain/correction/suggestion.dart), [prompt files](../README.md#correction-prompts).

## Source and contract differences

| Difference | Treatment in this baseline |
| --- | --- |
| CAP-4 literally describes side-by-side variants; the production list stacks rows. | The user explicitly authorized stacked suggestions exactly as the prototype for quick task 261005-2g5, overriding that wording for this task. Three variants, scoped selection and concurrent original/results readability remain covered. Generated SPEC is unchanged; the discrepancy remains documented. |
| CAP-14 defines visible-panel toggle; [visible Settings summon](../lib/src/application/panel_controller.dart) additionally returns to panel. | Include that settings-specific behavior; the SPEC does not explicitly forbid it. |
| AGENTS §4.1 says hiding must be able to abandon a correction; [departure logic](../lib/src/application/correction_controller.dart) says no departure cancels. | Preserve existing hidden completion and flag the tension; this presentation task does not change that lifecycle policy or canonical documents. |
| [Controller](../lib/src/application/correction_controller.dart) describes a selection toggle; [widget](../lib/src/ui/panel/correction_panel.dart) guards repeated selection. | Mirror visible repeated-selection behavior. |
| [Hotkey comments](../lib/src/ui/settings/hotkey_status_view.dart) say mechanism is hidden; actual capture labels and current-shortcut hints distinguish regimes. | Document rendered labels and effective facts rather than treating the comment as the whole UI contract. |

## Review fixtures and limits

Outside the app, the sample exposes light/dark/system appearance, completion/mid-stream failure/timeout, copy success/failure, settings success/failure/held pending, readable/empty/non-text/failed clipboard, external config edits, custom provider/log size, key sources, X11 effective/preferred differences and Wayland desktop wording/unknown/refused/unavailable/revoked states. These review controls do not belong in the production Settings inventory.

The initial sentence has authored variants. Arbitrary input is echoed with a few deterministic substitutions and can produce identical variants. This demonstrates interaction states, not correction quality, live provider authentication or backend response mapping. Enter dummy keys only: saving clears the field and retains presence/source status rather than any key value. Shortcut capture in the browser covers modified letters and digits; the Flutter app's wider key catalogue is represented by desktop fixtures. The external **Repeat failed action (sample)** convenience is separate from the Settings action inventory.

Browser smoke evidence establishes sample click/keyboard flows, literal text rendering, constrained layouts and the absence of outgoing requests, native clipboard calls and browser-storage writes. It does not validate native hotkeys, portals/compositors, OS focus/selection, actual config/history persistence, exact Flutter pixels, CAP-1's 100 ms summon budget, CAP-9's correction quality, daemon autostart/residency, or RAM. Those need the Flutter app and desktop checks described in [risks](../_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md).

No diff, primary selection, invisible replacement, personalization, provider fallback/racing, mobile UI or analytics UI is introduced. Widget tests exercise real controller/fake-port effects, responsive light/dark surfaces and enlarged text; the Linux debug build checks native compilation. Live compositor behavior, real focus acquisition, 100 ms summon latency, provider quality and resident RAM still require desktop validation.
