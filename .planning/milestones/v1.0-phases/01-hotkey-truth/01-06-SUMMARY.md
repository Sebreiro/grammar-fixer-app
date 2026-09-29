---
phase: 01-hotkey-truth
plan: 06
subsystem: ui
tags: [global-shortcuts, xdg-portal, trigger-description, ad-9, ad-10, hotkey-03, hotkey-06, d-03, d-04, settings]

# Dependency graph
requires:
  - phase: 01-01
    provides: "The ratified `status-type` shape for GlobalHotkey's current-registration member — `HotkeyStatus? get current` carrying an outcome plus a nullable backendDescription, with HOTKEY-03's localized text riding the same member"
  - phase: 01-04
    provides: "HotkeyUnavailable's required three-value cause, and hotkey_status_view's cause-selected unavailable rendering that this plan had to leave intact while replacing everything beside it"
  - phase: 01-05
    provides: "The portal adapter's bounded handshake, tracked-session abandonment rule and _refusalFor/_PortalRefusal cause plumbing — the paths this plan hangs the description cache off"
provides:
  - "HotkeyStatus — a domain value type carrying the newest outcome and the backend's own wording for what is in effect, with value equality over both fields"
  - "GlobalHotkey.current — a synchronous, I/O-free accessor answering that status, so a settings surface that mounts long after a desktop-side rebind reads the live state instead of the startup bind's answer"
  - "Both adapters and all four fakes answer the member, each through one recording funnel rather than an assignment per return site"
  - "The portal's trigger_description is carried out of the adapter instead of only logged — from the BindShortcuts read-back, from every ShortcutsChanged, and from a new explicit ListShortcuts re-read"
  - "A settings screen that renders the reported combination on X11 and the desktop's own wording verbatim on Wayland, with the authoritative-versus-advisory regime label gone from the UI"
  - "SettingsState.hotkeyBackendDescription — the application-ring carrier that gets that wording from the port to the screen"
  - "A ShortcutsChanged for a session that never held our shortcut is no longer reported to the user as revoked"
  - "A compositor change that lands while a bind is in flight is no longer overwritten by that bind's answer on current"
affects: [01-07, 01-08, 01-10, phase-02-settings-tray, phase-07-arch-docs]

# Actuals (#2632) — estimateTokens scale (chars/4) over the realized diff, not a harness token count.
actuals:
  tokens: 17400
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A port gains a synchronous accessor beside its stream when the consumer is a surface that mounts late — the AD-8 isVisible/changes pairing, now used for the hotkey too"
    - "One recording funnel per adapter (`.then(_recordStatus)` on the queued bind, plus the push helper for backend-originated changes) instead of an assignment at every return site: 'every outcome updates the cache' becomes a property of the shape"
    - "Vendor text that is displayed rather than interpreted is rendered on a line of its own, under a line naming whose words it is — never interpolated into an app-authored sentence"
    - "A guard counter for 'whichever is newer': a bind captures the backend-change count when it is issued and declines to record its own answer if that count moved while it waited"

key-files:
  created:
    - lib/src/domain/hotkey/hotkey_status.dart
  modified:
    - lib/src/domain/hotkey/global_hotkey.dart
    - lib/src/infrastructure/hotkey/x11_global_hotkey.dart
    - lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart
    - lib/src/ui/settings/hotkey_status_view.dart
    - lib/src/ui/settings/settings_screen.dart
    - lib/src/application/settings_state.dart
    - lib/src/application/settings_controller.dart
    - test/fakes/fake_global_hotkey.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
    - test/application/state_equality_test.dart
    - test/application/settings_controller_test.dart
    - test/infrastructure/system/daemon_lifecycle_test.dart
    - test/infrastructure/system/daemon_startup_test.dart

