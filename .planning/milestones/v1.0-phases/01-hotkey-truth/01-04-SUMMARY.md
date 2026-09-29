---
phase: 01-hotkey-truth
plan: 04
subsystem: ui
tags: [dart, flutter, sealed-classes, enum, value-equality, dbus, x11, wayland, settings]

# Dependency graph
requires:
  - phase: 01-03
    provides: "the non-destructive X11 rebind — its edits collapsed one of x11_global_hotkey.dart's four HotkeyUnavailable construction sites, so this plan found 13 in lib/ where the plan text predicted 14"
  - phase: 01-01
    provides: "the X11KeyGrabRegistrar seam and the HotkeyRegistrar port that x11_global_hotkey.dart's refusal branches sit behind"
provides:
  - "HotkeyUnavailableCause — a three-value enum (noBackend, keyRefused, revoked) making D-06's three meanings machine-readable"
  - "HotkeyUnavailable.cause — a required, defaultless field beside the retained message; a construction site naming no cause does not compile"
  - "Value equality and hashCode over both cause and message, so two outcomes differing only in cause cannot dedupe against each other and suppress a SettingsState rebuild"
  - "_PortalRefusal carries a cause out of the four-deep portal handshake; _refusalFor returns cause and sentence together so the two cannot drift"
  - "hotkey_status_view.dart selects its first line from the cause rather than from the text of message, and cannot render a blank unavailable state"
affects: [02-tray-and-settings, 01-06, 01-10, 07-spine-reconciliation]

actuals:
  tokens: 84740
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Cause-as-value: a discriminator enum beside a retained free-text message, so a consumer branches on a field and the specific diagnosis still reaches the user verbatim"
    - "Classify-once: _refusalFor returns a (cause, message) record so the classification and the sentence are decided in one switch arm and cannot drift apart"
    - "Defaultless required field as a compile-time forcing function: a fourth cause cannot be added without every construction site deciding what the user is told"

key-files:
  created: []
  modified:
    - lib/src/domain/hotkey/hotkey_bind_outcome.dart
    - lib/src/ui/settings/hotkey_status_view.dart
    - lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart
    - lib/src/infrastructure/hotkey/x11_global_hotkey.dart
    - lib/src/infrastructure/system/daemon_startup.dart
    - lib/src/application/settings_controller.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
    - test/application/settings_controller_test.dart
    - test/domain/value_equality_test.dart
    - test/application/state_equality_test.dart
    - test/composition/daemon_graph_test.dart
    - test/infrastructure/system/daemon_lifecycle_test.dart
    - test/ui/settings/settings_screen_config_test.dart

key-decisions:
  - "Task 1 ratified `cause-field` on 2026-09-01: HotkeyUnavailable gains a required, defaultless cause enum beside the retained message, editing AD-9's verbatim field list at ARCHITECTURE-SPINE.md lines 274-278. ARCHITECTURE-SPINE.md is NOT edited by this phase; the record goes to deferred-work.md via plan 01-10 and Phase 7 reconciles the spine."
  - "Enum name is `HotkeyUnavailableCause`, declared beside the class it qualifies in hotkey_bind_outcome.dart rather than in a new file, following hotkey_binding.dart's in-tree `enum HotkeyModifier` precedent for AGENTS.md §3."
  - "keyRefused is deliberately wider than the literal per-key case: a portal that answered unreadably has demonstrably NOT left the user without a backend, so reporting noBackend would tell them to give up when retrying is not futile."
  - "None of the three cause lines names the tray. Every adapter message already ends by naming it, and a screen that added the sentence printed it twice. The single exception is _trayFallback on the empty-message path, where there is no adapter sentence to have carried it."
  - "The three causes chose NO new affordance. D-06 is explicit that the messages differ and the UI does not; the button count in hotkey_status_view.dart is still zero."
  - "settings_screen.dart and settings_screen_config_test.dart were listed in Task 3's <files> but needed no Task 3 edit — see Deviations."

