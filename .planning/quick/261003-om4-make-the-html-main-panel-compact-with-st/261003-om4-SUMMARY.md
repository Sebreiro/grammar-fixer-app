---
phase: quick-261003-om4
status: complete
completed: 2026-10-03
implementation_commit: 3f7fcba
documentation_commit: 0f2a977
---

# Compact prototype with stacked suggestions

Revised only the HTML design prototype according to the user's feedback. The approved Settings design is preserved; Flutter integration remains a later iteration.

## Delivered

- Default panel reduced from 840 × 650 to **640 × 360**, about 58% less area. Compact is 520 × 360; Wide is 760 × 420.
- Full-width suggestion rows stack vertically. Each has a shortcut, label, correction and explicit Copy button. Narrow rows place the label above the text.
- Main padding reduced to 10 px; row padding is 6 × 8 px with 4 px between rows. Removed redundant descriptions, subtitles and bottom hint band.
- Default sample shows the source and all three corrections with their Copy buttons. Source, result list and long correction text scroll independently.
- Copying/Copied occupies the stable Copy button; copy failures remain visible inline and recover using the same action.
- Settings retains its existing dimensions and appearance. Back restores the panel size, including manual resize dimensions; external preset selection resets overrides.
- Updated prototype instructions and the factual layout reference.

## Commits

- `3f7fcba` — compact HTML/CSS/JS implementation.
- `0f2a977` — prototype guide and UI reference.

## Verification

**23 browser checks passed**, covering compact row geometry, source/result readability, stream guards, keyboard selection, exact copy and recovery, Retry, settings drafts/pending/failures, narrow/long/enlarged layouts, local links and simulated boundaries. No page errors, outgoing requests or native clipboard/storage calls were observed. An additional capture run checked timeout recovery and failed-save value retention.

Settings before/after screenshots are byte-identical in light and dark themes. All 172 descendants have identical computed style values, with property order normalized. Settings HTML is unchanged from `e2be6d3`. See `evidence/settings-preserved.json`.

JavaScript syntax and whitespace checks passed. Required `dart analyze --fatal-infos` ran once and found no issues. Protected production/specification path diffs are empty. Existing local preview and its four assets return HTTP 200 at `http://localhost:8765/`.

Screenshots capture light/dark panels, narrow/long layouts, blank, streaming, failure, copied and settings feedback states. The default and narrow renders were visually inspected. Temporary browser tooling was reused from `/tmp`; no repository dependencies or test framework were added.

## Scope and decisions

The full GSD workflow was executed inline under the skill's agent restriction. User feedback supplied the discussion decisions; context, research, plan check, review and verification are recorded alongside this summary.

The user's latest instruction explicitly requests stacked rows for the design prototype. Production SPEC CAP-4 still requires side-by-side variants, so this artifact does not certify that production requirement. No SPEC, Flutter, provider, persistence, platform, configuration or ROADMAP implementation is changed. The user's pre-existing untracked `.planning/design/` input remains untouched.

The prototype uses the existing in-memory fixtures and adapters. Native behavior, provider quality, startup latency and resident RAM are outside this design-only task.