key-decisions:
  - "Final names, as the plan asked to be recorded: the file is `lib/src/domain/hotkey/hotkey_status.dart`, the type is `HotkeyStatus`, its fields are `outcome` (non-nullable `HotkeyBindOutcome`) and `backendDescription` (nullable `String`), and the port member is `HotkeyStatus? get current`. Every one is the working name from 01-01's ratification — nothing was renamed, so plan 01-10's ledger entry can cite these verbatim."
  - "`outcome` is non-nullable and `current` is the nullable half. 'Nothing has been asked of a backend yet' is the absence of a status, not a status carrying an absent outcome, so a consumer holding one always has something to render."
  - "The description had to be plumbed through SettingsState to reach the screen, which took three files the plan did not list. Without it the Wayland branch of the new rendering would have been unreachable in production — a stub, which the executor contract forbids. Carried as one nullable String beside `hotkeyBindOutcome` rather than by replacing that field with the whole `HotkeyStatus`, because plan 01-08 owns the outcome-versus-change precedence in that controller and a field swap would have pre-empted it."
  - "`ListShortcuts` is called from exactly one production site: a bind the compositor granted whose read-back carried no `trigger_description` at all. Unconditional use was rejected — AD-11 fixes the handshake at four steps and row A1 asserts 'exactly Register, CreateSession, BindShortcuts and nothing else' — and a method with no production caller would have been dead code, which CLAUDE.md forbids. Its failure is a log line, never a refusal: the shortcut is already bound and failing the bind over the wording for it would take a working hotkey away over a sentence."
  - "The `ShortcutsChanged`-without-grant edge that 01-05 filed open is FIXED here, because HotkeyStatus made it cheap and correct: a revocation is only reported when the last recorded status was a `HotkeyBound`. The session is tracked from the moment a BindShortcuts is abandoned (D-17), where nothing was granted, so a compositor announcing that session's shortcuts would otherwise have told the user their desktop took away a shortcut they never had."
  - "`_recordStatus` gives a description only to a `HotkeyBound`. That one rule makes three sites correct at once: a successful bind carries its own read-back, an abandoned rebind carries the *previous* wording (nothing clears the cache on the way into a rebind), and every unavailable outcome carries none, because there is no shortcut for wording to be about."
  - "A bind captures the backend-change count when it is issued and declines to record its answer if that count moved. Without it a bind parked on a portal dialog for a minute would overwrite a revocation that arrived while it waited, on the one member a late-mounting screen reads — which would make `HotkeyStatus.outcome`'s own 'whichever is newer' contract false. It is the adapter-side half only; the controller-side precedence stays plan 01-08's."
  - "Case 3 of the new rendering says 'A shortcut is in effect, but nothing was reported about which combination it is' rather than the plan's literal 'a sentence that says nothing is in effect'. The outcome on that branch is `HotkeyBound` — something took the request — so a sentence claiming nothing is in effect would be false, which is the class of claim this whole phase exists to remove."
  - "`_unavailableLines`' closing sentence ('Whether this app or your desktop would own the shortcut is not known until one is registered') was left exactly as 01-04 left it. It names no regime, it is on the path where nothing is registered, and SETTINGS-09 (FLAT-16) in Phase 2 owns whether that method should append a line of its own at all. Flagged for Phase 2 rather than resolved here."

patterns-established:
  - "A structurally unpassable acceptance grep is answered with an anchored substitute plus a recorded substitution, never by reshaping the code to satisfy the literal command"
  - "A ratified option is implemented under its ratified names, so the ledger entry that closes the gate can quote the code"

