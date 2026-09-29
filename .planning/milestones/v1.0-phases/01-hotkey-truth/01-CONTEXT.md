# Phase 1: Hotkey Truth - Context

**Gathered:** 2026-09-01
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase makes the hotkey surface tell the truth. A binding the daemon reports is the
binding the display server actually holds; a backend that is missing or refuses degrades
visibly instead of lying or preventing startup.

Ten requirements: HOTKEY-01, HOTKEY-02, HOTKEY-03, HOTKEY-04, HOTKEY-06, HOTKEY-07,
HOTKEY-08, HOTKEY-09, HOTKEY-10, ARCH-02.

**In scope:** the X11 grab path and its replacement, the Wayland portal handshake, the
`GlobalHotkey` port surface, the Settings shortcut control, and the packaging *decision*.

**Out of scope:** building the packaging pipelines, tray fan-out (Phase 2), notifications
of any kind, and all test/gate/CI work (removed from the milestone on 2026-08-31).

</domain>

<decisions>
## Implementation Decisions

Nineteen decisions from four discussion areas. The user asked to be questioned on product
behaviour rather than implementation, so these record **what the user must experience**;
the mechanism is the planner's and executor's to choose except where a decision names one.

### What the user sees when the desktop owns the binding

- **D-01:** When the desktop reassigns the shortcut behind the app's back, Settings shows
  the shortcut **currently in effect, silently** — no "your preference was overridden"
  notice. The app never displays the combination it requested in place of the one that is
  actually firing.
- **D-02:** A shortcut the desktop accepts but assigns *differently* counts as **bound**,
  not refused. Something opens the panel, which is what the user wanted; the exact
  combination is the desktop's to choose on Wayland.
- **D-03:** One UI everywhere, **mechanism hidden**. The app still grabs directly on X11 and
  declares via the portal on Wayland, but Settings presents only "the shortcut in effect".
  The authoritative-vs-advisory **regime label is dropped from the UI**.
  — **Reversibility:** costly — AD-10's ratified rule (spine line 620) *requires* the
  settings screen to show which regime is active. Dropping it is an amendment to a
  user-ratified decision, so restoring it later means re-opening that ratification, not
  just re-adding a widget.
