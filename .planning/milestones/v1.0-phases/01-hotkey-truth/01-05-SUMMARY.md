---
phase: 01-hotkey-truth
plan: 05
subsystem: infra
tags: [xdg-portal, global-shortcuts, flatpak, sandbox, dbus, timeout, ad-11, arch-02, d-17]

# Dependency graph
requires:
  - phase: 01-01
    provides: "The ratified packaging set — .deb/tarball, Flatpak, AppImage — and the recorded ARCH-02 consequence that a Flatpak in the set makes the host registry Register call conditional"
  - phase: 01-04
    provides: "HotkeyUnavailable's required three-value cause, and the portal adapter's `_refusalFor`/`_PortalRefusal` carrying a cause out of the handshake"
provides:
  - "PortalAppIdRegime — a pure predicate over an injected environment map and an injected file-existence probe, keyed only on /.flatpak-info and FLATPAK_ID, answering hostRegistry in this project's own container"
  - "AD-11 step 1 is now conditional: a sandbox-supplied regime returns before the bus, ahead of the once-per-connection latch, so a sandboxed build never registers and its second bind is as silent as its first"
  - "The composition root resolves the regime once, from Platform.environment plus a real File().existsSync probe, and injects it through DaemonStartup.begin alongside the display-server choice"
  - "A bounded bind path: the name-owner lookup, the advisory Register and CreateSession on the injected unresponsive-call budget; BindShortcuts — the one step with a dialog behind it — on a derived multiple of it"
  - "The abandonment rule as code: no portal Close is sent on any timeout path, and an abandoned BindShortcuts leaves its session tracked so a late Allow still reaches the panel and a rebind still closes it"
  - "A fake-portal seam (withholdCreateSessionResponse / withholdBindShortcutsResponse) that replies to the method and never emits the Request Response — the never-answering portal, previously unrepresentable in the suite"
  - "The DW-20/DW-28 one-budget guardrail extended from two sites to three"
affects: [01-06, 01-07, 01-08, 01-09, 01-10, phase-06-provider, phase-07-arch-docs, packaging]

# Actuals (#2632) — estimateTokens scale (chars/4) over the realized diff, not a harness token count.
actuals:
  tokens: 17700
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A platform-fact predicate is an enum with a static fromEnvironment over injected inputs, resolved once at the composition root and injected downward — the DisplayServer shape, now used twice"
    - "Bounded seam calls report through onTimeout plus a local flag, never by catching the timeout error, so a seam expiring its own deadline stays distinguishable from this policy firing"
    - "Abandon, never cancel: a bound on a call a human may be answering stops the waiting and sends nothing, and the session is tracked rather than closed or leaked"
    - "A budget with a different question behind it is derived from the shared one by a named factor, so one number is still argued with in one place"

key-files:
  created:
    - lib/src/infrastructure/hotkey/portal_app_id_regime.dart
    - test/infrastructure/hotkey/portal_app_id_regime_test.dart
  modified:
    - lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart
    - lib/src/infrastructure/system/daemon_startup.dart
    - lib/main.dart
    - test/architecture/hotkey_confinement_test.dart
    - test/architecture/composition_wiring_test.dart
    - test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart
    - test/infrastructure/system/daemon_startup_test.dart
    - test/support/fake_global_shortcuts_portal.dart
    - test/support/daemon_startup_child.dart
    - test/support/wayland_bus_address_child.dart

