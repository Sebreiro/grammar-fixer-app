---
phase: 01-hotkey-truth
plan: 01
subsystem: infra
tags: [packaging, flatpak, appimage, deb, xdg-portal, global-shortcuts, ad-9, ledger, deferred-work]

# Dependency graph
requires: []
provides:
  - "Ratified packaging set — .deb/tarball, Flatpak, AppImage — recorded in DW-89 with the 2026-08-14 four-format decision explicitly superseded"
  - "The D-19 finish-args set, recorded verbatim: --socket=wayland, --socket=fallback-x11, --share=ipc, --talk-name=org.freedesktop.secrets, and no --filesystem= of any kind"
  - "The ARCH-02 consequence: because Flatpak ships, the host portal registry Register call is conditional on a sandbox predicate, so AD-11's step 1 is a variable rather than a constant"
  - "Ratified shape of GlobalHotkey's current-registration member: status-type — HotkeyStatus? get current, carrying outcome plus a nullable backendDescription"
  - "Confirmation that HOTKEY-03's localized compositor description rides on that new member, not on a declared field of an existing type"
  - "Phase-7 spine-reconciliation hand-off entry enumerating all four AD-9 declaration edits with spine line ranges"
  - "Flatpak sidecar-reachability cost filed against the deferred packaging phase"
affects: [01-04, 01-05, 01-06, 01-09, 01-10, phase-06-provider, phase-07-arch-docs, packaging]

# Actuals (#2632) — estimateTokens scale (chars/4) over the realized diff, not a harness token count.
actuals:
  tokens: 3600
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Append-only ledger closure: status: flip plus one inserted resolution: line at column 0, with the superseded decision: text preserved verbatim below it"
    - "Contradiction between two ratified records is resolved in writing by naming the supersession, never by rewriting the losing record"

key-files:
  created: []
  modified:
    - _bmad-output/implementation-artifacts/deferred-work.md

key-decisions:
  - "Packaging: three formats — .deb/tarball, Flatpak, AppImage — no primary build, none second-class. Supersedes DW-89's 2026-08-14 four-format decision; the native Arch PKGBUILD is dropped from the committed set."
  - "Flatpak permission set: --socket=wayland, --socket=fallback-x11, --share=ipc, --talk-name=org.freedesktop.secrets (Phase 6 credential only). No --filesystem= grant of any kind, no --talk-name=org.freedesktop.Flatpak. The GlobalShortcuts portal needs no grant."
  - "GlobalHotkey current-registration member: status-type — one new member HotkeyStatus? get current returning a new domain type (outcome + nullable backendDescription), synchronous, no round trip."
  - "HOTKEY-03's localized description carrier folds into that same new member, so HotkeyRegistration's declared field list (spine 248-254) is not touched and only one AD-9 gate was spent instead of two."
  - "ARCHITECTURE-SPINE.md is not edited by this phase; the reconciliation for all four AD-9 declaration edits is filed as a Phase-7 (ARCH-06) hand-off entry."

patterns-established:
  - "Human decision gates that retroactively constrain code are taken in a dedicated wave-1 plan and recorded before any implementation plan runs"
  - "A flagged assumption travels with the record it underwrites, marked [ASSUMED] inline rather than absorbed as fact"

