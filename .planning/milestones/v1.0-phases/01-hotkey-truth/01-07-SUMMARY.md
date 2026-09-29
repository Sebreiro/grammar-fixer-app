---
phase: 01-hotkey-truth
plan: 07
subsystem: ui
tags: [flutter, hotkey, x11, wayland, riverpod, settings, keyboard-capture]

requires:
  - phase: 01-hotkey-truth (plan 02)
    provides: the removal of the `hotkey_manager` plugin, which is what dissolved the seven-label wrong-key set this plan empties
  - phase: 01-hotkey-truth (plan 06)
    provides: `GlobalHotkey.current` and the `SettingsState` description field the settings screen renders beside the capture control
provides:
  - a capture control that reads the physical key, replacing the free-text key-label field and its four modifier toggles (D-14)
  - a five-subject capture validator in the application ring, each subject with its own user-facing reason (D-15)
  - the registrable key vocabulary as a domain value, built at the composition root and injected, so neither the application ring nor the ui ring names the infrastructure catalogue (DW-71)
  - the dissolved wrong-key label set removed outright, with the measurement that dissolved it kept in the catalogue's doc (DW-43 resolved)
  - a usage-to-label reverse lookup on the catalogue, replacing the registrar's private copy of the same derivation
affects: [01-08, 01-09, 01-10, phase-2 SETTINGS-09, phase-7 ARCH-06]

actuals:
  tokens: 26895
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A vocabulary value crossing AD-1's rings by composition-root injection rather than by import — a seam declared over a domain type, overridden only in main.dart"
    - "A capture control keyed on `KeyEvent.physicalKey.usbHidUsage`, the same integer the key table and the grab already use"
    - "Refusal as a sealed verdict with one reason per cause, decided in the application ring and rendered by the ui ring"

key-files:
  created:
    - lib/src/ui/settings/hotkey_capture_field.dart
    - lib/src/application/hotkey_capture.dart
    - lib/src/domain/hotkey/registrable_keys.dart
  modified:
    - lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart
    - lib/src/infrastructure/hotkey/x11_global_hotkey.dart
    - lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart
    - lib/src/application/settings_controller.dart
    - lib/src/application/composition/port_providers.dart
    - lib/src/application/composition/controller_providers.dart
    - lib/main.dart
    - lib/src/ui/settings/settings_screen.dart
    - lib/src/ui/settings/preset_choice_list.dart

key-decisions:
  - "Task 1 answered `explain-in-place` by the user on 2026-09-02; the standing hint renders before the first keypress and only where the application itself holds the grab"
  - "`labelsThatBindTheWrongKey` and `bindsTheWrongKey` removed outright rather than left as an empty set, because an always-false predicate leaves branches that can never run (AGENTS.md §1); the measurement survives as a doc paragraph"
  - "The key vocabulary is a domain `RegistrableKeys` value behind a new `registrableKeysProvider` seam, overridden in main.dart with `HotkeyKeyCatalogue.registrableKeys()`; it lands on `SettingsController.captureValidator` as a field, not on `SettingsState`"
  - "AltGr is refused on the logical `LogicalKeyboardKey.altGraph`, not on the physical `altRight`; a plain right Alt still folds into `HotkeyModifier.alt`, because keying on the physical key would refuse a legitimate Alt combination on every layout with no Level 3"
  - "Bare Escape releases the capture focus instead of being captured, because the handler answers `handled` for every key and keyboard traversal cannot otherwise leave the control; Escape with a modifier is still bindable"
  - "Apply requests whatever the control displays, so re-applying a stored binding stays the recovery path the adapter suite relies on; only a *capture* can be refused"

patterns-established:
  - "Pattern: a ring-crossing vocabulary is a value built at the composition root, never an import — the seam is declared over a domain type so the declaration itself passes AD-1"
  - "Pattern: a refusal carries a cause enum plus one sentence per cause; the widget selects styling from the cause and never parses the sentence (the same rule 01-04 established for HotkeyUnavailable)"

requirements-completed: [HOTKEY-04]

