# Phase 01 — Answers to the blocking-human checkpoint gates

Recorded 2026-09-02 so the remaining plans can execute without re-asking. Each entry states who
decided and on what basis; nothing here is a claim that a gate was ratified when it was not.

Executors: treat these as the checkpoint answers. Do NOT re-ask these decisions. Reproduce the
relevant answer verbatim in your plan SUMMARY, as each plan's Task 1 acceptance criteria require.

---

## Plan 01-07, Task 1 — capture control behaviour for the already-held shortcut

**Decided by: the user, interactively, 2026-09-02. Option id: `explain-in-place`.**

Verbatim:

> `explain-in-place` — Do nothing special; the capture shows a standing hint that the current
> shortcut cannot be re-captured, and offer a plain "keep current" affordance. No grab lifecycle
> change, no heuristic, and nothing the app claims that it cannot know. The user is told the truth
> about why one combination behaves differently.

Consequences that bind the implementation:

- **No grab release/re-take during capture.** `release-during-capture` was rejected.
- **No timeout heuristic** inferring "that is already your shortcut" from absent key events.
  `treat-silence-as-current` was rejected.
- **The standing hint must render before the user presses anything**, not only after a failed
  capture. This does not come from the plan — it follows from the A4 measurement below, which shows
  a modifier-only press is indistinguishable from pressing the currently-held shortcut. A hint that
  appeared only after a failed capture would be indistinguishable from the control being broken.
- The accepted cost, on record: this states a mechanism difference between the display servers out
  loud, which D-03's "one UI everywhere" argues against. That was weighed and accepted. Do not
  suppress the difference to satisfy D-03.
- A fourth approach was considered and **not** chosen: correlating with the daemon's own in-process
  hotkey press event when the grab fires. It would have required suppressing the panel toggle during
  capture and touching `PanelController`. Do not implement it.

---

## Plan 01-09, Task 1 — dropping `const` from AD-9's declared `HotkeyBinding` constructor

**Decided by: the orchestrator, 2026-09-02, under the user's explicit instruction to complete the
phase unattended. Option id: `defensive-copy`.**

**This is NOT a human ratification of a frozen-spine edit.** The user declined the interactive gate
and delegated completion. Phase 7's ARCH-06 reconciliation must treat this entry as
orchestrator-selected and re-confirm it with a human before the spine is edited to match.

**The basis is requirement text, not orchestrator preference.** HOTKEY-09 reads:

> Defensively copy or wrap `HotkeyBinding.modifiers` so a caller mutating its own set cannot change
> a supposedly immutable domain value behind a `const` constructor

That mandates a mechanism, which admits only one of the plan's three options:

| Option | Verdict |
|---|---|
| `defensive-copy` | The only option that satisfies the requirement text. **Chosen.** |
| `document-the-rule` | Prose only — does not "defensively copy or wrap", so HOTKEY-09 stays unmet. Same shape as 01-04's rejected `message-only`. |
| `unmodifiable-view-const` | The plan documents that it does not work: a `const` constructor cannot call `Set.unmodifiable`. |

Consequences that bind the implementation:

- Drop `const` from the declared constructor and copy the set on construction, following
  `hotkey_grab.dart:17-35`, whose doc already states *"The constructor is therefore not `const`,
  which is the price."*
- Expected cost, per the plan's re-count: one `const` removal in `lib/`
  (`default_app_config.dart:142`, whose enclosing `AppConfig` is not itself `const`, so no cascade)
  and fifteen across seven `test/` files. Verify the count rather than trusting it — plan counts
  have drifted twice this phase.
- `ARCHITECTURE-SPINE.md` is **not** edited by this phase. The reconciliation for this and every
  other AD-9 declaration edit is a Phase-7 (ARCH-06) hand-off entry in the ledger.
- On record and unchanged by this decision: **there is no live defect today.** Every `lib/`
  construction site passes a fresh set literal and a `const` set literal is immutable at runtime.
  This is hardening against a future caller. Say so in the SUMMARY; do not overstate it as a fix.

---

## Flagged assumption A4 — now measured, and owed to plan 01-10's ledger work

A4 was recorded as *"ASSUMED — not reproduced in this session; follows from X11 passive-grab
semantics."* The orchestrator reproduced it on **2026-09-02** against a private `Xvfb :78`: three
X11 connections — one holding the passive grab (the daemon), one owning a real mapped focused window
that selected `KeyPressMask|KeyReleaseMask` (the settings screen), one injecting via XTEST — plus an
ungrabbed control case.

| Case | Grabbing client | Focused window |
|---|---|---|
| `Ctrl+Shift+G`, grab **held** | `KeyPress` keycode 42 | **never receives keycode 42** — only `Ctrl↓(0x0) Shift↓(0x4) Shift↑(0x5) Ctrl↑(0x4)` |
| `Ctrl+Shift+H`, not grabbed (control) | nothing | full sequence including keycode 43 |
| `Ctrl+Shift+G` after `XUngrabKey` | nothing | full sequence including keycode 42 |

**The assumption holds**, and the measurement adds a detail the plan did not anticipate: **it is not
silence.** The focused window receives the modifier down/up events and only ever misses the
terminating non-modifier key. Therefore a "modifiers pressed and released with no non-modifier key"
sequence is byte-identical to a user idly pressing and releasing Ctrl+Shift — which is why the
timeout heuristic was rejected, and why 01-07's hint must precede the first keypress.

**Scope limit, to be recorded honestly and not overstated:** measured under `Xvfb` with synthetic
XTEST events, not with a physical keyboard under a real window manager. Grab arbitration is
server-side so it should transfer, but real-desktop confirmation remains **owed**, not observed. A4
moves from "assumed" to "measured, with a stated scope limit" — not to "verified on a real desktop".