requirements-completed: [HOTKEY-03, HOTKEY-06]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "The port carries a synchronous, I/O-free current-registration member answering a HotkeyStatus, and every implementer answers it"
    requirement: "HOTKEY-06"
    verification:
      - kind: other
        ref: "grep -n 'get current' lib/src/domain/hotkey/global_hotkey.dart => line 92; awk '/get current/,/;/' … | grep -c 'Future|async|await' => 0"
        status: pass
      - kind: other
        ref: "every 'implements GlobalHotkey' file declares the member: 2 adapters + 4 test doubles, enumerated by grep -rln 'implements GlobalHotkey' test/ lib/"
        status: pass
      - kind: unit
        ref: "test/fakes_smoke_test.dart#every domain port has a constructible fake (a fake missing the member does not compile)"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos => No issues found (the type system is what makes a synchronous member synchronous at every implementer)"
        status: pass
    human_judgment: false
  - id: D2
    description: "HotkeyStatus carries the newest outcome plus the backend's own wording, with value equality over both fields so a consumer can dedupe"
    requirement: "HOTKEY-06"
    verification:
      - kind: unit
        ref: "test/application/state_equality_test.dart#CAP-8, HOTKEY-03: a differing config, outcome, backend wording or failure kind makes the states differ"
        status: pass
      - kind: other
        ref: "source: exactly two `final` fields, `operator ==` and `hashCode` over both — lib/src/domain/hotkey/hotkey_status.dart:29,52"
        status: pass
    human_judgment: false
  - id: D3
    description: "The portal's trigger_description reaches the adapter's status from the bind read-back, from every ShortcutsChanged and from an explicit ListShortcuts re-read, is never parsed, and the abandoned rebind carries the previous wording"
    requirement: "HOTKEY-03"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart — the full adapter group (A1 read-back, A19b/A19c/C1/C2 ShortcutsChanged, the rebind and abandonment rows) still passes with the description now returned rather than only logged"
        status: pass
      - kind: other
        ref: "grep -c 'ListShortcuts' … => 5, routed through _callThroughRequest; awk over the getter => 0 ListShortcuts; grep -nE 'split\\(|RegExp\\(|parse\\(' … => no match anywhere in the adapter"
        status: pass
      - kind: other
        ref: "three `effective: null` code sites survive (grep -n 'effective: null' | grep -v '///' => 3 — the literal count-of-4 gate is a pre-existing doc mention; see Deviations)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A settings screen shows the reported combination on X11 and the desktop's own wording verbatim on Wayland, never the requested combination, with no regime label anywhere"
    requirement: "HOTKEY-03"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#A15 HOTKEY-03, D-04: a backend that reports wording instead of a combination has that wording shown verbatim, labelled as the desktop's own"
        status: pass
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#A3 AD-10, T-01-30: a backend that reported neither a combination nor a description says so, and the request is not shown in its place"
        status: pass
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#A1/A2/A8 — the combination is rendered on both display servers and no 'owns this shortcut' / 'takes effect' / 'chooses the combination' sentence is found"
        status: pass
      - kind: other
        ref: "grep -c '_regimeOf|_regimeWithoutCombination' lib/src/ui/settings/hotkey_status_view.dart => 0, and 0 anywhere under lib/"
        status: pass
    human_judgment: false
  - id: D5
    description: "A revoked shortcut is reflected and never re-claimed, and a ShortcutsChanged for a session that never held our shortcut is not reported as a revocation"
    requirement: "HOTKEY-03"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart#C2 AD-11, AD-12: a shortcut the desktop no longer holds is pushed up as HotkeyUnavailable naming the removal"
        status: pass
      - kind: other
        ref: "code-only scan of _onShortcutsChanged's body (sed-anchored on the declaration, comments stripped): 0 matches for a re-bind, a BindShortcuts or a callMethod — D-08 holds"
        status: pass
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#A9 AD-11, AD-12: a shortcut the desktop dropped switches the screen to the unavailable statement"
        status: pass
    human_judgment: false
  - id: D6
    description: "What the user actually sees on a real desktop: the compositor's own wording, and a desktop-side rebind made with the Settings screen closed showing up on mount"
    verification: []
    human_judgment: true
    rationale: "OWED, not observed — all three of Task 3's human checks. This container has no compositor, no session bus and no xdg-desktop-portal, so the two real-session steps (a German desktop rendering Strg+Umschalt+G, and a rebind made in the desktop's own settings with this app's screen closed) cannot be run here at all. The X11 step is owed for a different reason: the app builds and runs under Xvfb, but opening Settings requires a tray interaction nothing in this container can drive, and the only release bundle predates these commits. What each step asserts is pinned by widget rows (A1/A2/A8 for the absent regime wording, A15 for the verbatim description, and the port's synchronous member for the mount-time read), but a widget row is not a session. Filed as WINDOWS.md entry 10."