coverage:
  - id: D1
    description: "The user sets the shortcut by pressing the combination; no free-text key field and no modifier toggles remain"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#CAP-12, D-14: the modifiers the capture reads and the combination the screen reads back use one vocabulary"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/settings.png — live daemon under Xvfb :78, real X11 grab held"
        status: pass
    human_judgment: false
  - id: D2
    description: "A bare key is refused at capture with its own reason and the previous shortcut is kept (D-13, T-01-36)"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-13, D-15, T-01-36, T-01-37: a bare key and an AltGr combination are each refused at capture, with their own reason, and neither reaches the controller"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/hc1_barekey.png — bare `j` refused live, reason rendered in the error colour"
        status: pass
    human_judgment: false
  - id: D3
    description: "An AltGr combination is refused rather than folded into Alt, with a reason distinct from the bare-key one (T-01-37)"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-13, D-15, T-01-36, T-01-37: a bare key and an AltGr combination are each refused at capture, with their own reason, and neither reaches the controller"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/hc3_altgr.png — ISO_Level3_Shift+g through the real GTK embedder produced the AltGr refusal, settling flagged assumption A3"
        status: pass
    human_judgment: false
  - id: D4
    description: "A modifier-only press commits nothing and the capture keeps waiting; a held key commits exactly once"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-14, D-15: a modifier on its own commits nothing, a held key commits once, and a refusal clears when a combination that works is captured"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/hc2_modifieronly.png, scratchpad/hc4_released.png — Ctrl alone waited; Ctrl+Shift+J held 2.5s committed one combination"
        status: pass
    human_judgment: false
  - id: D5
    description: "Tab with a modifier is captured rather than eaten by focus traversal, now that the vendor plugin no longer mis-binds it"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-13, D-14, D-16, Task 1: Tab is capturable, the standing hint about the current shortcut is up before anything is pressed, and the control is read-only while a bind is in flight"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/hc5_tab.png — Ctrl+Tab captured live"
        status: pass
    human_judgment: false
  - id: D6
    description: "The control is read-only while a bind is in flight and displays no shortcut as in effect before it is (D-16)"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-13, D-14, D-16, Task 1: Tab is capturable, the standing hint about the current shortcut is up before anything is pressed, and the control is read-only while a bind is in flight"
        status: pass
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_config_test.dart#A17 AD-11: the controls are disabled while a mutation is in flight, and a failed one re-enables them"
        status: pass
    human_judgment: true
    rationale: "The automated rows drive it through a gated fake. The live half is OWED, not observed: an X11 grab resolves synchronously in microseconds and this container has no portal to park a bind on, so there is no in-flight window to see."
  - id: D7
    description: "Task 1's `explain-in-place`: pressing the shortcut you already have does nothing special, and a standing hint says why before anything is pressed"
    requirement: "HOTKEY-04"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#D-13, D-14, D-16, Task 1: Tab is capturable, the standing hint about the current shortcut is up before anything is pressed, and the control is read-only while a bind is in flight"
        status: pass
      - kind: manual_procedural
        ref: "scratchpad/settings.png (hint up before any keypress) and scratchpad/hc7_pressed_current.png (Ctrl+Shift+G went to the grab, not to the box)"
        status: pass
    human_judgment: false
  - id: D8
    description: "The dissolved seven-label wrong-key set no longer special-cases anything, and every gate row that read it names a live subject"
    requirement: "HOTKEY-04"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/hotkey_key_catalogue_test.dart#HOTKEY-04: the reverse lookup and the vocabulary are views of the one label table"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#AD-10, AD-12: a key outside the catalogue is refused before the backend is touched"
        status: pass
      - kind: unit
        ref: "test/architecture/hotkey_confinement_test.dart#AD-1, HOTKEY-04: the vocabulary the settings screen validates against is this build's, and refuses everything outside it"
        status: pass
    human_judgment: true
    rationale: "The truth the plan itself marked `verification: backstop` — that all seven of the dissolved labels now bind CORRECTLY — is not asserted by any of these rows. Space, Tab and Enter were each captured and bound live in this session (Ctrl+Tab captured; Alt+Space grabbed in the adapter suite), but F1-F4 were not exercised on a real X session at all. A verifier must not read D8 as proof of the backstop truth."
  - id: D9
    description: "Neither the application ring nor the ui ring names the infrastructure key catalogue; the vocabulary arrives by injection from main.dart"
    requirement: "HOTKEY-04"
    verification:
      - kind: unit
        ref: "test/architecture/ad1_import_rule_test.dart (all four ring rules plus the seam classification row, raised to 11 seams)"
        status: pass
      - kind: unit
        ref: "test/architecture/composition_wiring_test.dart (both parity directions: the declared seam has an override, the override has a seam)"
        status: pass
    human_judgment: false

duration: 41 min
completed: 2026-09-02
status: complete
---

# Phase 01 Plan 07: The Capture Control Summary

**The key-label text field is gone: the user presses the combination, the physical key's USB HID usage is the lookup, and every combination the app can already tell will not fire is refused at capture with its own reason — while the seven labels that used to bind the wrong key dissolved with the vendor plugin and stopped being a special case anywhere.**

## Performance

- **Duration:** 41 min
- **Started:** 2026-09-02T21:29Z
- **Completed:** 2026-09-02T22:10Z
- **Tasks:** 2 of 3 executed (Task 1 was a pre-answered checkpoint — see below)
- **Files modified:** 25 (3 created, 1 deleted, 21 modified)

## Task 1 — the answer, verbatim

Task 1 was a `blocking-human` `checkpoint:decision`. It was **not re-asked**: the answer was
already on disk in `01-GATE-ANSWERS.md`, decided by the user interactively on 2026-09-02, option id
**`explain-in-place`**. Reproduced verbatim as that task's acceptance criteria require:

