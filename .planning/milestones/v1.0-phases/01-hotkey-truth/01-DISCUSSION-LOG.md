# Phase 1: Hotkey Truth - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-01
**Phase:** 1-Hotkey Truth
**Areas discussed:** AD-9 declaration edits, Packaging format (ARCH-02), Replacing hotkey_manager, Wayland read-back & the catalogue

**Process note.** The first question of the first area was asked as a technical choice
(port shape). The user redirected: *"Ask me business questions for each task instead of
technical."* Every subsequent question was reframed as product behaviour, with
implementation left to Claude. Three requirements with no user-facing surface (HOTKEY-07,
HOTKEY-09, HOTKEY-10) were taken without asking as a result.

---

## AD-9 declaration edits

### Q1 — Desktop reassigns the shortcut externally; what does Settings show?

| Option | Description | Selected |
|--------|-------------|----------|
| The live shortcut, silently | Always shows what is actually firing; the user's saved preference disappears without comment | ✓ |
| Live shortcut + a notice | Shows what is firing plus a line saying the desktop changed it | |
| Preference first, effective beside it | Shows the request as the main value with the effective one next to it | |

**User's choice:** The live shortcut, silently.
**Notes:** Claude flagged that this still requires the app to *know* the live shortcut, so
the read-back work stands — it just gets no notice attached.

### Q2 — What is the user told when the hotkey is not working?

| Option | Description | Selected |
|--------|-------------|----------|
| Three distinct messages | No-backend / key-refused / binding-revoked each get their own wording | ✓ |
| Three messages + tailored action | As above, each offering a matching next step in the UI | |
| Keep one message | One sentence covering all three, always naming the tray fallback | |

**User's choice:** Three distinct messages, without per-case action affordances.

### Q3 — Desktop revokes the shortcut mid-run; re-claim it?

| Option | Description | Selected |
|--------|-------------|----------|
| No — just reflect it | Show it as unbound; the user re-applies | ✓ |
| Retry once, then reflect | One silent attempt, then fall back | |
| Keep retrying | Treat the saved preference as standing intent | |

**User's choice:** No — just reflect it.

### Q4 — Requested Ctrl+Shift+G, desktop assigned Super+G. Success?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — a shortcut works | Treat it as bound; the combination is the desktop's to choose | ✓ |
| No — report it as refused | Honest about intent, but labels a working shortcut broken | |

**User's choice:** Yes — a working shortcut counts as bound.

### Q5 — X11 combination already owned by another application?

| Option | Description | Selected |
|--------|-------------|----------|
| Refuse, keep the old one | Tell the user it is taken; the previous shortcut keeps working | ✓ |
| Refuse, leave nothing bound | Unambiguous state, but costs a working shortcut | |
| Accept and warn | Saves the preference and admits it may not fire | |

**User's choice:** Refuse, keep the old one.

### Q6 — Which failure messages keep the tray-menu line?

| Option | Description | Selected |
|--------|-------------|----------|
| All three keep it | Always tell the user the panel is still reachable | ✓ |
| Only the permanent one | Just the no-backend case, whose user has no alternative | |
| None — say it once elsewhere | Surface the fallback in one fixed place in the UI | |

**User's choice:** All three keep it.

### Q7 — What does the user see while a bind is in flight?

| Option | Description | Selected |
|--------|-------------|----------|
| Busy, field locked | Read-only with clear progress until the desktop answers | ✓ |
| Busy, field still editable | More responsive; requires defining queue-or-drop behaviour | |
| Optimistic — show it applied | Fastest-feeling; displays a shortcut not yet in effect | |

**User's choice:** Busy, field locked.

### Q8 — How long to wait for a portal that never answers?

| Option | Description | Selected |
|--------|-------------|----------|
| A few seconds, then fail | Bounded wait; previous shortcut stays in effect | ✓ |
| Wait longer, ~30s | Accommodates compositors that prompt the user for permission | |
| Wait indefinitely | Simplest to reason about; a dropped request locks Settings | |

**User's choice:** A few seconds, then fail.

---

## Packaging format (ARCH-02)

### Q1 — How should users get the app onto their machine?

