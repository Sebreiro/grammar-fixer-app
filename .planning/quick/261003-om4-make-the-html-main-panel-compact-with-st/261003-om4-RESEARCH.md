# Focused implementation research

The existing classic-script prototype supports direct file opening and already isolates correction state from presentation. Change panel HTML, panel-specific CSS and card rendering; retain fixtures and state logic.

Use one grid per suggestion row: compact register/shortcut, flexible scrollable text, visible Copy. Stack rows in a vertically scrolling results region. Keep the editor pinned above results so long output and selecting the third row do not scroll the original away.

Avoid empty feedback slots. Copying/Copied can occupy the existing Copy button label; retain the persistent live region for announcements and show failures below the affected row. Keep button width stable through success feedback.

Settings uses the same resizable preview frame. Scope smaller dimensions to the panel surface; preserve the prior 840×650 / 620×560 / 960×720 preferences presets. Remember manual dimensions per surface and reset those overrides when the external size selector changes.

Record the approved Settings screenshot before edits and compare the same region after. Reuse existing temporary Playwright/Chromium tooling; adapt geometry checks from horizontal cards to stacked rows, while retaining behavior assertions. Check compact/narrow/long/scaled text and all panel feedback states.

No new dependencies or external research are needed. The latest user instruction authorizes stacked layout in the prototype; the production side-by-side contract remains unchanged.
