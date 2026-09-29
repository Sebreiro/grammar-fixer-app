# Phase 1: Hotkey Truth - Research

**Researched:** 2026-09-01
**Domain:** Linux global-hotkey acquisition (X11 passive grabs + XDG GlobalShortcuts portal), Dart FFI, hexagonal port surgery under a frozen architecture spine, Linux desktop packaging
**Confidence:** HIGH for everything measured in this container; MEDIUM for portal-spec claims; LOW for the Flutter thread model and for anything needing a real desktop session

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

Nineteen decisions from four discussion areas. The user asked to be questioned on product
behaviour rather than implementation, so these record **what the user must experience**;
the mechanism is the planner's and executor's to choose except where a decision names one.

**What the user sees when the desktop owns the binding**

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

**What the user is told when it fails**

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

**Startup, and the missing library**

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

**How the user sets the shortcut**

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

**Packaging (ARCH-02)**

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

**Requirement amendments the planner must honour**

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

### Deferred Ideas (OUT OF SCOPE)

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
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOTKEY-01 | Replace the `hotkey_manager` X11 grab path with a registrar that reads the grab's real result, so a grab another client already owns reports failure instead of success (`DW-39`) | § *The X11 Grab Replacement*. **Measured in this container:** `XGrabKey` + `XSetErrorHandler` + `XSync` reports `BadAccess` (code 10, request 33) synchronously when a second client holds the combination. Also verified `hotkey_manager_linux_plugin.cc:96` discards `keybinder_bind`'s `gboolean` and `:99` answers `true` regardless. |
| HOTKEY-02 | A missing `libkeybinder-3.0.so.0` degrades the hotkey visibly instead of preventing startup (`DW-40`) | § *The X11 Grab Replacement*, § *Pitfall 1*. **Measured:** the release runner's own `DT_NEEDED` names `libhotkey_manager_linux_plugin.so`, which itself `NEEDED`s `libkeybinder-3.0.so.0`. Also measured: `libgdk-3.so.0` already `NEEDED`s `libX11.so.6`, so the recommended replacement adds no new runtime dependency at all. |
| HOTKEY-03 | Read the Wayland effective binding back rather than echoing the request (`DW-66`) | § *The Sandbox-Safe Portal Handshake*. Portal spec confirms **no machine-readable combination exists anywhere in the reply** — D-04/D-05 are correct and HOTKEY-03's amendment stands. `ListShortcuts` is the unused on-demand read-back the phase should adopt. |
| HOTKEY-04 | The key vocabulary cannot yield a shortcut that does not fire (`DW-71`) | § *Correction C3* — **the seven `labelsThatBindTheWrongKey` dissolve on X11 once `hotkey_manager` goes.** Measured against libX11 and GTK3 here. The validator's subject changes; § *HOTKEY-04 after the replacement* gives the new one. |
| HOTKEY-06 | `GlobalHotkey` gains a synchronous current-registration accessor (`FLAT-02`) | § *AD-9 Declaration Edits*, edit **A**. Recommended shape folds HOTKEY-03's carrier into the same new member so one human decision covers both. |
| HOTKEY-07 | State the precedence between `bind()` and `bindingChanges` (`FLAT-03`) | § *HOTKEY-07: the precedence rule, and the gap it exposes*. Portal spec states no ordering; the tree already implements one rule for startup (`applyStartupOutcome`) and a contradictory one for rebinds (`changeHotkey`). |
| HOTKEY-08 | Split `HotkeyUnavailable`'s three meanings (`FLAT-04`) | § *AD-9 Declaration Edits*, edit **B**, with two concrete shapes and the call-site cost of each (20 construction sites measured). |
| HOTKEY-09 | `HotkeyBinding.modifiers` cannot be mutated behind its `const` constructor (`FLAT-05`) | § *AD-9 Declaration Edits*, edit **D**. In-tree precedent is `HotkeyGrab`. Cost measured: 1 `const` site in `lib/`, 24 in `test/`. |
| HOTKEY-10 | Re-key the `libkeybinder` hardness re-measure trigger (`FLAT-11`) | § *HOTKEY-10 dissolves*. Verified: the trigger's subject (`hotkey_manager_linux 0.2.0`, transitive) leaves the tree entirely under D-12. Recommendation: close with the finding + one envelope clause edit. |
| ARCH-02 | Decide the packaging format, recording the `Registry.Register` consequence (`DW-89`) | § *The Sandbox-Safe Portal Handshake*, § *Flatpak Permission Mechanics*, § *Correction C1* (the ledger already records a **four**-format decision that D-18 contradicts). |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md and AGENTS.md)

These are as binding as the locked decisions. Every one of them constrains a task in this phase.

| Constraint | Source | Consequence for this phase |
|---|---|---|
| Domain (`lib/src/domain/`) imports only `dart:` libraries | CLAUDE.md; AGENTS.md §4; `test/architecture/ad1_import_rule_test.dart` | `dart:ffi` is a `dart:` library, so an FFI-based registrar could technically live anywhere — but it must stay in `infrastructure/` because the port abstraction is the point (AD-1, AD-17). |
| No Flutter import may reach `lib/src/infrastructure/hotkey/` except the one exempt seam file | AGENTS.md §4.2; `test/architecture/hotkey_confinement_test.dart` | The replacement **must not** import Flutter. `dart:ffi` and `dart:isolate` satisfy this; a Flutter FFI *plugin package* would not, if its Dart API touched `package:flutter`. |
| Vendor types never cross a port boundary | AD-1, AD-17; CLAUDE.md | `Pointer`, `DynamicLibrary`, `DBusValue`, keysym ints and accelerator strings all stay adapter-private. `HotkeyGrab` is the existing crossing type. |
| Failure is a value, never an exception | AGENTS.md §8; AD-12; CLAUDE.md | `bind()` never throws. Every new failure path (library absent, `XOpenDisplay` null, `BadAccess`, portal timeout) becomes a `HotkeyBindOutcome`. |
| Never log `error.toString()`; log `error.runtimeType` and app-authored context | `Logger` port doc; CLAUDE.md | The existing `_errorContext(Object)` helper is the pattern — reuse it verbatim in any new adapter. |
| One public type per file, snake_case file name | AGENTS.md §3 | A new `X11KeyGrabRegistrar` goes in `x11_key_grab_registrar.dart`, private helpers prefixed `_`. |
| Every `ignore` comment carries a one-line justification; no `dynamic`; no `!` to silence the analyzer | `analysis_options.yaml`; AGENTS.md §6 | FFI struct/typedef code must not reach for `dynamic` or `!`. |
| Merge gate is `dart analyze --fatal-infos` clean | `.github/workflows/ci.yml:96`; AGENTS.md §6 | **Measured baseline: clean, "No issues found!" (2026-09-01).** |
| `unawaited_futures` lint is on | `analysis_options.yaml` | An isolate spawn or a `SendPort` round trip must be awaited or `unawaited(...)`. |
| Comments explain *why*, never *what*; no `TODO` without a concrete follow-up | AGENTS.md §1 | This codebase's doc comments are load-bearing records. A deleted file's measured facts (the `keybinder_bind` discard, the `std::map::insert` non-overwrite) must be re-homed or deliberately retired, not silently lost. |
| Consistency beats personal taste — match the surrounding code | AGENTS.md §1 | Reuse `_queue`, `_guard`, `_log`, `_errorContext`, `_disposed` idioms; they are identical across both adapters and the panel adapter. |

---

## Summary

Phase 1 is three separable engineering problems wearing one requirement cluster, plus two
human decisions that gate all of them.

**The X11 half is smaller than it looks and the recommended route is not the one the ledger
proposed.** `DW-39` proposed a `dart:ffi` binding to `libkeybinder-3.0.so.0`, and flagged its
own risk: keybinder calls GDK and installs an X11 event filter, so it must run on the GTK main
thread, which needs `g_idle_add` marshalling and a threading surface no test in this container
can touch. That risk is real and — measured — worse than the ledger knew: `NativeCallable.listener`
*cannot* be used as a `GSourceFunc` (it neither returns a value nor runs on the calling thread),
so the marshalling the ledger sketched does not compose. There is a strictly simpler route that
sidesteps GTK entirely: **`dart:ffi` against `libX11.so.6` on a private `Display` owned by a
dedicated Dart isolate.** I proved every step of it against a live X server in this container:
`XGrabKey` under an `XSetErrorHandler` + `XSync` reports a conflicting grab as `BadAccess`
(code 10, request 33) *synchronously*, a second connection's passive grab really does receive
`KeyPress` with the right keycode and modifier state, and `libX11.so.6` is already an
unconditional `DT_NEEDED` of `libgdk-3.so.0` — so this route adds **no** new runtime dependency
to the envelope and D-11's "library absent" case becomes structurally unreachable rather than
merely handled.

**The Wayland half is a surgical edit to a large file, not a rewrite.** The 1307-line adapter
is long because its doc comments are a measurement record, not because its control flow is
tangled: it is one linear four-step handshake plus a small set of well-separated helpers, and
CONTEXT.md's cited line numbers (342, 874, 971, 1124, 1135) are all correct. Three edits land
here — a sandbox predicate around step 1, a carrier for the localized `trigger_description`,
and a bounded wait on the bind path — and each cuts along an existing seam. The portal spec
confirms D-04/D-05: **no field in any GlobalShortcuts reply carries a machine-readable
combination**, so HOTKEY-03's amendment is correct and not a compromise.

**The gates are bigger than the roadmap says.** The roadmap names two human decisions; CONTEXT.md
adds a third. Research finds **four** distinct edits to AD-9's verbatim-frozen block, and a
principled way to collapse them: three are *additions* that leave every declared field and
constructor untouched, which is exactly the precedent `global_hotkey.dart`'s own doc records for
`bindingChanges`; only one — dropping `const` from `HotkeyBinding`'s declared constructor — is an
edit to a declared constructor, and only that one plus HOTKEY-08's cause discriminator need fresh
human ratification. Separately, the deferred-work ledger already carries a 2026-08-14 human
decision on packaging naming **four** formats (adding a native Arch PKGBUILD); D-18 names three.
That contradiction must reach the human at the ARCH-02 checkpoint.

**Primary recommendation:** Replace the X11 grab with a `dart:ffi` → `libX11.so.6` passive-grab
registrar running its own `Display` in a dedicated Dart isolate, detecting refusal via
`XSetErrorHandler` + `XSync`; delete `hotkey_manager` from `pubspec.yaml`; make the portal's
`Registry.Register` conditional on a `/.flatpak-info`-keyed sandbox predicate injected the same
way `DisplayServer.fromEnvironment` is; and take **one** combined human decision that ratifies
the AD-9 additions and the packaging format before any file in `lib/src/infrastructure/hotkey/`
is touched.

---

## Corrections to CONTEXT.md and the roadmap

**Read this section first.** Everything here changes what a plan should say. Each item names the
evidence.

### C1 — The ledger already records a packaging decision, and it names *four* formats, not three

D-18 commits to `.deb`/tarball, Flatpak and AppImage. `DW-89`'s own `decision:` line, dated
2026-08-14, records a prior human answer: *"Pick a format now -- all four -- the human named four
targets rather than one: Flatpak, .deb, AppImage, and a native Arch package (PKGBUILD/pacman) for
a direct launch on Arch-based systems."*
[VERIFIED: `_bmad-output/implementation-artifacts/deferred-work.md:1349`]

The two records disagree by one format. Nothing in this phase's *code* changes either way — the
Flatpak inclusion is what drives the `Registry.Register` conditional and both records include it —
but ARCH-02's deliverable is *the decision, recorded*, and closing `DW-89` with a record that
contradicts its own `decision:` line would leave the ledger self-inconsistent. **The planner must
put this contradiction in front of the human at the ARCH-02 checkpoint** and record one answer in
both places.

### C2 — There are **four** AD-9 declaration edits in this phase, not one (roadmap) or three (CONTEXT.md)