# Metrics
duration: 26 min
completed: 2026-09-02
status: complete
---

# Phase 1 Plan 6: Hotkey Truth on Screen Summary

**The settings screen now reads what is in effect synchronously from the port and renders it in whichever vocabulary is truthful — the reported combination on X11, the compositor's own `trigger_description` verbatim on Wayland — with the authoritative-versus-advisory regime label gone and the requested combination nowhere on screen.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-09-02T11:31:40Z
- **Completed:** 2026-09-02T11:57:00Z
- **Tasks:** 3 of 3
- **Files modified:** 13 modified, 1 created

## Accomplishments

- **`GlobalHotkey` gained the ratified synchronous member.** `HotkeyStatus? get current` answers the newest outcome plus the backend's own wording, reads a cached field, and performs no I/O — so a tray daemon's settings screen, which is almost never mounted when a desktop rebinds the shortcut, no longer has to have been listening (FLAT-02). Both adapters and all four test doubles answer it in the same change, each recording through one funnel rather than an assignment per return site.
- **The portal's own description is carried out of the adapter instead of only logged.** `_logTriggerDescription` now returns what it extracts; the adapter caches it from the `BindShortcuts` read-back (after the discard check, never before it), from every `ShortcutsChanged` that still holds our id, and from a new explicit `ListShortcuts` re-read routed through `_callThroughRequest`. All three `effective: null` outcomes carry the right wording, with the abandoned rebind carrying the **previous** one.
- **The regime label is gone from the UI (D-03) and the desktop's words are shown as its own (D-04).** `_regimeOf` and `_regimeWithoutCombination` are deleted with every call; `_boundLines` renders three cases and no branch without a combination reaches for the preference. The Wayland description is rendered on a line of its own under "Your desktop holds this shortcut and describes it as:" — verbatim, no recasing, no re-spelling into `Ctrl+Shift+G`.
- **Two defects beyond the plan's letter, both closed with it rather than filed.** A `ShortcutsChanged` for a session that never had a grant is no longer reported as `revoked` (01-05 left this open and asked this plan to evaluate it), and a bind parked on a portal dialog can no longer overwrite a compositor change that landed while it waited.
- **The suite is unchanged in size and green.** 959 passing / 2 skipped scoped, 165 passing / 7 skipped under `flutter test`, `dart analyze --fatal-infos` clean, and the total `test(` count across `test/` is 982 — exactly the baseline. Five regime-asserting widget rows were adapted, not added; A15 became D-04's verbatim-wording row and A3 the neither-reported row.

## Task Commits

1. **Task 1: Add the ratified port member and make both adapters answer it, in one compiling change** — `57749dc` (feat)
2. **Task 2: Carry the compositor's own description out of the adapter instead of only logging it** — `47da214` (feat)
3. **Task 3: The settings screen shows the desktop's own wording, and the regime label is gone** — `810aac7` (feat)

## Files Created/Modified

