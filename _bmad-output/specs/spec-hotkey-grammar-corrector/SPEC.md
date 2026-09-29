---
id: SPEC-hotkey-grammar-corrector
companions:
  - llm-provider-contract.md
  - risks.md
  - ../../planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md
sources:
  - ../../brainstorming/brainstorm-hotkey-grammar-corrector-2026-07-26/brainstorm-intent.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Hotkey Grammar Corrector

## Why

A pain to solve, and a vision to realize. Non-native English writers hesitate in the gap between finishing a message and pressing Send — the discomfort is fear of sending something incorrect, and it spans grammar, tone, idiom, and confidence, not grammar alone. Every existing remedy costs a context switch: leave the app, paste into a browser tool, wait, copy back. That switch is expensive enough that people either skip the check or stall on it. This work puts correction inside the send-a-message moment: a resident tray daemon that a global hotkey turns into a working panel fast enough that checking stops feeling like an interruption. Speed is not a nice-to-have here; it is the reason the product changes behavior at all.

## Capabilities

- **CAP-1**
  - **intent:** A user can summon the correction panel from any application with a global hotkey, without launching or waiting for an app to start.
  - **success:** With the daemon already resident, the panel is visible and focused within 100 ms of the hotkey press, measured on both X11 and Wayland.
  - **note:** The hotkey is a toggle — see CAP-14 for what a second press does.

- **CAP-2**
  - **intent:** A user can have the text they just copied appear in the panel without pasting it themselves.
  - **success:** A new summon after dismissal seeds the editor from the current readable plain-text clipboard. Returning after iconification or focus loss preserves the existing session without reading the clipboard. An empty or non-text clipboard, or a failed read, leaves a usable blank editor.

- **CAP-3**
  - **intent:** A user can edit or extend the captured text before correction runs, so the panel works as a micro-editor rather than a read-only preview.
  - **success:** Text typed or edited in the panel is what gets corrected; the original clipboard content is not used once the user has modified it.

- **CAP-4**
  - **intent:** A user can choose between register variants of the same correction — formal, casual, shorter — produced together rather than by re-running the correction.
  - **success:** A single correction call yields the labeled register variants side by side, and pressing 1, 2, or 3 selects the corresponding variant.

- **CAP-5**
  - **intent:** A user sees corrections forming as the model produces them, rather than waiting on a blank panel for a complete response.
  - **success:** Partial suggestion text is rendered in the panel before the provider's response has finished.

*CAP-6 is retired. It held the per-suggestion diff view, now a Non-goal. The id is never reassigned.*

- **CAP-7**
  - **intent:** Every correction a user runs is retained locally, so later work can analyse the user's grammar history.
  - **success:** After a correction, a record holding the input text and the returned suggestions exists in the local database and is still readable after an application restart.

- **CAP-8**
  - **intent:** An operator can change which LLM backend serves corrections by editing configuration or the in-app settings, without touching application code.
  - **success:** Switching the active provider and preset — from either surface — changes which backend serves the next correction, with no code change and no rebuild of the correction pipeline.

- **CAP-9**
  - **intent:** A user can turn text they wrote into polished, native-sounding English — corrected for grammar, tone, and idiom, not grammar alone.
  - **success:** Given non-native input containing grammatical errors and non-idiomatic phrasing, the returned suggestions read as fluent native-speaker English while preserving the writer's intended meaning.

- **CAP-10**
  - **intent:** A user can see what they originally wrote next to the corrections, rather than losing the original the moment suggestions arrive.
  - **success:** The original text and at least one correction variant are readable in the panel at the same time, without scrolling one out of view.

- **CAP-11**
  - **intent:** A user can take a chosen correction back to the message they were writing, via an explicit copy action on the suggestion they picked.
  - **success:** Pressing a suggestion's copy button places exactly that suggestion's text on the system clipboard; each suggestion has its own button.

- **CAP-12**
  - **intent:** A user can choose which key combination summons the panel, rather than living with a fixed binding.
  - **success:** On X11, a hotkey changed in the in-app settings takes effect without restarting the daemon and persists to the config file across restarts. On Wayland, the settings surface submits the chosen combination as a preferred trigger, displays the combination actually in effect, and reflects a rebind made in the compositor — in both cases without restarting the daemon.
  - **note:** The split is not an implementation detail. Under Wayland the compositor owns the binding, so the settings surface is authoritative on X11 and advisory on Wayland. See the Wayland binding-authority constraint below.

- **CAP-13**
  - **intent:** A user learns when a correction failed and can try again, without leaving the panel they are already looking at.
  - **success:** When the active provider errors or times out mid-stream, the error is shown inline in the panel — not as a toast or a separate window — replacing the empty or half-streamed suggestion, and a Retry action re-runs the correction on the same input text.