> `explain-in-place` — Do nothing special; the capture shows a standing hint that the current
> shortcut cannot be re-captured, and offer a plain "keep current" affordance. No grab lifecycle
> change, no heuristic, and nothing the app claims that it cannot know. The user is told the truth
> about why one combination behaves differently.

How the four binding consequences were honoured:

1. **No grab release/re-take during capture.** Nothing in this plan touches the grab lifecycle;
   `X11GlobalHotkey`, `X11KeyGrabRegistrar` and `PanelController` keep the ownership 01-03 gave
   them. `grep -rn 'release\|ungrab' lib/src/ui/` finds nothing.
2. **No timeout heuristic.** There is no `Timer`, no `Duration` and no elapsed-time reasoning in
   `hotkey_capture_field.dart` or `hotkey_capture.dart`. Every answer is computed from the key event
   in hand.
3. **The hint renders before the user presses anything.** It is standing text in the build tree,
   gated only on `authority == BindingAuthority.application`. Observed live: the first screenshot of
   the settings screen, taken before any key was sent, already carries it (`scratchpad/settings.png`).
4. **The fourth, unchosen approach was not implemented.** Nothing correlates a capture with the
   daemon's own hotkey press event, and `PanelController` is untouched.

**One judgement call inside the answer, recorded for review.** The hint is shown only where the
claim is *true* — when the application owns the binding, which is the X11 grab. Under the portal the
compositor owns it and ordinary key events do reach a focused window; before any backend has
answered, nothing is held for a grab to swallow. Rendering it unconditionally would have stated
something false on Wayland, which is the one thing `explain-in-place` exists to avoid. The recorded
cost of the answer — that this states a mechanism difference D-03 argues against — is unchanged and
accepted; the hint's own doc comment says so out loud.

## Accomplishments

- **`hotkey_capture_field.dart` (516 lines) replaces `hotkey_preference_field.dart` (260 lines,
  deleted).** The capture reads `event.physicalKey.usbHidUsage` — exactly the integer the key table
  is keyed on and that `HotkeyGrab` carries — so there is no label guessing, no layout dependence,
  and a key whose name the user could never guess still binds. The four modifier toggles went with
  the text field: modifiers are read from `HardwareKeyboard.instance.logicalKeysPressed` at the
  moment a non-modifier key goes down, which is what makes a modifier-only press commit nothing.
- **Five refusal subjects, five distinct sentences**, decided in the application ring by
  `HotkeyCaptureValidator` and rendered by the widget: no modifier (D-13), modifier-only, a key
  outside the vocabulary, AltGr / Level 3, and a key with no portal trigger. The order is
  load-bearing — Level 3 is tested first, because an AltGr press carries no `HotkeyModifier` at all
  and every later branch would have described it as "no modifier": the right refusal with the wrong
  cause.
- **The dissolved set is gone, not emptied.** `labelsThatBindTheWrongKey`, `bindsTheWrongKey` and
  the X11 adapter's before-the-backend branch for them are removed. The measurement that dissolved
  them (XStringToKeysym and gtk_accelerator_parse probes from 2026-09-01) is now a doc paragraph in
  the catalogue, replacing the paragraph that explained why the set was populated.
- **The vocabulary crosses AD-1's rings as a value.** `RegistrableKeys` is a domain type;
  `registrableKeysProvider` is a new seam declared over it; `main.dart` overrides it with
  `HotkeyKeyCatalogue.registrableKeys()`. After this plan, `HotkeyKeyCatalogue` is named in
  `lib/main.dart` and under `lib/src/infrastructure/` and **nowhere else under `lib/src/`**.
- **A live end-to-end observation, not just a green suite.** The daemon was built and run against a
  private `Xvfb :78` with a real X11 passive grab. Capture → refusal → Apply → bind → grab swap was
  driven with `xdotool` and read off screenshots: after applying a captured `Ctrl+Shift+J`, the new
  combination toggles the panel and the old `Ctrl+Shift+G` does nothing at all (screen mean
  brightness 51074 vs 0). That is D-10's rebind, observed from the new control.

## Task Commits

1. **Task 1: the capture-control decision** — no commit; pre-answered on disk in
   `01-GATE-ANSWERS.md` (commit `ba79c04`), reproduced verbatim above.
2. **Task 2: turn the catalogue into a capture validator, and empty the dissolved set** —
   `d22851b` (feat)
3. **Task 3: the capture control** — `a2f2189` (feat)

**Plan metadata:** this SUMMARY plus STATE/ROADMAP/REQUIREMENTS (docs).

## Files Created/Modified

**Created**

- `lib/src/domain/hotkey/registrable_keys.dart` — `RegistrableKeys` / `RegistrableKey`: the key
  vocabulary as a domain value, keyed on USB HID usage, each entry carrying its label and whether a
  `preferred_trigger` can be built for it. Copies and freezes its map on construction.
