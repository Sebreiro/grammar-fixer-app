# Phase 2: Daemon Truth — Settings, Panel, Teardown, Provider & Spine — Specification

**Created:** 2026-09-14
**Ambiguity score:** 0.142 (gate: ≤ 0.20)
**Requirements:** 26 locked

## Goal

Every remaining surface of the shipped daemon tells the truth about what it actually did: a preset
change serves the very next correction, hotkey state reaches the tray on every transition, the panel
is a window the app deliberately shaped and an editor that never silently eats the user's text, the
daemon has one bounded way to stop, CAP-8's provider choice has a second option, and the frozen
records describe the daemon that shipped.

## Background

The MVP ships and works. What does not hold is the *reporting*: forty verified-open ledger entries
say so, and each was re-confirmed against the code before this spec was written.

Confirmed open at `HEAD` during this session's scout:

- `activePresetProvider` is overridden exactly once, in [main.dart:629](../../../lib/main.dart#L629),
  from `startup.active.preset`. `SettingsController.changeActivePreset`
  ([settings_controller.dart:242](../../../lib/src/application/settings_controller.dart#L242)) writes
  the config and nothing else — the `(provider, preset)` pair
  [`CorrectionController`](../../../lib/src/application/correction_controller.dart#L67-L68) holds is
  never rebuilt, so a preset change takes effect only after a daemon restart.
- `ProviderRegistry` ([provider_registry.dart](../../../lib/src/infrastructure/correction/provider_registry.dart))
  holds exactly one factory. CAP-8 offers a choice of one.
- [main.dart:647-678](../../../lib/main.dart#L647-L678) sets `setTitle`, `setSkipTaskbar` and
  `setPreventClose` on the toplevel — no size, no minimum size, no position.
- [json_config_store.dart:144](../../../lib/src/infrastructure/config/json_config_store.dart#L144) and
  `:170` interpolate `$error` into warning text, which the `Logger` port's own doc bans.
- `_releaseWithoutLifecycle` ([main.dart:524](../../../lib/main.dart#L524)) awaits every teardown step
  unbounded before `exit(1)`.
- `_showingSettings` ([daemon_home.dart:95](../../../lib/src/ui/daemon_home.dart#L95)) stays true when
  the hotkey hides the window, so the next press lands on settings.
- Two `lib/` comments still cite `<Ctrl><Shift>g` as the spine's example
  ([hotkey_key_catalogue.dart:9](../../../lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart#L9),
  [default_app_config.dart:140](../../../lib/src/infrastructure/config/default_app_config.dart#L140));
  the spine no longer contains it.

The phase is organised as six internal waves (A–F) merged from the former Phases 2–7. The wave order
is a dependency order, not a priority order: A → (B → C), (D → E) → F.

## Requirements

### Wave A — Settings & tray fan-out

1. **Preset reaches the next correction** *(SETTINGS-01 / DW-16)*: changing the active preset rebuilds
   the active `(CorrectionProvider, Preset)` pair without a daemon restart.
   - Current: `activePresetProvider` is a one-time override from the startup value; `changeActivePreset`
     writes config only
   - Target: a preset change rebuilds the pair the correction controller uses, and the next correction
     started after the change runs under the new preset
   - Acceptance: after `changeActivePreset`, a correction submitted subsequently carries the new
     preset; a correction already in flight when the change lands completes under the old preset

2. **Bind and config cannot disagree** *(SETTINGS-02 / DW-68)*: a refused bind and the written config
   cannot report different shortcuts.
   - Current: the remaining `changeHotkey` bind-before-write divergence lets a refused bind leave a
     written config naming a shortcut that is not held
   - Target: config names the shortcut actually in effect after every `changeHotkey`, refused or not
   - Acceptance: a `changeHotkey` whose bind is refused leaves config naming the previously-bound
     shortcut, and the settings read-out and the config file agree

3. **Tray learns every hotkey transition** *(SETTINGS-03 / DW-69, SETTINGS-06 / DW-79, SETTINGS-08 / FLAT-13)*:
   hotkey availability reaches the tray on every later transition, not only at startup.
   - Current: the tray surface is written once at startup; a refused rebind or a compositor
     `ShortcutsChanged` that drops the shortcut reaches only the settings screen
   - Target: both AD-12 consumers — tray and settings — observe every hotkey state transition,
     including no-backend, key-refused and revoked
   - Acceptance: a refused rebind, a dropped shortcut, and a total absence of backend each change what
     the tray reports; AD-12's "after the fact" refresh cases are covered

4. **Counted-echo bookkeeping resolved** *(SETTINGS-04 / DW-77)*: `SettingsController`'s
   `Map<AppConfig,int>` echo counter is replaced or removed.
   - Current: a counted-echo map survives from before `_beginMutation` made overlapping mutations
     unreachable from outside the class
   - Target: the bookkeeping matches what is now reachable — a plain set, or removal, with the decision
     stated
   - Acceptance: no `Map<AppConfig,int>` echo counter remains, and the settings echo behaviour is
     unchanged for every transition the existing suite exercises

5. **No exception text in a logged line** *(CONFIG-01 / DW-23)*: `ConfigLoadResult.warning` stops
   interpolating an exception's `toString()`.
   - Current: `json_config_store.dart:144` and `:170` embed `$error` in warning text
   - Target: warnings name the file path and the application-authored problem; the exception
     contributes only its `runtimeType` to structured context
   - Acceptance: no logged line in `lib/` interpolates an exception value; a malformed config still
     yields defaults plus a surfaced warning and never fails startup

### Wave B — Panel geometry, selection & clipboard

6. **The app shapes its own window** *(PANEL-01 / DW-50)*: panel size, minimum size and position are
   chosen and set by the application.
   - Current: only `setTitle`, `setSkipTaskbar` and `setPreventClose` are called; geometry is whatever
     the default toplevel has
   - Target: the app sets size, minimum size and position explicitly, each call justified in the
     hidden-window allowlist
   - Acceptance: the three geometry calls are present and justified; on a display smaller than the
     chosen minimum the panel shrinks to fit the display rather than overflowing it; with no display
     geometry readable the app uses its chosen default and startup still succeeds

7. **A click selects a variant** *(PANEL-02 / DW-52)*: a pointer click on a suggestion card selects
   that variant.
   - Current: cards have no tap-to-select; the `1`/`2`/`3` digit shortcuts are keyboard-only
   - Target: a click does exactly what the matching digit key does — selection, not copy
   - Acceptance: clicking card *n* selects variant *n*; clicking the already-selected card is a no-op
     and never deselects; copy remains a separate deliberate action

8. **Selection works off QWERTY** *(PANEL-04 / DW-57)*: variant selection works on layouts where the
   logical digit keys select nothing today.
   - Current: the `1`/`2`/`3` hint promises keys that on a non-QWERTY layout select nothing
   - Target: what the hint shows is what actually selects, on every layout the daemon can run under
   - Acceptance: on a layout where the logical digit keys do not fire, selection still works and the
     rendered hint matches the key that actually selects

9. **The editor's corner belongs to the editor** *(PANEL-07 / DW-72)*: the settings affordance no
   longer overlaps the panel editor's top-right corner.
   - Current: a pointer landing in the editor's top-right reaches the settings affordance
   - Target: the affordance and the text field do not overlap
   - Acceptance: a pointer landing anywhere inside the editor's bounds reaches the text field

10. **A successful copy is visible** *(PANEL-05 / DW-59)*: a completed clipboard write renders
    feedback.
    - Current: a working clipboard and a hung write look identical to the user
    - Target: success renders its own feedback, distinct from in-flight and from failure
    - Acceptance: a completed copy renders feedback; a failed or hung write renders a distinct state
      and never renders the success feedback

11. **Overlapping copies have a defined winner** *(PANEL-03 / DW-55)*: two overlapping clipboard
    writes cannot land in whatever order the platform chose.
    - Current: writes are unserialized; ordering is the platform's
    - Target: writes are serialized and the last request wins
    - Acceptance: copy(1) then copy(2) before the first lands leaves variant 2 on the clipboard and
      renders feedback for 2 only; two copies of identical text resolve by the same last-wins rule; a
      copy of an empty or absent suggestion is refused with a reported reason and never writes empty
      over the clipboard

12. **The panel cannot hold a stale controller** *(PANEL-06 / DW-62)*: a provider graph rebuild cannot
    leave the panel bound to a dead correction controller.
    - Current: the panel binds its controller once in `initState`
    - Target: either the binding follows a rebuild, or the graph property that makes the single bind
      safe is pinned and stated
    - Acceptance: a provider graph rebuild leaves the panel driving the live controller, or a pinned
      invariant proves a rebuild cannot occur, with the choice recorded

### Wave C — Panel window-event reconciliation

13. **No typed text is lost, in any order** *(PANEL-19 / FLAT-52, PANEL-14 / FLAT-47)*: no text the
    user typed into the panel editor is lost by a summon, a click-away, a minimize/restore or a focus
    loss, in any order.
    - Current: an abandoned `hide` whose late echo lands after a completed `show` is attributed
      `dismissed`, so a click-away plus a summon discards the user's typed text; a blur latched under a
      `_requestTimeout`-abandoned request can be released into a `hide` racing a window call still in
      flight
    - Target: a late echo from an abandoned request is never attributed to a completed later request,
      and a latched blur from an abandoned request cannot be released into a racing `hide`
    - Acceptance: for every ordering of summon / click-away / minimize+restore / focus-loss, non-empty
      editor text survives; an empty editor has nothing to lose and the rule binds only on non-empty
      text; text is preserved byte-for-byte, never trimmed or re-encoded

14. **A discarded draft is a visible discard** *(SETTINGS-05 / DW-78)*: an unapplied hotkey draft has a
    decided, visible fate across a view swap.
    - Current: summoning the panel or losing focus silently discards whatever the user typed into the
      key field
    - Target: the draft is discarded and the key field then shows the shortcut actually in effect, so
      the user can see the change did not take — never a silent discard
    - Acceptance: after a view swap an unapplied draft is gone and the field reads the effective
      shortcut; a draft identical to the shortcut in effect is discarded with no visible change,
      because there is nothing different to show

15. **The panel never steals the keyboard** *(PANEL-15 / FLAT-48, PANEL-10 / FLAT-43, PANEL-12 / FLAT-45)*:
    the panel does not take the keyboard from the application the user just clicked into.
    - Current: a show's trailing `focus()` fires while a blur is latched; the gap in `_apply` between
      the pre-`focus()` re-check and the call lets a window event re-map a window the mirror gave up
      on; `_releaseDeferredBlur`'s `_focused` re-check cannot tell a self-caused focus-in from the
      user's and can swallow the dismissal DW-32 exists to answer
    - Target: the trailing `focus()` is suppressed under a latched blur, the `_apply` gap is closed,
      and the adapter distinguishes a focus-in it caused from the user's
    - Acceptance: a show that lands while a blur is latched does not call `focus()`; no window event
      arriving inside the `_apply` gap re-maps a given-up window; a self-caused focus-in does not
      satisfy the `_focused` re-check

16. **The hotkey returns to the panel** *(SETTINGS-07 / DW-81)*: pressing the hotkey on the settings
    screen returns the user to the panel.
    - Current: the press hides the window and leaves `_showingSettings` true, so the next press lands
      on settings
    - Target: the press swaps the view back to the panel instead of hiding the window
    - Acceptance: hotkey pressed while settings shows leaves the window visible on the panel; pressing
      it on settings when the panel has never been shown opens the panel in its empty state

17. **The window double models iconified** *(PANEL-13 / FLAT-46)*: `FakePanelWindow` models an
    iconified toplevel.
    - Current: DW-31's minimize/restore rows assume the window side rather than asserting it
    - Target: the fake models iconified as a state distinct from hidden
    - Acceptance: the minimize/restore rows assert the window state as a claim; iconified and hidden
      are distinguishable in the fake

### Wave D — Startup, abort & teardown discipline

18. **The abort path always reaches exit** *(STARTUP-01 / FLAT-27, STARTUP-02 / FLAT-31)*: a failure on
    the abort path cannot leave a resident windowless daemon.
    - Current: a throw from `_abort`'s own `logger.error` on a broken stderr is caught by the installed
      handlers, reported as handled, and `exit` is skipped; `DaemonStartup.begin` and the
      not-the-daemon exit sit outside `main`'s abort guard
    - Target: a throw from the abort path's own logging still reaches `exit`, and both startup and the
      not-the-daemon exit run inside the abort guard
    - Acceptance: a throw from `_abort`'s logging reaches `exit(1)`; a rethrow from `DaemonStartup.begin`
      or the not-the-daemon exit runs the abort guard rather than leaving the process resident

19. **One bounded way to stop** *(STARTUP-03 / FLAT-34, STARTUP-05 / FLAT-38)*: the pre-lifecycle abort
    path cannot hang, and a stop during startup is ordered.
    - Current: `_releaseWithoutLifecycle` awaits `disposeControllers`, `panelVisibility.dispose` and
      `database.close` unbounded; a stop request arriving during startup's `bindHotkey` portal wait runs
      the ordered teardown underneath the rest of startup, leaving `applyStartupBindOutcome` touching a
      disposed graph
    - Target: one injected teardown bound is reused at every site on that path, and a stop during
      startup does not interleave with the rest of startup
    - Acceptance: every await on the pre-lifecycle teardown path is bounded by the same injected
      duration; a teardown with nothing to release still completes and exits; a step's failure never
      skips a later step; a stop during the portal wait runs the ordered teardown exactly once and
      `applyStartupBindOutcome` never touches a disposed graph

### Wave E — Second correction provider

20. **CAP-8 has something to choose** *(PROVIDER-02 / DW-115)*: an OpenAI-compatible provider is
    selectable and streams register variants.
    - Current: `ProviderRegistry` holds exactly one factory; the provider choice has one option
    - Target: the user selects the OpenAI-compatible provider, sets its base URL and model, and
      receives streamed register variants; the API key resolves from the OS secret store, then an
      environment variable, then the config file; the daemon never *writes* the key to the config file;
      the register-tagged stream parser is shared with the sidecar adapter, not duplicated; no
      `switch (providerId)` exists below the composition root
    - Acceptance: variants stream from the OpenAI-compatible endpoint; the key is resolved in
      `keyring → env → config` order with the winning source surfaced in settings; the daemon writes no
      key to `config.json`; a missing base URL or model yields `providerUnavailable` with an actionable
      message on the first `correct()` and never blocks startup; two corrections of the same text are
      independent stateless sessions; a second submit cancels the first and tears down the HTTP
      request; variants stream in the order the endpoint emits them
    - **Locked decision:** `CorrectionFailureKind` gains **no fifth member**. Provider failures map into
      the existing four; `providerError` carries an actionable message. This answers the roadmap's
      scheduled human gate — no UI change, no persisted-value change, no spine renegotiation.

21. **An unknown provider id has an architecture answer** *(PROVIDER-03 / FLAT-19)*: config naming a
    provider this build does not ship is answered in the architecture, not only in the code.
    - Current: `ProviderRegistry.create` returns null for an unknown id and the caller decides; no
      architecture decision records what should happen
    - Target: a recorded architecture decision states the behaviour the code implements
    - Acceptance: an unknown provider id yields a startup warning and an unconfigured provider, never a
      failed startup, and an architecture decision records that as the rule

### Wave F — Architecture & spine currency

22. **The error contract agrees with itself** *(ARCH-01 / DW-5)*: the controllers' error contract is
    reconciled.
    - Current: the contract lives in story 3's matrix while the frozen source spec reads `N/A` for 12
      of 13 rows
    - Target: matrix and source spec state the same contract
    - Acceptance: no row reads `N/A` where the matrix states a behaviour; the two documents do not
      disagree on any of the 13 rows

23. **The spine states the rules the code needs** *(ARCH-04 / FLAT-08, ARCH-03 / FLAT-07)*.
    - Current: the spine specifies collection equality for `List` (AD-2) and `Set` (AD-9) but not
      `Map`, which the shipped code already needs and states itself; the runtime-dependency list omits
      a StatusNotifier/AppIndicator host
    - Target: the `Map` rule sits beside the other two, and the tray host appears in the
      runtime-dependency list, marked as the one dependency whose absence is silent rather than visibly
      degrading
    - Acceptance: the spine contains a `Map` collection-equality rule and a StatusNotifier/AppIndicator
      runtime-dependency entry carrying that silence note

24. **The spine is current** *(ARCH-06 / FLAT-10, ARCH-05 / FLAT-09, ARCH-08 / FLAT-20)*.
    - Current: the `Dart SDK` row is stale, the pin-renegotiation paragraph carries a now-false EOL
      warning, two `lib/` comments cite a `<Ctrl><Shift>g` example the spine no longer contains, and the
      Structural Seed omits roughly twenty shipped files including two the spine's own normative prose
      cites by name
    - Target: those items are closed, alongside the Phase 1 AD-9 declaration edits filed for this wave
    - Acceptance: the `Dart SDK` row matches the pinned SDK; the EOL warning is true or gone; no `lib/`
      comment cites `<Ctrl><Shift>g` as a spine example; the Structural Seed lists the omitted files,
      including the two cited by name

25. **No frozen record this phase touches is false** *(PANEL-11 / FLAT-44, PANEL-17 / FLAT-50, PANEL-09 / FLAT-42, SETTINGS-09 / FLAT-16, ARCH-07 / FLAT-12)*.
    - Current: story 5's `<intent-contract>` claims DW-30–DW-33 were implemented as written, now false
      for DW-32 and DW-33; CAP-2's success clause and AD-8/AD-18's snippets are falsified by the shipped
      code with the only record in Dart doc comments; the checklist-step renumbering ban permanently
      exempts two rounds of runtime claims from ever being observed; `hotkey_status_view.dart`'s doc
      comment states nothing is appended while the method beneath it appends a line; the architecture
      run's frozen `reviews/` reports carry no disposition and mislead an auditor in both directions
    - Target: each record matches the code, or carries a recorded disposition saying why it does not
    - Acceptance: each of the five records is corrected or dispositioned; the renumbering ban no longer
      permanently exempts the two rounds; the `hotkey_status_view.dart` doc comment matches the method
      beneath it

26. **The ledger is append-only again** *(LEDGER-01 / DW-13)*.
    - Current: story instructions direct deleting closed ledger entries, against the append-only
      contract `deferred-work.md` states; DW-13 and DW-108 both record violations
    - Target: no instruction directs deletion; closing an entry flips `status:` and adds `resolution:`
    - Acceptance: no instruction in the tree directs deleting a ledger entry; this phase's own 40
      closures each flip `status:` and add `resolution:`, and the ledger diff shows non-zero additions
      with zero deleted entry headings

## Boundaries

**In scope:**

- All 40 roadmap requirements for Phase 2, across waves A–F, with no deferral
- Wave A: SETTINGS-01…04, SETTINGS-06, SETTINGS-08, SETTINGS-09, CONFIG-01
- Wave B: PANEL-01…PANEL-07
- Wave C: PANEL-09…PANEL-15, PANEL-17, PANEL-19, SETTINGS-05, SETTINGS-07
- Wave D: STARTUP-01…STARTUP-03, STARTUP-05
- Wave E: PROVIDER-02, PROVIDER-03 — including the `SecretStore` port and its keyring/env/config
  resolution chain, which PROVIDER-02 cannot be delivered without
- Wave F: ARCH-01, ARCH-03…ARCH-08, LEDGER-01, plus the Phase 1 AD-9 declaration edits filed for this
  wave as a hand-off entry
- Closing all 40 ledger entries append-only

**Out of scope:**

- **Phase 1's remaining gap-closure plans (01-21…01-24)** — Phase 2 assumes Phase 1 closes first and
  does not re-specify the probe's permissions, the doc-count sweep, the suite-flakiness diagnosis or
  the DW-131 entry
- **A fifth `CorrectionFailureKind` member** — decided against this session; widening forces a UI
  change, a persisted-value change and a spine renegotiation for no gain the message cannot carry
- **New test, gate or CI work** — removed from milestone scope 2026-08-31; existing tests must not
  break, but no phase adds a gate, fixes a flake, or makes a runtime observation
- **Any schema change** — Drift's v1 snapshot can only be captured while v1 is live; bumping
  `schemaVersion` would destroy the baseline every existing user is on
- **The history/sqlite data-safety cluster** (file permissions, retention, corrupt-DB recovery,
  schema snapshot) — entirely `parked` in the ledger, maps to zero of the 50 requirements
- **New user-facing capabilities beyond PROVIDER-02** — the SPEC's 14 capabilities are frozen
- **Non-Linux platforms, Electron and webview shells** — standing SPEC constraints
- **Rewriting the hexagonal architecture** — the 19 ADs are frozen; a fix needing a verbatim-fixed port
  declaration edited is human-gated, not an architectural rewrite

## Constraints

- **Frozen contract.** `ARCHITECTURE-SPINE.md`'s 19 ADs and the SPEC's 14 capabilities are frozen. Any
  edit to a verbatim-fixed port declaration is a human-gated decision, taken before the task it gates.
- **Architecture.** Hexagonal, four rings, one-way imports; vendor types never cross a port boundary;
  seams wired only at the composition root (AD-1, AD-17), enforced by the analyzer rule and
  `test/architecture/ad1_import_rule_test.dart`. In particular, no `switch (providerId)` below the
  composition root, and the OpenAI-compatible adapter's HTTP types stay adapter-private.
- **Both display servers.** Every hotkey and panel behaviour must hold on X11 and on the Wayland XDG
  GlobalShortcuts portal, where the compositor — not the app — owns the binding.
- **Privacy.** Input text, suggestion bodies and clipboard content are never logged. History holds user
  plaintext.
- **Ledger discipline.** `deferred-work.md` is append-only; closing an entry flips `status:` and adds
  `resolution:`. Entries are never deleted.
- **Concurrency.** One hotkey/correction/settings flow at a time. CAP-1's <100 ms budget is met by
  staying off the show path, not by parallelism. Exactly one worker isolate exists
  (`X11KeyGrabRegistrar`); do not add a second.
- **Closure evidence is inspection.** `.github/workflows/ci.yml` still reads `STATUS: NEVER EXECUTED`.
  A green local run of the existing suite is the whole of the evidence available.
- **Wave E needs research.** "OpenAI-compatible" hides real divergence in streaming framing, error
  shapes and structured-output support; acceptance is gated on two distinct endpoints. Secret Service
  behaviour across gnome-keyring / KWallet / no service at all also needs research. Waves A–D and F are
  standard patterns and need none.
- **Wave order is a dependency order:** A → (B → C), (D → E) → F. Wave F is honest only after the work
  it describes has landed.
- **SETTINGS-02 (DW-68) carries DW-84's contingent closure** — descoping it silently un-closes another
  ledger entry.

## Acceptance Criteria

**Wave A**

- [ ] A correction submitted after `changeActivePreset` runs under the new preset, with no daemon restart
- [ ] A correction in flight when the preset changes completes under the old preset
- [ ] A `changeHotkey` whose bind is refused leaves config naming the previously-bound shortcut
- [ ] A refused rebind, a dropped shortcut, and a total absence of backend each change what the tray reports
- [ ] No `Map<AppConfig,int>` echo counter remains in `SettingsController`
- [ ] No logged line in `lib/` interpolates an exception value; a malformed config still yields defaults plus a warning

**Wave B**

- [ ] The panel's size, minimum size and position are set by the app and justified in the hidden-window allowlist
- [ ] On a display smaller than the chosen minimum, the panel shrinks to fit rather than overflowing
- [ ] Clicking card *n* selects variant *n*; clicking the selected card is a no-op
- [ ] Selection works, and the rendered hint matches the selecting key, on a layout where the logical digit keys do not fire
- [ ] A pointer landing anywhere inside the panel editor's bounds reaches the text field
- [ ] A completed copy renders success feedback; a failed or hung write renders a distinct state
- [ ] copy(1) then copy(2) before the first lands leaves variant 2 on the clipboard, with feedback for 2 only
- [ ] A copy of an empty or absent suggestion is refused with a reason and never writes empty over the clipboard
- [ ] A provider graph rebuild leaves the panel driving the live controller, or a pinned invariant proves a rebuild cannot occur

**Wave C**

- [ ] For every ordering of summon / click-away / minimize+restore / focus-loss, non-empty editor text survives, byte-for-byte
- [ ] A late echo from an abandoned `hide` is not attributed `dismissed` after a completed `show`
- [ ] After a view swap, an unapplied hotkey draft is gone and the key field reads the effective shortcut
- [ ] A show landing while a blur is latched does not call `focus()`
- [ ] No window event arriving inside the `_apply` gap re-maps a window the mirror gave up on
- [ ] A self-caused focus-in does not satisfy `_releaseDeferredBlur`'s `_focused` re-check
- [ ] The hotkey pressed on the settings screen leaves the window visible on the panel
- [ ] `FakePanelWindow` distinguishes iconified from hidden, and the minimize/restore rows assert it

**Wave D**

- [ ] A throw from `_abort`'s own logging reaches `exit(1)`
- [ ] A rethrow from `DaemonStartup.begin` or the not-the-daemon exit runs the abort guard
- [ ] Every await on the pre-lifecycle teardown path is bounded by one injected duration reused at every site
- [ ] A teardown step's failure never skips a later step, and the address is always released
- [ ] A stop during the portal wait runs the ordered teardown exactly once; `applyStartupBindOutcome` never touches a disposed graph

**Wave E**

- [ ] The OpenAI-compatible provider is selectable and streams register variants from a configured endpoint
- [ ] The API key resolves `keyring → env → config`, with the winning source surfaced in settings
- [ ] The daemon writes no API key to `config.json`
- [ ] A missing base URL or model yields `providerUnavailable` with an actionable message on first `correct()`, never blocking startup
- [ ] `CorrectionFailureKind` still has exactly four members
- [ ] The register-tagged stream parser is shared by both adapters, not duplicated
- [ ] No `switch (providerId)` exists below the composition root
- [ ] A second submit cancels the first and tears down its HTTP request
- [ ] An unknown provider id yields a startup warning and an unconfigured provider, never a failed startup, and an architecture decision records it

**Wave F**

- [ ] No row of the controllers' error contract reads `N/A` where the matrix states a behaviour
- [ ] The spine contains a `Map` collection-equality rule beside AD-2's `List` and AD-9's `Set`
- [ ] The spine's runtime-dependency list contains a StatusNotifier/AppIndicator host with its silence note
- [ ] The `Dart SDK` row matches the pinned SDK and the EOL warning is true or gone
- [ ] No `lib/` comment cites `<Ctrl><Shift>g` as a spine example
- [ ] The Structural Seed lists the omitted shipped files, including the two cited by name in normative prose
- [ ] Each of the five frozen records (story 5 intent-contract, CAP-2 success clause, AD-8/AD-18 snippets, renumbering ban, `hotkey_status_view.dart` doc comment) is corrected or dispositioned
- [ ] The architecture run's frozen `reviews/` reports carry a recorded disposition
- [ ] No instruction in the tree directs deleting a ledger entry
- [ ] All 40 closures flip `status:` and add `resolution:`; the ledger diff shows non-zero additions and zero deleted entry headings

**Phase-wide**

- [ ] The existing suite still passes locally; no test is deleted or weakened to make a claim pass
- [ ] All 40 roadmap requirements are closed in `deferred-work.md`

## Edge Coverage

**Coverage:** 31/59 applicable edges resolved · 28 dismissed · 0 unresolved

| Category | Requirement | Status | Resolution / Reason |
|----------|-------------|--------|---------------------|
| unclassified | R1 | ✅ covered | Next-correction-after-change vs in-flight settled in AC |
| boundary | R2 | ⛔ dismissed | Bind refused/accepted is two-valued; no threshold or range exists |
| precision | R2 | ⛔ dismissed | No numeric or rounding contract; a binding value is compared to a config value |
| concurrency | R2 | ✅ covered | Refused bind during an in-flight write leaves config on the previous shortcut; `_beginMutation` already makes a second overlapping mutation unreachable |
| adjacency | R3 | ⛔ dismissed | Tray and settings are two consumers of one state, not entities that merge or collide |
| empty | R3 | ✅ covered | No backend at all is reported on the tray with its cause (user decision, round 3) |
| ordering | R3 | ✅ covered | Both consumers observe every transition; no ordering between them is claimed |
| adjacency | R4 | ⛔ dismissed | A bookkeeping-structure swap has no comparable entities |
| empty | R4 | ✅ covered | Zero outstanding echoes behaves identically to the map form |
| ordering | R4 | ⛔ dismissed | A set has no order, and the requirement's premise is that order never mattered |
| empty | R5 | ✅ covered | An exception with an empty or absent message still yields a warning naming the file path |
| encoding | R5 | ⛔ dismissed | The warning is never measured or compared for length; no encoding contract applies |
| boundary | R6 | ✅ covered | Display smaller than the minimum → shrink to fit (user decision, round 3) |
| adjacency | R6 | ⛔ dismissed | Geometry is set once from chosen values; nothing touches or merges |
| empty | R6 | ✅ covered | No readable display geometry → chosen default, startup still succeeds |
| ordering | R6 | ⛔ dismissed | The three geometry calls are independent property sets; order is unobservable |
| precision | R6 | ⛔ dismissed | Sizes are integer logical pixels; no rounding contract |
| unclassified | R7 | ✅ covered | Click on the already-selected card is a no-op, never a deselect |
| unclassified | R8 | ✅ covered | The rendered hint must match the key that actually selects |
| empty | R9 | ⛔ dismissed | A layout-overlap fix has no empty-input case |
| encoding | R9 | ⛔ dismissed | No string comparison is involved in hit-testing a region |
| unclassified | R10 | ✅ covered | Success feedback only on success; hung/failed writes render a distinct state |
| adjacency | R11 | ✅ covered | Two copies of identical text resolve by the same last-wins rule |
| empty | R11 | ✅ covered | Empty/absent suggestion copy is refused, never writes empty over the clipboard |
| ordering | R11 | ✅ covered | Last request wins (user decision, round 3) |
| concurrency | R11 | ✅ covered | Same rule; writes are serialized behind it |
| boundary | R12 | ⛔ dismissed | A single rebuild event has no threshold |
| precision | R12 | ⛔ dismissed | No numeric contract |
| empty | R13 | ✅ covered | An empty editor has nothing to lose; the rule binds on non-empty text |
| encoding | R13 | ⛔ dismissed | Text is preserved verbatim as a Dart `String`; no length or equality comparison is performed on it |
| concurrency | R13 | ✅ covered | No ordering of summon/click-away/minimize/focus-loss loses text |
| unclassified | R14 | ✅ covered | A draft identical to the effective shortcut is discarded with no visible change |
| boundary | R15 | ⛔ dismissed | The only threshold on this surface is the request timeout, which is R19's subject |
| precision | R15 | ⛔ dismissed | No numeric contract |
| unclassified | R16 | ✅ covered | Hotkey on settings with the panel never shown opens the panel in its empty state |
| unclassified | R17 | ✅ covered | Iconified is modelled as a state distinct from hidden |
| unclassified | R18 | ✅ covered | A throw from the abort logger itself still reaches `exit(1)` |
| adjacency | R19 | ⛔ dismissed | One `Duration` applied at each site; no comparable entities |
| empty | R19 | ✅ covered | A teardown with nothing to release still completes and exits |
| ordering | R19 | ✅ covered | Documented step order; one step's failure never skips a later one |
| concurrency | R19 | ✅ covered | A stop during the portal wait runs the ordered teardown exactly once |
| adjacency | R20 | ✅ covered | Key in two sources → first source wins, source surfaced (user decision, round 3) |
| empty | R20 | ✅ covered | Missing base URL or model → `providerUnavailable` with an actionable message, never blocks startup |
| ordering | R20 | ✅ covered | Variants stream in the order the endpoint emits them; parser shared with the sidecar adapter |
| idempotency | R20 | ✅ covered | Two corrections of the same text are independent stateless sessions |
| concurrency | R20 | ✅ covered | One correction at a time; a second submit cancels the first and tears down the HTTP request |
| unclassified | R21 | ✅ covered | Unknown id → startup warning plus unconfigured provider, never a failed startup |
| unclassified | R22 | ⛔ dismissed | A documentation reconciliation has no input domain to probe |
| adjacency | R23 | ⛔ dismissed | Spine prose edit; no input domain |
| empty | R23 | ⛔ dismissed | Spine prose edit; no input domain |
| ordering | R23 | ⛔ dismissed | Spine prose edit; no input domain |
| adjacency | R24 | ⛔ dismissed | Spine prose edit; no input domain |
| empty | R24 | ⛔ dismissed | Spine prose edit; no input domain |
| ordering | R24 | ⛔ dismissed | Spine prose edit; no input domain |
| concurrency | R24 | ⛔ dismissed | Spine prose edit; no input domain |
| adjacency | R25 | ⛔ dismissed | Frozen-record correction; no input domain |
| empty | R25 | ⛔ dismissed | Frozen-record correction; no input domain |
| ordering | R25 | ⛔ dismissed | Frozen-record correction; no input domain |
| unclassified | R26 | ✅ covered | Closing flips `status:` and adds `resolution:`; diff shows additions, zero deleted headings |

No `backstop` rows: the milestone schedules no new test work, so a held-out edge test is not an
available resolution. Every applicable edge is either an acceptance criterion above or dismissed with
its reason.

## Prohibitions (must-NOT)

**Coverage:** 2/2 applicable prohibitions resolved · 0 unresolved

| Prohibition (must-NOT statement) | Requirement | Status | Verification / Reason |
|----------------------------------|-------------|--------|------------------------|
| MUST NOT send the user's text to any endpoint the user did not explicitly configure — no live default base URL, and adding the second provider MUST NOT change which provider serves existing users | R20 | resolved | verification: judgment — reviewer confirms no default base URL points at a live service and that existing configs keep their provider |
| MUST NOT discard text the user typed — panel editor or hotkey draft — without the user being able to see it happened | R13, R14 | resolved | verification: judgment — reviewer confirms every discard path renders a visible change |
| MUST NOT log input text, suggestion bodies, clipboard content or the API key, including via an exception's `toString()` | R5, R20 | ⛔ dismissed | Already a standing project rule (privacy constraint, `Logger` port doc) and carried as a positive requirement: R5's acceptance is "no logged line in `lib/` interpolates an exception value". Not re-minted as a prohibition |
| MUST NOT write the API key to `config.json` or any file the daemon creates | R20 | ⛔ dismissed | Carried as a positive acceptance criterion under R20 ("the daemon writes no API key to `config.json`"). Not re-minted |
| MUST NOT delete or rewrite a closed ledger entry | R26 | ⛔ dismissed | Process discipline, not product behaviour (user decision, round 4). Already a positive requirement — R26's acceptance requires non-zero additions and zero deleted entry headings |
| MUST NOT close a requirement with a doc claim the shipped code falsifies | R22–R25 | ⛔ dismissed | Process discipline, not product behaviour (user decision, round 4). Already the positive content of R22–R25 |

**Canon referral:** TLS/certificate validation on the new HTTP client, and path handling on config and
secret paths, are canon security — owned by `/gsd-secure-phase` and existing lint, not minted here.

**Verification tier:** both kept prohibitions are `judgment`, not `test`. The milestone bans new test,
gate and CI work (user decision, round 4), so no wired-check descriptors are captured.

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                        |
|--------------------|-------|------|--------|--------------------------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | Six waves, one dependency order, behaviour-first bar named    |
| Boundary Clarity   | 0.86  | 0.70 | ✓      | 40 requirements retained; Phase 1 spillover explicitly out    |
| Constraint Clarity | 0.84  | 0.65 | ✓      | Wave E human gate answered; key-resolution chain decided      |
| Acceptance Criteria| 0.80  | 0.70 | ✓      | 42 pass/fail criteria across six waves plus phase-wide        |
| **Ambiguity**      | 0.142 | ≤0.20| ✓      |                                                              |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

No dimension is below minimum. One stated assumption rides into planning:

- **Reading a key from `config.json` is permitted; writing one is not.** The user's resolution chain
  ends at `config`, while roadmap criterion 13 says the key is "never written to `config.json`". These
  are read as compatible: the daemon reads a hand-placed key as the last link in the chain, surfaces
  that the file was the source, and warns it is plaintext — but never writes one back. Stated to the
  user at the gate and not objected to.

## Interview Log

| Round | Perspective    | Question summary                                  | Decision locked                                                        |
|-------|----------------|---------------------------------------------------|------------------------------------------------------------------------|
| 1     | Researcher     | Does Phase 2 assume Phase 1's gap plans are done? | Yes — Phase 1 closes first; 01-21…01-24 are out of Phase 2's scope      |
| 1     | Researcher     | What must be observably true for "done"?          | Behaviour changes are the bar; doc/spine work supports them. All 40 requirements retained, Wave F not deferred |
| 1     | Simplifier     | What does the user see when the new provider fails? | No fifth `CorrectionFailureKind`; four kinds, `providerError` carries an actionable message. **Answers the roadmap's scheduled Wave E human gate** |
| 2     | Boundary Keeper| Where does the API key live with no secret service?| Resolution chain `keyring → env var → config`; daemon never writes the key to config |
| 2     | Boundary Keeper| What does a click on a suggestion card do?        | Click selects, exactly as the matching digit key does; copy stays separate |
| 2     | Boundary Keeper| Fate of an unapplied hotkey draft on a view swap? | Discarded, but visibly — the field then shows the shortcut in effect     |
| 3     | Failure Analyst| Two overlapping copies — which text wins?         | Last request wins                                                        |
| 3     | Failure Analyst| API key present in more than one source?          | First source wins; settings surfaces which source supplied it            |
| 3     | Failure Analyst| Display smaller than the panel's minimum size?    | Shrink to fit the display; the minimum is a preference, not a floor      |
| 3     | Failure Analyst| Tray presentation when there is no backend at all?| (Answered "tray silent", then corrected in round 4)                      |
| 4     | Seed Closer    | That answer would delete SETTINGS-03/06/08 — meant?| No — keep the tray fully informed, including no-backend. No requirement changes |
| 4     | Seed Closer    | Which must-NOTs bind, and how are they verified?  | Two kept (unconfigured endpoint, silent text discard), both `judgment` tier; four dismissed as already-positive requirements or process discipline |

---

*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Spec created: 2026-09-14*
*Next step: /gsd-discuss-phase 2 — implementation decisions (how to build what's specified above)*