- **CAP-14**
  - **intent:** A user can copy more than one variant before dismissing the panel, and can get the panel out of the way without hunting for a close control.
  - **success:** Copying a suggestion leaves the panel open with the other variants still copyable; the panel hides when it loses focus; and pressing the summoning hotkey while the panel is visible hides it rather than re-showing it.

## Constraints

- Flutter desktop, Linux first. No Electron and no webview shell — the app must feel native, stay lightweight, and remain cross-platform. The ~96 MB standing RAM cost of Flutter is accepted in exchange for developer experience and a future mobile path.
- The app is a resident tray daemon with a pre-created hidden window. The hotkey only *shows* an existing panel — it never constructs one. Show-on-demand window construction is ruled out.
- The global hotkey must work under both X11 and Wayland. Wayland grants no free global key grabs, so the hotkey layer cannot assume an X11-style grab and must route through the compositor's mechanism (XDG GlobalShortcuts portal or equivalent).
- Under Wayland the GlobalShortcuts portal owns the binding: the app submits a preferred trigger and reads back what is actually in effect, while the compositor and user choose the combination. This rules out a settings surface that presents the hotkey as app-owned on both display servers, and rules out treating a requested binding as the effective one.
- The global hotkey is a toggle: pressed with the panel hidden it shows, pressed with the panel visible it hides. A show-only handler that ignores current visibility is ruled out.
- Exactly one LLM provider is active at a time, chosen via config. No cascading, fallback, or racing backends — including the rejected pattern of an instant local draft that a remote answer later replaces.
- Every correction is a stateless new LLM session. No context carryover and no personalization.
- No latency tricks or placeholder fake-outs. Perceived speed must come from genuine engineering — process residency and token streaming. LLM latency itself is addressed by swapping models in config, not by engineering around it.
- Correction history is stored locally in an embedded database. No remote store.
- The LLM provider interface is text-in / stream-out and not HTTP-specific; prompt and model travel together as a preset; the response is a structured `suggestions[]` whose shape also serves as the correction-history schema. Full contract in [llm-provider-contract.md](llm-provider-contract.md).
- The default configuration ships the Claude Agent SDK provider on model `claude-sonnet-5`. This is a default, not a lock — CAP-8 still requires switching providers by configuration alone.
- Every user-facing setting is reachable two ways — an in-app settings surface and the config file — and the two stay in sync. A change made in settings writes through to config, which rules out an in-memory-only settings UI.

## Non-goals

- X11 primary-selection input (correcting highlighted text with no Ctrl+C step) — phase 2.
- Invisible-replace mode (silent clipboard swap plus toast, with the panel only on long-press) — phase 2.
- Personalization or context carryover across sessions, including feeding past mistakes into the prompt — phase 2.
- The grammar-progress analytics feature itself. MVP records the data that feeds it; MVP surfaces no analytics UI.
- LLM model speed and output-quality tuning. Addressed by swapping models via config, not by work inside this scope.
- Cascading or fallback LLM backends.
- Mobile platforms. Flutter is chosen partly to keep that path open, but no mobile target is in this scope.
- Privacy controls around sending clipboard text to a third-party LLM — no consent flow, no data-handling disclosure, no local-only-provider requirement. Explicitly not a concern for this build.
- Per-suggestion diff view (highlighting inserted and removed words against the input). Considered and declined for MVP; the retired CAP-6 held it. Phase 2 at the earliest, alongside the analytics feature it would have fed.

## Success signal

A non-native speaker, mid-conversation, presses the hotkey with their draft message on the clipboard, sees their original alongside corrections streaming into a panel that appeared in under 100 ms, picks the variant they like, copies it with one press, and returns to sending — without leaving the app they were typing in and without the check feeling like a detour. Demonstrable end to end on a Linux desktop under both X11 and Wayland — on Wayland, a compositor that implements the GlobalShortcuts portal — with the correction recorded in local history.

## Assumptions

- Desktop-only for MVP. Flutter keeps a mobile path open, but no mobile target is in scope.
- "SQLite or similar" resolves to an embedded local database; the exact library is an architecture decision, not a commitment made here.
- Keys 1/2/3 imply exactly three register variants in MVP, rather than a variable-length suggestion list.
- MVP stores correction history but surfaces no analytics over it, since the analytics feature is deferred.
- Selecting a variant and copying it are distinct acts: selection highlights, the copy button transfers. Nothing states that selection alone copies.
- The Claude Agent SDK provider runs locally on the user's machine, matching the source's "local" framing. Whether it reaches a remote endpoint underneath is an implementation detail this contract does not fix.
- Hiding the panel discards nothing that needs saving: the correction is already in history (CAP-7) and copying is explicit (CAP-11), so a focus-loss hide needs no confirmation prompt.
- Wayland global-hotkey support is scoped to compositors implementing the GlobalShortcuts portal. wlroots-based compositors (Sway, Hyprland, Niri) ship no backend, so the hotkey is unavailable there and the tray remains the way to open the panel.