- **D-04:** On Wayland, Settings displays **the desktop's own description text verbatim**
  (e.g. a German desktop's `Strg+Umschalt+G`), not a re-rendering in the app's notation.
  Accuracy beats uniform notation. Accepted cost: shortcut notation differs between X11 and
  Wayland even though the regime label is hidden.
- **D-05:** Nothing in the product needs the Wayland shortcut as a **structured
  combination** — the app needs only *whether* something is held and *what text to show*.
  No parsing of localised portal text. See the HOTKEY-03 amendment below.

### What the user is told when it fails

- **D-06:** The three causes get **three distinct messages** — no global-shortcut support on
  this desktop / that key was refused, pick another / your shortcut was taken away. No
  per-case action buttons; the messages differ, the UI affordances do not.
  — **Reversibility:** one-way — `HotkeyUnavailable` is named in AD-9's frozen
  field-and-constructor list with a single `final String message`. Distinguishing three
  causes edits that declaration. Undoing it means reverting a published domain type that
  `SettingsState` contains transitively and that consumers will have started switching on.
- **D-07:** **All three messages keep the tray-menu line.** Whatever went wrong, the user is
  always told the panel is still reachable from the tray.
- **D-08:** When the desktop revokes the shortcut, the daemon **does not try to re-claim
  it**. It reflects the loss; the user re-applies when they want it back. No retry, no
  automatic re-establish — on Wayland the compositor is the authority and fighting it risks
  an override loop.
- **D-09:** A shortcut lost mid-session is discovered **when the user next looks**. No
  desktop notification, no interruption, no tray warning state from this phase. The daemon
  stays invisible; a failed keypress simply does nothing.
- **D-10:** On X11, a combination another application already owns is **refused, and the
  previously working shortcut stays in effect**. The user is told it is taken and asked for
  a different one. They never lose a working shortcut they did not ask to give up.

### Startup, and the missing library

- **D-11:** A missing `libkeybinder-3.0.so.0` must leave the daemon **running with the
  hotkey disabled** — tray icon present, panel reachable from the tray, Settings reporting
  the shortcut unavailable. Today the process dies at the dynamic loader with no window, on
  Wayland machines too. This is the phase's most severe user-facing defect.
- **D-12:** The shortcut plumbing is replaced as **one clean change** — old path deleted, no
  runtime fallback, no user-visible toggle. Keeping the old path would defeat the fix: it is
  what forces the library at launch, and it is what reports refused grabs as successes.
  — **Reversibility:** one-way — closing D-11 requires the `hotkey_manager` plugin to stop
  being linked into the runner at all (see Integration Points). Removing a Flutter plugin
  dependency regenerates `linux/flutter/generated_plugins.cmake` and changes the runner's
  own `DT_NEEDED`; restoring it later re-introduces the launch-time hard dependency on every
  host, including Wayland-only ones.

### How the user sets the shortcut

- **D-13:** **At least one modifier is always required.** No bare-key shortcuts, not even
  function keys. A global grab takes the key from every application, and a user who binds
  bare `G` loses the letter system-wide — in an app built for people writing English text.
- **D-14:** The user **presses the combination** to set it. A capture control replaces the
  current key-label field. The user never has to know their key is called `Pause` or
  `ISO_Level3_Shift`.
  — **Reversibility:** costly — replaces `lib/src/ui/settings/hotkey_preference_field.dart`
  (260 lines) and changes what `HotkeyKeyCatalogue` is for. Reverting means restoring both
  the widget and the catalogue's curation role. See the HOTKEY-04 amendment below.
- **D-15:** A captured combination the app can tell will not fire is **rejected at capture**,
  with the reason, keeping the previous shortcut. The user never saves something broken and
  never waits until Apply to find out.
- **D-16:** While a bind is in flight, the user sees a **busy state with the key field
  locked** read-only. No optimistic display of a shortcut that is not yet in effect.
- **D-17:** A portal that never answers **fails after a few seconds**, leaving the previous
  shortcut in effect. Settings never hangs with no way out.

### Packaging (ARCH-02)

- **D-18:** Ship **all three formats** — `.deb`/tarball, Flatpak, and AppImage — with **no
  primary build**; all three are offered equally and none may be second-class.
  — **Reversibility:** one-way *for this phase's code*. Flatpak's inclusion is what forces
  the portal handshake to be written sandbox-safe (no unconditional `Registry.Register`),
  which is the retroactive constraint the roadmap flagged. That code shape cannot be
  un-decided after the handshake is written; it must be settled before
  `wayland_portal_global_hotkey.dart` is touched.
- **D-19:** The Flatpak declares the **narrowest permission set that works** — clipboard,
  the OS secret store for a future API key, and its own data directory. No home-directory
  access, no broad filesystem. The app reads everything the user copies and stores their
  plaintext history, so a modest install prompt is part of being trustworthy.

### Requirement amendments the planner must honour

Two requirements change shape as a consequence of the decisions above. Neither loses its
user-facing goal.

- **HOTKEY-03** is written as *"read the compositor's effective binding back **as a
  combination** rather than displaying only the portal's localized `trigger_description`"*.
  Per D-04 and D-05, the app displays that localised text and does **not** parse it into a
  structured combination. The requirement's goal is preserved and is the acceptance test:
  **never echo back what was requested; always show what is actually in effect.** The
  read-back still happens — the app reads the portal's report rather than its own request —
  it simply is not parsed.
- **HOTKEY-04** is written as *"curate the settings key field against `HotkeyKeyCatalogue`
  so the seven labels that bind on Wayland but are refused on X11 cannot be entered by
  name"*. Per D-14 there is no entry-by-name, so the requirement becomes **validate what
  was captured** rather than curate what can be typed. `HotkeyKeyCatalogue` survives as the
  validator behind D-15's reject-at-capture, not as a text-field allowlist. Same goal: the
  user cannot end up with a shortcut that does not fire.

### Claude's Discretion

The user explicitly delegated implementation and asked for product questions only. The
following carry no user-visible surface and were taken without asking:

- **HOTKEY-07** — stating the precedence between `bind()`'s returned outcome and the
  `bindingChanges` stream when the portal emits `ShortcutsChanged` before the
  `BindShortcuts` reply. Internal ordering rule; write it down and enforce it.
- **HOTKEY-09** — defensively copying or wrapping `HotkeyBinding.modifiers` so a caller
  mutating its own set cannot change a supposedly immutable domain value.
- **HOTKEY-10** — re-keying the `libkeybinder` hardness re-measure trigger to a version the
  tree can observe changing. **Note:** D-12 removes `hotkey_manager` entirely, so this
  requirement's premise may dissolve — verify at planning time whether the trigger still has
  a subject, and if not, close it with that finding rather than inventing work.
- The **shape of the `GlobalHotkey` port** — whether current registration is exposed as a
  synchronous accessor, a replaying stream, or an application-ring cache. D-01 requires the
  app to *know* the live binding; the mechanism is unconstrained. AD-9's precedent for this
  class of addition is recorded in the shipped code: `bindingChanges` and the `operator==`
  overrides were added and *"recorded in the deferred-work ledger and the story's Spec
  Change Log rather than hand-edited into the spine."*
- How `HotkeyUnavailable` distinguishes D-06's three causes (a `kind` field, a sealed
  hierarchy, or otherwise) — subject to the AD-9 gate noted in D-06.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The frozen contract