patterns-established:
  - "Cause-as-value beside a retained message: the enum answers 'what should the user do', the message answers 'what exactly happened', and neither is asked to do the other's job"
  - "A required defaultless field as the mechanism that makes a future fourth case impossible to add silently"
  - "Widget-test rows that push the SAME message text under DIFFERENT causes, so a screen that regressed to matching on prose could not distinguish them and the row fails"

requirements-completed: [HOTKEY-08]

coverage:
  - id: D1
    description: "A consumer distinguishes 'no backend on this desktop' from 'that key was refused' from 'your shortcut was taken away' by reading HotkeyUnavailable.cause, without inspecting the text of message"
    requirement: HOTKEY-08
    verification:
      - kind: unit
        ref: "test/domain/value_equality_test.dart (5 HotkeyUnavailable construction sites, cause-bearing)"
        status: pass
      - kind: other
        ref: "grep -rn 'HotkeyUnavailable(' lib/src/infrastructure lib/src/application — all 13 construction sites name a cause (multi-line-aware check; see Issues Encountered)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The cause field is required and defaultless, so a construction site that does not name a cause does not compile"
    requirement: HOTKEY-08
    verification:
      - kind: other
        ref: "grep -n 'required this.cause' lib/src/domain/hotkey/hotkey_bind_outcome.dart — matches; no line in that file assigns a default"
        status: pass
      - kind: other
        ref: "export PATH=...; dart analyze --fatal-infos — No issues found!"
        status: pass
    human_judgment: false
  - id: D3
    description: "HotkeyUnavailable equality and hashCode cover both cause and message, so two values differing only in cause are not equal and a SettingsState holding one is never deduped against a state holding the other"
    requirement: HOTKEY-08
    verification:
      - kind: unit
        ref: "test/domain/value_equality_test.dart; test/application/state_equality_test.dart"
        status: pass
      - kind: other
        ref: "grep -n 'Object.hash' lib/src/domain/hotkey/hotkey_bind_outcome.dart — Object.hash(cause, message) inside HotkeyUnavailable"
        status: pass
    human_judgment: false
  - id: D4
    description: "_PortalRefusal carries a cause out of the four-deep portal handshake, and _refusalFor assigns it per detected condition rather than as a blanket value"
    requirement: HOTKEY-08
    verification:
      - kind: unit
        ref: "test/infrastructure (scoped dart test run, 946 passing)"
        status: pass
      - kind: other
        ref: "grep -n 'class _PortalRefusal' -A 10 lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart — const _PortalRefusal({required this.cause, required this.message}) plus _PortalRefusal.of(_Refusal)"
        status: pass
    human_judgment: false
  - id: D5
    description: "hotkey_status_view.dart renders a different sentence for each of the three causes, selected by the cause rather than by the content of message"
    requirement: HOTKEY-08
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart — 'A6 AD-12: with no backend at all...' and 'A9 AD-11, AD-12: a shortcut the desktop dropped...' (the latter pushes the same message text under revoked then keyRefused)"
        status: pass
      - kind: other
        ref: "grep -n 'message.contains|message ==|message.startsWith|message.toLowerCase' lib/src/ui/settings/hotkey_status_view.dart — no matches"
        status: pass
    human_judgment: false
  - id: D6
    description: "An empty or whitespace message still yields a non-empty rendering that names the tray"
    requirement: HOTKEY-08
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart — the blank-message push in 'A9 AD-11, AD-12: a shortcut the desktop dropped...' asserts both the cause sentence and 'tray menu still opens the panel'"
        status: pass
    human_judgment: false
  - id: D7
    description: "A degraded or lost hotkey produces no desktop notification, no modal and no tray alarm — the daemon stays invisible and the user finds out when they next look (D-09)"
    verification:
      - kind: other
        ref: "grep -rn 'SnackBar|showDialog|AlertDialog|SystemSound|HapticFeedback' lib/src/ui/settings/hotkey_status_view.dart lib/src/ui/settings/settings_screen.dart — no matches"
        status: pass
    human_judgment: false
  - id: D8
    description: "The three sentences read as three different things to a person in a live session, on a real desktop, for each of the three causes"
    requirement: HOTKEY-08
    verification: []
    human_judgment: true
    rationale: "Task 3's <human-check> requires driving each cause in a live GUI session and reading the sentence. Owed for all three causes — see the Human-Check Results table. keyRefused needs a second X client holding the grab and a human clicking through Settings; noBackend needs a session with no global-shortcut mechanism; revoked needs a compositor that takes the shortcut away. This devcontainer has Xvfb but no GUI driver, and the only release bundle on disk predates both task commits, so running it would have exercised the old code and produced a false pass."