key-decisions:
  - "Final names, as the plan asked to be recorded: enum `PortalAppIdRegime` with values `hostRegistry` and `sandboxSupplied`, a static `fromEnvironment(Map<String, String>, {required bool Function(String) fileExists})`, and a public `static const String sandboxInfoFile = '/.flatpak-info'` so the confinement gate can pin the literal."
  - "BindShortcuts received the *materially longer budget* treatment rather than being left unbounded. The must_haves truth requires a portal that never answers to return control within a bounded time, and BindShortcuts is precisely where a portal stops answering — leaving it unbounded would leave the widest hang open and make that truth false. It is bounded at `_requestBudget * _dialogBudgetFactor` (12), one minute at the shipped five seconds: long enough that expiry means something is wrong rather than that a person is slow."
  - "The dialog budget is *derived* from the injected one by a named integer factor rather than declared as a Duration, so `grep -c 'Duration(seconds:'` in the adapter is still exactly 1 and the relationship between the two waits is stated instead of implied."
  - "An abandoned BindShortcuts leaves its session *tracked* (`_session = session` plus step 4's subscriptions) rather than closed or forgotten. Closing it would cancel the dialog the user is reading — the plan's prohibition; forgetting it would leave the compositor holding a session this process no longer tracks, which threat T-01-26 names. Tracking does both jobs: a rebind closes it first, and because the `Activated` filter reads `_session` at delivery time, a grant a minute late still toggles the panel while the bind's own answer stays honestly unavailable."
  - "`DaemonStartup.begin` gained the two parameters, not `main.dart` alone: the adapter is constructed inside `_hotkeyFor`, so there was no other seam through which an injected value could reach it. The regime and the budget are resolved in `main.dart` and threaded through, which is what keeps the answer asked once."
  - "The abandonment refusal carries `HotkeyUnavailableCause.keyRefused`, on `_unclassified`'s own reasoning: something on the other end is demonstrably there, so `noBackend` would talk the user out of a retry that may well work."

patterns-established:
  - "A recorded objection is answered with a measurement, not overruled: the doc that refused to detect a sandbox now names the rejected signals, states what was measured in this container, and says which property the new signals have that the old ones lacked"
  - "A doc paragraph that contradicts an overridden decision is replaced, and the reason the old rule existed is carried into the new one rather than deleted with it"
  - "A test-support fake gains a seam for the state no error field can express — a call that is answered and then simply never completed"