- `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
  — the 19 ADs. Read **AD-9** (lines 235–300: the verbatim port declaration and the rule
  that *"the declared fields and constructors above are the fixed part"*), **AD-10**
  (line 302: `bind()` reports the effective binding and who owns it), **AD-11** (the portal
  call sequence and its app-id hazard), **AD-12** (lines 321–326: every refusal is a value,
  and the half that is easy to get wrong — `HotkeyUnavailable` **only when nothing is
  held**), and **line 584** (the measured `libkeybinder` hardness — why D-11 needs the
  plugin gone, not merely unused). **Line 620** is the user-ratified
  authoritative-on-X11 / advisory-on-Wayland stance that D-03 amends.
- `_bmad-output/implementation-artifacts/deferred-work.md` — the origin of every
  requirement. `DW-39`, `DW-40`, `DW-66`, `DW-71`, `DW-89` by heading; `FLAT-02`, `FLAT-03`,
  `FLAT-04`, `FLAT-05`, `FLAT-11` by order of appearance among the flat
  `- source_spec:` bullets. **Append-only** — close an entry by flipping `status:` and
  adding `resolution:`, never by deleting it.

### This milestone
- `.planning/ROADMAP.md` § *Phase 1: Hotkey Truth* — goal, the five success criteria, and
  the standing constraints. Note the roadmap frames criterion 1 as *two* human decisions;
  D-06 establishes there is a **third** AD-9 declaration edit in this phase.
- `.planning/REQUIREMENTS.md` — full text of the ten requirements, and
  § *Removed: Test-Shaped Work* for the 38 requirements deleted on 2026-08-31.
- `.planning/PROJECT.md` — constraints, and the Key Decisions table.

### Codebase maps
- `.planning/codebase/CONCERNS.md` § *Wayland Portal Global Hotkey* and
  § *X11 vs Wayland Divergence* — why the 1307-line adapter is flagged fragile.
- `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STACK.md`,
  `.planning/codebase/INTEGRATIONS.md`.

### Code that carries evidence in its own doc comments
- `lib/src/infrastructure/hotkey/hotkey_registrar.dart` — the class doc states the two
  facts HOTKEY-01 exists for, with upstream file:line citations: the plugin builds the
  keybinder accelerator in C, and **it discards `keybinder_bind`'s `gboolean` and answers
  `true` regardless**, so a refused grab arrives as success. Read this before designing the
  replacement.
- `lib/src/domain/hotkey/global_hotkey.dart` — the AD-9 precedent for adding a member
  without touching declared fields, stated in the `bindingChanges` doc comment.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` (222 lines) — carries **probed
  evidence** about key labels, including `labelsThatBindTheWrongKey` (the seven that resolve
  to keypad/ISO/3270 variants, DW-43). This is the validator D-15 needs; keep the evidence,
  change the role.
- `lib/src/infrastructure/hotkey/display_server.dart` — pure function over an injected
  environment map, already the single place the X11/Wayland choice is made, once, at startup.
- `lib/src/infrastructure/hotkey/hotkey_grab.dart` and `hotkey_registrar.dart` — the
  infrastructure-private seam the replacement slots into. The port stays; the
  implementation behind it changes.
- The panel adapter's existing bounded-request mechanism is the model for D-17's timeout —
  do not invent a second timeout pattern.

