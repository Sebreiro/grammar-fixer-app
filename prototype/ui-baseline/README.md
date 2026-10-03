# Focused command panel design prototype

This standalone HTML prototype applies the selected focused command panel brief. It explores a new appearance and preferences layout; Flutter implementation belongs to a later iteration. The existing `ui-baseline` entry path is retained so earlier links still work.

Open [index.html](index.html) directly in a browser. No install or build is needed. Or, from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Visit http://127.0.0.1:8765/prototype/ui-baseline/. The [current Flutter UI and UX reference](../../docs/UI_UX_REFERENCE.md) remains a source-behavior reference.

## Design direction

Neutral light and dark surfaces, system typography, restrained blue accents, a clear editor/action hierarchy and three adjacent variation cards. Each card has a visible Copy button, selection shortcut and independent text scrolling. The original stays above the results and scrolls separately. At constrained widths, cards scroll horizontally rather than becoming a stacked list: this resolves the brief's CAP-4 conflict in favor of the SPEC's side-by-side requirement.

Settings uses General / AI / Advanced navigation in the same frame. At compact widths it switches to a category selector. Model information stays with its preset; the AI category links to the active preset's prompt in Advanced. Technical details use expandable explanations. Controls distinguish immediate changes from Apply/Save, with pending, saved and failure feedback beside the affected group.

## Review the design

Use the **Preview controls** outside the app frame:

1. Switch **Appearance** between System, Light and Dark. System follows the browser preference. Choose Comfortable, Compact or Wide, or resize the frame from its lower-right corner.
2. **Panel scene** starts with completed sample variations so the design is visible immediately. Try Ready, Blank, Long text, held Streaming and Correction failure. Held Streaming shows the sample adapter's partials and waits until another scene or submission; ordinary correction still completes in 800 ms.
3. Edit **Your text**, then **Correct** or editor-scoped **Ctrl+Enter**. Partial results cannot select or copy. After completion, click a card or focus Suggestions and press **1/2/3**; selection does not copy. Focused cards also select with Enter/Space. Digits in the editor remain ordinary text.
4. Use each **Copy** button. Copying/Copied feedback stays beside that card and the panel stays open. Set **Next copy → Failure** to inspect the inline message, then retry the same Copy action. Expand **Simulated effects** to inspect exact sample clipboard output.
5. Set **Next correction → Mid-stream failure** or **Timeout** and submit. Edit the input after failure, switch the outcome to Complete, then **Retry**: it uses the original submitted input, while keeping the edited draft.
6. Open **Settings**. Use General / AI / Advanced, arrow keys/Home/End on the category tabs, or the compact selector. Category changes and Back/reopen preserve prompt and provider drafts without saving. Unsaved API key input clears on leaving, as disclosed beside the key field.
7. Expand **Settings & desktop scenarios**. Choose **Hold pending**, change a setting, navigate or use Back, reopen and **Complete pending**. Pending guards prevent another mutation; navigation and Back remain available. For **Failure**, use the affected control's original Apply/Save action to recover. Failed saves keep committed values. The external replay button is only a review convenience.
8. In AI, select the compatible provider, enter a sample URL/model and save. Use dummy API keys only. In Advanced, edit the prompt, then trigger **External config edit** to review dirty-draft protection and stale-save handling. The current preset is identified above the prompt.
9. Inspect X11 and Wayland shortcut fixtures in General. Requested and effective bindings remain distinct. Window actions demonstrate dismissal/fresh clipboard versus restoration after focus loss or minimization.

## Sample limits

All corrections, clipboard, configuration, history and desktop effects are simulated in transient memory. No provider request, native clipboard, portal, tray, config file, keyring, database or browser-storage write occurs. Reload resets the sample. The completed/long/error review scenes are fixtures and do not create sample history records; submissions do.

The initial sentence has authored register variants. Other input uses a few deterministic substitutions and may produce identical variants. This demonstrates interaction and appearance, not model quality. Enter dummy credentials only: the masked key field never persists its value and a successful save clears it.

Sample timings and browser geometry do not validate native hotkeys, the 100 ms summon target, streaming latency, real persistence, text replacement, compositor behavior or resident RAM. The existing session/restoration fixtures are retained; hidden sample streams can finish, matching the documented current-source behavior. The AGENTS cancellation-on-hide discrepancy remains a later production concern recorded in the UI/UX reference.

Scripts load locally in fixtures → state → app order. Browser verification tools stay under `/tmp`, outside project dependencies. The brief at `.planning/design/FOCUSED_COMMAND_PANEL_DESIGN_BRIEF.md` is the design input; SPEC and its companions remain authoritative and unchanged.