requirements-completed: [ARCH-02, HOTKEY-06]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "DW-89 closed with a resolution naming the three committed packaging formats, the D-19 finish-args set, and the Register/AD-11-step-1 consequence"
    requirement: "ARCH-02"
    verification:
      - kind: other
        ref: "grep -n '^status: done' deferred-work.md | awk -F: '$1==1348' — line 1348 is 'status: done 2026-09-01'"
        status: pass
      - kind: other
        ref: "awk 'NR==1349 && /^resolution:/' — resolution inserted at column 0 directly beneath the status line"
        status: pass
      - kind: other
        ref: "awk NR==1349 index checks for --socket=wayland, --socket=fallback-x11, --share=ipc, --talk-name=org.freedesktop.secrets, 'Register', 'conditional', '.deb', 'Flatpak', 'AppImage'"
        status: pass
    human_judgment: false
  - id: D2
    description: "The ratified status-type AD-9 port-surface addition (HOTKEY-06, folding HOTKEY-03's description carrier) filed as an open flat entry"
    requirement: "HOTKEY-06"
    verification:
      - kind: other
        ref: "grep -n '^  summary:' deferred-work.md | tail -3 — new entry at line 1737 with fields indented exactly two spaces, status: open"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phase-7 ARCHITECTURE-SPINE.md reconciliation hand-off filed, enumerating all four AD-9 declaration edits with spine line ranges; no line of the spine edited"
    verification:
      - kind: other
        ref: "new flat entry at line 1742; git status --porcelain _bmad-output/planning-artifacts/ prints nothing"
        status: pass
    human_judgment: false
  - id: D4
    description: "Flatpak sidecar-reachability cost filed against the deferred packaging phase as its own entry, carrying the A6 [ASSUMED] caveat"
    verification:
      - kind: other
        ref: "new flat entry at line 1747, status: open, contains [ASSUMED] and the flatpak-spawn --host contradiction"
        status: pass
    human_judgment: false
  - id: D5
    description: "Append-only discipline held: exactly one line deleted across the whole edit, no existing decision/reason/origin/location/severity/summary/evidence text rewritten"
    verification:
      - kind: other
        ref: "git diff --numstat -- deferred-work.md => 17 insertions, 1 deletion; awk NR==1350 confirms DW-89's original decision: line preserved verbatim"
        status: pass
      - kind: other
        ref: "grep -c '^  status: open' => 55, up from 52 (never lower); git diff --diff-filter=D HEAD~1 HEAD => empty"
        status: pass
    human_judgment: false
  - id: D6
    description: "Control: the Dart tree is unchanged and still the tree later plans in this phase assume"
    verification:
      - kind: integration
        ref: "dart analyze --fatal-infos => 'No issues found!'"
        status: pass
      - kind: unit
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart => 946 passed / 2 skipped / 0 failed, matching the 2026-09-01 baseline exactly"
        status: pass
    human_judgment: false
  - id: D7
    description: "The supersession record reads unambiguously to a later reader — DW-89 now carries two disagreeing ratified answers by design, and which one governs must be obvious without external context (threat T-01-01, repudiation)"
    verification: []
    human_judgment: true
    rationale: "Mechanical checks prove the supersession sentence is present and names both records; they cannot prove a later reader will not be misled by two adjacent ratified answers. DW-13 and DW-108 record prior append-only violations on this exact file, so legibility of the disagreement is the mitigation and only a human read can confirm it."

# Metrics
duration: 6 min
completed: 2026-09-01
status: complete
---

# Phase 1 Plan 01: Packaging and AD-9 Port-Surface Decisions Summary

**Three-format packaging set (.deb/tarball, Flatpak, AppImage) ratified and recorded in DW-89 with its own 2026-08-14 four-format decision explicitly superseded, plus `status-type` ratified as `GlobalHotkey`'s current-registration member — the two human gates that retroactively constrain plans 01-05 and 01-06.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-09-01T15:44:49Z
- **Completed:** 2026-09-01T15:50:50Z
- **Tasks:** 3 (2 blocking-human decision checkpoints, 1 auto)
- **Files modified:** 1

## Accomplishments

