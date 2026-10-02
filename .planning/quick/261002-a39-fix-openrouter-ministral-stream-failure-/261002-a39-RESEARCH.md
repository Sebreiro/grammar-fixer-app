# OpenRouter stream completion research

Date: 2026-10-02

## Finding

OpenRouter documents a final accounting chunk before `[DONE]`. It contains a
content-free choice that repeats the preceding `finish_reason` and includes a
`usage` object. Treating that chunk as a second terminal event rejects a valid
response after its suggestion text has streamed.

Primary source: [OpenRouter streaming documentation](https://openrouter.ai/docs/api_reference/streaming).

## Existing implementation

Current `chat_completion_sse_decoder.dart`, repaired in `466be28`, already
accepts a repeated `stop` when accompanied by object-valued usage and no
nonempty content. It still requires `[DONE]` and rejects invalid data, late
content, changed finish reasons, generic duplicate stops, truncated transport,
and oversized input.

The existing pure decoder regressions and held-open loopback-provider test
cover this exact accounting shape and streaming before completion. Prior
task `261002-7wk` recorded the original failure and passing live check after
this repair. The source checkout at this task's start was clean at `7e2a982`.

## Current live evidence

The actual `OpenAiCompatibleCorrectionProvider` completed two fresh requests
using the exact requested endpoint and model, default request options, and
shipped prompt with enforced register tags. Neither emitted a failure event
or failure log. No additional source repair is supported by these results.

## Recommended resolution

Verify existing regressions, run the analyzer, produce a fresh Linux release
bundle, and record the successful live checks. The user must fully quit the
tray daemon and launch the rebuilt executable to load the source repair.
Whether the user's installed copy is stale remains unconfirmed.

## Follow-up: packaged desktop reproduction

The user supplied the exact sentence and clarified that the failing app was
an AppImage. Three current-source requests completed after 1145, 871, and
743 ms, with first deltas at 620, 438, and 305 ms. An exact-request raw probe
also received HTTP 200, the tagged answer, stop, repeated-stop usage, and DONE;
the current decoder accepted it.

The older `build/releases/` AppImage contained a different AOT library
(SHA256 `4cc7879ff432f4bdd87e10759c47b18ace06daaf7f49d21fee28041296d23894`).
The `build/appimage/` copy matched the current Flutter AOT library
(`1c2497364e83953488cb6a1ad29b183ba91dbe77a3c8562ba469c383d2a1858a`).
The older release reproduced the exact invalid/interrupted stream error
visibly in an isolated X11 desktop with the supplied sentence and model.

A freshly packaged current build displayed all three corrections, but exposed
a separate packaging issue: dynamic SQLite loading failed and history was not
saved. Linuxdeploy sets the executable RUNPATH to `$ORIGIN/../lib`, while
Flutter's bundled code-asset library is in `usr/bin/lib`. AppRun previously
only added `usr/lib` to LD_LIBRARY_PATH. Including `usr/bin/lib` fixes the
library search; the next real packaged correction persisted one completed
history row and three suggestions at 1283 ms.

This finding concerns the AppImage launcher only. The stream decoder and
history schema needed no additional change. The final package uses the
repository-pinned linuxdeploy and AppImage runtime checksums, the current
Flutter bundle, the existing pinned sidecar SDK, and the corrected AppRun.
