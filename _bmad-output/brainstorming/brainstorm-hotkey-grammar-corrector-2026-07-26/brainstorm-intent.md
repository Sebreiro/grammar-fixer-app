# Brainstorm Intent: Hotkey Grammar Corrector

> **Synced 2026-08-05 with `_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md`.**
> Sections marked *(post-brainstorm)* record decisions made while distilling the spec, not in the original session.
> The SPEC is the canonical contract; this document is narrative background.

## Product Concept

A resident tray daemon (Linux-first, cross-platform) that turns clipboard text into polished native-speaker English on a global hotkey. The hotkey instantly opens a pre-built panel — a micro-editor, not a popup — where the captured text is editable, multiple correction suggestions stream in from an LLM, and the original stays visible beside them. Corrections are stored in a local SQLite history for future grammar-progress analytics.

## Core Job / Problem

Remove the anxiety between writing and hitting Send. The core discomfort is fear of sending an incorrect message — the job covers grammar, tone, idiom, and confidence, not grammar alone. Speed is essential: correction must feel instant enough to fit inside the send-a-message moment.

## MVP Scope (Decided Features)

- Global hotkey toggles a pre-built panel; app stays resident as tray daemon
- Input source: clipboard
- Editable panel: user can write/append text before correction runs
- Original text stays visible alongside the corrections *(post-brainstorm)*
- Multiple correction suggestions per call (not just one); register variants from a single call — formal / casual / shorter — selectable with keys 1/2/3
- Every suggestion carries its own copy button; copying is how corrected text gets back into the message *(post-brainstorm)*
- LLM tokens stream into the panel so corrections appear progressively
- Local SQLite (or similar) DB storing all correction history
- One active LLM provider selected via config or in-app settings
- Every prompt is a stateless new LLM session — no personalization or context carryover
- Provider errors and timeouts appear inline in the panel with a Retry action *(post-brainstorm)*

## Panel Behaviour *(post-brainstorm)*

- Stays open after a copy, so a second variant can be copied without re-running
- Hides when it loses focus
- Hides when the summoning hotkey is pressed again — the hotkey is a **toggle**, not show-only

## Explicit Decisions / Constraints

- Tech stack: Flutter desktop, Linux first — accepts ~96 MB standing RAM for developer experience and a future mobile path
- No Electron — must be native-feeling, lightweight, cross-platform
- Architecture: resident tray daemon with pre-created hidden window; the hotkey only toggles panel visibility, never constructs the window (target <100 ms show, natives achieve ~10–50 ms)
- One LLM at a time via config — no cascading/fallback backends
- Default provider: **Claude Agent SDK** (`claude-agent-sdk` / `@anthropic-ai/claude-agent-sdk`) on model **`claude-sonnet-5`** — a default, not a lock *(post-brainstorm)*
- Every user-facing setting (hotkey, active provider/model) is reachable from both an in-app settings screen and the config file, and the two stay in sync *(post-brainstorm)*
- Stateless LLM sessions in MVP
- No cheats/tricks for speed — genuine engineering; LLM latency handled by experimenting with different models
- Scope focus: the app itself plus the LLM abstraction layer; LLM model speed/tuning explicitly out of scope
- Privacy of clipboard text sent to a third-party LLM is explicitly out of scope for this build — no consent flow, no local-only-provider requirement *(post-brainstorm)*

## LLM Abstraction Principles

- Interface is text-in / stream-out — not HTTP-specific
- Config describes many providers; exactly one is active
- Prompt + model travel together as a preset — combined with stateless sessions, model experimentation becomes config-only
- Response is structured (`suggestions[]`) to feed the multi-suggestion UI
- The structured `suggestions[]` response doubles as the history-DB schema — provider design = analytics design

**Naming note** *(post-brainstorm)*: the product once called the "Claude Code SDK" is now the **Claude Agent SDK** — Claude Code packaged as a library. It is a different package from the Anthropic API SDK's Tool Runner, which only loops over tools you define. The Sonnet 5 model id is exactly `claude-sonnet-5`, no date suffix.

## Deferred to Phase 2 (Out of MVP Scope)

- X11 primary-selection input (correct highlighted text with no Ctrl+C step)
- Invisible-replace mode: silent clipboard swap + toast, panel only on long-press (quick vs. review mode)
- Personalization / context carryover across sessions
- Grammar-progress analytics feature built on the correction history DB
- **Diff view** — highlighting inserted/removed words per suggestion. Raised in the session with the verdict left open; decided **out of MVP** during spec distillation, alongside the analytics feature it would have fed. *(post-brainstorm)*

## Known Risks / Landmines

- Wayland global-hotkey handling: no free global hotkeys as on X11; requires portal/compositor-specific mechanisms — Linux-first plan must account for both X11 and Wayland. Note the hotkey is a toggle, so the handler must consult current visibility rather than blindly showing *(post-brainstorm)*
- X11 primary selection (phase 2) is X11-specific; has no direct Wayland equivalent
- Flutter standing RAM (~96 MB) is an accepted cost, but "warm resident daemon" memory footprint is a watch item for a tray app