| Option | Description | Selected |
|--------|-------------|----------|
| Plain .deb / tarball | No sandbox to fight; what the shipped code assumes | ✓ |
| Flatpak | Works everywhere, sandboxed; forbids the current registration call | ✓ |
| AppImage | Single file, no install, no sandbox; weak autostart story | ✓ |
| Decide later, keep both open | Rewrite for both regimes and defer the choice | |

**User's choice:** All three.
**Notes:** Claude scoped this against ARCH-02's text — the requirement asks only that the
format be *decided and recorded*, so building three pipelines was captured as a deferred
idea rather than pulled into Phase 1. Flagged the live consequence: Flatpak's inclusion
forces the portal handshake to be written sandbox-safe, which is the retroactive constraint
the roadmap warned about.

### Q2 — Should the app behave the same sandboxed and unsandboxed?

| Option | Description | Selected |
|--------|-------------|----------|
| Same everywhere — desktop decides | Always declare a capability, never claim a combination | ✓ (needed clarification) |
| Differ by capability | Claim where possible, declare where not — the ratified stance | |
| Restrict Flatpak, note it | Advisory-only Flatpak, full-featured .deb/AppImage | |

**User's choice:** Same everywhere — then clarified, see below.
**Notes:** Claude blocked on this rather than proceeding. X11 has **no** "desktop decides"
mechanism — no portal to declare to — so the answer was not implementable as stated, and it
contradicted Q5 of the previous area (X11 app-is-authority, refuse a taken combination).

### Q2b — Clarification: which did you mean?

| Option | Description | Selected |
|--------|-------------|----------|
| Same UI, mechanism hidden | Grab on X11, declare on Wayland, but present only "the shortcut in effect" | ✓ |
| Drop the regime label only | Keep behaviour, stop displaying which regime is active | |
| No user-chosen shortcut at all | Fixed default only — would breach CAP-12, a frozen capability | |

**User's choice:** Same UI, mechanism hidden.
**Notes:** Claude recorded that hiding the regime is itself an amendment to a
**user-ratified** spine line (AD-10 requires Settings to show which regime is active), so it
lands as a tracked change rather than a quiet one.

### Q3 — What Flatpak permissions should be declared?

| Option | Description | Selected |
|--------|-------------|----------|
| Narrowest set that works | Clipboard, secret store, own data directory | ✓ |
| Add home directory access | More future flexibility, scarier install prompt | |
| Decide when we build it | Defer the manifest entirely | |

**User's choice:** Narrowest set that works.

### Q4 — Which build is the primary download?

| Option | Description | Selected |
|--------|-------------|----------|
| Flatpak | Best for non-technical users; makes the sandboxed path the main path | |
| AppImage | Lowest friction to try; weakest for a resident daemon | |
| .deb / tarball | Best system integration on the distros it covers | |

**User's choice:** "we need all 3" — no primary build; all three offered equally.
**Notes:** Claude noted this reinforces Q2b — with no second-class build, the sandboxed path
cannot be the degraded one.

---

## Replacing hotkey_manager

### Q1 — Missing `libkeybinder-3.0.so.0` kills the app at launch. What instead?

| Option | Description | Selected |
|--------|-------------|----------|
| Start, hotkey disabled | Tray and panel work; Settings reports the shortcut unavailable | ✓ |
| Start, offer to help | As above, plus distro-specific install guidance | |
| Refuse to start, but explain | Smaller change, but a Wayland user still cannot run it | |

**User's choice:** Start, hotkey disabled.
**Notes:** Claude had established from the spine's own measurement (line 584) that this
requires the `hotkey_manager` plugin to leave the build entirely — the library is reached
through the runner's own `DT_NEEDED` before `main()` runs, so `dlopen` alone is insufficient.

### Q2 — How to handle the risk of replacing launch-path plumbing?

| Option | Description | Selected |
|--------|-------------|----------|
| One clean change | Replace outright, delete the old path | ✓ |
| Keep the old path as fallback | Safer against new bugs, but defeats the entire fix | |
| Behind a setting | Escape hatch, at the cost of a permanent plumbing toggle | |

**User's choice:** One clean change.

### Q3 — Shortcut lost mid-session; when does the user find out?

| Option | Description | Selected |
|--------|-------------|----------|
| When they next look | No interruption; a failed keypress does nothing | ✓ |
| Desktop notification | Timely, but a new outward-facing capability | |
| Tray icon changes | Passive and visible, but tray fan-out is Phase 2's work | |