- `lib/src/domain/hotkey/hotkey_status.dart` — **created.** `HotkeyStatus` with `outcome` and `backendDescription`, value equality over both, and the doc that states why the description is rendered and never parsed.
- `lib/src/domain/hotkey/global_hotkey.dart` — `HotkeyStatus? get current`, documented on three points: why synchronous (AD-8's `isVisible`/`changes` pairing, FLAT-02), null-until-asked rather than null-as-error, and the AD-9 change class, quoting `bindingChanges`' own precedent sentence.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — a status field, the getter, and `_recordStatus` on the queued bind's tail. `backendDescription` is null here, with the reason: this app owns the grab, so the combination is what is reported.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — the status and description caches, the bind-answer guard, the `ListShortcuts` re-read, the never-granted revocation guard, and a rewritten class-doc measurement paragraph citing DW-66's ratified `decision:`.
- `lib/src/ui/settings/hotkey_status_view.dart` — both regime helpers deleted, `_boundLines` rewritten over three cases, a `backendDescription` parameter, and a class doc that records D-03's amendment and its accepted cost.
- `lib/src/application/settings_state.dart`, `lib/src/application/settings_controller.dart`, `lib/src/ui/settings/settings_screen.dart` — the carrier that gets the wording from the port to the screen (see Deviations).
- `test/fakes/fake_global_hotkey.dart` — answers `current`, recorded from `bind` and `emitBindingChange` through one place, with a `backendDescription` knob so a row can drive a portal-shaped backend.
- `test/ui/settings/settings_screen_hotkey_test.dart` — five rows adapted, no rows added.
- `test/application/state_equality_test.dart` — the existing differing-fields row extended to the new state field.

## Decisions Made

See the `key-decisions` frontmatter for the full list. The four that a later reader is most likely to need:

1. **Names.** `HotkeyStatus`, `outcome`, `backendDescription`, `current` — all as ratified in 01-01, nothing renamed, so plan 01-10 can cite the code.
2. **The description is plumbed through `SettingsState`**, in three files the plan did not list, because otherwise the Wayland rendering would be unreachable in production.
3. **`ListShortcuts` has exactly one production caller** — a granted bind whose read-back carried no wording — because an unconditional call would add a fifth step to AD-11's fixed sequence and a caller-less method would be dead code.
4. **Only a `HotkeyBound` gets a description**, which is the single rule that makes the successful bind, the abandoned rebind and every unavailable outcome correct at once.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] The description had nothing to travel on from the port to the screen**

- **Found during:** Task 3
- **Issue:** Task 3's `<files>` list is `hotkey_status_view.dart` plus its test, and the widget is fed `outcome: _state.hotkeyBindOutcome` from `SettingsState`. Nothing in the plan carried `backendDescription` from `GlobalHotkey.current` into that state, so the widget's Wayland branch — the ordinary Wayland case, and the point of D-04 — would have been unreachable in production: a stub, which the executor contract forbids and which the SUMMARY rules require to be declared rather than shipped quietly.
- **Fix:** `SettingsState` gained one nullable `hotkeyBackendDescription`; `SettingsController` writes it from `_hotkey.current?.backendDescription` in the same synchronous turn as each outcome (in `changeHotkey`, `applyStartupOutcome` and `_onBindingChanged`) and carries it through the three transitions that change nothing else; `settings_screen.dart` passes it to the widget. The field participates in `SettingsState`'s equality, without which a state carrying new wording would compare equal to the old one and never render.
- **Why not the whole `HotkeyStatus` in the state:** plan 01-08 owns the outcome-versus-change precedence inside that controller, and replacing `hotkeyBindOutcome` with a status would have pre-empted it. Recorded here so 01-08 can make that swap deliberately if it wants it.
- **Files modified:** `lib/src/application/settings_state.dart`, `lib/src/application/settings_controller.dart`, `lib/src/ui/settings/settings_screen.dart`, `test/application/state_equality_test.dart`
- **Verification:** `flutter test test/ui/settings` — 46 rows, including A15 asserting the exact German string reaches the screen; scoped `dart test` 959 passing; `dart analyze --fatal-infos` clean.
- **Committed in:** `810aac7`

**2. [Rule 1 - Bug] A `ShortcutsChanged` for a session that never held our shortcut was reported as a revocation**