duration: 1h 45m
completed: 2026-09-02
status: complete
---

# Phase 01 Plan 04: HotkeyUnavailable's Three Causes Summary

**`HotkeyUnavailable` gained a required, defaultless three-value `cause` enum beside its retained `message`, and the settings read-out now picks what it says from that field instead of from the prose — closing FLAT-04 and HOTKEY-08.**

## Performance

- **Duration:** ~1h 45m across two sessions (Task 2 on 2026-09-01, Task 3 resumed and finished 2026-09-02)
- **Started:** 2026-09-01T22:18:02Z (Task 2 commit; Task 1 ratified earlier that day)
- **Completed:** 2026-09-02T10:41:00Z
- **Tasks:** 3 of 3
- **Files modified:** 13 (6 in `lib/`, 7 in `test/`)

## Accomplishments

- **Three meanings became one field.** `HotkeyUnavailableCause{noBackend, keyRefused, revoked}` is declared beside the class it qualifies, and `HotkeyUnavailable.cause` is required with no default. A consumer that wants to know whether retrying is futile reads a field; nothing has to match on English any more. That is HOTKEY-08's whole requirement text and FLAT-04's fix.
- **The settings screen tells the three apart on screen.** `_causeLine` switches exhaustively over the three causes, producing "no combination can be registered here" / "choose a different one and apply it again" / "set it again when you want it back". The widget rows push the *same message text* under two different causes, so a screen that regressed to matching on prose would fail rather than silently render identically.
- **A blank adapter message can no longer produce a blank unavailable state.** Because the first line comes from the cause, that is now structurally impossible; `_trayFallback` carries D-07 on the one path where there is no adapter sentence to have carried it.
- **The cause classification is per-branch, not blanket.** `_refusalFor` assigns `noBackend` to socket failures, closed buses, `ServiceUnknown`/`UnknownObject` and the wlroots `UnknownMethod`/`UnknownInterface` case, and `keyRefused` to the unclassified fallback — the reasoning behind T-01-17, which is that a blanket cause sends the user in the wrong direction.

## Task Commits

1. **Task 1: Ratify the edit to AD-9's declared field list** — no commit (checkpoint:decision, gate=`blocking-human`); the answer is recorded in commit `34e588c`'s body and reproduced verbatim below.
2. **Task 2: Add the cause and name it at every construction site, in one compiling change** — `34e588c` (feat), 12 files
3. **Task 3: The settings screen tells the three causes apart, and every one still names the tray** — `d923b13` (feat), 2 files

**Plan metadata:** see the `docs(01-04)` commit that carries this SUMMARY.

## Task 1's Answer, Verbatim

Task 1's acceptance criteria require the human's answer recorded verbatim in this SUMMARY. Ratified **2026-09-01**:

> The human chose option id `cause-field`: `HotkeyUnavailable` gains a required, defaultless `cause` enum field beside the retained `message`, editing AD-9's verbatim field list at ARCHITECTURE-SPINE.md lines 274–278. Confirmed with the answer: the field is required with no default; the record goes to `deferred-work.md` via plan 01-10; `ARCHITECTURE-SPINE.md` is NOT edited by this phase (Phase 7 reconciles it).

As committed in `34e588c`'s body: *"Edits AD-9's verbatim field list at spine 274-278, ratified 2026-09-01. The spine is not edited here; Phase 7 reconciles it."*