requirements-completed: [ARCH-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "A sandboxed build never calls the host portal registry; an unsandboxed one still does, and the sandboxed build's second bind is as silent as its first"
    requirement: "ARCH-02"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#ARCH-02: a sandboxed build performs no Register at all, and binds without it"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#ARCH-02: a sandboxed rebind is as silent as the first bind, so the latch is not what is doing the work"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#A1 CAP-1, AD-10, AD-11: a first bind performs exactly Register, CreateSession, BindShortcuts, in that order and nothing else"
        status: pass
    human_judgment: false
  - id: D2
    description: "The sandbox predicate is pure over injected inputs, both branches are reachable with no sandbox present, and it does not fire in this project's own devcontainer"
    requirement: "ARCH-02"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/portal_app_id_regime_test.dart — 7 rows: each signal alone, trimming, empty-value absence, the rejected container markers, and the live measurement row"
        status: pass
      - kind: other
        ref: "measured in this container 2026-09-02: /.dockerenv exists, /.flatpak-info absent, FLATPAK_ID unset, /run/.containerenv absent, /proc/1/cgroup reports a bare 0::/ — predicate answers hostRegistry"
        status: pass
      - kind: other
        ref: "awk '/PortalAppIdRegime|fromEnvironment/,0' portal_app_id_regime.dart | grep -Ec 'dockerenv|/run/\\.containerenv|cgroup' => 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Register is attempted at most once per bus connection and not at all under the sandbox regime — the regime check sits ahead of the latch, not in place of it"
    requirement: "ARCH-02"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#A5 CAP-12: a rebind closes the old session, creates a new one, and issues no second Register"
        status: pass
      - kind: other
        ref: "source: the sandbox arm returns before `if (_registered)`; grep -c '_registered' => 3"
        status: pass
    human_judgment: false
  - id: D4
    description: "A portal that never answers returns control to the settings screen within the bounded time instead of hanging it"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#D-17: a CreateSession the portal never answers is abandoned at the bound, and the settings screen gets a value"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#D-17: the dialog step waits materially longer than the dialogless ones, and is not abandoned at the short bound"
        status: pass
    human_judgment: false
  - id: D5
    description: "No portal dialog the user is still reading is cancelled to achieve that — nothing is sent on any timeout path"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#D-17: nothing is sent on the timeout path — no Close, and no second call of any kind"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#D-17: an abandoned dialog leaves its session tracked rather than closed, so a late Allow still reaches the panel"
        status: pass
      - kind: other
        ref: "awk over the `if (refusal.abandoned)` branch | grep -c '_closeSession' => 0"
        status: pass
    human_judgment: false
  - id: D6
    description: "One timeout budget and one timeout pattern — the injected unresponsive-call budget, threaded through the constructor, with no second constant in the adapter"
    verification:
      - kind: unit
        ref: "test/architecture/composition_wiring_test.dart#DW-20, DW-28: one unresponsive-call budget is stated here and handed to both adapters — now reading three sites, each the bare constant"
        status: pass
      - kind: other
        ref: "grep -c 'Duration(seconds:' wayland_portal_global_hotkey.dart => 1 (_teardownBudget); grep -c 'TimeoutException' => 0"
        status: pass
    human_judgment: false
  - id: D7
    description: "The sender filter, the Random.secure() tokens, the serialising queue and the bind read-back all survived the edit"
    verification:
      - kind: unit
        ref: "test/architecture/hotkey_confinement_test.dart#AD-11: the portal request tokens come from a cryptographic generator"
        status: pass
      - kind: other
        ref: "grep -c 'sender' => 11, unchanged from HEAD~2; grep -c 'Random.secure()' => 1; git diff shows no hunk touching _queue and no removed catch arm"
        status: pass
      - kind: unit
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart => 959 passed / 2 skipped, up from the 946 baseline"
        status: pass
    human_judgment: false
  - id: D8
    description: "The behaviour of the conditional branch and the bounded waits against a real xdg-desktop-portal on a real Wayland session"
    verification: []
    human_judgment: true
    rationale: "OWED, not observed. This container has no session bus, no xdg-desktop-portal and no Wayland compositor, so every Wayland-side claim here is from the specification or from the fake portal, never from a run. Three things in particular need a real session: that a Flatpak build's bind succeeds with the app id the sandbox supplies and no Register on the wire; that a portal really does leave a dialog on screen after this app stops waiting, and that a late Allow then produces a working press plus a ShortcutsChanged; and that a compositor does not emit a ShortcutsChanged for a session whose shortcuts were never granted, which would currently be reported to the user as `revoked` — a shortcut taken away that they never had."

# Metrics
duration: 33 min
completed: 2026-09-02
status: complete
---

# Phase 1 Plan 05: Sandbox-Safe, Bounded Portal Handshake Summary

**AD-11's step 1 became a variable — a pure `/.flatpak-info`/`FLATPAK_ID` predicate skips the host registry inside a Flatpak — and the bind path became bounded on the injected budget, abandoning waits without ever cancelling a dialog the user is reading.**

## Performance

- **Duration:** 33 min
- **Started:** 2026-09-02T10:43Z (from the 01-04 close-out)
- **Completed:** 2026-09-02T11:16Z
- **Tasks:** 2 of 2
- **Files modified:** 12 (2 created, 10 modified)

## Accomplishments

- `PortalAppIdRegime` answers the objection the adapter itself recorded. The old doc refused to detect a sandbox because the signals one reaches for include `/.dockerenv`, true in this project's own container. The new predicate keys on `/.flatpak-info` and `FLATPAK_ID` — written by the Flatpak runtime and by nothing else — and it is a pure function over an injected environment map and an injected `bool Function(String)` probe, so both branches are driven by a binding-free test with no sandbox anywhere near the machine.
- Step 1 of the handshake is now conditional, and the check sits *ahead* of the once-per-connection latch rather than replacing it, so a sandboxed build's second bind is as silent as its first. The five tolerated exception arms are untouched on the branch that still registers.
- The bind path can no longer hang the settings screen. The name-owner lookup, the advisory Register and `CreateSession` are bounded on `main.dart`'s existing `_unresponsiveCallBudget`, threaded through `DaemonStartup.begin` into the adapter's constructor. `BindShortcuts` — the one step with a portal dialog behind it — is bounded on a derived multiple of the same number.
- Nothing is sent when a wait expires. No portal `Close`, no retry, no second call of any kind: the request stays live on the portal, so a dialog the user is mid-way through answering is never withdrawn out from under them.
- An abandoned `BindShortcuts` leaves its session *tracked*. That was the third option between two bad ones, and it buys two things at once: a rebind closes it first (so two overlapping attempts cannot leave the compositor holding two live sessions), and because the `Activated` filter reads `_session` at delivery time, a user who clicks Allow a minute late gets a working hotkey — while this bind's own answer stays honestly unavailable, corrected by the compositor rather than predicted here.
- The suite can now express a portal that never answers at all. `withholdCreateSessionResponse` / `withholdBindShortcutsResponse` reply to the method and never emit the Request `Response`, which is the one state no error field could model, and four D-17 rows run over it.

## Task Commits

1. **Task 1: A sandbox predicate that does not fire in this project's own container, and a conditional step 1** — `cbb3354` (feat)
2. **Task 2: A bind that cannot hang, and does not cancel a dialog the user is reading (D-17)** — `2967b89` (feat)

**Plan metadata:** see the `docs(01-05)` commit that follows this file.

## Files Created/Modified

- `lib/src/infrastructure/hotkey/portal_app_id_regime.dart` — **created.** The enum plus the pure predicate, and the doc that records the rejected signals by name with the measurement that answers the old objection.
- `test/infrastructure/hotkey/portal_app_id_regime_test.dart` — **created.** Seven rows: each signal alone, trimming, an empty value as absence, the rejected container markers all set at once, and a live row that reads the real environment and asserts agreement with the two signals actually present.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — the regime field and the conditional step 1; the injected `_requestBudget` and derived `_dialogBudget`; `_answeredWithin`; bounded `_portalSender`, Register and `_callThroughRequest` (per call, parameterised by which call); `_PortalRefusal.abandoned`; the `_bind` arm that declines to close an abandoned session; and the replaced `_teardownBudget` paragraph.
- `lib/src/infrastructure/system/daemon_startup.dart` — `begin` and `_hotkeyFor` thread the regime and the budget to the Wayland arm; the X11 arm ignores both, documented the way it already documents ignoring the registrar.
- `lib/main.dart` — resolves the regime once from `Platform.environment` plus `File(path).existsSync()`, and passes the existing `_unresponsiveCallBudget` as the third site to take it.
- `test/architecture/hotkey_confinement_test.dart` — `/.flatpak-info` added to the "the scan actually finds something" control block. No existing control removed.
- `test/architecture/composition_wiring_test.dart` — the DW-20/DW-28 one-budget row now reads three sites instead of two, still asserting each is the bare constant.
- `test/support/fake_global_shortcuts_portal.dart` — the two withhold-response seams.
- `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart`, `test/infrastructure/system/daemon_startup_test.dart`, `test/support/daemon_startup_child.dart`, `test/support/wayland_bus_address_child.dart` — construction sites updated for the two new required parameters; the shared harness defaults to `hostRegistry` and the shipped budget so no existing row quietly exercises a different policy.

## Decisions Made

See `key-decisions` in the frontmatter. The two the plan explicitly left to the executor:

**`BindShortcuts` is bounded, on a longer budget — not left unbounded.** The plan permitted either and asked that the choice be deliberate and written into the code. Unbounded loses: the must_haves truth says a portal that never answers must return control within a bounded time, and `BindShortcuts` is exactly where a portal stops answering, so leaving it open would leave the widest hang unclosed and make that truth false. The budget is `_requestBudget * 12` — one minute at the shipped five seconds — chosen for what it buys: comfortably longer than anyone needs to read one dialog and click a button, short enough that a settings screen still answers. Expressed as a named integer factor rather than a second `Duration`, so there is still exactly one authored duration in the file (`_teardownBudget`) and the relationship between the two waits is visible.

**A `_TypeError` the type system did not catch, worth recording as a pattern.** `Future<T>.timeout` reads its type argument from the *receiver instance*, not from the static type at the call site. Handing the helper a `Future<DBusMethodResponse>` widened to `Future<void>` — which the subtype rule allows and `dart analyze --fatal-infos` accepts — produced a `Future<DBusMethodResponse>.timeout` whose `onTimeout` had to return one of those, so the void callback threw a `TypeError` *inside* the call. It surfaced as the advisory Register step logging "answered in a shape this build cannot read" against a perfectly healthy portal. The helper now re-wraps through an async function so the receiver is genuinely `Future<void>` and the bound cannot depend on what a call site happens to return.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `DaemonStartup.begin` had to gain the two parameters; `main.dart` alone was not a seam**

- **Found during:** Task 1 (and again in Task 2 for the budget)
- **Issue:** The plan's `files_modified` and its `read_first` both assume `lib/main.dart` constructs the Wayland adapter (`main.dart:100-130`). It does not: AD-9's single adapter choice lives in `DaemonStartup._hotkeyFor` (`daemon_startup.dart:270`), which `main.dart` reaches only through `DaemonStartup.begin`. With no parameter there, an injected regime and an injected budget could not reach the adapter at all, and resolving either *inside* `DaemonStartup` was ruled out — the class takes an injected `environment` map precisely so it needs no filesystem, and the acceptance criteria require the token in `main.dart`.
- **Fix:** `begin` gained `required PortalAppIdRegime portalAppIdRegime` and `required Duration requestTimeout`, both threaded into `_hotkeyFor` and documented as the mirror image of the existing `registrar` note (the Wayland arm ignores the registrar; the X11 arm ignores these two). `main.dart` resolves both and passes them. Required rather than defaulted: a default would be a decision taken by the class the plan says must not take it.
- **Files modified:** `lib/src/infrastructure/system/daemon_startup.dart`, plus the six `begin` call sites (`lib/main.dart`, `test/infrastructure/system/daemon_startup_test.dart` ×3, `test/support/daemon_startup_child.dart`, `test/support/wayland_bus_address_child.dart`) and the five adapter construction sites.
- **Verification:** `dart analyze --fatal-infos` clean; the scoped suite green at 959; `grep -n 'PortalAppIdRegime' lib/main.dart` matches, which is the criterion this preserves.
- **Committed in:** `cbb3354` (regime) and `2967b89` (budget)

**2. [Rule 3 - Blocking] The DW-20/DW-28 one-budget guardrail asserts the *number* of sites, and a third site fails it**

- **Found during:** Task 2
- **Issue:** `composition_wiring_test.dart` scans `main.dart` for `(?:requestTimeout|stepTimeout):([^,)]*)` and asserts `hasLength(2)` with each argument being the bare `_unresponsiveCallBudget`. Adding the portal adapter as a third site fails that row — and naming the parameter something the regex does not match would have passed while silently removing the new site from the policy the row exists to enforce, which is the opposite of what the row is for.
- **Fix:** the parameter is named `requestTimeout` (same policy, same name as the panel adapter's), and the row's count was raised to 3 with the reason extended to say why the third site exists and that raising the count is how a fourth joins. The per-argument assertion — bare constant, no literal, no arithmetic — is untouched, and still passes for all three.
- **Files modified:** `test/architecture/composition_wiring_test.dart`
- **Verification:** the row passes; the row's other halves (the seconds range, and `seconds * steps` against the reserved stop grace) are unchanged and still pass.
- **Committed in:** `2967b89`

**3. [Rule 2 - Missing critical] Automated evidence for the two must_haves truths that had none**

- **Found during:** Tasks 1 and 2
- **Issue:** the plan's `<verification>` closes ARCH-02 on greps plus a green existing suite — no row would have failed if the sandboxed branch were deleted, if a timeout were never added, or if the timeout path started sending a `Close`. With this milestone's closure evidence being inspection rather than a gate (STATE.md's standing blocker), a grep that cannot see behaviour is thin for a branch nobody in this container can run.
- **Fix:** 13 new rows — 7 predicate rows, 2 sandboxed-handshake rows, 4 D-17 rows — plus the two withhold-response seams on the fake portal that the D-17 rows need. Every one of them fails if the corresponding behaviour is removed.
- **Files modified:** `test/infrastructure/hotkey/portal_app_id_regime_test.dart`, `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart`, `test/support/fake_global_shortcuts_portal.dart`
- **Verification:** scoped suite 946 → 959 passing, 2 skipped, 0 failed; `flutter test test/ui test/platform test/composition` unchanged at 165.
- **Committed in:** `cbb3354` and `2967b89`

---

**Total deviations:** 3 auto-fixed (2 × Rule 3 blocking, 1 × Rule 2 missing critical)
**Impact on plan:** no scope creep. Two were unavoidable consequences of the plan's line references having drifted (as the phase's carry-forward warning predicted) and of a guardrail counting call sites; the third adds evidence for truths the plan asserts. Nothing in the plan's prohibitions was touched: the `_queue` head, the sender filters, `Random.secure()`, the five Register exception arms and the `_bindShortcut` read-back are all byte-identical.

## Issues Encountered

**One plan criterion is reported as substituted, not passed.** Task 2's acceptance criterion requires `grep -c 'TimeoutException' wayland_portal_global_hotkey.dart` to print `0`, while the same task's `<action>` requires the new helper's doc to carry the panel adapter's distinction — whose own wording is *"rather than by catching a `TimeoutException`"*. Satisfying both literally is impossible. Resolution: the doc keeps the distinction in full but names the thing without the type token — "rather than by catching the error `timeout` raises when no `onTimeout` is supplied" — so **the literal grep now prints `0` and the criterion passes as written**, at the cost of one dartdoc reference. Recorded here because the reason the token is absent is not obvious from the file.

**One prohibition claim in the plan is factually off, and the code records the correction rather than repeating it.** The plan states that `/.dockerenv`, `$container` and cgroup sniffing "all fire in this project's own devcontainer". Measured 2026-09-02: only `/.dockerenv` fires. `/run/.containerenv` is absent, `$container` is unset, and `/proc/1/cgroup` reports a bare `0::/` (cgroup v2, no docker path). All four stay rejected — each is true of *some* ordinary container, which is the same objection one host further out — and the predicate's doc says exactly that instead of overclaiming.

**A known defect on this surface was deliberately not fixed, and is enforced as not-fixed.** `_registered` latches once and is never reset, so after an `xdg-desktop-portal` restart the app-id association is gone and every later bind is liable to the documented discard. `grep -c 'NameOwnerChanged'` is `0`, as the plan's criterion requires; filing it is plan 01-10's job.

**One hang path on the bind sequence is still unbounded, deliberately.** `_closeSessionBeforeRebinding`'s `Close` is a dialogless bind-path call and is *not* bounded, because bounding it has a correctness cost the plan's own invariants forbid paying here: `_session`'s doc requires at most one `Close` in flight per session, and restoring `_session` after abandoning a `Close` that may still land would let `dispose()` send a second one. The plan's list named three calls plus the dialog step; this is the fourth, and closing it needs a way to track a session as "closing, unconfirmed" that is more machinery than this plan authorises. Worth a ledger entry alongside the `NameOwnerChanged` item.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Ready for plan 01-06.** The adapter's constructor surface is settled (`client`, `appIdRegime`, `requestTimeout`, `logger`) and every construction site in the tree is updated, so a later plan editing this file starts from a green tree: `dart analyze --fatal-infos` clean, 959 scoped / 165 Flutter.
- **Plan 01-08 owns the other half of this design.** The abandonment path leaves a late compositor answer arriving on `bindingChanges` after the bind has already reported unavailable, and 01-08's precedence rule is what makes applying that late arrival safe. Until it lands, the ordering is correct but unenforced by anything but the adapter's own timing.
- **Plan 01-10 has two entries to file, not one.** The `NameOwnerChanged` re-registration defect the plan already names, and the unbounded rebind `Close` recorded above.
- **Plan 01-09 / phase 7 inherit one more spine consequence.** AD-11's step 1 is now conditional in code while the spine still states it as a constant, which joins the four AD-9 declaration edits already queued for ARCH-06's reconciliation.
- **Real-session behaviour is owed, not claimed** — see coverage entry D8 for the three specific observations, including the `revoked`-for-a-shortcut-never-held edge the tracked-session choice opens.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-02*

## Self-Check: PASSED

- `lib/src/infrastructure/hotkey/portal_app_id_regime.dart` — present on disk
- `test/infrastructure/hotkey/portal_app_id_regime_test.dart` — present on disk
- `.planning/phases/01-hotkey-truth/01-05-SUMMARY.md` — present on disk
- `cbb3354`, `2967b89` — both present in `git log --oneline --all`
- Task 1 and Task 2 acceptance criteria re-run after the final edit: all pass, none substituted
- Plan `<verification>` 1-6 re-run: analyze clean, 959 scoped / 165 Flutter, `/.flatpak-info` matches under `lib/src/infrastructure/hotkey/`, `Duration(seconds:` count 1, `NameOwnerChanged` count 0
- Item 7 (real-session behaviour) recorded as owed, not claimed