- **DW-89 closed** (ARCH-02's whole deliverable). The three-vs-four packaging contradiction reached the human and was settled in one direction, in writing, with the losing record left intact.
- **The `Register` consequence recorded** beside the format choice: because Flatpak ships, the host portal registry `Register` call becomes conditional on a sandbox predicate, so AD-11's step 1 is a variable in the sequence rather than a constant. This is what makes plan 01-05's handshake sandbox-safe.
- **`status-type` ratified** as the shape of `GlobalHotkey`'s current-registration member, closing HOTKEY-06's gate and folding HOTKEY-03's description carrier into the same addition — one AD-9 gate spent instead of two.
- **Phase-7 spine hand-off filed** enumerating all four AD-9 declaration edits with spine line ranges. No line of `ARCHITECTURE-SPINE.md` was edited.
- **Flatpak sidecar-reachability cost filed** against the deferred packaging phase so it is not discovered mid-build.
- **The ledger lost exactly one line** — DW-89's old `status: open`, the line the closure replaces.

## Human Answers (verbatim — plans 01-05 and 01-06 read these and must not re-ask)

### Task 1 — packaging formats: `three-formats`

> `.deb`/tarball, Flatpak, AppImage — D-18 as stated on 2026-09-01, with no primary build and none second-class.
>
> Because this differs from DW-89's own `decision:` line (four formats, 2026-08-14, ledger line 1349), the `resolution:` you insert MUST explicitly name the supersession: the 2026-09-01 three-format answer governs, the 2026-08-14 four-format `decision:` line is superseded, and the native Arch PKGBUILD is dropped from the committed set. State it in words — do not silently disagree, and do not rewrite or delete line 1349.
>
> The four `finish-args` lines stand as you measured them, uncorrected: `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, and `--talk-name=org.freedesktop.secrets` (Phase 6's API key only). No `--filesystem=` of any kind. Record that the GlobalShortcuts portal needs no grant, and that a sandboxed build must therefore not call the host portal registry's `Register` method — making AD-11's step 1 conditional rather than constant.

### Task 2 — `GlobalHotkey` current-registration member: `status-type`

> One new member `HotkeyStatus? get current`, returning a new type carrying `outcome` plus a nullable `backendDescription`. No declared field of `HotkeyRegistration` / `HotkeyBound` / `HotkeyUnavailable` is touched, so the in-tree `bindingChanges` precedent covers the addition. Synchronous — no microtask on the settings-screen mount path. This closes HOTKEY-06 and carries HOTKEY-03's compositor description text on the same member.

## Task Commits

1. **Task 1: Packaging format decision** — no commit (`checkpoint:decision`, `gate="blocking-human"`; answer recorded above and transcribed in Task 3)
2. **Task 2: `GlobalHotkey` member ratification** — no commit (`checkpoint:decision`, `gate="blocking-human"`; same)
3. **Task 3: Write both decisions into the append-only ledger** — `faab606` (docs)

**Plan metadata:** see the `docs(01-01): complete packaging and AD-9 port-surface decisions plan` commit.

## Files Created/Modified

- `_bmad-output/implementation-artifacts/deferred-work.md` — DW-89 closed (line 1348 `status: done 2026-09-01`, line 1349 the inserted single-line `resolution:`, line 1350 the original `decision:` preserved verbatim); three new flat entries appended at lines 1736–1749 (AD-9 port-surface ratification, Phase-7 spine reconciliation hand-off, Flatpak sidecar cost), each with fields indented exactly two spaces and each `status: open`.

## Decisions Made

All five key decisions are listed in the frontmatter. The two that were the human's to make are quoted verbatim above. Three follow-on calls were taken by the executor within the plan's instructions:

- **The sidecar cost is recorded in two places, not one.** DW-89's resolution names it as an open cost on the deferred packaging phase (as the plan's Edit 1 required) *and* it has its own flat entry (as the coordinator directed). The resolution points at the standalone entry rather than carrying the full argument, so DW-89 does not become the home for a cost that belongs to the packaging phase.
- **`source_spec:` for the three new flat entries is `.planning/phases/01-hotkey-truth/01-01-PLAN.md`.** Existing flat entries cite the spec that raised them; this plan is the honest origin, and it keeps the entries traceable back to the decision gate.
- **A5 is recorded inside DW-89's resolution as an unverified premise of the permission set** (the Flatpak runtime redirecting `XDG_DATA_HOME`/`XDG_CONFIG_HOME` into `~/.var/app/$FLATPAK_ID`, so `AppPaths.fromEnvironment` needs no change). The permission set is only correct if that holds, so the caveat belongs with the set rather than in a separate entry.

## Deviations from Plan

### Auto-fixed Issues

**1. [Coordinator-directed addition] Fourth ledger edit — the Flatpak sidecar cost got its own flat entry**

- **Found during:** Task 3 (ledger write), on explicit coordinator instruction accompanying the checkpoint answers
- **Issue:** The plan's Edit 1 recorded the sidecar reachability cost *only* inside DW-89's `resolution:`. The coordinator judged the finding material enough to need its own entry against the packaging phase, since a cost buried in a closed entry's resolution is not visible to ledger triage — `bmad-loop sweep` counts `status:` lines, and a closed entry contributes nothing.
- **Fix:** Appended a third new flat entry (beyond the plan's two) recording the daemon → Python sidecar → `claude` CLI chain, the sandbox unreachability of both host binaries, the bundling-vs-`flatpak-spawn --host` fork with the note that the escape route contradicts D-19, and the A6 `[ASSUMED]` caveat. DW-89's resolution still names the cost and now points at this entry. **DW-89 was not reopened.**
- **Files modified:** `_bmad-output/implementation-artifacts/deferred-work.md` (same file — the plan's `files_modified` is unaffected)
- **Verification:** Entry present at line 1747, `status: open`, two-space indent confirmed by `grep -n '^  summary:' | tail -3`. Append-only invariant still holds: `git diff --numstat` reports 17 insertions and **1** deletion.
- **Committed in:** `faab606` (Task 3 commit)

**Consequence for the plan's own verification, recorded so a later reader is not confused by a passing check that reads as failing:** plan `<verification>` item 3 and Task 3's fifth `<automated>` check both expect the flat `status: open` count to end **two** higher than before (52 → 54). It ends **three** higher (52 → 55) because of this third entry. The check's `<fails_when>` condition is "the count is lower than it was before this task" — 55 is higher, so the check passes as written; only the parenthetical expectation of "+2" is superseded.

---

**Total deviations:** 1 (coordinator-directed scope addition; no auto-fixed bugs, no blockers, no architectural changes)
**Impact on plan:** Additive and inside the plan's declared file set. The append-only invariant, the one-deleted-line gate, and the untouched-spine gate all still hold. No scope creep into code — this plan still creates no file and edits no Dart.

## Issues Encountered

None. Every automated `<verify>` and every `<acceptance_criteria>` item passed on the first run, and the plan's assumed byte offsets for DW-89 (`status: open` at 1348, `decision:` at 1349) were verified against the file before editing rather than trusted.

Both plan-level controls confirm the tree is unchanged for the plans that follow:

- `dart analyze --fatal-infos` — **No issues found!**
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — **946 passed / 2 skipped / 0 failed**, matching the 2026-09-01 baseline exactly. (A bare `dart test` is wrong in this tree and fails to load 69 suites; it was not used.)

## Known Stubs

None. This plan writes no code and leaves no placeholder. The three new ledger entries carry `status: open` deliberately — they are open work items handed to later plans (01-06, 01-10) and later phases (7, packaging), not unfinished work from this plan.

## Threat Flags

None. No new network endpoint, auth path, file-access pattern or schema change was introduced — the only change is a local file write under git. The plan's own register was honored: T-01-01 (repudiation) is mitigated by the explicit supersession sentence and carried into UAT as coverage item D7; T-01-02 (tampering / append-only) is mitigated by the one-deleted-line gate, which passed; T-01-03 (information disclosure via a widened permission set) is mitigated — no `--filesystem=` and no `--talk-name=org.freedesktop.Flatpak` were recorded, and the set was not widened for pipeline convenience; T-01-04 (host escape) remains `accept`, recorded as an open cost rather than taken.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Ready for 01-02.** Wave 1 is complete and both gates that block the rest of the phase are answered:

- **Plan 01-05** can now write the portal handshake sandbox-safe: Flatpak is in the committed set, so `Registry.Register` is conditional on a sandbox predicate (`PortalAppIdRegime`). The decision it needed is recorded in DW-89 and cannot be un-decided.
- **Plan 01-06** can now implement `HotkeyStatus? get current` with `outcome` plus nullable `backendDescription`, and must carry HOTKEY-03's localized description on that member — not on a declared field of `HotkeyRegistration`. Both answers are quoted verbatim above; do not re-ask.
- **Plan 01-04** (`HotkeyUnavailable`'s cause) and **plan 01-09** (`HotkeyBinding`'s `const` constructor) each still own their own fresh AD-9 ratification gate. Those were deliberately not settled here.

**Carried concerns, none blocking:**

- **HOTKEY-06 is ratified, not implemented.** FLAT-02 remains `status: open`; plan 01-06 lands the code and plan 01-10 closes it. The `requirements-completed` entry above is intentional per the template contract (copy the plan's `requirements` verbatim) — the shared-ID gate defers marking HOTKEY-06 `Complete` in REQUIREMENTS.md until every declaring plan has a SUMMARY.
- **Two unverified assumptions now underwrite a recorded decision.** A6 (no Python/`claude` bundling exists today) and A5 (the Flatpak runtime redirects XDG variables, so `AppPaths.fromEnvironment` needs no change) are both marked `[ASSUMED]` in the ledger. Neither affects Phase 1 code; both land on the packaging phase. If A5 is wrong, a Flatpak build writes to an unwritable path.
- **The probe row for HOTKEY-06 remains `unclassified`/`unresolved`** and was not auto-resolved with a backstop. Plan 01-06's truths cover the requirement's behavior; what stays open is whether an edge case of the *shape* kind exists on it at all.

## Self-Check: PASSED

- `_bmad-output/implementation-artifacts/deferred-work.md` — FOUND on disk
- Task 3 commit `faab606` — FOUND in `git log --oneline --all`
- No files claimed as created (this plan creates none), so nothing to verify there
- `dart analyze --fatal-infos` clean and 946/2/0 test result re-confirmed after the ledger commit

**Requirement marking deferred by the shared-ID gate, not skipped.** `requirements.ready-ids` returned `0/2 ready`: `ARCH-02` is also declared by plans 01-05 and 01-10, and `HOTKEY-06` by plans 01-06 and 01-10. Neither may read `Complete` in REQUIREMENTS.md until every declaring plan has a SUMMARY, so `requirements.mark-complete` was correctly not run. Both IDs are re-evaluated each time a sibling plan in this phase finishes.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-01*