### Established Patterns
- **Failure as value, never exception.** `bind()` never throws and never rejects (AD-12).
  Every decision above must land as a `HotkeyBindOutcome`, not an error.
- **`HotkeyUnavailable` only when nothing is held.** When a previously granted combination
  is still in effect, a refused rebind returns `HotkeyBound` naming *that* combination and
  logs the abandonment. D-10 is this rule, surfaced to the user.
- **Vendor types never cross the port boundary** (AD-1, AD-17). `dbus`, `ffi` and any
  keybinder handle stay adapter-private.
- **Hotkey confinement.** No Flutter import may reach `x11_global_hotkey.dart`, directly or
  transitively — `test/infrastructure/system/daemon_startup_test.dart` imports it and runs
  under `dart test`, which cannot resolve `dart:ui`. A Flutter import there does not fail a
  test, it stops the whole binding-free suite from resolving.
- Default shortcut is `Ctrl+Shift+G`, applied at every startup
  (`lib/src/infrastructure/config/default_app_config.dart:142`). There is no
  "nothing configured yet" state to design for.

### Integration Points
- **`pubspec.yaml:37` — `hotkey_manager: 0.2.3` must be removed** for D-11 to be
  achievable, and `ffi` added. This is the crux: `linux/flutter/generated_plugins.cmake`
  lists `hotkey_manager_linux` in `FLUTTER_PLUGIN_LIST` and links every plugin
  unconditionally, with no display-server condition, which puts
  `libhotkey_manager_linux_plugin.so` in the **runner's own** `DT_NEEDED`. The loader
  therefore resolves runner → plugin → `libkeybinder-3.0.so.0` at process start, *before*
  `main()` and so before the adapter is chosen. `dlopen` alone does not fix this; the plugin
  must stop being linked.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` (1307 lines, flagged
  fragile) — three `effective: null` construction sites at lines **342, 874, 971**, and
  `trigger_description` handled at **1124/1135**. D-18's sandbox-safe handshake and D-04's
  read-back both land here. **Decide packaging before touching this file.**
- `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart` (242 lines) — deleted by
  D-12, along with its tests.
- `lib/src/ui/settings/hotkey_preference_field.dart` (260 lines) — replaced by D-14's
  capture control.
- `lib/src/ui/settings/hotkey_status_view.dart` (178 lines) — renders D-06's three messages
  and D-07's tray line. Also the subject of SETTINGS-09 in **Phase 2**; coordinate rather
  than collide.
- `lib/src/infrastructure/hotkey/xdg_shortcut_trigger.dart` (202 lines) — serialises the
  `preferred_trigger` the portal receives.

</code_context>

<specifics>
## Specific Ideas

- The user's framing throughout: **ask about what the user of the daemon experiences, not
  about port design.** Honour this in any further clarification — bring product questions,
  take the technical calls.
- The daemon should **stay invisible** (D-09). This is the strongest through-line in the
  discussion: no notifications, no interruptions, no nagging. A failed keypress does nothing
  and the user finds out when they look. Weigh future proposals against it.
- **Accuracy over uniform presentation** (D-04). Where the two conflict, show the user what
  is true even if it renders differently across display servers.
- **Never advertise a shortcut that does not fire.** D-10, D-15 and D-16 are three faces of
  this, and it is the phase's core value in one sentence.

</specifics>

<deferred>
## Deferred Ideas

- **Build the three release pipelines** — `.deb`/tarball packaging, the Flatpak manifest,
  and the AppImage recipe. ARCH-02 requires only that the format be *decided and recorded*,
  which D-18 does. Building three pipelines is a phase of its own, and it is now on the
  critical path to shipping since D-18 commits to all three.
- **Autostart on login.** A tray-resident daemon needs it, and each of the three packaging
  formats handles it differently. Not among Phase 1's ten requirements. Belongs with the
  packaging phase above.
- **Desktop notifications as a capability.** Declined for the shortcut-lost case (D-09), but
  worth recording that the app has no notification surface at all today — a future
  capability decision, not an oversight.
- **A tray warning state for a degraded hotkey.** Raised and declined for this phase (D-09).
  Phase 2 (Settings & Tray Fan-Out) owns tray rendering; this phase produces the state it
  would render.

</deferred>

---

*Phase: 1-Hotkey Truth*
*Context gathered: 2026-09-01*
