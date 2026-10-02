# Current UI baseline prototype

This static prototype mirrors the current correction panel and Settings for review before a later redesign. It approximates the existing indigo Material appearance; it does not change the Flutter app.

Open [index.html](index.html) directly in a browser. No install or build is needed. Alternatively, from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Visit http://127.0.0.1:8765/prototype/ui-baseline/. The [UI and UX reference](../../docs/UI_UX_REFERENCE.md) lists source evidence, control behavior and source/contract differences.

## Review the flows

1. Edit **Your text**, then **Correct** or editor-scoped **Ctrl+Enter**. Watch sample partials become **Corrected**, **Casual**, **Short**. Focus the suggestions region and press **1/2/3** to select. **Copy** updates the sample clipboard output and leaves the panel open.
2. Choose **Mid-stream failure** or **Timeout** outside the app. Submit, edit the input, then choose **Complete** and **Retry**. Retry uses the submitted text.
3. **Open settings** using the gear. Change a control while the external mutation outcome is **Hold pending**; use **Back**, reopen, and **Complete pending**. Choose **Failure**, make another change, then **Success** and repeat the original setting action to review recovery. The external **Repeat failed action (sample)** button is a review convenience; the app's Settings has no Retry button.
4. Select the compatible provider, supply a sample URL/model, and save. Use dummy text only in **API key**; a successful save clears it. Try editing the prompt before **External config edit** to see the dirty-draft warning.
5. Switch desktop shortcut fixtures to inspect authority and effective wording. Click the shortcut field to capture; bare Escape exits capture. Use the external window buttons to compare dismissal/fresh clipboard with minimize or focus loss/restoration. Native close follows the committed close preference; **Reset sample** restarts a simulated Quit.

**System** appearance follows the browser's theme; external **Light/Dark** overrides aid review. The app frame can be resized using its bottom-right corner. Short frames scroll the whole panel; editor, suggestions and settings controls also scroll independently.

## Sample limits

All adapters use transient memory and fixed timers. No provider request, native clipboard, portal, tray, config file, keyring or database is accessed. The external history count records sample completions only; there is no history UI. Reload resets everything.

The initial sentence has authored register variants. Other input is echoed with a few deterministic grammar substitutions; it is not an LLM or a correction-quality benchmark. Sample timings do not establish the native 100 ms summon target, streaming latency or resident RAM.

The masked key field is for dummy input only. The prototype retains only sample key presence/source status, never the entered value in config/history/browser storage. Keep real credentials out of a review artifact.

The scripts load locally in fixtures → state → app order. Playwright verification tooling lives under `/tmp` and is not a project dependency. Native desktop behavior and exact Flutter pixels require separate checks.

Shortcut capture in this sample accepts letters and digits with Ctrl, Alt or Super. The Flutter app supports a wider key catalogue; use desktop-state fixtures to review other bindings.