- `lib/src/application/hotkey_capture.dart` — `HotkeyCapture` (the four ring-neutral values the
  widget extracts from a key event), `HotkeyCaptureRefusal` (five causes), the sealed
  `HotkeyCaptureVerdict`, and `HotkeyCaptureValidator`.
- `lib/src/ui/settings/hotkey_capture_field.dart` — the capture control, its surface, the refusal
  notice and the standing hint. No logger reaches this file at all (T-01-41).

**Modified**

- `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` — dissolved set removed with its
  history preserved as a comment; `labelForUsage` reverse lookup and `registrableKeys()` factory
  added, both derived from the one `labels` table; `carriesUsage` re-expressed as a view of the
  same map.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — the dead second refusal branch removed,
  its long comment replaced by a short note recording that the defect left with the plugin.
- `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` — its private `_labelsByUsage` map
  deleted in favour of `HotkeyKeyCatalogue.labelForUsage`, so one derivation serves both callers.
- `lib/src/application/settings_controller.dart` — takes `registrableKeys` and exposes
  `captureValidator`.
- `lib/src/application/composition/port_providers.dart`, `controller_providers.dart`, `lib/main.dart`
  — the seam, the hand-off and the override.
- `lib/src/ui/settings/settings_screen.dart` — the construction site, now passing the validator.
- `lib/src/ui/settings/preset_choice_list.dart` — a doc cross-reference to the renamed widget.
- Nine test files (see Deviations for the ones outside the plan's `files_modified`).

**Deleted**

- `lib/src/ui/settings/hotkey_preference_field.dart`, the symbol `HotkeyPreferenceField` and
  `offeredKeyExamples`. `grep -rn 'HotkeyPreferenceField' lib/ test/` returns nothing.

## Decisions Made

**1. The dissolved-set symbol was removed outright.** The plan left this to the executor. Removing
is the cleaner reading it names: an empty set with an always-false predicate leaves branches that
can never run, which AGENTS.md §1 forbids, and the branches would have had to go anyway. Plan 01-10's
ledger closure can quote the catalogue's doc paragraph (and this commit) rather than a live symbol.

**2. The injection route, exactly.** Seam `registrableKeysProvider`, declared
`Provider<RegistrableKeys>` in `lib/src/application/composition/port_providers.dart:103`, throwing
`UnimplementedError('main.dart must override registrableKeysProvider')` in the established shape.
`controller_providers.dart:55` passes `ref.watch(registrableKeysProvider)` to `SettingsController`.
`lib/main.dart:614-616` overrides it: `registrableKeysProvider.overrideWithValue(HotkeyKeyCatalogue.registrableKeys())`.
The value lands on the controller as **a field** (`SettingsController.captureValidator`, wrapping the
vocabulary), **not** on `SettingsState`: it never changes, and a state field would have had to be
carried unchanged through all five of that class's hand-built transitions — a cost 01-06 already paid
once for a value that does change. `settings_state.dart` was therefore not touched, despite being in
the plan's `files_modified`.

**3. The AltGr predicate actually used.** `LogicalKeyboardKey.altGraph`, checked both as the event's
own logical key and among `logicalKeysPressed`. **Not** the physical `PhysicalKeyboardKey.altRight`.
This is the correctness point, not a safety margin: on a layout that maps Level 3 to the right Alt
key the GTK embedder reports `altGraph`, and on one that does not the same physical key reports an
ordinary `altRight` — so keying on the physical key would have refused a legitimate `Alt`
combination for every user on a US layout. A plain right Alt still folds into `HotkeyModifier.alt`;
only Level 3 is refused.

**Flagged assumption A3 is now MEASURED, not assumed.** The plan recorded "that AltGr surfaces on
Linux GTK as `PhysicalKeyboardKey.altRight` with a logical `altGraph` was **not** verified in this
session". It has now been verified: `xdotool key ISO_Level3_Shift+g` against the running daemon on
`Xvfb :78` produced the `levelThreeModifier` refusal and its own sentence, not the bare-key one
(`scratchpad/hc3_altgr.png`). The logical-key half of the mapping is confirmed on a real X server
through the real embedder. Scope limit, stated honestly: `Xvfb` with a synthetic XTEST event and the
container's default layout, not a physical keyboard on a user's own layout.

**4. Bare Escape releases the capture focus rather than being captured.** The handler answers
`KeyEventResult.handled` for every key — which is the only way `Tab` and `Escape` reach a capture at
all — and that disables focus traversal, so a keyboard-only user would have had no way out of the
control. Bare `Escape` therefore unfocuses and clears any refusal; `Escape` with a modifier is
captured like any other combination, which is all D-13 permits anyway. **Declared rather than
discovered:** it is the one key the capture treats as an exit instead of as a combination, so the
truth "a captured combination with no modifier is refused with the reason" has this one stated
exception, where the press is not treated as a capture at all.

**5. Apply requests whatever the control displays.** Only a *capture* can be refused. A binding
already in config — including a hand-edited bad one — stays appliable, because re-requesting the
same combination is the recovery path `x11_global_hotkey_test.dart` relies on ("the refusal was not
recorded as held, so the recovery path is open"), and because AD-13 makes the store the validation
point for what is stored. Refusing to re-apply would have closed a path the adapter deliberately
leaves open.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The capture surface overflowed a narrow window by 76 pixels**
- **Found during:** Task 3
- **Issue:** The surface laid the combination and its hint out in a `Row` with only one flexible
  child. `settings_screen_config_test.dart`'s A12 row drives a short/narrow window and the render
  library reported `A RenderFlex overflowed by 76 pixels on the right`. Nothing sizes this toplevel
  (deferred work), so a user can drag it to any width — this is the same class of defect the notice
  cap in `settings_screen.dart` exists for.
- **Fix:** The surface is a `Column`: combination on top, hint below in `bodySmall`. The comment
  records the measured overflow so the shape is not "tidied" back.
- **Files modified:** `lib/src/ui/settings/hotkey_capture_field.dart`
- **Verification:** `flutter test test/ui/settings/settings_screen_config_test.dart` — 26 rows pass,
  no overflow reported; and the live screenshots show both lines inside the box.
- **Committed in:** `a2f2189`

**2. [Rule 3 - Blocker] Six files outside the plan's `files_modified` had to change**
- **Found during:** Tasks 2 and 3 — the fourth consecutive plan this phase where the file list was
  incomplete.
- **Issue and fix, file by file:**
  - `test/architecture/ad1_import_rule_test.dart` — its seam-classification row **fails** on any
    unclassified seam in `port_providers.dart`. `registrableKeysProvider` was added to
    `_uiBannedSymbols` (a widget must get the vocabulary from the controller, never read the seam)
    and `_knownPortSeamCount` raised 10 → 11, with the reason written in.
  - `test/composition/composition_root_test.dart`, `test/composition/daemon_graph_test.dart`,
    `test/ui/settings_harness.dart` — the three shared override lists; every controller graph in the
    suite fails to build without the new seam.
  - `test/application/settings_controller_test.dart` (10 construction sites),
    `test/application/controller_resilience_test.dart` (1) — the new required constructor argument.
    Both now build the vocabulary with `HotkeyKeyCatalogue.registrableKeys()`, so the application
    rows validate against the vocabulary this build really ships. A test may name the catalogue;
    AD-1's scans cover `lib/src/` only, and `test/application/correction_controller_test.dart`
    already imports infrastructure.
  - `test/ui/settings/settings_screen_config_test.dart` — three rows drove the deleted `TextField`
    and `FilterChip`s (the busy-state row, the re-seed row, and the `didUpdateWidget` guard row).
    All three re-pointed at the capture surface; the claims are unchanged.
  - `test/infrastructure/hotkey/xdg_shortcut_trigger_test.dart` — one row and one group doc read the
    dissolved set. The plan did not list this file; the row is re-pointed (below).
  - `lib/src/ui/settings/preset_choice_list.dart` — a doc comment referencing
    `HotkeyPreferenceField.enabled`, which the Task 3 gate (`grep -rn 'HotkeyPreferenceField'`
    produces no matches) would otherwise have failed on.
- **Verification:** both suites at baseline; every Task 2 and Task 3 gate re-run (below).
- **Committed in:** `d22851b`, `a2f2189`

**3. [Rule 2 - Missing critical] Two assertions had to be scoped rather than deleted, and one
weakened claim is recorded here rather than hidden**
- **Found during:** Task 3
- **Issue:** `settings_screen_hotkey_test.dart`'s A3 and A15 rows assert
  `find.textContaining('Ctrl+Shift+G')` finds **nothing** — "the request is nowhere on screen",
  protecting T-01-30 (a settings UI claiming a hotkey it did not set). The old field spread the
  request across a text box holding `G` and four toggles, so no contiguous string existed. The
  capture control renders the combination it will request as one string, which is what an input for
  a shortcut *is*, so the literal assertion fails on a correct implementation.
- **Fix:** Both finders are now scoped to `HotkeyStatusView` — the read-out. The claim they exist
  for is intact and precisely stated: the *effective* read-out never echoes the request. The reason
  strings say what was scoped and why.
- **Honest note for review:** this is strictly weaker than the row as written. "The request appears
  nowhere on the screen" is no longer true, and cannot be while an input control shows its input.
  If the intended invariant was screen-wide, this needs a product answer rather than a test edit.
- **Files modified:** `test/ui/settings/settings_screen_hotkey_test.dart`
- **Committed in:** `a2f2189`

---

**Total deviations:** 3 auto-fixed (1 × Rule 1 bug, 1 × Rule 3 blocker, 1 × Rule 2).
**Impact on plan:** no scope creep. One is a genuine layout defect the plan's own narrow-window
discipline would have caught in review; one is the recurring incomplete file list; one is a test
claim that had to be re-scoped and is flagged rather than quietly narrowed.

## Gate rows re-pointed or retired

Every row that read the dissolved set was re-pointed at a live subject. None was deleted, and none
passes vacuously.

| Row | Was | Now |
|---|---|---|
| `hotkey_key_catalogue_test.dart` "the labels that bind the wrong key are exactly these seven" | pinned the seven by literal value | **re-pointed** → "the reverse lookup and the vocabulary are views of the one label table": every label round-trips through `labelForUsage`, the injected vocabulary equals `labels` in order, and every entry has a portal trigger |
| `hotkey_confinement_test.dart` "nothing under settings offers a key label the X11 adapter refuses" | iterated the dissolved set over settings-directory literals (would have looped zero times) | **re-pointed** → scans those literals for key-label-shaped words against a named closed list and fails on any the catalogue cannot register |
| `hotkey_confinement_test.dart` "every key label the screen offers as an example is one this build can register" | read `offeredKeyExamples` out of the deleted widget | **RETIRED, with a stated successor.** There are no offers left to read — the user presses rather than reads. In its place the row asserts what now guarantees the user cannot choose an unregistrable key: the injected vocabulary carries exactly what the catalogue registers, the validator accepts every key in it, and it refuses `PrintScreen` (0x00070046) with `keyNotRegistrable`. Strictly stronger than the row it replaces, which could only check three labels somebody remembered to list. The retirement and its reason are written into the file. |
| `hotkey_confinement_test.dart` positive control `labelsThatBindTheWrongKey contains 'Space'` | would fail the moment the set emptied | **re-pointed** at the live scan subject (`_keyLabelShapedWords contains 'Space'`, and `Space` is registrable so it is not a hit) |
| `x11_global_hotkey_test.dart` "a key the backend would bind to its keypad variant is refused" | iterated the dissolved set (would have looped zero times) | **re-pointed** → four real keys outside the catalogue (`PrintScreen`, `CapsLock`, `F13`, `Numpad0`), each asserted to be outside it first so the row cannot prove nothing |
| `x11_global_hotkey_test.dart` "a rebind to one of the keypad-variant keys does the same" | asserted `Alt+Space` was refused | **re-pointed** → asserts the opposite fact about the same combination: `Alt+Space` is an ordinary rebind now. Worth a row rather than a deletion because `Alt+Space` is the combination DW-43 was filed about. |
| `x11_global_hotkey_test.dart` "the refusal is case- and whitespace-insensitive" | drove `' space '` and asserted a refusal | **re-pointed** → the normalization it relied on is still load-bearing for hand-edited config, so `' space '` must now reach the backend as the same grab a canonical spelling would |
| `xdg_shortcut_trigger_test.dart` "the seven labels the X11 backend binds to the wrong key are still expressible" | read the dissolved set | **re-pointed** → the seven are named as literals and asserted expressible on **both** display servers, i.e. the divergence is gone rather than pinned. The group doc's caveat was rewritten to match. |
| `settings_screen_hotkey_test.dart` "deselecting every modifier is cautioned rather than refused" | asserted the **opposite** of D-13 | **re-pointed** → D-13 reverses it (the refusal itself is the row above), and this row now carries Tab capture, the standing hint + Keep current, and the D-16 read-only lock |

**Test row count is unchanged: 970 before, 970 after** (`grep -rc "  test(" test/ | awk -F: '{s+=$2} END {print s}'`).
No new test file. `testWidgets` rows: 20 before and 20 after in
`settings_screen_hotkey_test.dart`, 26 before and after in `settings_screen_config_test.dart`.

## Verification

Both baselines held exactly, with no regression:

| Command | Result |
|---|---|
| `dart analyze --fatal-infos` | **No issues found** (whole workspace) |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **959 passing / 2 skipped** — baseline exactly |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | **165 passing / 7 skipped** — baseline exactly |
| `dart test --exclude-tags=live test/architecture/ad1_import_rule_test.dart` | 28 passing |

### Task 2 acceptance criteria

| Criterion | Result |
|---|---|
| `grep -c 'bindsTheWrongKey' lib/src/infrastructure/hotkey/x11_global_hotkey.dart` | `0` ✓ |
| `grep -rn "Precondition the caller owns" lib/src/infrastructure/hotkey/hotkey_registrar.dart` | no matches ✓ (already gone from 01-02) |
| reverse lookup derived, not a second table | ✓ `_labelsByUsage` is `{for (final label in labels) ?usbHidUsageFor(label): label}`; the registrar's duplicate was deleted |
| five subjects, five distinct sentences | ✓ read the five branches in `hotkey_capture.dart`; each returns its own `reason` |
| AltGr branched explicitly, not mapped to `alt` | ✓ `usesLevelThreeModifier` is the first branch |
| `grep -rn 'HotkeyKeyCatalogue' lib/src/application/ \| wc -l` | `0` ✓ |
| `grep -rln 'HotkeyKeyCatalogue' lib/src/ui/ \| grep -v hotkey_preference_field \| wc -l` | `0` ✓ |
| `grep -c 'HotkeyKeyCatalogue' lib/main.dart` | `2` ✓ (≥ 1) |
| `ad1_import_rule_test.dart` passes | ✓ |
| both seam halves landed (`composition_wiring_test.dart`) | ✓ |
| the three confinement rows name live subjects | ✓ (table above) |
| the adapter rows no longer assert a refusal that does not happen | ✓ |
| `test(` count unchanged | ✓ 970 → 970 |
| the catalogue's doc records **why** the set is empty | ✓ with the three-way measurement |
| ≥ 900 passing, analyze clean | ✓ 959 |

**One criterion was substituted, and it is named rather than reported as passed.** The plan's
`grep -c 'altGraph\|altRight\|Level3\|ISO_Level3' lib/src/application/` **cannot pass as written**:
`grep -c` against a directory exits 2 with `Is a directory` and prints no count. The substitute run
was `grep -rn 'altGraph\|altRight\|Level3\|ISO_Level3\|Level 3' lib/src/application/ | wc -l` → **7**,
which proves the same property (the Level-3 predicate is named and reasoned about in the application
ring). This is the third plan this phase to hit a structurally unpassable single-line grep.

### Task 3 acceptance criteria

| Criterion | Result |
|---|---|
| `test -e lib/src/ui/settings/hotkey_preference_field.dart` | exit 1 ✓ (gone) |
| `grep -rn 'HotkeyPreferenceField' lib/ test/` | no matches ✓ |
| new file is a `StatefulWidget`, owns its `FocusNode` as a field, disposes it | ✓ `FocusNode` ×2, `.dispose()` ×3 |
| nothing allocated in `build` | ✓ the plan's `awk` gate prints `0` |
| `grep -c 'KeyRepeatEvent'` | `2` ✓ (≥ 1) |
| `grep -c 'physicalKey'` | `2` ✓ (≥ 1) |
| applied binding built from a fresh set literal | ✓ `HotkeyBinding(modifiers: {..._combination.modifiers}, …)`, and the validator also copies |
| `grep -rn 'SnackBar\|showDialog\|AlertDialog'` | no matches ✓ (D-09) |
| `grep -rn 'HotkeyKeyCatalogue' lib/src/application/ lib/src/ui/ \| wc -l` | `0` ✓ |
| `grep -rln 'HotkeyKeyCatalogue' lib/src/ \| grep -vc '^lib/src/infrastructure/'` | `0` ✓ |
| `ad1_import_rule_test.dart` passes | ✓ |
| `release-during-capture` exit paths | n/a — the answer was `explain-in-place`; no grab lifecycle change exists to enumerate |
| `test(` count unchanged | ✓ |
| all four automated commands pass | ✓ |

### The `<human-check>` rows — six observed, one owed

The daemon was **built and run** (`flutter build linux --debug`, then launched against a private
`Xvfb :78`, 1280x900) with a real X11 passive grab held, and driven with `xdotool`. Screenshots are
in the session scratchpad. This is the same route the `hidden_window_test` skip reason describes as
unavailable for *window-manager* questions; it is available here because these seven rows are about
key delivery and widget behaviour, which a bare X server does answer. Caveats: no window manager, no
session bus (the tray could not register — logged and survived, as designed), and synthetic XTEST
events rather than a physical keyboard.

| Row | Result |
|---|---|
| 1. bare key → refused, with a reason, previous unchanged | **OBSERVED.** `j` → "A shortcut needs at least one of Ctrl, Alt, Shift or Super…" in the error colour; the box still read `Ctrl+Shift+G` (`hc1_barekey.png`) |
| 2. `Ctrl` alone → nothing committed, still waiting | **OBSERVED.** "Keep holding, then press the key you want to use." in the ordinary voice, box unchanged (`hc2_modifieronly.png`) |
| 3. `AltGr`+`G` → refused, reason ≠ the bare-key reason | **OBSERVED.** "AltGr cannot be part of a shortcut here — a shortcut carries Ctrl, Alt, Shift or Super, and AltGr is none of them." and the bare-key sentence was absent (`hc3_altgr.png`). This is what settles A3. |
| 4. hold `Ctrl+Shift+J` for two seconds → committed once | **OBSERVED for the commit; "exactly once" is the automated row's.** Held 2.5 s with auto-repeat running: the box read `Ctrl+Shift+J` during the hold and after release, with no flicker or drift (`hc4_held.png`, `hc4_released.png`). A screenshot cannot count commits; the once-ness is pinned by `bindCalls` in the widget row. |
| 5. `Tab` with a modifier → captured, not swallowed | **OBSERVED.** `Ctrl+Tab` → the box read `Ctrl+Tab`, focus did not move (`hc5_tab.png`) |
| 6. bind in flight → read-only, nothing shown as in effect | **OWED, not observed.** An X11 grab resolves synchronously in microseconds and this container has no portal to park a bind on, so there is no in-flight window to photograph. Covered automatically by two rows driving a gated fake. Filed to `WINDOWS.md`. |
| 7. press the shortcut you already have → Task 1's behaviour, and nothing else | **OBSERVED, and it confirms A4 end-to-end on the settings screen.** With `Ctrl+Shift+G` grabbed and the capture focused, pressing it did **not** reach the capture: the grab fired and the daemon did what the shortcut says (the view swapped back to the panel). The box kept its pending capture; nothing false was claimed; the standing hint had already said why (`hc7_pressed_current.png`) |

**Bonus observation, beyond the plan's rows.** Capture → Apply → real grab swap: after applying a
captured `Ctrl+Shift+J`, `config.json` on disk held `{modifiers:[control,shift], key:'J'}`, the
read-out said `In effect: Ctrl+Shift+J`, the standing hint renamed the current shortcut, pressing
`Ctrl+Shift+J` toggled the panel (screenshot mean brightness 51074) and pressing the old
`Ctrl+Shift+G` did nothing at all (mean 0). D-10/CAP-12's rebind, observed from the new control.

## Known Stubs

None. Every branch added is reachable, and the two that are not reachable *through today's shipped
vocabulary* are documented as vocabulary guards rather than dead code:

- `HotkeyCaptureRefusal.noPortalTrigger` fires only for a vocabulary entry with
  `hasPortalTrigger: false`. Every key the shipped catalogue produces has a keysym name (the two
  label tables are held equal in both directions by `xdg_shortcut_trigger_test.dart`), so no key
  reaches it today. It is a guard over *injected data*, not over a compile-time fact: a build whose
  two tables diverged would carry such a key, and the validator refuses it by reading the flag
  rather than by knowing which build it is in. The catalogue-test row asserts the flag is true for
  every current entry, so a divergence fails loudly instead of silently.
- `HotkeyCaptureRefusal.modifierOnly` needs the ui ring's `keyIsModifier`, which only that ring can
  compute; the row above observes it live.

## Issues Encountered

**1. `simulateKeyDownEvent` cannot spell AltGr on the `linux` keymap.** The raw-event half of
Flutter's key simulator resolves a key code out of `kGlfwToLogicalKey`, and GLFW has no AltGr, so
`platform: 'linux'` asserts `Key LogicalKeyboardKey#altGraph not found in linux keyCode map`. That
one event is sent with `platform: 'web'` (whose map carries `AltGraph`); what the widget reads is the
`KeyData` both paths produce, and the *real* app was then driven with a real `ISO_Level3_Shift` press
under X11, which is the observation that matters. Recorded in the row's own comment.

**2. `pkill -f "Xvfb :78"` killed the shell running it** (the pattern matches the shell's own command
line). Cost one aborted attempt; the live session was then brought up without it. Worth remembering
for the next live-test run.

## Ledger and follow-ups owed

- **DW-43 is resolved by this phase** and should be closed by plan 01-10 rather than carried: its
  cause left the tree with the vendor plugin, the set and its predicate are gone, and the measurement
  is preserved in the catalogue's doc.
- **DW-71's route is now implemented** as ratified — the vocabulary is supplied by
  `SettingsController` and built at the composition root — and can be closed by 01-10 with a
  quotable seam name.
- **A3 moves from ASSUMED to MEASURED** (this session, `Xvfb`, synthetic XTEST): worth recording in
  01-10's ledger work alongside A4.
- **Phase 7 / ARCH-06** is unaffected by this plan: no AD-9 declaration was edited and
  `ARCHITECTURE-SPINE.md` was not touched. The new seam is an addition to `port_providers.dart`,
  which AD-17 describes generically.
- **Phase 2 / SETTINGS-09** still owns `hotkey_status_view.dart`'s closing ownership sentence; this
  plan left that file untouched.

## Next Phase Readiness

Ready for plan 01-08 (the `SettingsController` write-precedence work, which this plan deliberately
did not restructure) and 01-09 (the `HotkeyBinding` defensive copy — note that `RegistrableKeys`
already copies and freezes its own map, and `HotkeyCaptureValidator` hands `HotkeyBinding` a fresh
set, so 01-09's change will find one fewer caller to fix).

01-04's cause-driven rendering in `hotkey_status_view.dart` and 01-06's verbatim
`trigger_description` line are both intact — that file was not modified by this plan, and its whole
suite is green.

## Self-Check: PASSED

- All three created files exist on disk; `hotkey_preference_field.dart` confirmed deleted.
- Both task commits exist in `git log`: `d22851b`, `a2f2189`.
- Both test baselines re-run after the last edit and unchanged: 959/2 and 165/7.
- `dart analyze --fatal-infos` clean across the workspace.
- Every `<human-check>` row is recorded above as **observed** (six, with screenshot references) or
  as **owed** (one, row 6, filed to `WINDOWS.md` as entry 13). Nothing is reported as passed that
  was not run.