The roadmap's criterion 1 names one (`GlobalHotkey`'s accessor). CONTEXT.md's D-06 adds a second
and says *"there is a **third** AD-9 declaration edit in this phase"*. Research finds four. See
§ *AD-9 Declaration Edits* for each, with the AD line cited and the precedent mechanism spelled
out. The fourth (`HotkeyBinding`'s `const` constructor, HOTKEY-09) is the one CONTEXT.md files
under "Claude's Discretion" without noticing it touches the frozen block.

### C3 — The seven "wrong key" labels dissolve on X11 the moment `hotkey_manager` goes

This is the most consequential correction, because HOTKEY-04's amendment rests on it.

`HotkeyKeyCatalogue.labelsThatBindTheWrongKey` = `{Space, Tab, Enter, F1, F2, F3, F4}`
[VERIFIED: `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart:134-142` —
`static const Set<String> labelsThatBindTheWrongKey = <String>{ 'Space', 'Tab', 'Enter', 'F1', 'F2', 'F3', 'F4', };`].
Its own doc states the cause: `hotkey_manager` sends `hotKey.physicalKey.keyCode`, which
`uni_platform` resolves by scanning Flutter's `kGtkToLogicalKey` for the *first* entry whose value
is the logical key — and that table lists the keypad/ISO/3270 variants first.

**Measured here on 2026-09-01, the X11 and GTK key paths do not have this defect.** Probing the
installed `libX11.so.6` and GTK3 directly:

```
XStringToKeysym("space")  -> 0x00000020  keycode 65 -> keysym 0x0020 (space)
XStringToKeysym("Tab")    -> 0x0000ff09  keycode 23 -> keysym 0xff09 (Tab)
XStringToKeysym("Return") -> 0x0000ff0d  keycode 36 -> keysym 0xff0d (Return)
XStringToKeysym("F1")     -> 0x0000ffbe  keycode 67 -> keysym 0xffbe (F1)
XStringToKeysym("F4")     -> 0x0000ffc1  keycode 70 -> keysym 0xffc1 (F4)
gtk_accelerator_parse("<Control><Shift>space") -> keyval=0x0020 mods=0x0005  name=<Shift><Control>space
gtk_accelerator_parse("<Alt>F1")               -> keyval=0xffbe mods=0x0008  name=<Alt>F1
```

No `KP_Space`, no `ISO_Left_Tab`, no `3270_Enter`, no `KP_F1`–`KP_F4` anywhere.
[VERIFIED: direct `ctypes` probe of `/usr/lib/x86_64-linux-gnu/libX11.so.6`, `libgdk-3.so.0` and
`libgtk-3.so.0` in this container, 2026-09-01; keycode round-trip performed against a live
`Xvfb :77` server.]

**Consequence.** DW-43 is an artefact of a *vendor package's reverse lookup table*, not of X11,
not of keybinder, and not of GTK. Once the plugin is gone and the registrar resolves keys by
keysym name — which `XdgShortcutTrigger.keysymNameFor` already does, measured against xkbcommon
1.6.0 — all seven bind correctly. `labelsThatBindTheWrongKey` should become **empty**, and DW-43
should be closed as resolved by this phase, not carried.

HOTKEY-04's amendment therefore needs a different subject. See § *HOTKEY-04 after the replacement*.

### C4 — D-17's timeout reverses a design decision recorded in the code, and the planner must say so

D-17 says a portal that never answers *"fails after a few seconds"*. The adapter's own source says
the opposite, deliberately:

> "Deliberately on the teardown path alone. The bind path has no timeout by intent: AD-11 makes a
> portal dialog the user must answer normal, and cancelling one out from under them would be worse
> than waiting."
> [VERIFIED: `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:1300-1307`]

D-17 is a legitimate product override of an engineering judgement, and it wins — but the plan must
carry the *reason the old rule existed* into the new one, or the daemon will start cancelling
portal dialogs the user is still reading. See § *Pitfall 4* for the shape that satisfies both.

### C5 — Every line number CONTEXT.md cites in the Wayland adapter is correct

Verified by grep against the current file (1307 lines):
`:342`, `:874`, `:971` are the three `effective: null,` construction sites;
`:1124` is `final description = properties?['trigger_description'];`;
`:1135` is `'trigger_description': description is DBusString`.
[VERIFIED: `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`]

### C6 — The `DT_NEEDED` chain CONTEXT.md describes is exactly right, measured today

```
$ readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector | grep NEEDED
 (NEEDED)  Shared library: [libhotkey_manager_linux_plugin.so]
 ...
$ readelf -d build/linux/x64/release/bundle/lib/libhotkey_manager_linux_plugin.so | grep NEEDED
 (NEEDED)  Shared library: [libkeybinder-3.0.so.0]
 ...
```
[VERIFIED: `readelf -d` against this tree's committed release bundle, 2026-09-01]

`linux/flutter/generated_plugins.cmake` links every entry of `FLUTTER_PLUGIN_LIST` with
`target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)` and no display-server condition.
[VERIFIED: `linux/flutter/generated_plugins.cmake`]

**New, and useful:** the same file's `FLUTTER_FFI_PLUGIN_LIST` loop does **not** call
`target_link_libraries` — an FFI plugin is bundled but never enters the runner's `DT_NEEDED`.
That is why an FFI route (any of the three options below) genuinely closes D-11 where `dlopen`
inside a linked plugin would not.

### C7 — `libX11.so.6` is already a hard dependency of every build, on both display servers

```
$ readelf -d /usr/lib/x86_64-linux-gnu/libgdk-3.so.0 | grep -E "NEEDED.*(X11|Xext)"
 (NEEDED)  Shared library: [libX11.so.6]
 (NEEDED)  Shared library: [libXext.so.6]
```
[VERIFIED: 2026-09-01]

The runner `NEEDED`s `libgtk-3.so.0` and `libgdk-3.so.0`, which `NEEDED` `libX11.so.6`. So on any
host where this Flutter app can start at all, `libX11.so.6` is already resolved and loaded.
A `DynamicLibrary.open('libX11.so.6')` from Dart returns a handle to the already-loaded copy.
**Choosing the X11 route means D-11's "library absent" branch becomes unreachable rather than
merely handled**, and the envelope's runtime-dependency list loses `libkeybinder-3.0-0` outright
instead of demoting it.

### C8 — `ffi` is already resolved; adding it is a promotion, not a new dependency

`pubspec.lock` records `ffi` at **2.2.0**, `dependency: transitive`.
[VERIFIED: `pubspec.lock:220-227`]
`dart:ffi` itself is a VM core library and needs no package. `package:ffi` supplies only
`malloc`/`calloc`/`Utf8` conveniences. Promoting it to a direct dependency at the already-resolved
version cannot move any other pin.

### C9 — Removing `hotkey_manager` breaks at least five *existing* test rows, and the milestone forbids writing new ones

The milestone removed all test-shaped work, but existing tests must not be broken — and several
are hard-coded to the file this phase deletes:

| File | Row / assertion | Why it breaks |
|---|---|---|
| `test/architecture/hotkey_confinement_test.dart:48-62` | `expect(_filesReferencing('package:hotkey_manager/'), [_seamFile])` | becomes `[]` vs `[_seamFile]` |
| `test/architecture/hotkey_confinement_test.dart:78-112` | Flutter-import scan expects `[_seamFile]` for `package:flutter/` | becomes `[]` |
| `test/architecture/hotkey_confinement_test.dart:366,379` | `expect(_filesReferencing('package:hotkey_manager'), isNotEmpty)`, `expect(File(_seamFile).existsSync(), isTrue)` | file is deleted |
| `test/architecture/hotkey_confinement_test.dart:221-313` | Two rows read `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` and `offeredKeyExamples` from `hotkey_preference_field.dart` | D-14 deletes that widget and C3 empties that set |
| `test/architecture/composition_wiring_test.dart:864,895,901` | `expect(main, contains('final hotkeyRegistrar = HotkeyManagerRegistrar();'))` plus two ordering rows | literal no longer in `main.dart` |
| `test/platform/hotkey_manager_registrar_test.dart` (608 lines) | whole suite drives the deleted seam through mocked channels | deleted with the seam |
| `test/infrastructure/hotkey/x11_global_hotkey_test.dart` (739 lines) | drives `X11GlobalHotkey` through `FakeHotkeyRegistrar` | survives if the port stays; check `:437`'s comment about the shipped seam's disposal behaviour |
| `test/fakes/fake_hotkey_registrar.dart:24` | doc comment cites the deleted platform suite | comment-only |

[VERIFIED: grep of `test/` for `hotkey_manager|HotkeyManagerRegistrar|hotKeyManager`]

**This is maintenance of an existing gate, not new test work** — it is in scope, and it must be
budgeted as its own task or the phase ends red.

### C10 — A bare `dart test` does not work in this tree; use the CI-scoped command

```
$ dart test                                     # 69 suites FAIL TO LOAD, 0 pass
$ dart test --exclude-tags=live \
    test/application test/architecture test/domain test/infrastructure \
    test/fakes_smoke_test.dart
  00:58 +946 ~2: All tests passed!
```
[VERIFIED: both commands run 2026-09-01. The scoped form is `.github/workflows/ci.yml:103-106`.]

A bare `dart test` also sweeps `test/ui`, `test/composition` and `test/platform`, which need a
Flutter binding and cannot resolve `dart:ui`. **946 passed / 2 skipped / 0 failed in 58 s** is the
Phase 1 baseline. Any plan step that says "run `dart test`" is wrong.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Acquiring an X11 passive key grab | Infrastructure (`infrastructure/hotkey/`) | — | Vendor/platform seam behind `HotkeyRegistrar`; `dart:ffi` handles and keysyms never rise (AD-1, AD-9) |
| Detecting that a grab was refused | Infrastructure | — | `BadAccess` is an X protocol fact; it becomes a rejected `Future` at the seam and a value at the adapter (AD-12) |
| Declaring a Wayland shortcut via the portal | Infrastructure | — | `package:dbus` is confined to one file by `hotkey_confinement_test.dart` |
| Deciding *whether this build is sandboxed* | Infrastructure (pure function over injected environment) | — | Same shape as `DisplayServer.fromEnvironment` — a pure predicate a binding-free test can drive |
| Choosing which adapter runs | Infrastructure (`daemon_startup.dart:264-268`) | Composition root (`main.dart`) | AD-9: one choice, once, no runtime switch |
| Holding "what is bound right now" | Infrastructure (adapter), read through the port | Application (`SettingsController`) | HOTKEY-06: the adapter is the only thing that knows; the port is how the app asks |
| Classifying *why* the hotkey is unavailable | Domain (`HotkeyBindOutcome`) | Infrastructure (each adapter picks the cause) | HOTKEY-08: a consumer must switch on a type, not parse a string |
| Rendering the three messages + tray line | UI (`hotkey_status_view.dart`) | Application (`SettingsState`) | AD-12: the screen renders `message` verbatim and claims nothing of its own |
| Capturing a key combination from the user | UI (`ui/settings/`) | Application (`SettingsController` supplies the vocabulary) | D-14; DW-71's ratified answer is "expose the catalogue *through* the controller", not reach across AD-1's rings |
| Validating a captured combination | Application (predicate) over an Infrastructure-sourced vocabulary | UI (renders the refusal) | D-15; AD-1 forbids `ui` importing `HotkeyKeyCatalogue` |
| Bounding a portal call | Infrastructure (adapter) | — | D-17; reuse the `_answered(...).timeout(budget, onTimeout:)` idiom, do not invent a second |
| Deciding the packaging format | *Human*, recorded in `deferred-work.md` + `ARCHITECTURE-SPINE.md` | — | ARCH-02; it constrains code but is not itself code |

---

## Standard Stack

No new third-party runtime dependency is required by the recommended route. This is a *removal*
phase for the dependency graph.

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `dart:ffi` | Dart 3.12.2 (SDK) | Call `XGrabKey`/`XNextEvent`/`XSetErrorHandler` against `libX11.so.6` | Core VM library; no package, no plugin, no `DT_NEEDED` entry, resolvable under `dart test` [VERIFIED: `dart --version` → Dart 3.12.2 via Flutter 3.44.8] |
| `dart:isolate` | Dart 3.12.2 (SDK) | Own the X event loop on a real OS thread without blocking the UI isolate | Core library; keeps the blocking `XNextEvent`/poll off the Flutter isolate |
| `ffi` | 2.2.0 | `malloc`/`calloc`/`Utf8` helpers for `XStringToKeysym(const char*)` | Already in `pubspec.lock` as transitive at exactly this version [VERIFIED: `pubspec.lock:220-227`]; promoting it moves no other pin. **Optional** — `dart:ffi` alone can do it with a manually-allocated `Pointer<Uint8>` |
| `dbus` | 0.7.14 | Existing GlobalShortcuts portal transport | Unchanged; already pinned [VERIFIED: `pubspec.yaml:34`] |

### Removed

| Package | Version | Why removed |
|---------|---------|-------------|
| `hotkey_manager` | 0.2.3 | D-12. Removing the direct dependency is the *only* way the plugin stops being linked into the runner (C6). Takes `hotkey_manager_linux`, `hotkey_manager_macos`, `hotkey_manager_platform_interface` and `hotkey_manager_windows` out of `pubspec.lock` with it [VERIFIED: `pubspec.lock:302-341`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `dart:ffi` → `libX11.so.6` (**recommended**) | `dart:ffi` → `libkeybinder-3.0.so.0` (`DW-39`'s proposal) | Keybinder is a thin wrapper over the same `XGrabKey`, but calls GDK and installs a GDK event filter, so `keybinder_init`/`keybinder_bind` must run on the **GTK main thread** — a thread Dart may or may not be on (§ *Open Question 1*). Adds a runtime dependency the X11 route does not need. Its one advantage: `gtk_accelerator_parse` handles virtual modifiers (`<Super>`) for you, which the X11 route must do itself. |
| `dart:ffi` from the app isolate | A first-party FFI plugin package (C shim under `linux/`) | An FFI plugin is *not* link-time linked (C6), so it also closes D-11, and C code can call GTK on the right thread trivially. But it adds a build-system surface, a second language, and a package boundary — for a problem the X11 route does not have. |
| A dedicated Dart isolate for the X event loop | A `Timer.periodic` on the main isolate calling `XPending`/`XNextEvent` | Simpler, and works — `XPending` is non-blocking. But it puts FFI calls on Flutter's isolate at a fixed cadence, and AD-8 keeps the panel show path allocation-free. The isolate keeps the polling entirely off it. Recommend the isolate; the timer is an acceptable fallback if isolate lifecycle proves awkward under `dispose()`. |
| A runtime sandbox predicate | A `--dart-define` build-time constant per packaging target | D-18 says "no primary build, none second-class", which argues for **one** binary that behaves correctly in all three. A runtime predicate keyed on `/.flatpak-info` gives that; a build define gives three binaries that can each be built wrong. |

**Installation:**

```bash
# pubspec.yaml: delete the `hotkey_manager: 0.2.3` line (currently line 37),
# and (optionally) add the already-resolved ffi pin under `dependencies:`
#   ffi: 2.2.0
flutter pub get          # regenerates pubspec.lock and linux/flutter/generated_plugins.cmake
```

**Version verification, run 2026-09-01:**

```bash
$ grep -n -A5 '^  ffi:' pubspec.lock          # ffi 2.2.0, transitive, pub.dev
$ grep -n 'hotkey_manager' pubspec.yaml       # line 37
$ dart --version                              # Dart 3.12.2 (via Flutter 3.44.8, stable)
```

---

## Package Legitimacy Audit

This phase adds **no** package sourced from a search result or from training memory. The one
candidate promotion is already in the resolved dependency graph.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `ffi` 2.2.0 | pub.dev | Long-established Dart-team package | n/a (pub does not publish weekly counts here) | `github.com/dart-lang/native` (Dart team) | OK | Approved — already present as `dependency: transitive` in `pubspec.lock:220-227`, promoting only changes the `dependency:` field |
| `hotkey_manager` 0.2.3 | pub.dev | shipped, pinned | n/a | `github.com/leanflutter/hotkey_manager` | n/a | **REMOVED** by D-12 |
| `dart:ffi`, `dart:isolate` | Dart SDK core | n/a | n/a | dart-lang/sdk | OK | Not packages; no registry surface |

**Packages removed due to [SLOP] verdict:** none — no package in this phase was discovered by search.
**Packages flagged as suspicious [SUS]:** none.

> The `gsd-tools query package-legitimacy check` seam supports `npm|pypi|crates` only and rejects
> `pub`, so the automated verdict could not be obtained. [VERIFIED: seam returned
> `Usage: gsd-tools package-legitimacy check --ecosystem <npm|pypi|crates>`.] The audit above rests
> on the resolved `pubspec.lock` entry, which is stronger evidence than a registry existence check:
> the package is already in this build's dependency graph with a recorded sha256.

---

## Architecture Patterns

### System Architecture Diagram

```text
                        ┌──────────────────────────────────────┐
   key press ──────────▶│  X server (passive grab on root)     │
   (X11 session)        └──────────────┬───────────────────────┘
                                       │ KeyPress on our own Display
                                       ▼
   ┌───────────────────────────────────────────────────────────────┐
   │ helper Dart isolate (own OS thread, own libX11 Display)        │
   │   XOpenDisplay → XKeysymToKeycode → XGrabKey(×4 lock masks)    │
   │   XSetErrorHandler + XSync  ──▶ BadAccess? = REFUSED           │
   │   loop: XPending → XNextEvent → { KeyPress, MappingNotify }    │
   └──────────────┬──────────────────────────────▲─────────────────┘
       SendPort   │ press events                 │ grab / release commands
                  ▼                              │
   ┌───────────────────────────────────────────────────────────────┐
   │ HotkeyRegistrar (infrastructure-private seam)                 │
   │   grab(HotkeyGrab) → Future  ·  release() → Future             │
   │   presses → Stream<void>                                      │
   └──────────────┬────────────────────────────────────────────────┘
                  ▼
   ┌───────────────────────────────────────────────────────────────┐
   │ GlobalHotkey  (domain port — AD-9)                            │
   │   activations · bindingChanges · bind() · [NEW] current       │
   └───┬───────────────────────────────────────┬───────────────────┘
       │ X11GlobalHotkey                       │ WaylandPortalGlobalHotkey
       │                                       │
       │                        ┌──────────────┴───────────────────────┐
       │                        │ 0. sandboxed?  ──yes──▶ SKIP step 1  │
       │                        │ 1. Registry.Register(app_id)         │
   (nothing else can            │ 2. CreateSession  → Response         │
    change an X11 grab)         │ 3. BindShortcuts  → Response         │
       │                        │    read back `shortcuts` subset      │
       │                        │    keep `trigger_description`        │
       │                        │ 4. subscribe Activated /             │
       │                        │              ShortcutsChanged        │
       │                        │ (opt) ListShortcuts → refresh        │
       │                        └──────────────┬───────────────────────┘
       ▼                                       ▼
   ┌───────────────────────────────────────────────────────────────┐
   │ SettingsController (application) — owns precedence (HOTKEY-07) │
   │   applyStartupOutcome · changeHotkey · _onBindingChanged      │
   └──────────────┬────────────────────────────┬───────────────────┘
                  ▼                            ▼
        hotkey_status_view.dart      TrayPort.setHotkeyUnavailable
        (three messages + tray line)      (Phase 2 fans this out)
```

### Component Responsibilities

| Component | Responsibility | File |
|---|---|---|
| `X11KeyGrabRegistrar` (new) | Owns the helper isolate, the private `Display`, the grab set, and the press stream | `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` (new) |
| `_XlibBindings` (new, private) | `DynamicLibrary.open` + typedefs; nothing else in `lib/` names a `Pointer` | same file, private |
| `HotkeyRegistrar` | Unchanged seam interface; its doc's two "properties of the backend" must be rewritten | `hotkey_registrar.dart:42-79` |
| `X11GlobalHotkey` | Unchanged in shape; the `HotkeyUnavailable` construction sites gain a cause (HOTKEY-08) | `x11_global_hotkey.dart` (370 lines) |
| `HotkeyKeyCatalogue` | Label ⇄ USB HID usage; gains the reverse lookup D-14's capture needs; `labelsThatBindTheWrongKey` empties (C3) | `hotkey_key_catalogue.dart` (222 lines) |
| `XdgShortcutTrigger` | Label → keysym name. **Now used by both adapters** — the X11 registrar needs exactly this vocabulary | `xdg_shortcut_trigger.dart` (202 lines) |
| `WaylandPortalGlobalHotkey` | Handshake + signals; gains sandbox predicate, description carrier, bounded bind | `wayland_portal_global_hotkey.dart` (1307 lines) |
| `DisplayServer` | Unchanged; the shape to copy for the sandbox predicate | `display_server.dart` (37 lines) |
| `HotkeyPreferenceField` → capture control | Replaced by D-14 | `lib/src/ui/settings/hotkey_preference_field.dart` (260 lines) |
| `HotkeyStatusView` | Renders D-06's three messages + D-07's tray line; **also SETTINGS-09's subject in Phase 2** | `lib/src/ui/settings/hotkey_status_view.dart` (178 lines) |
| **deleted** | `HotkeyManagerRegistrar` + its 608-line platform suite | `hotkey_manager_registrar.dart` (242 lines), `test/platform/hotkey_manager_registrar_test.dart` |

---

### Pattern 1: The X11 grab replacement — private Display in a helper isolate

**What:** Open a second X connection that this app owns, install a synchronous error trap around
each `XGrabKey`, and read key presses off that connection from a dedicated Dart isolate.

**When to use:** This is the recommendation for HOTKEY-01/HOTKEY-02. It satisfies both constraints
CONTEXT.md names, and a third it does not:

- **Constraint A — no Flutter import.** `dart:ffi` and `dart:isolate` are VM core libraries.
  `daemon_startup_test.dart` runs under `dart test` and resolves them without a binding.
  [VERIFIED: the CI-scoped `dart test` run loads `test/infrastructure/**` today; `dart:ffi` is not
  in `hotkey_confinement_test.dart`'s Flutter-reference list (`package:flutter/`,
  `package:flutter_test/`, `package:flutter_riverpod/`, `dart:ui`).]
- **Constraint B — a real GTK/GLib main loop.** **This route does not need one.** Xlib on a
  `Display` you opened yourself is not GDK's `Display` and shares none of its state. Passive grabs
  are per-connection and X delivers the resulting `KeyPress` to the grabbing connection. This is
  how `xbindkeys`, `sxhkd` and `i3` work. It sidesteps § *Open Question 1* entirely.
- **A third constraint, unstated:** it must not add a dependency the packaging story has to carry.
  It does not — `libX11.so.6` is already a hard `DT_NEEDED` of `libgdk-3.so.0` (C7).

**Proven in this container against a live `Xvfb :77`, 2026-09-01:**

```text
--- grab Ctrl+Shift+G on connection 1 ---
  errors after XSync: []                 -> grab HELD
--- same grab on connection 2 (another client) ---
  errors after XSync: [(10, 33)]         -> grab REFUSED     # 10 = BadAccess, 33 = X_GrabKey
--- lock-mask variants on connection 2 (Lock, Mod2, Lock|Mod2) ---
  errors: []                                                 # separate grabs, no conflict
--- release on connection 1, then retry on connection 2 ---
  errors after XSync: []                 -> grab HELD
--- ungrab a grab that was never held ---
  errors: []                                                 # release is idempotent

--- key press delivery (XTEST synthesises Ctrl+Shift+G) ---
  pending events on grabbing client: 3
  event=34         keycode=772 state=0x40181 window=0x0      # MappingNotify
  event=KeyPress   keycode=42  state=0x0005  window=0x21f    # Shift|Control
  event=KeyRelease keycode=42  state=0x0005  window=0x21f
```

Four requirement-level facts fall straight out of that run:

1. **A refused grab is synchronously observable.** `XSetErrorHandler` + `XSync(dpy, False)` runs
   the handler *before* `XSync` returns. That is HOTKEY-01's whole content, and it is stronger than
   the ledger's proposal — `keybinder_bind`'s `gboolean` is one bit, whereas `BadAccess` names the
   condition. [VERIFIED: measurement above; corroborated by
   [CITED: x.org XGrabKey(3) — "If some other client has issued a XGrabKey with the same key
   combination on the same window, a BadAccess error results."]]
2. **The grab really delivers presses.** A second connection with no window of its own receives
   `KeyPress` on the root window with the right keycode and modifier state.
3. **Lock masks are separate grabs and must all be issued.** X matches modifier state exactly, so
   `Ctrl+Shift+G` will not fire while NumLock or CapsLock is on unless the extra masks are also
   grabbed. [VERIFIED: measurement; the four-variant convention is
   [CITED: tauri-apps/tao `IGNORED_MODS` = `{0, Mod2Mask, LockMask, Mod2Mask|LockMask}`] and
   [CITED: xbindkeys `grab_key.c`]]
4. **`MappingNotify` (type 34) really arrives** when the keyboard mapping changes. Keycodes are not
   stable across layout changes, so the registrar must `XRefreshKeyboardMapping` and re-grab.

**Skeleton** (illustrative; names are the planner's to fix):

```dart
// lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart
// No Flutter import: dart:ffi and dart:isolate are core libraries, and
// test/infrastructure/system/daemon_startup_test.dart runs under `dart test`.
import 'dart:ffi';
import 'dart:isolate';

// The four modifier states X must be told about separately: X matches state
// exactly, so a bare grab does not fire while NumLock or CapsLock is latched.
// Measured: the four are independent grabs and do not conflict with each other.
const int _lockMask = 1 << 1;   // CapsLock
const int _mod2Mask = 1 << 4;   // NumLock, by the near-universal convention
const List<int> _ignoredModifierStates = <int>[
  0, _lockMask, _mod2Mask, _lockMask | _mod2Mask,
];

const int _badAccess = 10;      // X.h
const int _xGrabKeyRequest = 33;
```

The grab step, in the helper isolate, in the order that makes the failure readable:

```
1. install XSetErrorHandler(trap)          // trap records (error_code, request_code)
2. trap.clear()
3. for state in _ignoredModifierStates:
       XGrabKey(dpy, keycode, mods | state, root, ownerEvents: true,
                GrabModeAsync, GrabModeAsync)
4. XSync(dpy, discard: false)              // the trap has fired by the time this returns
5. if trap saw BadAccess for the BASE state  -> refuse: another client owns it
   if trap saw BadAccess only for a lock variant -> keep the grab, log the degradation
6. on refusal: XUngrabKey every state we did get, so nothing is left half-held
```

**Anti-pattern this replaces:** `HotkeyManagerRegistrar.grab` resolving its `Future` and
`X11GlobalHotkey` turning that into `HotkeyBound(effective: requested)` — a claim the backend never
made. [VERIFIED: `hotkey_manager_linux_plugin.cc:96` calls
`keybinder_bind(keystring, handle_key_down, NULL);` with the `gboolean` discarded, and `:98-99`
returns `fl_method_success_response_new(fl_value_new_bool(true))` unconditionally. CONTEXT.md's
citation of `:95-99` is confirmed.]

**What the replacement owes the seam contract.** `HotkeyRegistrar`'s doc currently states two
"properties of the backend that callers must not re-derive" (`hotkey_registrar.dart:26-41`) — the
native keystring construction, and the indistinguishable refusal. **Both become false.** Rewrite
that doc rather than deleting it; the second property inverts (a refusal is now readable), and the
first becomes "the keysym name is computed in Dart by `XdgShortcutTrigger.keysymNameFor`, which is
what AD-9 always described". Also delete the *precondition* paragraph at `:57-65` about
`labelsThatBindTheWrongKey` — per C3 there is nothing left to precondition.

### Pattern 2: Reporting "library absent" as a value at first use (D-11)

`DynamicLibrary.open` throws `ArgumentError` when the soname cannot be resolved. The registrar
catches it at *first grab*, not at construction:

```dart
// Construction stays inert — main.dart builds this before it knows the display
// server, exactly as HotkeyManagerRegistrar was built inert today (main.dart:65).
// Nothing is dlopened, no isolate is spawned, no X connection is made until the
// first grab() is requested, so a Wayland session pays nothing for the arm it
// did not take.
```

The chain of values the adapter must produce, all `HotkeyUnavailable` with distinct causes:

| Condition | Where detected | Cause (HOTKEY-08) |
|---|---|---|
| `libX11.so.6` unresolvable | `DynamicLibrary.open` throws at first grab | `noBackend` — cannot happen on any host that starts the app (C7), but must still be a value |
| `XOpenDisplay(NULL)` returns `nullptr` | first grab | `noBackend` |
| keysym name unknown / key not in catalogue | before any FFI call | `keyRefused` |
| `XKeysymToKeycode` returns 0 | before `XGrabKey` | `keyRefused` |
| `BadAccess` on the base modifier state | after `XSync` | `keyRefused` |
| adapter disposed mid-grab | existing `_disposed` guards | existing "shut down during bind" wording |

**What `daemon_startup.dart` needs for a degraded-but-running daemon: nothing.** The path already
exists and already works. `DaemonStartup.bindHotkey` (`:170-190`) awaits `requestBinding`, logs a
warning on `HotkeyUnavailable`, tells the tray via `setHotkeyUnavailable(true)` inside a guard, and
returns — startup continues. `requestBinding` (`:208-228`) even absorbs an adapter that *throws*.
The reason D-11 fails today is purely that the process never reaches `main()`. [VERIFIED:
`lib/src/infrastructure/system/daemon_startup.dart:170-228`]

**The one composition change D-12 forces:** `main.dart:65` builds `HotkeyManagerRegistrar()` and
threads it into `DaemonStartup.begin(registrar: ...)`, and `DaemonLifecycle._closeHotkeyRegistrar`
closes it separately from the adapter (`daemon_lifecycle.dart:55-64`). Substituting the new type
is a one-word change at each site — but `composition_wiring_test.dart:864` asserts the *literal*
`'final hotkeyRegistrar = HotkeyManagerRegistrar();'`, so that row's expected string moves with it
(C9).

### Pattern 3: The sandbox-safe portal handshake (D-18, ARCH-02)

**The rule, from the spec, verbatim:** *"This interface will not work with applications
xdg-desktop-portal identifies as sandboxed."*
[CITED: flatpak.github.io/xdg-desktop-portal — `org.freedesktop.host.portal.Registry`]

That is stronger than AD-11's own framing. It is not merely *wrong* for a Flatpak to call
`Register`; the interface will not work, so the call is dead weight at best and an error line on
every launch at worst. Other facts from the same page:

- Signature: `Register (IN app_id s, IN options a{sv})`, interface version 1.
- "The app ID must match a `.desktop` file basename."
- "Registration can occur only once per connection."
- "Registration must happen before any portal method calls."
- **"Applications should listen for `NameOwnerChanged` signals to re-register after portal service restarts."**

The last one is a defect in the shipped adapter that nothing in the ledger records: `_registered`
is latched `true` once the bus answers and is **never reset** (`wayland_portal_global_hotkey.dart:173`,
set at `:454`). After an `xdg-desktop-portal` restart — which the adapter's own `_portalSender` doc
calls "routine on a session update" — the app id association is gone and every later `BindShortcuts`
is liable to the documented GNOME discard. See § *Open Question 4*.

**The sandbox predicate, and why the adapter's stated objection is answerable.** The adapter
currently refuses to detect the sandbox with this reasoning:

> "no sandbox detector exists here because the signals one would key off include `/.dockerenv`,
> which is true in this project's own container, so a detector would take the sandboxed branch in
> every test run"
> [VERIFIED: `wayland_portal_global_hotkey.dart:364-371`]

`/.dockerenv` is the wrong signal. Measured in this container, 2026-09-01:

```
/.dockerenv            EXISTS
/.flatpak-info         absent
/run/.containerenv     absent
FLATPAK_ID=<unset>  SNAP=<unset>  container=<unset>
```

`/.flatpak-info` is written by the Flatpak runtime inside the sandbox and by nothing else; `$FLATPAK_ID`
is exported by `flatpak run`. A predicate over those two does **not** fire here, which is exactly the
property the adapter's objection asked for. Shape it like `DisplayServer.fromEnvironment` — a pure
function over an injected environment map plus an injected file-existence probe — so a binding-free
test can drive both branches without a sandbox.

**The revised AD-11 sequence** (step 0 is new; steps 1–4 are unchanged in order):

```
0. sandboxed?  → the portal derives the app id from sandbox metadata; SKIP step 1 entirely
1. org.freedesktop.host.portal.Registry.Register(app_id)      [unsandboxed only]
2. GlobalShortcuts.CreateSession  → await Response on the Request path
3. GlobalShortcuts.BindShortcuts  → await Response; CHECK the `shortcuts` read-back
4. subscribe Activated + ShortcutsChanged, filtered on session handle and sender
```

**The read-back is not optional and the code already gets this right** (`:532-546`): a portal that
discards the bind answers *successfully* with the shortcut missing from the subset. The spec's own
wording is that the returned list is "a subset of the shortcuts which were passed in … (this
includes the set of all shortcuts and the empty set)".

**`ListShortcuts` is the read-back this phase should adopt for HOTKEY-03/D-01.** It exists, returns
the same `shortcuts a(sa{sv})` on its Response, and the adapter has never called it.
[CITED: `ListShortcuts (IN session_handle o, IN options a{sv}, OUT request_handle o)`;
Response carries `shortcuts` `a(sa{sv})`.] Use it as the on-demand refresh behind a synchronous
cached accessor: cache the last known `trigger_description` from `BindShortcuts`' Response and from
every `ShortcutsChanged`, and offer `ListShortcuts` as the explicit "re-read from the compositor"
path. **Do not** make the synchronous accessor perform a round trip — HOTKEY-06 asks for a
synchronous read precisely because a late-mounting settings screen must not await one.

### Pattern 4: `trigger_description` — D-04's read-back, and what it is not

The exact documented meaning, quoted: **"User-readable text describing how to trigger the shortcut
for the client to render."** [CITED: flatpak.github.io/xdg-desktop-portal —
`org.freedesktop.portal.GlobalShortcuts`]

Where it can appear, from the same page:

| Direction | Keys in each shortcut's `a{sv}` |
|---|---|
| Request (`BindShortcuts` input) | `description` (`s`), `preferred_trigger` (`s`, optional) |
| Response (`BindShortcuts`, `ListShortcuts`) | `description` (`s`), `trigger_description` (`s`) |
| `ShortcutsChanged` signal | same as Response |

**There is no machine-readable combination in any of them.** [CITED: same page — the response
property list contains `description` and `trigger_description` and nothing else.] D-04 and D-05 are
correct, and HOTKEY-03's amendment is a faithful reading of the protocol rather than a concession.

`preferred_trigger`'s syntax is defined by the freedesktop shortcuts specification, which
`XdgShortcutTrigger` already implements and which was measured against xkbcommon 1.6.0 when it was
written. Nothing in this phase needs to change it.

**Consequence for the port:** the localized text has to reach the `ui` ring, and today it goes only
to a log line (`_logTriggerDescription`, `:1120-1141`). See § *AD-9 Declaration Edits*, edit **C**.

**Consequence for the widget:** `hotkey_status_view.dart` currently renders
`_regimeWithoutCombination(...)` — *"This backend cannot report the combination in effect"* — for
every Wayland bind. D-03 drops the regime label and D-04 supplies the text, so both
`_regimeOf` and `_regimeWithoutCombination` (`:150-177`) are rewritten, and the `differs from your
preference` line (`:144-146`) has no counterpart on Wayland because there is nothing comparable.
**Coordinate with Phase 2**: SETTINGS-09 (FLAT-16) also edits this file's doc comment. Phase 1
should do the doc fix in passing and Phase 2 should verify rather than re-edit, or the two phases
collide.

### Anti-Patterns to Avoid

- **Parsing `trigger_description` back into a `HotkeyBinding`.** It is localized and
  backend-specific. The adapter's own doc calls this "a prediction of vendor and locale behaviour
  that fails silently". D-05 forbids it. So does AGENTS.md §1.
- **Calling `Registry.Register` unconditionally once Flatpak is in the set.** It "will not work"
  inside a sandbox (spec), and D-18 puts Flatpak in the set.
- **Detecting a sandbox with `/.dockerenv` or `$container`.** Fires in this project's own devcontainer.
- **`dlopen`ing keybinder while leaving `hotkey_manager` in `pubspec.yaml`.** The plugin's `.so` is
  in the runner's own `DT_NEEDED`; the loader resolves the chain before `main()`. D-12 exists
  because this half-measure does not work.
- **Grabbing only the base modifier state.** The hotkey silently stops working with NumLock on.
- **Blocking `XNextEvent` on the Flutter isolate.** Freezes the UI. Use the helper isolate, or
  `XPending`-gated polling.
- **A timeout on the bind path that cancels a portal dialog the user is reading.** See § *Pitfall 4*.
- **Letting an FFI `Pointer` or a keysym `int` cross `HotkeyRegistrar`.** `HotkeyGrab` is the
  crossing type and it carries only domain modifiers and a USB HID usage.
- **Reporting `HotkeyUnavailable` while a previous combination is still genuinely held.** AD-12's
  "half that is easy to get wrong". `X11GlobalHotkey._refusedBeforeBackend` (`:239-260`) is the
  worked example; every new refusal path must go through the same shape.

---

## AD-9 Declaration Edits

AD-9's rule, quoted: *"the declared fields and constructors above are the fixed part."*
[VERIFIED: `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md:296`]
The block it governs runs from line 235 to line 300.

**The precedent, stated concretely enough to become a task.** `global_hotkey.dart`'s
`bindingChanges` doc records how a member was added before:

> "Adding this member is an addition to AD-9's verbatim declaration that leaves every declared
> *field* of [HotkeyRegistration] untouched — the same class of change as the value equality above,
> recorded in the deferred-work ledger and the story's Spec Change Log rather than hand-edited into
> the spine."
> [VERIFIED: `lib/src/domain/hotkey/global_hotkey.dart:50-54`]

Concretely, that mechanism is three artefacts:

1. **The code carries the justification in its own doc comment**, naming the class of change and
   why it leaves declared fields untouched (the pattern at `global_hotkey.dart:50-54` and
   `hotkey_binding.dart:61-65`).
2. **A ledger entry records it**, appended in the file's own format, `status: open` until closed.
3. **The story's `## Spec Change Log`** records it for the spine to absorb later — in this
   workflow, the equivalent home is the phase's own artefacts plus a ledger entry that Phase 7
   (ARCH cluster) picks up when it reconciles the spine.

**What that precedent does *not* cover** is an edit to a *declared field list* or to a *declared
constructor*. Those need fresh ratification.

| # | Edit | AD-9 line | Class | Gate |
|---|---|---|---|---|
| **A** | `GlobalHotkey` gains a synchronous current-registration member beside `bindingChanges` (HOTKEY-06) | member list at `:283-299`; the port block `:281-300` | **Addition** — no declared field or constructor changes | Precedent applies. Roadmap criterion 1(a) asks the human to ratify anyway. |
| **B** | `HotkeyUnavailable` gains a machine-readable cause (HOTKEY-08, D-06) | `:274-278` — `const HotkeyUnavailable({required this.message}); final String message;` | **Declared field list** | **Fresh human ratification required.** |
| **C** | Somewhere for the compositor's localized description to reach the `ui` ring (HOTKEY-03, D-04) | `HotkeyRegistration` at `:248-254` declares exactly `effective` and `authority`; `HotkeyBound` at `:267-270` declares exactly `registration` | **Declared field list** *if* done as a third field; **Addition** if carried on the new member from **A** | Choosing the additive shape collapses this into **A**. |
| **D** | `HotkeyBinding`'s declared `const` constructor loses `const` (HOTKEY-09) | `:239-243` — `const HotkeyBinding({required this.modifiers, required this.key});` | **Declared constructor** | **Fresh human ratification required.** |

### The recommendation that minimises the gate surface

Fold **C** into **A** by adding *one* new member returning a *new* type, rather than a third field
on a declared one:

```dart
// domain/hotkey/hotkey_status.dart — a NEW type, so no declared field of
// HotkeyRegistration, HotkeyBound or HotkeyUnavailable is touched.
final class HotkeyStatus {
  const HotkeyStatus({required this.outcome, required this.backendDescription});

  /// The last outcome this backend produced, from bind() or from a
  /// backend-originated change — whichever is newer (HOTKEY-07).
  final HotkeyBindOutcome outcome;

  /// The backend's own user-readable text for what is in effect, verbatim and
  /// never parsed — the portal's `trigger_description` on Wayland, null on X11
  /// where the app owns the combination and can render it itself (D-04).
  final String? backendDescription;
  // == / hashCode over exactly these two fields, per AD-9's collection rule.
}

// domain/hotkey/global_hotkey.dart, added beside bindingChanges:
/// What is in effect right now, read synchronously.
///
/// AD-8 already pairs a synchronous `bool get isVisible` with `Stream<bool> get
/// changes` for exactly this reason: a tray daemon spends almost all its life
/// with no settings screen mounted, so a broadcast stream with no replay drops
/// every compositor rebind that happens while the screen is closed (FLAT-02).
/// Null until anything has been asked of a backend.
HotkeyStatus? get current;
```

This single addition closes **A** and **C**, gives D-01 its "shortcut currently in effect" without
a round trip, and leaves every declared field and constructor in AD-9's block untouched — squarely
inside the recorded precedent.

**The two edits that still need a human**, with the exact text to ratify:

> **Decision 1 (HOTKEY-08 / D-06).** `HotkeyUnavailable` gains a second declared field naming the
> cause — `noBackend`, `keyRefused`, `revoked` — so a consumer can tell them apart without parsing
> `message`. This edits AD-9's verbatim field list at spine line 274-278. `message` is retained
> unchanged, so AD-12's "render the message verbatim and append exactly one line" rule and all 20
> existing construction sites' wording survive. **Cost:** every `HotkeyUnavailable(` site must name
> a cause. **20 sites in `lib/`** — `x11_global_hotkey.dart` (5), `wayland_portal_global_hotkey.dart`
> (13), `settings_controller.dart` (1), `daemon_startup.dart` (1). *[The 20-site count is quoted
> from `FLAT-04`'s sibling entry at ledger line 1500, which states `grep -rn 'HotkeyUnavailable(' lib/`
> returns 20 across exactly those files — not independently re-counted this session.]*
> **Alternative rejected:** converting `HotkeyUnavailable` from `final class` to `sealed class` with
> three subtypes. It leaves the *field* list untouched but makes the type non-instantiable, so every
> one of the 20 sites plus every test naming the type changes, and every exhaustive switch over
> `HotkeyBindOutcome` must be re-examined. Strictly more churn for the same expressiveness.
> **No default value on the new field** — a default would silently label 20 existing sites with a
> cause nobody chose, which is the class of silent-wrongness this codebase files ledger entries about.

> **Decision 2 (HOTKEY-09 / FLAT-05).** `HotkeyBinding`'s declared constructor drops `const` and
> copies its `modifiers` set defensively, mirroring `HotkeyGrab`, whose own doc says: *"Copied on
> construction rather than held by reference… The constructor is therefore not `const`, which is the
> price."* [VERIFIED: `hotkey_grab.dart:18-27`] This edits AD-9's verbatim constructor at spine line
> 239-243. **Cost measured:** exactly **one** `const HotkeyBinding(` site in `lib/`
> (`default_app_config.dart:142`, and the enclosing `AppConfig` is not itself `const`, so the edit is
> local) and **24** in `test/`. All 25 are mechanical `const` removals.
> **Alternative:** leave the constructor `const` and document that callers must not retain the set —
> which is what `FLAT-05` itself lists as the other option. **Honest note the human should have:**
> no live defect exists today. Every in-`lib/` construction passes a fresh set literal
> (`hotkey_preference_field.dart:138` builds `{..._modifiers}`), and a `const` set literal is
> genuinely immutable at runtime. This is API hardening against a future caller, not a bug fix.

**Ledger + Spec Change Log obligations for all four**, per the precedent: append a note recording
each change and its class, and hand the spine reconciliation to Phase 7's ARCH cluster. Do **not**
hand-edit `ARCHITECTURE-SPINE.md` in Phase 1 — the precedent explicitly says these are "recorded in
the deferred-work ledger and the story's Spec Change Log rather than hand-edited into the spine."

---

## HOTKEY-07: the precedence rule, and the gap it exposes

**The protocol fact the rule must rest on:** the GlobalShortcuts documentation specifies no
ordering between the `BindShortcuts` Response and `ShortcutsChanged`.
[CITED: flatpak.github.io/xdg-desktop-portal — the page describes `ShortcutsChanged` only as
"Indicates that the information associated with some of the shortcuts has changed" and states no
ordering constraint.] So `FLAT-03` is right that both orderings are spec-legal.

**What the shipped adapter makes reachable today.** `_listenForShortcutSignals` is called *after*
`_bindShortcut` returns successfully (`wayland_portal_global_hotkey.dart:319-321`), so on this
adapter a `ShortcutsChanged` cannot be observed before the `BindShortcuts` Response — the
subscription does not exist yet. The inversion is therefore *possible in the protocol* and
*unreachable in this implementation*. Say so; do not claim a defect that cannot occur here.

**What the application ring actually implements — two contradictory rules:**

| Path | Rule | Evidence |
|---|---|---|
| Startup | **Newest wins.** `applyStartupOutcome` refuses to overwrite an outcome that is already set, precisely because a compositor change can land first. | `settings_controller.dart:294-312`, whose doc says "A **seed**, not an assignment… Overwriting unconditionally would replace that newer fact with an older one" |
| Backend-originated change | **Last writer wins.** `_onBindingChanged` overwrites unconditionally. | `settings_controller.dart:324-332` |
| User rebind | **`bind()` wins, unconditionally.** `changeHotkey` sets `hotkeyBindOutcome: outcome` from the bind result with no check for a newer event. | `settings_controller.dart:142-172` |

So a `ShortcutsChanged` that arrives *while* a user-initiated `bind()` is in flight — a portal
dialog makes that window seconds wide by design — is silently overwritten by the bind's own answer.
That is the same defect `applyStartupOutcome` was written to prevent, on the path that is easier to
reach.

**The rule to state (Claude's discretion per CONTEXT.md):**

> `bind()`'s returned outcome is authoritative **only for the transition it caused, and only until a
> backend-originated change is observed.** A `bindingChanges` event observed at any time after a
> `bind()` was issued supersedes that `bind()`'s return value, whichever resolves first in wall-clock
> order. Concretely: a consumer records a generation number when it issues a `bind()`, and discards
> the bind's outcome if a `bindingChanges` event arrived after that number was taken.
>
> Rationale: on Wayland the compositor is the authority (AD-10) and D-01 requires the app to show
> what is *currently* in effect. A stale `bind()` answer is by construction older than any event the
> backend originated afterwards.

**The concrete gap this creates for the plan:** `changeHotkey` needs the same "do not overwrite a
newer fact" guard `applyStartupOutcome` already has. `SettingsController` has `_beginMutation`
(`:123`, `:200+`) and could latch a flag when `_onBindingChanged` fires during a mutation. Note
that **SETTINGS-02 (DW-68) in Phase 2 is adjacent** — it closes the `changeHotkey`
bind-before-write divergence. Coordinate: HOTKEY-07 states the rule and fixes the precedence;
SETTINGS-02 fixes the config-write ordering. Two edits to one method across two phases is a
collision risk the planner should surface.

---

## HOTKEY-04 after the replacement

Per C3, the seven labels are no longer a problem. So what does D-15's "reject at capture" reject?

**What the validator still has to catch, all of it real:**

| Rejected | Why | Detectable where |
|---|---|---|
| No modifier at all | **D-13**, unconditionally | Pure predicate on the captured set |
| A modifier-only press (`Ctrl` alone, `Shift`+`Ctrl`) | There is no key to grab | The captured `physicalKey` is itself a modifier key |
| A key outside `HotkeyKeyCatalogue` | `X11GlobalHotkey._bind` refuses it before the backend (`:115-124`); `XdgShortcutTrigger` cannot express it either | `HotkeyKeyCatalogue.usbHidUsageFor(label) == null` |
| A combination using AltGr / `ISO_Level3_Shift` | `HotkeyModifier` has only `{control, alt, shift, meta}` — there is no value for Level 3, so the combination cannot be represented at all | The capture sees `LogicalKeyboardKey.altGraph` / `PhysicalKeyboardKey.altRight` with no matching `HotkeyModifier` |
| A combination whose `preferred_trigger` cannot be built | Would silently bind something else on Wayland (`XdgShortcutTrigger.forBinding` returns null and the adapter omits the hint) | `XdgShortcutTrigger.keysymNameFor(label) == null` |

**The vocabulary route DW-71 already ratified:** *"Expose the catalogue through a port — engineering
call, taking the non-destructive option. The ui ring gets a sanctioned way to read which labels this
build can register — **supplied by `SettingsController`** rather than reached for across AD-1's
rings — validated before Apply."*
[VERIFIED: `deferred-work.md:1182`]

That is a recorded decision and the planner should follow it rather than re-litigate: the catalogue
is injected into `SettingsController` (or exposed as a value on `SettingsState`), and the capture
widget validates against what the controller gives it. `hotkey_confinement_test.dart`'s two
`offeredKeyExamples` rows exist precisely because `ui` cannot import the catalogue; once the
vocabulary is supplied properly those rows change subject (C9).

### D-14's capture control: what Flutter can and cannot see

**The good news, and it is better than CONTEXT.md assumes.** Flutter's `KeyEvent.physicalKey` is a
`PhysicalKeyboardKey` whose `usbHidUsage` is *exactly* the integer `HotkeyKeyCatalogue` is keyed on
and that `HotkeyGrab` carries. [CITED: api.flutter.dev — `PhysicalKeyboardKey` "represents the
physical location of this key"; the tree's own `HotkeyManagerRegistrar._hotKeyFor` already does
`PhysicalKeyboardKey.findKeyByCode(grab.usbHidUsage)`.] So a capture control reads
`event.physicalKey.usbHidUsage` and looks it up directly — no label guessing, no layout dependence,
and dead keys are irrelevant because a dead key still has a physical location.

**What the catalogue needs that it does not have:** the reverse lookup, usage → label. It has
`usbHidUsageFor(label)` and `labels`, so a reverse map is a derivation from the existing table
(the same `for (final label in labels)` shape `_usages` at `:162-164` already uses), not new data.

**`HardwareKeyboard` gives the regularized stream** the capture needs: "one `KeyDownEvent`, zero or
more `KeyRepeatEvent`s, and one `KeyUpEvent` in order, all with the same physical key and logical
key." [CITED: api.flutter.dev — `HardwareKeyboard`]

**Pitfalls, all real:**

- **Ignore `KeyRepeatEvent`.** Holding the key would otherwise re-commit the capture repeatedly.
- **Modifier-only presses must not commit.** Read modifiers from
  `HardwareKeyboard.instance.logicalKeysPressed` at the moment a *non-modifier* `KeyDownEvent`
  arrives.
- **AltGr.** On Linux GTK, AltGr surfaces as `PhysicalKeyboardKey.altRight` with a logical
  `altGraph`. `HotkeyModifier` cannot express Level 3, so it must be **rejected**, not silently
  folded into `alt`. Folding it would produce a shortcut whose serialization is a plain `ALT`
  combination that fires on the wrong physical key. [ASSUMED — the GTK-embedder mapping of AltGr
  was not verified in this session; the *consequence* (no `HotkeyModifier` value exists) is verified
  from `hotkey_binding.dart:54`.]
- **`Tab` and `Escape` will be eaten by focus traversal and dismissal** unless the capture surface
  returns `KeyEventResult.handled` from a `Focus.onKeyEvent`. Since C3 makes `Tab` bindable again,
  this matters.
- **The currently-bound global hotkey cannot be re-captured on X11.** While the passive grab is
  held, pressing it goes to the grab, not to the focused window — so a user trying to re-enter their
  existing combination gets nothing (or gets the panel toggled). Two workable answers: release the
  grab for the duration of capture, or treat "no key event arrived" as "that is already your
  shortcut". **Flag this to the human** — it is a user-visible behaviour D-14/D-16 do not cover.
  [ASSUMED — not reproduced in this session; follows from X11 passive-grab semantics.]
- **Wayland gives the app no keyboard while the panel is unfocused**, but capture happens inside a
  focused settings window, so ordinary key events are available on both display servers.

---

## HOTKEY-10 dissolves

**The trigger, quoted:** the envelope says of the `libkeybinder` hardness measurement
*"Re-measure when the plugin version moves"*, about `hotkey_manager_linux 0.2.0`.
[VERIFIED: `ARCHITECTURE-SPINE.md:584`]

**Why it has no subject after D-12.** `pubspec.lock` records `hotkey_manager_linux` as
`dependency: transitive` (`:310-317`), reached through `hotkey_manager 0.2.3`'s own
`^0.2.0` constraint. Deleting the direct dependency removes `hotkey_manager`,
`hotkey_manager_linux`, `hotkey_manager_macos`, `hotkey_manager_platform_interface` and
`hotkey_manager_windows` from the lock entirely. [VERIFIED: `pubspec.lock:302-341`]

**And the claim it guarded is retired too.** The hardness clause exists because a library the app
cannot supply is resolved before `main()`. Under the recommended route `libkeybinder-3.0-0` leaves
the runtime-dependency list outright, and its replacement `libX11.so.6` is *already* an
unconditional `DT_NEEDED` of `libgdk-3.so.0` on every host (C7) — so no new hard dependency
appears and none needs a re-measure trigger.

**Recommendation: close `FLAT-11` with the finding, plus one envelope clause edit.** Do not invent
a re-keying target. Concretely:

1. Close `FLAT-11` (`status: done <date>` + `resolution:`) recording that the trigger's subject left
   the tree with `hotkey_manager`, and that the hardness claim it guarded was retired by D-11/D-12.
2. Amend the envelope clause at `ARCHITECTURE-SPINE.md:584`: drop `libkeybinder-3.0-0` from the
   runtime-dependency list and delete the "the exception is `libkeybinder-3.0-0`, which is hard
   today" paragraph and its re-measure sentence. **If the human chooses the keybinder-FFI route
   instead**, the clause changes rather than disappearing: `libkeybinder-3.0-0` becomes a
   *degrading* dependency (absence is a caught `ArgumentError`) and rejoins the set the envelope
   already characterises that way.
3. The spine also carries `| hotkey_manager | 0.2.3 |` in its Stack table, which becomes false.
   **Coordinate with Phase 7 (ARCH-06/FLAT-10, spine currency)** rather than doing a broad spine
   pass here.

---

## Runtime State Inventory

This is a replacement/refactor phase, so this section is mandatory. Every category was checked.

| Category | Items found | Action required |
|---|---|---|
| **Stored data** | **The user's `config.json` holds `hotkeyBinding` as `{modifiers, key}` with `key` a *label* string.** The default is `Ctrl+Shift+G` applied at every startup (`default_app_config.dart:142`). Because C3 makes the seven previously-refused labels bindable, an existing user whose config names `Space`/`Tab`/`Enter`/`F1`–`F4` — and who has been living with "hotkey inactive" — will find their shortcut **starts working** after this phase. That is the intended fix, but it is a silent behaviour change on an existing install. **No schema change and no migration is needed:** the on-disk shape is unchanged. | Code edit only. Record the behaviour change; no data migration. |
| | The history SQLite database is untouched by this phase. | None — verified: no hotkey field in `history.drift` and the roadmap forbids schema-changing work. |
| **Live service config** | **The Wayland compositor holds a live GlobalShortcuts session and shortcut binding**, created by `CreateSession`/`BindShortcuts` and destroyed when the bus connection closes. It is state on the compositor, not in git. A user who has already granted the shortcut through a GNOME/KDE portal dialog has a *stored grant* keyed to the app id. Changing the app id — which nothing in this phase does — would orphan it. | None, provided `applicationId` (`wayland_portal_global_hotkey.dart:123-124`) is not changed. **Do not change it.** |
| | **The installed `.desktop` entry** at `${XDG_DATA_HOME:-$HOME/.local/share}/applications/com.divertedriver.HotkeyGrammarCorrector.desktop`, written by `tool/install_desktop_entries.sh`, is what GNOME matches the app id against. It is outside git on any developer machine. | None this phase — but the packaging decision (D-18) changes how it ships, and `DW-89` records that the installer "remains a developer install, not a packaging step". |
| **OS-registered state** | **X11 passive grabs on the root window.** A running daemon holds them for the session. The X server drops a disconnecting client's passive grabs, and `x11_global_hotkey.dart:189-193` already records that reasoning. So an old binary's grabs do not survive its exit. | None — verified by the code's own note and by the release-then-grab discipline in `_releaseBeforeRebinding`. |
| | No systemd unit, no pm2 entry, no Task Scheduler equivalent. Autostart is a `.desktop` file in `~/.config/autostart/` (`linux/packaging/autostart/`), which names the binary and not the plugin. | None. |
| | **The AD-14 single-instance abstract socket under `$XDG_RUNTIME_DIR`.** Unaffected by this phase's changes, but a developer running old and new binaries alternately will hit `alreadyRunning`. | Operational note only. |
| **Secrets / env vars** | None. This phase touches no secret. `DBUS_SESSION_BUS_ADDRESS`, `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY` and `DISPLAY` are read, all already through injected environment maps. The new sandbox predicate adds `FLATPAK_ID` to that set. | None — verified: `grep` for secret-store usage in `lib/` finds none; `SecretStore` is Phase 6 work. |
| **Build artifacts / installed packages** | **`build/linux/x64/{debug,release}/bundle/lib/libhotkey_manager_linux_plugin.so` is a stale artefact after the dependency is removed.** A `flutter build linux` without a clean will not necessarily remove it, and `linux/flutter/ephemeral/.plugin_symlinks/hotkey_manager_linux` is a symlink `flutter pub get` maintains. | **Run `flutter clean` before re-measuring `readelf -d` on the runner**, or the verification reads a stale binary. This is the single most likely way the D-11 fix gets falsely reported as landed. |
| | `linux/flutter/generated_plugins.cmake` and `generated_plugin_registrant.cc` are **generated** files that `flutter pub get` rewrites. Both currently name `hotkey_manager_linux`. | Regenerated automatically — but they are committed to git, so the diff must be reviewed and committed, not assumed. |
| | `pubspec.lock` loses five entries. | Commit the regenerated lock. |

---

## Common Pitfalls

### Pitfall 1: Removing the dependency but reading a stale build

**What goes wrong:** The `readelf -d` check on the runner still shows
`libhotkey_manager_linux_plugin.so`, or shows nothing changed, and the executor concludes the fix
did not work — or, worse, the reverse: the binary was never rebuilt and the check passes vacuously.
**Why it happens:** `build/` is not cleaned by `flutter pub get`, and this project's own memory
records "stale `build/` gotcha" as a known trap in this devcontainer.
**How to avoid:** `flutter clean && flutter pub get && flutter build linux --release`, then
`readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector | grep NEEDED`.
**Warning signs:** the bundle's `lib/` still contains `libhotkey_manager_linux_plugin.so`; the
binary's mtime predates the pubspec edit.

### Pitfall 2: The confinement gate goes red and looks like a regression

**What goes wrong:** Five-plus existing architecture rows fail the moment the seam file is deleted
(C9), and the phase looks broken.
**Why it happens:** `hotkey_confinement_test.dart` and `composition_wiring_test.dart` pin the
*current* backend by file path and by source literal, deliberately — that is what makes AD-9's
"one-file change" claim checkable.
**How to avoid:** Sequence the plan so the gate update lands **in the same commit** as the removal,
and re-point the rows at the new file rather than deleting them. The `package:hotkey_manager` scan
becomes a scan for the FFI seam; the "scan actually finds something" control row needs a new
positive subject or it starts proving nothing.
**Warning signs:** a commit where `dart test` is red "temporarily"; a row deleted rather than
re-pointed.

### Pitfall 3: A grab that works until NumLock is pressed

**What goes wrong:** The hotkey works on the developer's machine and stops on a user's, or stops
after they use the numpad.
**Why it happens:** X matches modifier state exactly; NumLock (`Mod2Mask`) and CapsLock
(`LockMask`) are modifier bits in `XKeyEvent.state`.
**How to avoid:** Grab all four combinations of `{0, LockMask, Mod2Mask, LockMask|Mod2Mask}`, and
mask them out of `state` when matching an incoming event.
**Warning signs:** the hotkey works in one session and not another with no config change.
**Refinement:** `Mod2Mask == NumLock` is a near-universal convention rather than a guarantee. The
robust form discovers it with `XGetModifierMapping` and `XKeysymToKeycode(XK_Num_Lock)`. Treat the
constant as a documented assumption unless the discovery is cheap.

### Pitfall 4: A bind timeout that cancels the dialog the user is reading

**What goes wrong:** D-17 adds a few-second budget to the bind path; on GNOME the portal shows a
confirmation dialog the user must answer, and a five-second budget cancels it under them. The user
clicks "Allow" on a request that no longer exists.
**Why it happens:** D-17 reverses a decision the adapter's source records as deliberate (C4).
**How to avoid:** Distinguish *no answer at all* from *a dialog awaiting the user*. The `Response`
signal is the only thing the adapter waits on, and the portal emits nothing while a dialog is open —
so the two are genuinely indistinguishable from the bus alone. Practical shapes, in order of
preference:
1. **Bound only the steps with no dialog behind them.** The GlobalShortcuts portal shows its dialog
   on `BindShortcuts`, not on `CreateSession` — the adapter's own comment says so
   (`:474-476`). Bound `getNameOwner`, `Register` and `CreateSession`; leave `BindShortcuts`
   unbounded, or give it a much longer budget.
2. **Abandon the wait without cancelling the request.** Return the previous outcome to the UI after
   the budget and let a late `Response` arrive on `bindingChanges` — which is exactly what
   HOTKEY-07's precedence rule makes safe.
3. Never send a portal `Close` on timeout; the session is what the user is being asked about.
**Warning signs:** a fixed `_bindBudget` applied uniformly to `_callThroughRequest`.
**Reuse, do not reinvent:** the tree's bounded-request pattern is
`WindowManagerPanelVisibility._answered(String call, Future<void> Function() issue)` at
`window_manager_panel_visibility.dart:522-553` — `issue().timeout(_requestTimeout, onTimeout: ...)`
with a local flag rather than a caught `TimeoutException`, and the budget **injected** from
`main.dart:114` as `_unresponsiveCallBudget = Duration(seconds: 5)` (`main.dart:242`). Its doc
explains why the flag rather than the exception: "a seam is free to have deadlines of its own, and
one of those expiring is the window *refusing* the call, not this policy firing." The Wayland
adapter also already has a teardown-only budget, `_teardownBudget = Duration(seconds: 2)`
(`wayland_portal_global_hotkey.dart:1307`), applied as `.timeout(_teardownBudget)` at `:1029`.
**Use `_unresponsiveCallBudget`'s five seconds and inject it**; do not add a third constant.

### Pitfall 5: Losing the measured facts that live only in doc comments

**What goes wrong:** `hotkey_manager_registrar.dart` and `hotkey_registrar.dart` carry
first-hand measurements with upstream file:line citations — the `gtk_accelerator_name` construction,
the discarded `gboolean`, the `std::map::insert` non-overwrite that forces release-before-grab, the
`uni_platform` reverse-table cause of DW-43. Deleting the files deletes the record.
**Why it happens:** AGENTS.md §1 says "no dead code, git remembers it" — but git does not surface a
deleted comment to the next reader wondering why the registrar releases before it grabs.
**How to avoid:** Re-home the facts that still bind (release-before-grab is still required — two X
grabs on one combination is the same defect) into the new registrar's doc, and record the retired
ones in the ledger closure text for DW-39/DW-42/DW-43.
**Warning signs:** the new registrar has a thin doc comment and no citations.

### Pitfall 6: Two portal sessions, or two X grabs, from overlapping binds

**What goes wrong:** The compositor ends up holding two shortcuts, or keybinder/X holds two grabs;
one press toggles the panel twice and it appears never to open.
**Why it happens:** `SettingsController.changeHotkey` has no in-flight guard of its own, and a
portal dialog makes the window seconds wide.
**How to avoid:** Both adapters already solve this with a serialized `_queue`
(`x11_global_hotkey.dart:65-105`, `wayland_portal_global_hotkey.dart:196-256`). **Preserve the
`_queue` idiom exactly** in any rewrite. The Wayland one is load-bearing for a spec reason: "an
application can only attempt to bind shortcuts of a session once" [CITED], so a rebind must close
the old session and create a new one, and two interleaved rebinds leave an untracked live session.
**Warning signs:** a rewrite that awaits inside `bind()` without chaining onto `_queue`.

### Pitfall 7: `dart:ffi` callbacks and isolate lifetime

**What goes wrong:** The daemon will not exit, or a callback fires into a torn-down isolate.
**Why it happens:** `NativeCallable` keeps its isolate alive by default (`keepIsolateAlive`), and a
helper isolate holding an open `Display` blocks process exit.
**How to avoid:** `dispose()` must `XUngrabKey` every grab, close the `Display`, `close()` any
`NativeCallable`, and kill the isolate — each step independently guarded, matching
`X11GlobalHotkey.dispose`'s existing `_guard(...)` chain (`:333-353`). Note the tree already has a
recorded instance of this class of bug on the D-Bus side: an unclosed `DBusClient` "can stop the
Dart process terminating" (`wayland_portal_global_hotkey.dart:1009-1011`).
**Warning signs:** `dispose()` returns but the process lingers; `STARTUP-03` (Phase 5) is the
requirement about exactly this shape.

### Pitfall 8: Assuming the Dart callback runs on the GTK thread

**What goes wrong:** A keybinder-based route calls `keybinder_init()`/`keybinder_bind()` from the
Dart isolate, which touches GDK from the wrong thread; behaviour is undefined and typically silent.
**Why it happens:** `NativeCallable.isolateLocal` "must be invoked from the same thread that created
it" and `NativeCallable.listener` "can be invoked from any thread" but is a one-way callback with no
return value [CITED: api.dart.dev — `NativeCallable`]. A GLib `GSourceFunc` must return `gboolean`
*and* run on the main loop's thread, so **neither constructor can serve as a `g_idle_add` callback
that runs Dart code on the GTK thread**. The marshalling `DW-39` sketched does not compose as
written.
**How to avoid:** Prefer the X11 route, which never touches GTK. If keybinder is chosen anyway, the
marshalling has to happen in C, which means an FFI plugin — see § *Alternatives Considered*.
**Note:** `KeybinderHandler` itself is `void (*)(const char*, void*)`
[VERIFIED: `/usr/include/keybinder-3.0/keybinder.h:31`], so the *press* callback is
`NativeCallable.listener`-compatible even though the *bind* call is not.

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---|---|---|---|
| Label → keysym name | A second name table in the new registrar | `XdgShortcutTrigger.keysymNameFor` (`xdg_shortcut_trigger.dart:68-78`) | Already measured against xkbcommon 1.6.0; verified this session that every name it emits resolves through `XStringToKeysym` and canonicalizes back to itself. A second table is a second thing to drift. |
| Label → USB HID usage | A parallel map | `HotkeyKeyCatalogue.usbHidUsageFor` | The runs are derived, not listed, precisely to avoid transposition errors (`:32-51`). |
| Bounded platform call | A new timeout constant and a caught `TimeoutException` | `_answered(...)`'s `.timeout(budget, onTimeout:)` + injected `_unresponsiveCallBudget` | CONTEXT.md explicitly forbids a second timeout pattern; the existing one distinguishes "the seam's own deadline" from "our policy". |
| Serializing overlapping binds | A mutex or a boolean flag | The `_queue` idiom in both adapters | Both docs explain the exact double-binding failure it prevents. |
| Reducing an error to a log-safe map | Inline `{'error': e.toString()}` | `_errorContext(Object error)` (identical in both adapter files) | The Logger port bans `toString()` because vendor exceptions carry the payload. |
| Swallowing a logger failure | bare `catch` | `_log(void Function() emit)` | Same helper in three files; AGENTS.md forbids bare `catch`. |
| Accelerator / keystring construction | A Dart copy of `gtk_accelerator_name` | Nothing — the X11 route needs a keysym *name*, not an accelerator string | The whole DW-41/DW-43 lesson: a Dart prediction of a C function's output drifts silently. |
| Detecting the display server | A second env read | `DisplayServer.fromEnvironment` | AD-9: asked once, at startup, no runtime switch. |
| Rendering a binding as text | A second formatter | `hotkeyBindingLabel` / `hotkeyModifierLabel` (`hotkey_binding_label.dart`) | "one vocabulary with two homes" is what that file exists to prevent. |
| Parsing localized portal text | A `trigger_description` parser | Display it verbatim (D-04) | Localized, backend-specific, and not a trigger. |
| A sandbox detector from scratch | `/.dockerenv`, `$container`, cgroup sniffing | `/.flatpak-info` + `$FLATPAK_ID`, as a pure predicate over injected inputs | Measured: the first set fires in this project's own devcontainer; the second does not. |

---

## Code Examples

### Reading the compositor's own description without parsing it

```dart
// Source: the shipped adapter, wayland_portal_global_hotkey.dart:1120-1141 —
// this is where the value already is, and today it goes only to a log line.
void _logTriggerDescription(
  Map<String, DBusValue>? properties, {
  bool changed = false,
}) {
  final description = properties?['trigger_description'];
  // ...
  'trigger_description': description is DBusString ? description.value : null,
}
```

The phase's edit is to *keep* it rather than only log it: extract the same
`description is DBusString ? description.value : null` expression into a field the adapter holds,
update it from the `BindShortcuts` Response, from every `ShortcutsChanged`, and from a
`ListShortcuts` refresh, and surface it on the new synchronous `current` member (§ *AD-9 Declaration
Edits*, edit A/C).

### The existing bounded-request pattern D-17 must reuse

```dart
// Source: lib/src/infrastructure/panel/window_manager_panel_visibility.dart:531-553
Future<bool> _answered(String call, Future<void> Function() issue) async {
  var answered = true;
  await issue().timeout(
    _requestTimeout,
    onTimeout: () {
      answered = false;
    },
  );
  if (!answered) {
    _log(
      () => _logger.error(
        'the window did not answer $call within '
        '${_requestTimeout.inMilliseconds} ms; the request was abandoned so '
        'the next press is still served',
        context: {'call': call, 'timeout_ms': _requestTimeout.inMilliseconds},
      ),
    );
  }
  return answered;
}
```

Injected from `main.dart:114` (`requestTimeout: _unresponsiveCallBudget`), defined at
`main.dart:242` (`const Duration _unresponsiveCallBudget = Duration(seconds: 5);`).

### The keybinder ABI, if the human picks that route

```c
/* Source: /usr/include/keybinder-3.0/keybinder.h:31-54, read 2026-09-01 */
typedef void (* KeybinderHandler) (const char *keystring, void *user_data);

void     keybinder_init        (void);
gboolean keybinder_bind        (const char *keystring, KeybinderHandler handler, void *user_data);
gboolean keybinder_bind_full   (const char *keystring, KeybinderHandler handler,
                                void *user_data, GDestroyNotify notify);
void     keybinder_unbind      (const char *keystring, KeybinderHandler handler);
void     keybinder_unbind_all  (const char *keystring);
gboolean keybinder_supported   (void);
guint32  keybinder_get_current_event_time (void);
```

Note `keybinder_init` returns `void` — it cannot report failure — while `keybinder_bind` and
`keybinder_supported` return `gboolean`. The exported symbol set was confirmed with
`nm -D --defined-only /usr/lib/x86_64-linux-gnu/libkeybinder-3.0.so.0`.

### The sandbox predicate, shaped like `DisplayServer.fromEnvironment`

```dart
// Illustrative. The point is the shape: a pure function over injected inputs,
// so a binding-free test can drive both branches with no sandbox present.
//
// /.dockerenv is deliberately NOT a signal: it is true in this project's own
// devcontainer, which is what the adapter's existing doc gives as the reason no
// detector was written. /.flatpak-info is written by the Flatpak runtime inside
// the sandbox and by nothing else — measured absent here, 2026-09-01.
enum PortalAppIdRegime {
  /// The host portal registry associates our app id with this bus connection.
  hostRegistry,

  /// The sandbox supplies the app id; `Registry.Register` "will not work with
  /// applications xdg-desktop-portal identifies as sandboxed", so step 1 of
  /// AD-11 is skipped entirely (ARCH-02, D-18).
  sandboxSupplied;

  static PortalAppIdRegime fromEnvironment(
    Map<String, String> environment, {
    required bool Function(String path) fileExists,
  }) {
    if (fileExists('/.flatpak-info')) return sandboxSupplied;
    final flatpakId = environment['FLATPAK_ID']?.trim();
    if (flatpakId != null && flatpakId.isNotEmpty) return sandboxSupplied;
    return hostRegistry;
  }
}
```

---

## Flatpak Permission Mechanics (D-19)

D-19 asks for "the narrowest permission set that works — clipboard, the OS secret store for a future
API key, and its own data directory". Two of those three need **no** `finish-args` at all.

**Default sandbox, quoted:** *"No access to any host files except the runtime, the app,
`~/.var/app/$FLATPAK_ID`, and `$XDG_RUNTIME_DIR/app/$FLATPAK_ID`. Only the latter two being
writable."* And: access to `org.freedesktop.portal.*` D-Bus names is automatically allowed.
[CITED: docs.flatpak.org — Sandbox Permissions]

| D-19 need | `finish-args` | Notes |
|---|---|---|
| Its own data directory | **none** | `~/.var/app/$FLATPAK_ID` is writable by default. `AppPaths.fromEnvironment` reads XDG variables, which the Flatpak runtime redirects into that directory. [ASSUMED — the redirect is standard Flatpak behaviour but was not verified against `AppPaths` this session.] |
| Clipboard | **none of its own** — it comes with the display socket | `--socket=wayland` plus `--socket=fallback-x11` (and `--share=ipc`, conventional with X11). Clipboard on Wayland is `wl_data_device` on the compositor connection; on X11 it is selections on the X connection. |
| OS secret store | `--talk-name=org.freedesktop.secrets` | The Secret Service API on the session bus. **Phase 6 work** (PROVIDER-02's `SecretStore`) — D-19 records the intent, this phase does not implement it. |
| GlobalShortcuts portal | **none** | `org.freedesktop.portal.*` is allowed by default. |
| Network (the future OpenAI-compatible provider) | `--share=network` | Phase 6. |

**Recommended minimal `finish-args`, for the record ARCH-02 owes:**

```
--socket=wayland
--socket=fallback-x11
--share=ipc
--talk-name=org.freedesktop.secrets      # Phase 6, for the API key
```

No `--filesystem=` of any kind. No `--socket=session-bus`. No `--talk-name=org.freedesktop.Flatpak`.

**The load-bearing consequence D-18 and D-19 do not mention, and the human should hear at the
checkpoint.** The shipped default correction provider is three processes deep: daemon → Python
sidecar → `claude` CLI, and the spine's envelope lists "a Python 3.11+ interpreter with
`claude_agent_sdk` installed **plus** the `claude` CLI on `PATH`" as runtime dependencies the app
cannot supply itself. [VERIFIED: `ARCHITECTURE-SPINE.md:583`] Inside a Flatpak sandbox neither the
host's Python nor the host's `claude` CLI is on `PATH`. Making the Flatpak work therefore requires
either bundling both into the runtime or granting a host-escape (`--talk-name=org.freedesktop.Flatpak`
plus `flatpak-spawn --host`), and the second is the opposite of D-19's narrowest-set commitment.
**This does not block Phase 1** — ARCH-02 only records the decision — but it materially changes what
"ship a Flatpak" costs, and the roadmap already notes the packaging phase is now on the critical
path. [ASSUMED that no bundling work exists today — verified only that `assets/sidecar/` ships as a
Flutter asset and `tool/provision_sidecar.sh` creates a `.venv-sidecar/` outside the bundle.]

---

## The 1307-line file: structure and the seams to cut along

`wayland_portal_global_hotkey.dart` is long because its doc comments record measurements, not
because its control flow is tangled. Verified structure:

| Lines | Section | Rewrite exposure |
|---|---|---|
| 1–63 | Imports + class doc (the measurement record) | **Edit** — the "`effective` is always null by measurement" paragraph becomes "the localized description is carried, never parsed" |
| 64–112 | Factory + private constructor (guards `DBusClient.session()`'s throw) | none |
| 113–221 | Fields: `applicationId`, `shortcutId`, `_client`, `_activations`, `_bindingChanges`, `_session`, `_activated`, `_shortcutsChanged`, `_registered`, `_deadConnection`, `_disposed`, `_queue`, `_tokenSequence`, `_random` | **Add** — a cached `trigger_description`, a `HotkeyStatus?`, and the sandbox regime |
| 223–256 | `activations`, `bindingChanges`, `bind()` (queue head + two pre-queue fast paths) | **Add** — `current` getter |
| 257–357 | `_bind` — the whole AD-11 sequence, linear, one `try` | **Edit** — step 1 becomes conditional; the terminal `HotkeyBound(effective: null…)` at **:342** gains the description |
| 363–456 | `_registerApplicationIdOnce` — step 1, with five tolerated exception arms | **Edit** — early-return when sandboxed; `_registered` should reset on portal restart (§ Open Q4) |
| 462–495 | `_createSession` — step 2 | **Possibly bound** (no dialog behind it) |
| 497–546 | `_bindShortcut` — step 3 **including the read-back check** | **Edit** — capture `trigger_description` rather than only logging it |
| 548–580 | `_shortcutRequest` — builds `description` + `preferred_trigger` | none |
| 582–716 | `_callThroughRequest` — the Request/Response machinery; subscribe-before-call ordering, sender filtering, `finally` cancel | **Edit** — this is where a per-call budget would go (D-17) |
| 718–753 | `_portalSender` — per-call `GetNameOwner`, deliberately uncached | none |
| 755–787 | `_listenForShortcutSignals` — step 4, both signal subscriptions | **Consider** — `Deactivated` is not subscribed (correct for a press-toggle); a `NameOwnerChanged` watch would go here |
| 789–817 | `_onActivated` — CAP-1's whole press path | none — AD-8's budget |
| 819–878 | `_onShortcutsChanged` — three branches; the `effective: null` at **:874** | **Edit** — the `HotkeyBound` gains the description; D-08 forbids any re-claim attempt |
| 887–898 | `_pushBindingChange` | none |
| 906–979 | `_closeSessionBeforeRebinding` — the Wayland analogue of release-then-grab; `effective: null` at **:971** | **Edit** — the abandoned-rebind `HotkeyBound` carries the *previous* description |
| 981–1006 | `_logSessionAlreadyGone`, `_closeSession` | none |
| 1008–1056 | `dispose()` — ordered, guarded, with `_teardownBudget` on the Close | none |
| 1058–1066 | `_shutDownDuringBind` | **Edit** — gains a cause (HOTKEY-08) |
| 1068–1118 | `_readResponse`, `_shortcutsIn` — signature-checked parsing; `null` means "unreadable", `{}` means "discarded" | none — this distinction is load-bearing |
| 1120–1141 | `_logTriggerDescription` — **:1124** reads it, **:1135** logs it | **Edit** — return it instead of only logging |
| 1143–1240 | `_recordDeadConnection`, `_messageFor`, `_unclassified`, `_isConnectionFailure`, `_newToken`, `_guard`, `_log` | **Edit** — `_messageFor`'s switch is where each cause is assigned (HOTKEY-08) |
| 1243–1307 | `_PortalRefusal`, `_errorContext`, and the file-level constants | **Edit** — `_PortalRefusal` gains a cause so it can carry one out of the four-deep handshake |

**How to decompose without a 1307-line task.** Four independent slices, in dependency order:

1. **Sandbox predicate** — new file + `_registerApplicationIdOnce` early return + composition wiring.
   Touches ~30 lines of the adapter. Depends on the ARCH-02 checkpoint.
2. **Cause discriminator** — `_PortalRefusal` gains a cause; `_messageFor` assigns it; the 13
   `HotkeyUnavailable(` sites name one. Mechanical once the domain type exists.
3. **Description carrier** — `_logTriggerDescription` returns; a field caches; three `HotkeyBound`
   sites and the new `current` member carry it. Touches ~60 lines across five methods.
4. **Bounded bind** — one budget parameter through the constructor into `_callThroughRequest`, with
   Pitfall 4's dialog carve-out.

Slices 2, 3 and 4 are independent of each other and all depend on slice 1 only in commit order (the
ARCH-02 decision must precede the first edit to this file, per D-18's reversibility note).

---

## Ledger Mechanics: the exact shape of every entry this phase closes

`deferred-work.md` is **append-only**. Closing an entry flips `status:` and adds `resolution:`.
Entries are never deleted (`DW-13` and `DW-108` both record violations of that rule).
[VERIFIED: `deferred-work.md:1-59` header; `DW-13` at ledger line ~; `DW-108`]

**Two formats live in this file, and they indent differently.** Getting the indentation wrong makes
the entry invisible to `bmad-loop sweep`.

### Format 1 — canonical `### DW-n:` entries (all fields at column 0)

Live shape of the five this phase closes:

```
### DW-39: `keybinder_bind`'s discarded result makes AD-10's "a failed grab must not report success" unsatisfiable through `hotkey_manager`

origin: story 7-x11-global-hotkey-adapter.md, 2026-08-08
location: `hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:95-99`; consumed by lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart
severity: medium
reason: <one long paragraph, plus an indented continuation paragraph>
status: open
decision: 2026-08-14 Build the `dart:ffi` keybinder registrar — engineering call, …
```

| Entry | Ledger line (heading) | Fields present | Notes for the closure text |
|---|---|---|---|
| `DW-39` | **766** | `origin`, `location`, `severity`, `reason` (+ indented continuation), `status: open`, `decision: 2026-08-14 …` | Its `decision:` names the **keybinder-FFI** route. If the X11 route is chosen, the `resolution:` must say so explicitly and why (C7's no-new-dependency argument), or the ledger records a decision the code contradicts. Its own text says this one change closes **four** entries: DW-39, DW-40, **DW-42**, **DW-43**. Both of those extra two should be closed here too. |
| `DW-40` | **776** | same set, `status: open`, `decision: 2026-08-14 Closed by DW-39's replacement, and amend the envelope meanwhile` | Its `decision:` already corrects its own evidence: the executable does **not** carry libkeybinder directly; `libhotkey_manager_linux_plugin.so` does. Re-confirmed today (C6). |
| `DW-66` | **1129** | same set, `status: open`, `decision: 2026-08-14 Render the localized description -- the portal's trigger_description is displayed on the settings screen, clearly labelled as the desktop's own wording rather than this app's.` | **This is D-04, already ratified in the ledger on 2026-08-14.** The closure text should note the agreement. |
| `DW-71` | **1175** | same set, `status: open`, `decision: 2026-08-14 Expose the catalogue through a port -- … supplied by SettingsController rather than reached for across AD-1's rings -- validated before Apply` | The mechanism for HOTKEY-04 is already decided. Also record C3: the seven labels dissolve, so the "per-display-server difference" the decision mentions no longer exists. |
| `DW-89` | **1342** | same set, `status: open`, `decision: 2026-08-14 Pick a format now -- all four -- …` | **Contradicts D-18's three (C1).** Reconcile at the ARCH-02 checkpoint before writing the `resolution:`. |

Closure edit, per entry — replace the `status:` line and append one line after it:

```
status: done 2026-09-XX
resolution: <what closed it, with file:line evidence, in this file's house style>
```

The `decision:` line stays. Existing closed entries put `resolution:` immediately after `status:`
(e.g. ledger lines 77–78, 87–88, 412–413), so follow that ordering.

### Format 2 — flat `- source_spec:` entries (bullet at column 0, fields indented **two spaces**)

Live shape, byte-checked with `cat -A`:

```
- source_spec: `_bmad-output/implementation-artifacts/spec-dw-2-spine-currency-refresh.md`
  summary: <one sentence>
  evidence: <one long paragraph>
  status: open
```

There is **no** `origin:`, `location:`, `severity:`, `reason:` or `decision:` on these.

**FLAT numbering, resolved.** `REQUIREMENTS.md` says "numbered by their order of appearance in the
ledger", which is ambiguous — the file holds 108 flat entries and the first 56 are `parked`/`done`.
Verified: **FLAT-nn indexes the `status: open` flat entries only**, in file order, starting at
ledger line 1433.

| Requirement | Flat id | Ledger line | `summary:` opening words |
|---|---|---|---|
| — | FLAT-01 | 1433 | "The Flutter toolchain version still has two ungated hand-maintained homes…" (removed from scope, GATE cluster) |
| **HOTKEY-06** | **FLAT-02** | **1438** | "`GlobalHotkey.bindingChanges` is a broadcast stream with no replay and the port offers no synchronous current-registration accessor…" |
| **HOTKEY-07** | **FLAT-03** | **1443** | "`bind()`'s returned outcome and the `bindingChanges` stream are two writers of one piece of state with no stated precedence…" |
| **HOTKEY-08** | **FLAT-04** | **1448** | "`HotkeyUnavailable` now carries three distinct meanings on one variant holding only a `message`…" |
| **HOTKEY-09** | **FLAT-05** | **1453** | "`HotkeyBinding.modifiers` is a caller-supplied mutable `Set` held by reference behind a `const` constructor…" |
| **HOTKEY-10** | **FLAT-11** | **1483** | "The envelope's re-measure trigger for the `libkeybinder` hardness claim keys on a version nothing in the tree can observe changing…" |

Cross-checked against `REQUIREMENTS.md`'s descriptions for FLAT-07 (line 1463, StatusNotifier →
ARCH-03), FLAT-08 (1468, Map equality → ARCH-04), FLAT-09 (1473, `<Ctrl><Shift>g` comments →
ARCH-05), FLAT-10 (1478, spine currency → ARCH-06) and FLAT-13 (1493, tray fan-out → SETTINGS-08) —
all five match, which confirms the index.

Closure edit, per flat entry — **two-space indent, and the `status:` line is the anchor**:

```
  status: done 2026-09-XX
  resolution: <what closed it, with file:line evidence>
```

**Additional entries this phase should close**, named by DW-39's own `decision:` line and by C3:

| Entry | Why it closes here |
|---|---|
| `DW-42` | The vendor's undefined behaviour (`keybinder_unbind` on an uninitialised `const char*` after a missed `std::find_if`) leaves the process with the plugin. |
| `DW-43` | The seven wrong-key labels dissolve — measured (C3). |

Verify both are still `status: open` before writing a closure; the ledger is hand-maintained and
`REQUIREMENTS.md` records that 66 entries were already closed without the file always saying so.

---

## State of the Art

| Old approach | Current approach | When changed | Impact here |
|---|---|---|---|
| X11 `XGrabKey` as the universal Linux global-hotkey mechanism | `org.freedesktop.portal.GlobalShortcuts` on Wayland; X11 grabs remain correct on X11 | Interface landed in xdg-desktop-portal in 2024 | Exactly AD-9's two-adapter design. Nothing to change. |
| "Wayland has no global shortcuts" | GNOME (Mutter 46+) and KDE (Plasma 6.1+) implement the portal; **Hyprland ships its own** via `xdg-desktop-portal-hyprland`; wlroots' `xdg-desktop-portal-wlr` still does not, so Sway and Niri have none | ~2024–2026 | AD-12's headline case narrows: it names "every wlroots compositor" including Hyprland, which now has it. Worth a note when Phase 7 refreshes the spine. [ASSUMED — from a single web search summary, not verified against upstream release notes.] |
| Flutter's split UI/platform threads forcing platform channels for native calls | UI and platform threads **merged** — iOS/Android in 3.29, macOS/Windows in 3.35, Linux later | 2025–2026 | If merged on Linux at 3.44.8, direct FFI to GTK from Dart is safe and the keybinder route becomes viable. **Unverified** — see § *Open Question 1*. The recommended X11 route does not depend on the answer. |
| `RawKeyboard`/`RawKeyEvent` | `HardwareKeyboard`/`KeyEvent` with `physicalKey` + `logicalKey` and a regularized down/repeat/up sequence | Flutter ≥3.18 migration | D-14's capture control should use `HardwareKeyboard`, and `physicalKey.usbHidUsage` is a direct key into `HotkeyKeyCatalogue`. |
| `org.freedesktop.host.portal.Registry` absent | Present from xdg-desktop-portal 1.20; explicitly non-functional for sandboxed apps | ~2024 | The adapter's tolerance of `UnknownMethod`/`UnknownInterface`/`UnknownObject`/`ServiceUnknown` remains correct for older portals. |

**Deprecated / outdated in this tree:**

- `hotkey_manager` 0.2.3 as the X11 backend — removed by D-12; its Linux plugin's
  `hkm_register` cannot report a refused grab by construction.
- `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` — becomes empty (C3).
- `HotkeyPreferenceField`'s free-text key field and `offeredKeyExamples` — replaced by D-14.
- The envelope's "`libkeybinder-3.0-0`, which is hard today" clause — retired by D-11/D-12.
- The adapter's "no sandbox detector exists here" reasoning — answered by `/.flatpak-info`.

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | Flutter 3.44.8 on Linux runs the Dart UI isolate on the GTK platform thread (threads merged). | Alternatives Considered; Pitfall 8 | If wrong, the keybinder-FFI route silently corrupts GDK state. **The recommended X11 route does not depend on this** — that is a reason to prefer it. Only the engine strings `no-enable-merged-platform-ui-thread` and `!require_merged_platform_ui_thread` were observed in `libflutter_linux_gtk.so`; the default was not determined, and the web search results on the version disagreed with each other (3.39 vs 3.41). |
| A2 | `Mod2Mask` is NumLock on the user's X server. | Pitfall 3 | The hotkey stops working with NumLock on. Mitigation: discover it via `XGetModifierMapping`. |
| A3 | AltGr surfaces in Flutter on Linux as `PhysicalKeyboardKey.altRight` with logical `altGraph`. | HOTKEY-04 after the replacement | A capture control might fold AltGr into `alt` and produce a shortcut that fires on the wrong key. |
| A4 | While an X11 passive grab is held, the combination cannot be re-captured by the focused settings window. | HOTKEY-04 pitfalls | A user re-entering their current shortcut gets no key event (or toggles the panel). Needs a product answer. |
| A5 | The Flatpak runtime redirects `XDG_DATA_HOME`/`XDG_CONFIG_HOME` into `~/.var/app/$FLATPAK_ID`, so `AppPaths.fromEnvironment` needs no change. | Flatpak Permission Mechanics | The Flatpak build would write to an unwritable path. Phase-6/packaging-phase risk, not Phase 1. |
| A6 | No bundling of Python + `claude` CLI exists for a Flatpak today. | Flatpak Permission Mechanics | Understates the packaging cost the ARCH-02 decision commits to. |
| A7 | `flutter test` (the widget/composition/platform half) is currently green. | Validation Architecture | Not run this session — only the CI-scoped `dart test` was. A phase that breaks `test/ui/settings/` would not be caught by the measured baseline. |
| A8 | Hyprland now ships GlobalShortcuts, narrowing AD-12's "every wlroots compositor" claim. | State of the Art | Only affects a doc sentence, not code. |
| A9 | The 20 `HotkeyUnavailable(` construction sites in `lib/` (5 + 13 + 1 + 1) is still accurate. | AD-9 Decision 1 | The count is quoted from ledger line 1500's own `grep`, dated 2026-08-14; not re-counted this session. Under-counting understates the edit cost. |
| A10 | `dart:ffi` and `dart:isolate` imports do not trip `hotkey_confinement_test.dart`'s Flutter scan. | Pattern 1 | Read from the test's reference list (`package:flutter/`, `package:flutter_test/`, `package:flutter_riverpod/`, `dart:ui`) — neither is in it — but not executed against a file that imports them. |

---

## Open Questions

1. **Does Dart code run on the GTK main thread in Flutter 3.44.8 on Linux?**
   - *What we know:* `libflutter_linux_gtk.so` contains the strings
     `no-enable-merged-platform-ui-thread` and `!require_merged_platform_ui_thread`, so the switch
     exists in this engine build. Merging landed for iOS/Android in 3.29 and macOS/Windows in 3.35;
     Linux was implemented later and web sources disagree on when it became the default.
   - *What's unclear:* the default at 3.44.8.
   - *Recommendation:* **Do not resolve it — design around it.** The recommended X11 route touches
     no GTK/GDK state. If the human prefers the keybinder route, make a `pthread_self()` comparison
     between Dart and a GTK callback the **first task** of that route, as a spike with a
     `checkpoint:human-verify`, and note it can be run in this container under Xvfb (proved
     reachable: `Xvfb :77` accepted connections this session).

2. **Which packaging record wins — D-18's three formats or `DW-89`'s ratified four?** (C1)
   - *Recommendation:* a `checkpoint:decision` before any edit to `wayland_portal_global_hotkey.dart`,
     with the contradiction stated. Either answer produces the same code.

3. **Does dropping `const` from `HotkeyBinding` clear the bar, given no live defect exists?**
   - *What we know:* one `const` site in `lib/`, 24 in tests; the in-tree precedent (`HotkeyGrab`)
     paid exactly this price for exactly this reason; `FLAT-05` itself lists "document that callers
     must not retain the argument" as the alternative.
   - *Recommendation:* put both options and the honest "no live defect" note in front of the human
     (§ *AD-9 Decision 2*).

4. **Should the portal app-id registration be re-issued after an `xdg-desktop-portal` restart?**
   - *What we know:* the Registry docs say applications "should listen for `NameOwnerChanged`
     signals to re-register after portal service restarts" [CITED]. `_registered` latches once and
     never resets (`wayland_portal_global_hotkey.dart:173`, set at `:454`). The adapter's
     `_portalSender` doc already calls a portal restart "routine on a session update" and works
     around it for the *sender*, but not for the registration.
   - *Recommendation:* **out of scope for this phase's ten requirements** — file it as a new ledger
     entry rather than absorbing it. It is a real defect on the exact surface this phase is opening,
     so filing it while the file is open is cheap; fixing it is scope creep.

5. **How does the capture control handle the user pressing their currently-bound shortcut?** (A4)
   - *Recommendation:* one product question to the human at the same checkpoint as the others.

6. **Do `X11GlobalHotkey`'s existing 739 test rows survive the registrar swap?**
   - *What we know:* they drive the adapter through `FakeHotkeyRegistrar`, so the *seam* is what
     they exercise, not the backend. `:437`'s comment references the shipped seam's
     disposal-rejection behaviour, which the new registrar must preserve.
   - *Recommendation:* preserve `HotkeyRegistrar`'s contract exactly — reject once disposed, no-op
     release with nothing held — and the suite should pass unchanged. Confirm by running the scoped
     command, not by inspection.

---

## Environment Availability

Probed in this devcontainer, 2026-09-01.

| Dependency | Required by | Available | Version | Fallback |
|---|---|---|---|---|
| Flutter SDK | build, `flutter test` | ✓ | 3.44.8 stable, engine `13ffd72b2f`, Dart 3.12.2 | — |
| `dart analyze` | merge gate | ✓ | clean: "No issues found!" | — |
| `dart test` (CI-scoped) | baseline | ✓ | **946 passed / 2 skipped / 0 failed, 58 s** | bare `dart test` does **not** work (C10) |
| `libkeybinder-3.0.so.0` | current X11 path | ✓ | 0.3.2, at `/usr/lib/x86_64-linux-gnu/` | irrelevant under the recommended route |
| `/usr/include/keybinder-3.0/keybinder.h` | ABI reference | ✓ | — | — |
| `libX11.so.6` | recommended X11 route | ✓ | `libX11.so.6.4.0` | none needed — already `DT_NEEDED` of `libgdk-3.so.0` |
| `libgtk-3.so.0`, `libgdk-3.so.0` | keysym/accelerator probes | ✓ | GTK 3 | — |
| `libXtst.so.6` | synthesising key presses for observation | ✓ | 6.1.0 | — |
| `Xvfb` / `xvfb-run` | running the app and probing grabs | ✓ | `/usr/bin/Xvfb` — **`Xvfb :77` accepted connections this session** | — |
| An X display with valid auth | live observation | ✗ | `$DISPLAY=:21` and every socket in `/tmp/.X11-unix` refuse: "Authorization required, but no authorization protocol specified" | Start a private `Xvfb` — proved to work |
| A session D-Bus with `xdg-desktop-portal` | portal observation | ✗ | not present | none — Wayland behaviour is owed to a real desktop session |
| A Wayland compositor | portal observation | ✗ | not present | none |
| StatusNotifier/AppIndicator host | tray observation | ✗ | not present | none (already filed as `FLAT-07`/ARCH-03) |
| `readelf`, `nm`, `objdump` | `DT_NEEDED` verification | ✓ | binutils | — |
| Python 3 + `ctypes` | ad-hoc native probing | ✓ | — | — |

**Missing with no fallback (blocks *observation*, not implementation):** a real desktop session with
a portal and a compositor. Every Wayland-side claim in this document is from the specification or
from the shipped code, never from a run.

**Missing with fallback:** a display. `Xvfb` works and was used to prove the entire X11 grab path
this session.

---

## Validation Architecture

`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section is required.

**Framing, per the phase brief:** all test/gate/CI work was removed from this milestone on
2026-08-31 (`REQUIREMENTS.md` § *Removed: Test-Shaped Work*). **This section proposes no new test
files.** It says how a human or the executor observes that each behaviour is true, using commands
that run against the real tree today.

### Test framework

| Property | Value |
|---|---|
| Framework | `test` 1.31.0 (pure Dart) + `flutter_test` (SDK) |
| Config file | `dart_test.yaml` (`concurrency: 1` is a correctness requirement — see DW-15; `live` tag is skipped by default) |
| Quick run command | `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` |
| Full suite command | the above, plus `flutter test` for `test/ui`, `test/composition`, `test/platform` |
| Measured baseline (2026-09-01) | quick run: **946 passed / 2 skipped / 0 failed in 58 s**; `dart analyze`: **clean** |
| Anti-pattern | a bare `dart test` — fails to load 69 suites (C10) |

### Phase requirements → observation map

| Req | Behaviour to observe | Type | Command / step | Exists? |
|---|---|---|---|---|
| HOTKEY-01 | A grab another client owns reports failure, not success | manual, real X | Start the daemon; in another terminal run a second client holding `Ctrl+Shift+G` (e.g. the `ctypes` probe in this document against the same display); apply the same shortcut in Settings; the screen states it is taken and the previous shortcut still fires | ✅ reproducible — proved this session against `Xvfb :77` |
| HOTKEY-01 | The plugin's discarded return is gone from the tree | inspection | `grep -rn 'package:hotkey_manager' lib/ pubspec.yaml` → no matches | ✅ |
| HOTKEY-02 | The runner no longer resolves keybinder at load | automated one-liner | `flutter clean && flutter pub get && flutter build linux --release && readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector \| grep -c keybinder` → `0`; and `ls build/linux/x64/release/bundle/lib/ \| grep -c hotkey_manager` → `0` | ✅ — `readelf` present |
| HOTKEY-02 | The daemon starts with the library removed | manual, real host | Rename `libkeybinder-3.0.so.0`, launch under `xvfb-run`; tray present, panel opens from the tray, Settings reports the shortcut unavailable | ⚠️ needs a tray host (absent here) — owed to a real session |
| HOTKEY-03 | Settings never echoes the request on Wayland | inspection + manual | `grep -n 'preference' lib/src/ui/settings/hotkey_status_view.dart` — no path renders `preference` as the effective value; on a real GNOME/KDE session the shown text is the portal's own | ⚠️ manual half owed to a real session |
| HOTKEY-04 | A capture the app knows will not fire is rejected at capture | manual, any display | Open Settings, press a bare key → refused with a reason; press `Ctrl` alone → nothing committed; press AltGr+G → refused | ✅ runnable under `xvfb-run` |
| HOTKEY-04 | The seven labels are no longer special-cased | inspection | `grep -n 'labelsThatBindTheWrongKey' lib/ test/` — set is empty or the symbol is gone, and the two `hotkey_confinement_test.dart` rows that read it have been re-pointed | ✅ |
| HOTKEY-06 | A settings screen mounting after a compositor rebind reads current state | inspection + manual | `grep -n 'current' lib/src/domain/hotkey/global_hotkey.dart` shows the member; on a real session, rebind in the desktop's own settings with the app's screen closed, then open it | ⚠️ manual half owed to a real session |
| HOTKEY-07 | The precedence rule is written down and enforced | inspection | The rule appears in `global_hotkey.dart`'s doc **and** `changeHotkey` has the same "do not overwrite a newer fact" guard `applyStartupOutcome` has (`settings_controller.dart:294-312`) | ✅ |
| HOTKEY-08 | A consumer tells the three causes apart without parsing | inspection | `grep -rn 'HotkeyUnavailable(' lib/` — every site names a cause; `hotkey_status_view.dart` switches on the cause, not on `message` content | ✅ |
| HOTKEY-09 | `modifiers` cannot be mutated behind the constructor | inspection | `grep -n 'Set<HotkeyModifier>.unmodifiable' lib/src/domain/hotkey/hotkey_binding.dart` matches, and `grep -c 'const HotkeyBinding(' lib/` → `1` (the declaration) | ✅ |
| HOTKEY-10 | The re-measure trigger names something observable, or is retired | inspection | `grep -n 'hotkey_manager' pubspec.lock` → no matches; the envelope clause at spine line ~584 no longer names it | ✅ |
| ARCH-02 | The decision is recorded and the handshake honours it | inspection | `DW-89` shows `status: done` + `resolution:`; `grep -n 'flatpak-info' lib/src/infrastructure/hotkey/` matches; `Register` is inside a regime branch | ✅ |
| All | Nothing existing broke | automated | the quick run command → `946+ passed, 0 failed`; `dart analyze --fatal-infos` → clean | ✅ |

### Sampling rate

- **Per task commit:** `dart analyze --fatal-infos` plus the quick run command.
- **Per wave merge:** the quick run command plus `flutter test`.
- **Phase gate:** both green, plus the `readelf` one-liner on a freshly `flutter clean`ed release
  build, plus the manual observations owed to a real desktop session recorded as owed rather than
  claimed.

### Wave 0 gaps

**None — no new test infrastructure is proposed and none may be.** The work Wave 0 *does* owe is
maintenance of the existing gate, which is not test-shaped work but a consequence of the deletion:

- [ ] Re-point `test/architecture/hotkey_confinement_test.dart` rows at `:48-62`, `:78-112`,
      `:221-313`, `:366`, `:379` — five rows, plus the `_seamFile` constant at `:535-536`.
- [ ] Re-point `test/architecture/composition_wiring_test.dart` rows at `:864`, `:895`, `:901`.
- [ ] Delete `test/platform/hotkey_manager_registrar_test.dart` (608 lines) with the seam it drives.
- [ ] Fix the stale doc reference in `test/fakes/fake_hotkey_registrar.dart:24`.
- [ ] Check `test/infrastructure/hotkey/x11_global_hotkey_test.dart:437`'s comment about the shipped
      seam's disposal behaviour still describes the new registrar.

---

## Security Domain

`workflow.security_enforcement` is `true`, `security_asvs_level` is 1.

### Applicable ASVS categories

| ASVS category | Applies | Standard control in this phase |
|---|---|---|
| V2 Authentication | no | Single-user resident desktop daemon; no authentication surface |
| V3 Session management | **yes, in an unusual sense** | The *portal* session (`org.freedesktop.portal.Session`) is a capability handle. It must be closed on rebind and on teardown, and exactly one `Close` may ever be in flight — the adapter's `_session` discipline (`:143-152`) is the control and must survive the rewrite |
| V4 Access control | **yes** | D-Bus signal **sender filtering**. `Activated` is the whole path from a key press to a panel that reads the clipboard, so an unfiltered subscription lets any peer on the session bus forge a summon. The adapter filters `Activated` and `ShortcutsChanged` on sender (`:772-787`) and matches the Request `Response` on the portal's resolved *unique* name (`:582-640`). **Both are load-bearing and must not be simplified away.** |
| V5 Input validation | **yes** | Two untrusted inputs: (a) the D-Bus reply, validated by signature before use — `_readResponse` checks `DBusUint32`/`DBusDict` and the exact `a{sv}` signature (`:1068-1085`), `_shortcutsIn` checks `(sa{sv})` (`:1097-1118`); (b) the hand-editable `config.json` hotkey, validated by `HotkeyKeyCatalogue` before any backend call. D-15 adds a third: the captured combination. |
| V6 Cryptography | **yes, narrowly** | `Random.secure()` for portal `handle_token`s, so the Request object path is not guessable by another bus peer. Pinned by `hotkey_confinement_test.dart:150-168`, which fails if `Random()` is substituted. **Do not touch.** |
| V7 Error handling & logging | **yes** | Never log `error.toString()`; never log input text, suggestion bodies or clipboard content. `_errorContext` is the enforcement. A new registrar must use it. |
| V8 Data protection | **yes, at the edge** | This phase does not touch history, but D-19's Flatpak permission set is a data-protection decision: the daemon reads everything the user copies and stores plaintext history. The narrowest-set commitment is the control. |
| V12 Files & resources | **yes** | The new sandbox predicate reads `/.flatpak-info` — a fixed, non-user-controlled path. No user input reaches a filesystem call. |
| V13 API / IPC | **yes** | The X connection and the D-Bus connection are both IPC boundaries. The X one is new; see below. |

### Known threat patterns for this stack

| Pattern | STRIDE | Standard mitigation |
|---|---|---|
| A bus peer forges `Activated` and summons the clipboard-reading panel | Spoofing | Sender-filtered `DBusSignalStream` (already shipped, `:772-787`) — **preserve** |
| A bus peer forges a `Response` on a guessed Request path | Spoofing | Match on the portal's resolved unique name + `Random.secure()` tokens (already shipped) — the adapter's own doc records that a client owning no name forged one and got a `HotkeyBound` before this was added |
| A global grab silently captures every keystroke of a chosen key | Information disclosure | D-13 (a modifier is always required) is the control, plus the existing bare-key caution. A bare printable key would take that letter from every application. |
| The daemon is told to bind a key it cannot register and reports success | Repudiation / integrity | HOTKEY-01's readable refusal; AD-12's "unavailable only when nothing is held" |
| A Flatpak calls `Registry.Register` and receives a portal error on every launch | Denial of service (self-inflicted), noise | The sandbox predicate |
| A vendor exception's `toString()` carries user text into a log | Information disclosure | `_errorContext(error)` → `{'error_type': …}` only |
| An FFI `Pointer` outlives its isolate and is dereferenced | Tampering / crash | Own every pointer in one isolate; `close()` every `NativeCallable`; guard every teardown step |
| A `postinstall`-style supply-chain vector | Tampering | Not applicable — pub packages have no install scripts, and this phase *removes* a package rather than adding one |

**Net security effect of this phase: positive.** It removes a native plugin from the runner's link
set, removes four packages from the dependency graph, adds no network surface, and replaces an
unverifiable success claim with a protocol-level refusal.

---

## Sources

### Primary (HIGH confidence — measured in this container, 2026-09-01)

- `readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector` — runner `DT_NEEDED` includes `libhotkey_manager_linux_plugin.so`
- `readelf -d build/linux/x64/release/bundle/lib/libhotkey_manager_linux_plugin.so` — includes `libkeybinder-3.0.so.0`
- `readelf -d /usr/lib/x86_64-linux-gnu/libgdk-3.so.0` — includes `libX11.so.6`, `libXext.so.6`
- `/usr/include/keybinder-3.0/keybinder.h:31-54` — the full keybinder ABI
- `nm -D --defined-only /usr/lib/x86_64-linux-gnu/libkeybinder-3.0.so.0` — the eight exported symbols
- `~/.pub-cache/hosted/pub.dev/hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:90,92,95,96,99` — `gtk_accelerator_name`, `hotkey_id_map.insert`, `keybinder_init`, the discarded `keybinder_bind` result, the unconditional `true`
- `ctypes` probe of `libX11.so.6` — `XStringToKeysym`/`XKeysymToString` for 29 names
- `ctypes` probe of `libgdk-3.so.0` / `libgtk-3.so.0` — `gdk_keyval_from_name`, `gtk_accelerator_parse`/`gtk_accelerator_name` round trips
- `ctypes` probe against a live `Xvfb :77` — `XGrabKey`/`XSetErrorHandler`/`XSync` BadAccess detection, lock-mask independence, `XUngrabKey` idempotence, `XKeysymToKeycode` round trips, and `XTEST`-driven `KeyPress` delivery to a second connection
- `dart analyze` — clean; `dart test --exclude-tags=live <scoped>` — 946/2/0 in 58 s
- File existence probe: `/.dockerenv` present, `/.flatpak-info` absent, `$FLATPAK_ID` unset
- The tree itself: `ARCHITECTURE-SPINE.md` (AD-9 `:235-300`, AD-10 `:302`, AD-11, AD-12 `:321-326`, envelope `:584`, Ratified Divergence `:620`); `deferred-work.md` (DW-39 `:766`, DW-40 `:776`, DW-66 `:1129`, DW-71 `:1175`, DW-89 `:1342`, FLAT-01…11 `:1433-1487`); `lib/src/**`; `test/architecture/**`; `pubspec.yaml`, `pubspec.lock`, `linux/flutter/generated_plugins.cmake`, `.github/workflows/ci.yml`, `dart_test.yaml`, `analysis_options.yaml`, `AGENTS.md`, `.claude/CLAUDE.md`

### Secondary (MEDIUM confidence — official documentation, fetched this session)

- flatpak.github.io/xdg-desktop-portal — `org.freedesktop.portal.GlobalShortcuts`: method and signal signatures, `description`/`preferred_trigger`/`trigger_description`, "An application can only attempt to bind shortcuts of a session once", no machine-readable combination, no stated Response/`ShortcutsChanged` ordering
- flatpak.github.io/xdg-desktop-portal — `org.freedesktop.host.portal.Registry`: `Register (IN app_id s, IN options a{sv})`, "This interface will not work with applications xdg-desktop-portal identifies as sandboxed", once per connection, before any portal call, re-register on `NameOwnerChanged`
- docs.flatpak.org — Sandbox Permissions: `--socket=`, `--share=`, `--talk-name=`, `--filesystem=`; the default-access sentence; portal names allowed by default
- api.dart.dev — `NativeCallable`: `isolateLocal` "must be invoked from the same thread that created it"; `listener` "can be invoked from any thread", no `exceptionalReturn`
- api.flutter.dev — `HardwareKeyboard`, `KeyEvent.physicalKey`, `PhysicalKeyboardKey`
- x.org — `XGrabKey(3)`: BadAccess on a conflicting grab by another client

### Tertiary (LOW confidence — web search summaries, flagged as such)

- Flutter Linux merged UI/platform thread default version — results were self-contradictory (3.39 vs 3.41) and are the basis of A1
- wlroots / Hyprland / Niri GlobalShortcuts status in 2026 — basis of A8
- The four-lock-mask grab convention — corroborated by `tauri-apps/tao` and `xbindkeys` source, which is real code but not a specification

---

## Metadata

**Confidence breakdown:**

- **X11 replacement mechanism: HIGH** — every step proved against a live X server in this container, including the failure detection HOTKEY-01 turns on.
- **The DW-43 dissolution (C3): HIGH** — measured three ways (libX11 keysym round trip, GDK keyval lookup, GTK accelerator round trip, plus a real keycode round trip on Xvfb).
- **`DT_NEEDED` chain and the D-11 mechanism: HIGH** — `readelf` on this tree's own build.
- **Portal protocol facts: MEDIUM** — official documentation, fetched this session, never run against a portal.
- **AD-9 edit enumeration and the precedent mechanism: HIGH** — read from the spine and from the shipped code's own doc comments.
- **Ledger shapes and FLAT numbering: HIGH** — byte-checked with `cat -A`, cross-validated against `REQUIREMENTS.md` for five unrelated FLAT ids.
- **Existing-test breakage inventory: HIGH** — grep + reading the assertions.
- **Flutter thread model: LOW** — see A1. Deliberately routed around rather than resolved.
- **Flatpak permission set: MEDIUM** — official docs for the mechanics; the sidecar consequence is reasoned, not tested.
- **Capture-control pitfalls: MEDIUM/LOW** — the `physicalKey.usbHidUsage` fit is verified from the tree's own code; the AltGr and re-capture behaviours are assumptions (A3, A4).

**Research date:** 2026-09-01
**Valid until:** 2026-10-01 for the measured facts (they are properties of a pinned tree and of X11, which does not move); **2026-09-15** for the portal and Flatpak claims, which track upstream releases; the Flutter thread-model question should be re-checked on any SDK bump.