Against Task 1's four remaining acceptance criteria: the answer names exactly one option id (`cause-field`); it is not `message-only`, so no replan and no HOTKEY-08 escalation was needed; it confirms the field is required with no default; and it confirms the ledger record and the spine's exclusion from this phase.

## The Final Enum Name

**`HotkeyUnavailableCause`** — the plan's working name, kept unchanged. Declared **beside** `HotkeyUnavailable` in `lib/src/domain/hotkey/hotkey_bind_outcome.dart` rather than in a new file, following `hotkey_binding.dart`'s in-tree `enum HotkeyModifier` beside `final class HotkeyBinding` precedent, which the plan named as the second defensible reading of AGENTS.md §3.

## The Cause Chosen at Every Construction Site

`lib/` holds **13** `HotkeyUnavailable` construction sites, not the 14 the plan's `<interfaces>` block predicted — see Deviations. Every one names a cause.

| Site | Enclosing member | Cause | Why |
|---|---|---|---|
| `x11_global_hotkey.dart:204` | `_bind` | `keyRefused` | The X server refused the grab. A working backend, one bad key. |
| `x11_global_hotkey.dart:289` | `_refusedBeforeBackend` | `keyRefused` | A key outside the catalogue, or one whose grab cannot be built — caught before the backend is touched, but the backend is there. |
| `x11_global_hotkey.dart:326` | `_shutDownDuringBind` | `noBackend` | There is no backend left; the existing wording already said so. |
| `wayland_portal_global_hotkey.dart:248` | `bind` | `dead.cause` (`noBackend`) | Dead connection, latched by `_recordDeadConnection`. |
| `wayland_portal_global_hotkey.dart:265` | `_bind` | `dead.cause` (`noBackend`) | Same latch, checked again inside `_bind`. |
| `wayland_portal_global_hotkey.dart:272` | `_bind` | `noBackend` | Unusable bus address — there is no portal to talk to. |
| `wayland_portal_global_hotkey.dart:356` | `_bind` | `refusal.cause` (from `_refusalFor`) | Handshake failure; the cause travels out of the four-deep handshake on `_PortalRefusal`. |
| `wayland_portal_global_hotkey.dart:366` | `_bind` | `refusal.cause` (from `_refusalFor`) | Second handshake-failure return, same carrier. |
| `wayland_portal_global_hotkey.dart:909` | `_onShortcutsChanged` | **`revoked`** | The one site in the codebase that produces it, and the case the enum exists for. D-08 forbids re-claiming. |
| `wayland_portal_global_hotkey.dart:1012` | `_closeSessionBeforeRebinding` | `refusal.cause` | A dead connection recorded mid-rebind. |
| `wayland_portal_global_hotkey.dart:1128` | `_shutDownDuringBind` | `noBackend` | No backend left. |
| `daemon_startup.dart:222` | `requestBinding` | `noBackend` | The backstop for an adapter that threw; the branch is about the backend not answering. |
| `settings_controller.dart:432` | `_bind` | `noBackend` | The application-ring backstop for a bind that failed outside the adapter — read the surrounding `try` and it is the same "no answer came back" shape. |

**`_refusalFor`'s switch arms** (`wayland_portal_global_hotkey.dart:1242+`), where the classification is actually made:

| Detected condition | Cause |
|---|---|
| `SocketException` | `noBackend` |
| `OSError` / `DBusClosedException` | `noBackend` |
| `DBusServiceUnknownException` / `DBusUnknownObjectException` | `noBackend` |
| `DBusUnknownMethodException` / `DBusUnknownInterfaceException` | `noBackend` — the wlroots case: Sway, Hyprland and Niri ship no GlobalShortcuts interface |
| unclassified (`_unclassified`) | `keyRefused` — the portal demonstrably answered, so telling the user to give up would be wrong |

The plan's `<flagged_assumptions>` said the causes for `daemon_startup.dart:222` and `settings_controller.dart:432` were not pre-decided and asked the executor to say so if neither fitted honestly. **Both fit `noBackend` honestly** and were assigned it; no forced choice was needed.

