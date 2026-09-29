# Hotkey Grammar Corrector

## What This Is

A Linux tray-resident Flutter daemon that turns text you already wrote into polished,
native-sounding English. A global hotkey summons a panel pre-filled with the clipboard,
an LLM provider streams back three register variants (formal, casual, shorter), and every
correction is kept in a local SQLite history. It is for non-native English writers who want
a correction pass available from any application without switching windows or waiting on a
cold start.

The MVP is built: 11 BMAD stories closed and all 14 capabilities of the frozen
SPEC implemented for X11 and the Wayland XDG GlobalShortcuts portal. v1.0 hardened
the shipped daemon through 53 plans. The remaining live desktop checks are recorded
as unobserved in the milestone audit.

## Core Value

The daemon corrects text reliably on both display servers and never loses, corrupts, or
leaks the user's text — a correction that silently truncates or a history file every local
account can read is worse than no daemon at all.

## Requirements

### Validated

<!-- Shipped and confirmed by the 11 closed BMAD stories and the codebase map. -->

- ✓ CAP-1 — Global hotkey summons the resident panel without app launch (X11 + Wayland) — existing
- ✓ CAP-2/CAP-3 — Panel opens pre-filled from the clipboard and acts as a micro-editor — existing
- ✓ CAP-4 — One correction call yields labeled register variants, selectable by 1/2/3 — existing
- ✓ CAP-5 — Suggestions stream into the panel as the provider produces them — existing
- ✓ CAP-7 — Every correction persists to local SQLite and survives restart — existing
- ✓ CAP-8 — Provider and preset are configuration, not code (Claude Agent SDK sidecar default) — existing
- ✓ CAP-9 — Corrections read as fluent native English, not grammar-only fixes — existing
- ✓ CAP-10/CAP-11 — Original and variants readable together; per-suggestion copy — existing
- ✓ CAP-12 — Hotkey rebinding: authoritative on X11, advisory on Wayland — existing
- ✓ CAP-13 — Provider failure and timeout surface inline in the panel with Retry — existing
- ✓ CAP-14 — Panel is a toggle, hides on focus loss, survives a copy — existing
- ✓ Hexagonal architecture with enforced import direction and vendor seams at the composition root — existing
- ✓ Phase 01 hotkey hardening — HOTKEY-01, HOTKEY-02, HOTKEY-04, HOTKEY-06 through HOTKEY-10 verified in `01-VERIFICATION.md`
- ✓ Phase 01 HOTKEY-03 and ARCH-02 — closed for milestone tracking by explicit maintainer waiver; real-portal behavior remains unobserved in `01-VERIFICATION.md`
- ✓ v1.0 ledger hardening — all 50 in-scope requirements mapped to completed plans and passed phase reports; the Wayland retained-refusal gap is fixed in source
- ✓ v1.0 Settings and panel truth — typed hotkey status reaches Settings and tray; panel copy, visibility, and draft handling follow the recorded contracts
- ✓ v1.0 provider choice and teardown — a second OpenAI-compatible provider is selectable, and startup/stop use bounded release steps
- ✓ v1.0 architecture and ledger — 19 ADs match the shipped source and all 40 Phase 02 ledger mappings retain evidence-qualified closure

### Active

No next milestone scope has been selected. The v1.0 audit records the live checks,
CI flake, and parked data-safety work available for later prioritization.

### Out of Scope

- **All test, gate, CI, runtime-observation and review-pass work** — 38 requirements removed outright on 2026-08-31 at the user's direction as not a priority for this milestone, deleting the Gate Reality, Runtime Observation and Deferred Review Passes phases. The ledger entries stay `status: open`; the milestone does not schedule them. Consequence on record: `ci.yml` has still never executed, and the surviving 50 requirements close on inspection rather than on a gate that ran.
- Data safety — history plaintext file permissions, unbounded growth with no retention policy, no recovery path for a corrupt `history.sqlite`, no committed schema snapshot; the whole cluster is `parked` in the ledger and maps to zero v1 requirements
- The 74 `parked` ledger entries — known, filed, and deliberately not scheduled; parking is a status flip, not a deletion, and they can be un-parked per-entry when picked up
- The 66 `done` ledger entries — closed by the shipped stories; retained for traceability only
- New user-facing capabilities beyond DW-115 — the SPEC's 14 capabilities are frozen and CAP-6 is retired; this milestone hardens what exists rather than extending it
- Non-Linux platforms — Linux-first is a standing constraint; a mobile path is accepted as future, not current, scope
- Electron or webview shells — ruled out by the SPEC's constraints; the ~96 MB Flutter RAM cost is accepted

## Context

**Where the work comes from.** This project has no fresh requirements-gathering phase. Its
scope is an existing artifact: the BMAD deferred-work ledger, 1733 lines and 229 entries
accumulated across 11 stories, 8 `bmad-loop` runs, and a 2026-08-14 sweep triage that grouped
the then-open set into 24 bundles. At intake the ledger held 89 open, 74 parked, 66 done.

**The ledger has two formats, and only one is machine-visible.** 121 entries are canonical
`### DW-n:` headings that `bmad-loop sweep` parses. 108 more were appended in flat
`- source_spec:` form by dev sessions and never normalized — the orchestrator counts none of
them, so they are invisible to triage and to the TUI alike. The ledger's own header documents
this as an unfixed defect and undercounts it at 55. Of the 89 open items, 52 are flat. Any
tooling built on the ledger must read both forms.