**User's choice:** When they next look.

### Q4 — Allow shortcuts with no modifier?

| Option | Description | Selected |
|--------|-------------|----------|
| No — require a modifier | Prevents binding a bare letter and losing it system-wide | ✓ |
| Allow function keys only | Single-keypress without the catastrophic case; more rules | |
| Allow anything | Maximum freedom; a bare `G` removes the letter system-wide | |

**User's choice:** No — require a modifier.

### Q5 — How does the user set the shortcut?

| Option | Description | Selected |
|--------|-------------|----------|
| Press the combination | Capture control; no key names to know | ✓ |
| Choose from a list | Nothing invalid enterable by construction; today's behaviour | |
| Press, with a list fallback | Both paths, both to keep consistent | |

**User's choice:** Press the combination.
**Notes:** Claude flagged two consequences — HOTKEY-04 changes from *curate what can be
typed* to *validate what was captured*, and this adds real UI work to a phase carrying no
`UI hint`.

---

## Wayland read-back & the catalogue

### Q1 — Portal reports the shortcut only as localised text. What does Settings display?

| Option | Description | Selected |
|--------|-------------|----------|
| Translate to our own format | One visual language everywhere; parsing localised text is guesswork | |
| Show the desktop's text as-is | Always accurate; notation then differs between X11 and Wayland | ✓ |
| Show what we asked for | Consistent notation, but a guess that the desktop honoured it | |

**User's choice:** Show the desktop's text as-is.
**Notes:** The accepted cost was stated in the option itself — notation differs across
display servers even though the regime label is hidden. Accuracy was chosen over uniformity.

### Q2 — Captured combination that the app knows will not fire?

| Option | Description | Selected |
|--------|-------------|----------|
| Reject at capture | Declines immediately with a reason; previous shortcut kept | ✓ |
| Accept, fail on apply | One failure path for everything; user learns later | |
| Warn but allow | Respects that our key knowledge may be wrong on odd hardware | |

**User's choice:** Reject at capture.

### Q3 — Does anything need the Wayland shortcut as a structured combination?

| Option | Description | Selected |
|--------|-------------|----------|
| No — text is enough | App needs only *whether* something is held and *what text to show* | ✓ |
| Yes — keep it structured | Satisfies HOTKEY-03 literally; fragile localised parsing nothing consumes | |
| Show both | Authoritative text plus our interpretation; invites "which is real?" | |

**User's choice:** No — text is enough.
**Notes:** Claude raised this because Q1's answer collides with HOTKEY-03 as written
(*"read the effective binding back **as a combination** rather than displaying only the
portal's localized `trigger_description`"*). Resolution recorded in CONTEXT.md as a
requirement amendment: the goal — never echo the request, always show what is in effect —
is preserved and becomes the acceptance test; the structured parsing is dropped.

---

## Claude's Discretion

The user delegated all implementation explicitly (*"Ask me business questions ... instead of
technical"*). Taken without asking:

- **HOTKEY-07** — precedence between `bind()`'s outcome and the `bindingChanges` stream when
  the portal emits `ShortcutsChanged` before the `BindShortcuts` reply.
- **HOTKEY-09** — defensive copy/wrap of `HotkeyBinding.modifiers`.
- **HOTKEY-10** — re-keying the `libkeybinder` hardness re-measure trigger. Flagged: its
  premise may dissolve once `hotkey_manager` is removed; verify at planning time.
- **The `GlobalHotkey` port shape** — synchronous accessor vs replaying stream vs
  application-ring cache. The user's decisions constrain the *behaviour*, not the mechanism.
- **How `HotkeyUnavailable` distinguishes three causes** — field, sealed hierarchy, or other.

## Deferred Ideas

- Build the three release pipelines (.deb/tarball, Flatpak manifest, AppImage recipe) — now
  on the critical path to shipping, since all three formats were committed to.
- Autostart on login for the tray daemon — handled differently by each packaging format.
- Desktop notifications as a capability — declined for the shortcut-lost case; the app has
  no notification surface at all today.
- A tray warning state for a degraded hotkey — declined here; Phase 2 owns tray rendering.