## Files Created/Modified

- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` — `HotkeyUnavailableCause` and the required `cause` field; equality and `hashCode` extended to `Object.hash(cause, message)`
- `lib/src/ui/settings/hotkey_status_view.dart` — the outcome switch destructures `(:final cause, :final message)`; `_unavailableLines(cause, message)`, the new `_causeLine(cause)` switch, and `_trayFallback` for the empty-message path
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — `_PortalRefusal` gains a cause; `_messageFor` became `_refusalFor`, returning `(cause, message)` together
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — three construction sites
- `lib/src/infrastructure/system/daemon_startup.dart` — the `requestBinding` backstop
- `lib/src/application/settings_controller.dart` — the application-ring backstop
- `test/ui/settings/settings_screen_hotkey_test.dart` — rows covering all three causes, the same-message/different-cause pair, and the blank-message path
- `test/application/settings_controller_test.dart`, `test/domain/value_equality_test.dart`, `test/application/state_equality_test.dart`, `test/composition/daemon_graph_test.dart`, `test/infrastructure/system/daemon_lifecycle_test.dart`, `test/ui/settings/settings_screen_config_test.dart` — existing construction sites now name a cause

## Verification Results

| Check | Result |
|---|---|
| `dart analyze --fatal-infos` | **No issues found!** |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **All tests passed!** — 946 passing, 2 skipped (≥ 900 ✓) |
| `flutter test test/ui/settings` | **All tests passed!** — 46 |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | **All tests passed!** — 165 |
| `grep -c 'noBackend' hotkey_status_view.dart` | 1 (≥ 1 ✓) |
| `grep -c 'keyRefused' hotkey_status_view.dart` | 1 (≥ 1 ✓) |
| `grep -c 'revoked' hotkey_status_view.dart` | 2 (≥ 1 ✓) |
| `grep -c 'noBackend\|keyRefused\|revoked' hotkey_status_view.dart` | 4 (≥ 3 ✓) |
| No branching on message content | **no matches** ✓ |
| No notification surface in either UI file | **no matches** ✓ |
| Button count in `hotkey_status_view.dart` | `ElevatedButton` 0, `TextButton` 0, `OutlinedButton` 0 — unchanged from HEAD ✓ |
| `grep -c 'tray' hotkey_status_view.dart` | 8 (≥ 1 ✓) |
| `_regimeOf` / `_regimeWithoutCombination` untouched | **byte-identical** to HEAD, verified by extracting both method regions and `diff`-ing ✓ |
| `_boundLines` untouched | **byte-identical** ✓ |
| `testWidgets(` count in the changed test file | 20 before, 20 after — unchanged ✓ |
| New test files added | **none** ✓ |
| Every `lib/` construction site names a cause | **13/13** ✓ (multi-line-aware check — see Issues Encountered) |
| Sender filter on the revocation signal survives (T-01-21) | preserved — `sender: _portalService` at `:822` and `:829` ✓ |

### Human-Check Results

Recorded honestly. The plan's instruction was *"never as passed when it was not run."*

| Cause | Result | Why |
|---|---|---|
| `keyRefused` | **Owed to a real session** | Needs a second X client holding the grab *and* a human clicking through Settings to apply the combination. This devcontainer has `Xvfb` and `xvfb-run`, but no GUI driver to open Settings and press Apply. The only release bundle on disk (`build/linux/x64/release/bundle/`, 2026-09-01 09:36) **predates both task commits**, so running it would have exercised the pre-`cause` code and produced a false pass. |
| `noBackend` | **Owed to a real session** | Needs a session with no global-shortcut mechanism. Anticipated as owed by the plan itself. |
| `revoked` | **Owed to a real session** | Needs a compositor that takes the shortcut away. Anticipated as owed by the plan itself. |
| "No notification, dialog or sound appears in any case (D-09)" | **Observed at source, not in a session** | The negative source gate over both UI files returns no matches, and this plan added no notification surface. That the *running* app produces none is the part still owed with the three rows above. |

The source-level and widget-level substitutes that *did* run are recorded in `coverage` D5–D7. What is owed is specifically the visual reading — that the three sentences read as three different things to a person.

## Decisions Made

- **`keyRefused` is deliberately wider than "this key was refused."** A portal that answered unreadably, or refused to open a session, has demonstrably *not* left the user without a backend. Reporting `noBackend` there would tell them to give up when retrying is not futile; reporting `keyRefused` sends them to the one action that might work, and the specific diagnosis stays in `message`, which every surface renders. Documented on the enum value itself.
- **None of the three cause lines names the tray.** `_unavailableLines` puts the cause sentence first and the adapter's message second, and every adapter message already ends by naming the tray. A cause line that named it too would print it twice, which is exactly the failure the widget's existing contract doc records. `_trayFallback` is reached *only* when `message.trim().isEmpty`, precisely so the tray is never named twice on the paths where the adapter already named it.
- **Whitespace counts as absent.** `message.trim().isEmpty` rather than `message.isEmpty` — a message of blank space would otherwise render a stripe of nothing between two sentences that read as consecutive. This is a check on *emptiness*, not on content, so it does not violate the no-branching-on-prose gate.
- **`_messageFor` became `_refusalFor`, returning a `(cause, message)` record.** The plan asked for the cause to be assigned in `_messageFor`'s switch. Returning both halves from one arm means the classification and the sentence are decided together and cannot drift — a later edit cannot reword an arm's message without seeing the cause it sits beside.

## Deviations from Plan

### Auto-fixed / adapted

**1. [Rule 3 - Blocking] `settings_screen.dart` and `settings_screen_config_test.dart` were listed in Task 3's `<files>` but needed no Task 3 edit**

- **Found during:** Task 3, checking the pre-existing working-tree work against the acceptance criteria
- **Issue:** Task 3's `<files>` names four files. Only two were modified. The question was whether the other two were a gap or genuinely unnecessary.
- **Resolution — genuinely unnecessary, and deliberately not edited:**
  - `lib/src/ui/settings/settings_screen.dart` holds one pattern-match site, `HotkeyUnavailable() => null,` at `:144`, inside `_authority`. It compiles unchanged when a field is added, and Task 3's acceptance criteria ask nothing of it — the cause does not change *who owns the binding*, because when nothing is bound nobody owns it, which is the AD-10 point that `null` already makes. D-03 drops the regime label anyway. Task 2 did not touch it either, for the same reason.
  - `test/ui/settings/settings_screen_config_test.dart` has one construction site at `:603`, which **Task 2 already updated** to name a cause. Task 3's criteria are about the three-branch rendering, which the hotkey test file covers.
  - Editing either one purely to match the plan's file list would have been change for its own sake. Recorded here rather than silently.
- **Files modified:** none
- **Verification:** `grep -n 'HotkeyUnavailable' lib/src/ui/settings/settings_screen.dart` → one line, a pattern match; `dart analyze --fatal-infos` clean; `flutter test test/ui/settings` passes

**2. [Observation, not a fix] `lib/` holds 13 construction sites, not the 14 the plan predicted**

- **Found during:** Task 3 verification, re-counting to check Task 2's coverage
- **Issue:** The plan's `<interfaces>` block listed four `x11_global_hotkey.dart` sites (at pre-01-03 lines 176, 245, 265, 302) for a total of 14. The tree has three, for a total of 13.
- **Cause:** plan 01-03's non-destructive-rebind edits collapsed one of them. The plan itself warned that "line numbers in `x11_global_hotkey.dart` shift by plan 01-03's edits — locate by grep, not by offset"; the *count* shifted too. Task 2's commit body already recorded 13.
- **Impact:** none on correctness. Every site in the tree names a cause. Noted so a later reader comparing the plan's table against the code does not go hunting for a fourteenth site.
- **Files modified:** none

**3. [Observation] The plan's own `cause:` gate is defeated by `dart format`**

See Issues Encountered — the gate as written cannot pass on formatted Dart, and the substitute check is recorded there.

---

**Total deviations:** 1 adaptation (Rule 3, resolved by *not* editing), 2 recorded observations
**Impact on plan:** No scope change. The one adaptation avoided two gratuitous edits; the two observations correct the plan's counts and one of its gates for future readers.

## Issues Encountered

**The plan's `cause:` gate is unpassable as written on `dart format`ed source.** Task 2's acceptance criterion and plan-level verification step 4 both read:

```
grep -rn 'HotkeyUnavailable(' lib/src/infrastructure lib/src/application | grep -vc 'cause:'
```

and require it to print `0`. It prints **11**. That is not a missing cause — it is that `dart format` wraps every one of these constructors across lines, so `HotkeyUnavailable(` and `cause:` land on *different* lines and a per-line `grep -v` can never see them together. Two of the 11 are the unrelated `setHotkeyUnavailable` hits the plan's own `<interfaces>` block already documented as false positives.

The substitute check actually run, which is multi-line-aware: for every `HotkeyUnavailable(` occurrence in the four adapter/controller files (excluding `setHotkeyUnavailable`), scan the following lines for a `cause`. **All 13 construction sites name one.** Two sites needed a window wider than four lines because a doc comment sits between the constructor and its first argument (`wayland_portal_global_hotkey.dart:909` → `cause:` at `:921`; `daemon_startup.dart:222` → `cause:` at `:228`).

The compile-time guarantee is the stronger evidence anyway: the field is required and defaultless, so `dart analyze --fatal-infos` returning **No issues found!** *is* the proof that no site was missed. A grep cannot be more authoritative than the analyzer on this particular question.

**Task 3's work was already in the working tree, uncommitted, from an interrupted prior session.** It was verified against every acceptance criterion rather than re-derived, and nothing in it needed changing. No `git checkout`, `restore`, `stash`, `reset` or `clean` was run against either file.

## SETTINGS-09 (FLAT-16) Coordination

The plan asked whether this edit made the `_unavailableLines` doc comment accurate as a side effect, so Phase 2 verifies rather than re-edits. **Answer: partially, and deliberately not resolved.**

- **What changed:** the doc no longer contradicts itself. The old comment said "nothing is appended to it" while the method appended `'Whether this app or your desktop would own the shortcut is not known until one is registered.'` The new doc states plainly that the closing line *is* an append and that **SETTINGS-09 (FLAT-16) in Phase 2 owns whether it should exist at all.**
- **What did not change:** the append itself. The line is still emitted. The doc's original *claim* about the adapter's `message` — rendered as it stands, no tray sentence added by the screen — remains true and is now true of `_causeLine`'s three sentences as well, none of which names the tray.
- **What Phase 2 should therefore do:** verify, not re-edit the doc. The self-contradiction FLAT-16 reported is gone; the substantive question (should this widget append a line of its own?) is untouched and still SETTINGS-09's to answer. This phase deliberately did not pre-empt it.

One further coordination note for Phase 2 and for plan 01-06: `_regimeOf`, `_regimeWithoutCombination` and `_boundLines` are **byte-identical** to their pre-plan state, verified by diffing the extracted method regions. D-03 drops the regime label and D-04 supplies the compositor's description text in its place, but that text does not exist until plan 01-06 carries it out of the adapter. Plan 01-06 owns that edit and will find these three methods exactly as it expects them.

## Ledger Work Owed

**Plan 01-10 must record the AD-9 declaration edit in `_bmad-output/implementation-artifacts/deferred-work.md`.** Task 1's answer explicitly routes the record there rather than into `ARCHITECTURE-SPINE.md`. Two ledger entries are in scope:

- **FLAT-04** (the `HotkeyUnavailable` three-meanings entry, `deferred-work.md:1450-1453`) — `status: open` today, and this plan is its fix. Closing it means flipping `status:` and adding `resolution:`, never deleting it (the ledger is append-only).
- **A new entry, or an amendment, recording that AD-9's verbatim field list at spine 274–278 was edited** by human ratification on 2026-09-01, for Phase 7 to reconcile into the spine. Unlike `GlobalHotkey.bindingChanges`, this is *not* covered by the in-tree precedent for additions-beside — it changes a declared field list — which is why it needed its own decision.

`ARCHITECTURE-SPINE.md` is **out of date as of this plan** and stays that way by design until Phase 7.

## Threat Model Compliance

| Threat | Disposition | Evidence |
|---|---|---|
| T-01-17 (blanket cause misdirects the user) | mitigated | Every cause assigned per branch; the full 13-site and `_refusalFor` tables are above. `revoked` is produced at exactly one site, the `_onShortcutsChanged` revocation branch. |
| T-01-18 (consumers branching on prose) | mitigated | `grep` for `message.contains|==|startsWith|toLowerCase` in the widget → no matches. A widget row pushes the same message under two causes, so a prose-matching regression fails a test rather than going silent. |
| T-01-19 (rendered sentences leaking user text) | mitigated | All four sentences (`_causeLine` ×3, `_trayFallback`) are `const` string literals describing the mechanism. No interpolation of clipboard content, input text or a suggestion body anywhere in the unavailable path. |
| T-01-20 (notification storm on repeated revocation) | mitigated | No notification surface exists to storm on — negative source gate over both UI files returns no matches. |
| T-01-21 (forged revocation from a bus peer) | mitigated, preserved not added | The `_onShortcutsChanged` subscription is still sender-filtered on the portal's resolved unique name (`sender: _portalService`, `:822` and `:829`), with an in-code comment at `:918` marking the filter load-bearing. This plan's edits to that method did not simplify it away. |
| T-01-SC (package-manager installs) | accepted, n/a | No install occurred; `pubspec.yaml` and `pubspec.lock` are untouched. |

No new threat surface was introduced — no new endpoint, auth path, file access or schema change. No `## Threat Flags` section is needed.

## Known Stubs

None. No hardcoded empty value, placeholder string, `TODO`, `FIXME` or unwired data source was introduced. No test was skipped or marked `skip:`. The only defect-register item this plan leaves behind is the owed human-check, recorded as `human_judgment: true` in `coverage` D8 and in the Human-Check Results table — it is an unrun verification, not a stub.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Ready.** What the rest of the phase and Phase 2 inherit:

- **Plan 01-06** finds `_regimeOf`, `_regimeWithoutCombination` and `_boundLines` byte-identical, as designed. Its D-03/D-04 edit does not collide with anything here.
- **Plan 01-10** owes the two ledger records described above.
- **Phase 2's tray fan-out (SETTINGS-03, SETTINGS-06)** inherits a machine-readable `cause` and never has to parse prose to route on it, which was the stated reason `message-only` was rejected at Task 1.
- **Phase 2's SETTINGS-09 (FLAT-16)** should verify rather than re-edit the `_unavailableLines` doc; the substantive append question is untouched.
- **Phase 7** reconciles AD-9's spine declaration.

**Concern:** the three human-check rows are owed to a real session on real hardware. The rendering is proven at source and by widget rows, but nobody has yet *read* the three sentences on a live desktop. Worth folding into whatever UAT pass covers the hotkey surface — the failure mode it would catch is a sentence that is technically correct and reads badly, which no grep can see.

## Self-Check

**PASSED**

- `lib/src/ui/settings/hotkey_status_view.dart` — FOUND
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` — FOUND
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — FOUND
- `test/ui/settings/settings_screen_hotkey_test.dart` — FOUND
- Commit `34e588c` — FOUND in `git log --all`
- Commit `d923b13` — FOUND in `git log --all`
- No file deletions in either commit — verified with `git diff --diff-filter=D HEAD~1 HEAD`
- `.planning/config.json` excluded from both commits — verified; it carries an unrelated orchestrator change and remains uncommitted in the working tree
- No untracked `.claude/` tooling file entered either commit — every stage was an explicit `git add <path>`

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-02*