- **Found during:** Task 2 (carried forward from 01-05's SUMMARY, which filed it open and asked this plan to evaluate it)
- **Issue:** `_session` is tracked from the moment a `BindShortcuts` is abandoned (D-17), where nothing was granted at all. A compositor announcing that session's shortcuts without our id took the revocation branch, so the user was told "Your desktop took this shortcut away" about a shortcut they never had.
- **Fix:** the branch reports a revocation only when the last recorded status is a `HotkeyBound`. Otherwise it logs that the compositor confirmed what this app already knew and emits nothing — the same reasoning the unreadable-payload branch above it already uses: the loss it would report was never established. The `HotkeyStatus` work is what made this expressible in one condition, which is why it was in scope rather than deferred.
- **Files modified:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`
- **Verification:** rows A19c and C2 (which emit the drop after a real grant) still pass; the whole adapter group is green.
- **Committed in:** `47da214`

**3. [Rule 1 - Bug] A bind's answer could overwrite a newer compositor change on `current`**

- **Found during:** Task 2
- **Issue:** `BindShortcuts` can sit behind a dialog for up to a minute. A `ShortcutsChanged` arriving in that window is the newer fact, but the bind's answer was recorded when it finally returned — so the one member a late-mounting settings screen reads would report the shortcut the app asked for over the one the compositor last named, making `HotkeyStatus.outcome`'s own "whichever is newer" contract false.
- **Fix:** a backend-change counter, captured when a bind is issued and compared when its answer lands; a bind whose window saw a change returns its answer to the caller but does not record it, and logs one line saying so. Counting backend changes only (never bind answers) is what stops one queued bind discarding the next one's answer.
- **Files modified:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`
- **Verification:** scoped suite green; the controller-side half of the same question stays plan 01-08's, unchanged.
- **Committed in:** `47da214`

### Acceptance criteria substituted rather than satisfied literally

Two of the plan's literal commands are structurally unpassable in a `dart format`ted tree. Neither was answered by reshaping the code; both were replaced by an anchored substitute that tests the real property, and neither is reported as having passed literally. Filed as WINDOWS.md entry 12.

| Plan's literal criterion | What it prints | Substitute run, and the real property |
| --- | --- | --- |
| `grep -c 'effective: null' wayland_portal_global_hotkey.dart` must print `3` | `4` — and it printed `4` at `HEAD~1` too, before this plan touched the file: `_onShortcutsChanged`'s doc comment has quoted the literal `` `effective: null` `` since before wave 6 | `grep -n 'effective: null' … \| grep -v '///'` prints **3**, the three construction sites at lines 530, 1319 and 1479. No site was added or removed and no combination was synthesised. |
| `awk '/_boundLines/,/^  }$/' hotkey_status_view.dart \| grep -c 'preference'` must be at most `1` | `3` | The same plan requires the "that differs from your preference" line to be **kept**, and `dart format` writes it across three lines (`if (effective != preference)`, the prose containing the word, and `hotkeyBindingLabel(preference)`) — so the literal gate cannot be met while obeying the instruction beside it. `sed -n '/^  List<String> _boundLines/,/^  }$/p'` shows all three occurrences inside the `effective != null` branch, ahead of both no-combination branches. Pinned behaviourally as well, by rows A3 (`'your preference'` findsNothing) and A15 (`'differs from your preference'` findsNothing). |

The `_onShortcutsChanged` re-bind gate has the same shape: run literally it prints `3`, because the awk range starts at the class doc's `[_onShortcutsChanged]` reference 1,170 lines above the method and sweeps in `bind()`. Anchored on the declaration and with comments stripped it prints **0**, so D-08 holds; the only match in the anchored range is a comment that mentions `BindShortcuts` by name.

---

**Total deviations:** 3 auto-fixed (1 × Rule 2 missing critical functionality, 2 × Rule 1 bug) plus 2 recorded criterion substitutions.
**Impact on plan:** No scope creep. The Rule 2 plumbing is the minimum that keeps Task 3's Wayland branch from being a stub, and it stops short of the `SettingsState` change plan 01-08 may want. Both Rule 1 fixes are inside the file Task 2 already rewrites, and one of them is a defect 01-05 explicitly handed to this plan.

## Issues Encountered

- **The plan's Task 3 wording for case 3 would have made the screen lie.** It asks for "a sentence that says nothing is in effect" on the branch where a backend reported neither a combination nor wording — but that branch's outcome is `HotkeyBound`, so something *is* in effect and only its identity is unknown. The rendered sentence says that instead: "A shortcut is in effect, but nothing was reported about which combination it is, so this app cannot show it." The criterion the plan actually pins — that the branch must not render `preference` — is met.
- **`ListShortcuts` is implemented but unexercised.** The fake portal implements no `ListShortcuts` and always sends a `trigger_description`, so the single production caller never fires in the suite. Its parsing reuses `_shortcutsIn` and `_descriptionIn`, which the tested paths exercise, so what is untested is the call itself. The plan's own flagged assumptions anticipate this ("a documented-but-unexercised path, and its first real exercise is owed to a session with a portal"); filed as WINDOWS.md entry 11 rather than papered over with a synthetic row, since the plan also required the total `test(` count to stay unchanged.
- **Phase 2 coordination, as the plan asked.** `_unavailableLines`' closing sentence — "Whether this app or your desktop would own the shortcut is not known until one is registered" — was **left exactly as 01-04 left it**. It names no regime, it is only reached where nothing is registered, and SETTINGS-09 (FLAT-16) owns the question of whether that method should append a line of its own. Nothing in this plan made 01-04's doc comment on that point inaccurate, so **Phase 2 should verify rather than re-edit**, with one thing newly worth its attention: with D-03's regime label gone from `_boundLines`, that closing line is now the only ownership vocabulary left anywhere in the status view. The field label `Shortcut preference` in `hotkey_preference_field.dart` also survives untouched — it is AD-10's "what you type is a request" vocabulary rather than the regime read-out, and plan 01-07 replaces that widget wholesale under D-14.
- **01-04's cause work is intact**, which the prompt required checking: `_causeLine`, `_trayFallback` and the cause-selected `switch` are untouched, no rendering path matches on message prose, and the row that pushes identical message text under two different causes still passes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Ready for plan 01-07** (HOTKEY-04's capture control, and the catalogue's change of role). It edits `settings_state.dart`, `settings_controller.dart` and `settings_screen.dart`, all three of which this plan touched — the changes are additive (one state field, one controller helper, one widget argument) and none of them touches the authority handling 01-07 works on.
- **Owed to plan 01-08:** the precedence rule this plan deliberately did not write. The adapter now keeps "whichever is newer" for `current`; the port doc's statement of the rule and the controller-side tie-break are 01-08's, and its author should decide whether `SettingsState` should carry the whole `HotkeyStatus` instead of the outcome plus a description field.
- **Owed to plan 01-10's ledger work:** the AD-9 declaration edit made here (`GlobalHotkey.current` plus the new `HotkeyStatus` type, ratified 2026-09-01), DW-66's closure with the final names quoted above, the D-03 amendment to AD-10's ratified stance at spine line 620, and WINDOWS.md entries 10–12. `ARCHITECTURE-SPINE.md` was **not** edited — `git status --porcelain _bmad-output/` is empty.
- **Concern, unchanged in kind from wave 5:** every Wayland claim here is from the specification, the shipped code or the fake portal, never from a run. The three human checks are owed, not observed.

## Self-Check: PASSED

- `lib/src/domain/hotkey/hotkey_status.dart` — FOUND
- `lib/src/ui/settings/hotkey_status_view.dart` — FOUND
- `lib/src/domain/hotkey/global_hotkey.dart` — FOUND
- Commit `57749dc` — FOUND
- Commit `47da214` — FOUND
- Commit `810aac7` — FOUND
- `dart analyze --fatal-infos` — clean
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — 959 passing, 2 skipped
- `flutter test --exclude-tags=live test/ui test/composition test/platform` — 165 passing, 7 skipped
- `grep -rhoE 'test\(' test/ | wc -l` — 982, the pre-plan baseline
- `git status --porcelain _bmad-output/` — empty

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-02*