**Entry quality is high but stale-prone.** Entries carry `reason:` and `evidence:` bodies with
file:line references and reproducing greps, which makes verification cheap. But status is
hand-maintained, so an item fixed by later work can sit at `open` indefinitely — which is why
every open entry is checked against the current code before it becomes a requirement.

**Codebase state at v1.0.** Flutter 3.44.8 / Dart 3.12.2, Riverpod 3.4.2, Drift 2.34.3 + SQLite 3.5.1.
The Claude Agent SDK sidecar remains the default provider; an OpenAI-compatible HTTP adapter
is selectable by config. Four dependency rings retain the composition-root boundary. The final
local analyzer and existing Dart/Flutter suites passed; CI and eight Phase 02 live checks were
not observed as passing.

**Environment.** Development happens in a Linux devcontainer; the Flutter SDK lives outside the
repo and `build/` can hold stale artifacts across SDK changes.

## Constraints

- **Tech stack**: Flutter/Dart on Linux with GTK3, X11 and Wayland — fixed by the frozen SPEC and the shipped code; no Electron, no webview
- **Architecture**: Hexagonal, four rings, one-way imports; vendor types never cross a port boundary and seams are wired only at the composition root (AD-1, AD-17) — enforced by an analyzer rule and architecture tests
- **Contract**: `ARCHITECTURE-SPINE.md`'s 19 ADs and the SPEC's 14 capabilities are frozen; several ledger items exist precisely because a fix would require editing a verbatim-fixed port declaration, which is a human-gated decision
- **Ledger discipline**: `deferred-work.md` is append-only — closing an entry flips `status:` and adds `resolution:`; entries are never deleted (DW-13 and DW-108 both record violations of this rule)
- **Display servers**: Every hotkey and panel behavior must hold on both X11 and Wayland, where the compositor — not the app — owns the binding; the two backends diverge and the map flags that divergence as fragile
- **Privacy**: Input text and suggestion bodies are never logged; history holds user plaintext, which makes file permissions and retention correctness issues rather than polish

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Scope from 89 open ledger entries, leaving 74 parked out | Parked items were known but deliberately unscheduled | ✓ Good — 50 surviving requirements completed after the 2026-08-31 scope cut |
| Verify open entries against current code before making requirements | Hand-maintained ledger status could be stale | ✓ Good — the final 50 requirements have code/document evidence and three-source traceability |
| Treat flat `- source_spec:` entries as first-class alongside canonical DW entries | Flat entries were invisible to older tooling | ✓ Good — original canonical and flat entry blocks retain dated resolutions |
| Keep DW-115 (second provider) in scope | CAP-8 needed a real provider choice | ✓ Good — OpenAI-compatible adapter shipped beside the default sidecar |
| Remove all test, gate, CI, runtime-observation and review-pass work (38 of 88 requirements), deleting three phases outright rather than parking them | Not a priority for this milestone; the user chose deletion over deferral so the remaining documents read clean | 2026-08-31 — Roadmap reduced to 7 phases / 50 requirements. Trade-off accepted on record: closure evidence is now inspection, not a gate that has run |
| Accept Phase 01's intermittent CI merge-gate gap by verification override | CI is not needed for this milestone; the 2026-09-14 verifier measured 7/8 passes and the residual flakes remain filed, so acceptance must not be described as a green gate | 2026-09-23 — Project maintainer accepted the override in `01-VERIFICATION.md`; the clipboard-safety gap was closed by plan 01-25 |
| Accept Phase 01's remaining human checks by explicit waiver | The maintainer directed that all human-needed checks be marked passed after UAT tests 15–21 were reviewed | 2026-09-23 — Seven previously skipped UAT checks and two real-compositor truths accepted for phase progression; original skip reasons and missing live observations remain in `01-UAT.md` and `01-VERIFICATION.md` |
| D-16 best-effort panel placement | Warm hotkey path and Wayland placement limits prevent exact current-pointer-display placement | ✓ Good — startup/cached geometry and compositor placement recorded; exact behavior unobserved |
| D-17 preserve hand-placed config API key on later saves | A whole-file Settings rewrite must retain a user-authored key | ✓ Good — preservation implemented; literal never-rewrite wording is not claimed |
| D-18 replace Wayland preference with structured effective binding when available | Config must keep one honest restart value | ✓ Good — structured effective data wins; unstructured description remains display text |
| D-19 ratify the defensive-copy HotkeyBinding constructor | Phase 01 changed the frozen AD-9 declaration before owner ratification | ✓ Good — existing implementation ratified and AD-9 regenerated |
| D-20 waive eight Phase 02 live checks for v1.0 progression | Locked scope excludes new runtime-observation work | ⚠ Revisit — all eight remain unobserved, with five complete behavior truths accepted for progression |
| D-21 add typed retained Wayland result | A refused Session.Close can leave the old shortcut live while the proposed one is rejected | ✓ Good in source/model — HotkeyRetained, Settings/tray, config seed and AD-9/10/12 agree; live compositor check remains open |

## Current State

v1.0 Ledger Hardening is complete: two phases, 53 plans, and 50 in-scope requirements.
The [v1.0 milestone audit](milestones/v1.0-MILESTONE-AUDIT.md) records the owner waivers
and evidence limits. No next milestone is active.

## Next Milestone Goals

Select scope from the unobserved desktop/provider checks, CI reliability, and parked
data-safety entries. These are candidates, not commitments for a new version.

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-26 after v1.0 milestone*
