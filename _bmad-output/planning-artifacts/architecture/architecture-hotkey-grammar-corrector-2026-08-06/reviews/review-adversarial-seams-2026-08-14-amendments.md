# Adversarial seams review — ARCHITECTURE-SPINE.md, 2026-08-14 amendment pass

**Lens.** Attack the spine as an adversary: construct two units one level down that each obey
every AD to the letter yet still build incompatibly — clashing shared-data shapes, two owners of
one entity, conflicting state-mutation paths. Every pair found is a hole to close with a new or
tightened AD.

**Target.** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
(status `final`, `updated: 2026-08-14`).

**Scope.** This was an *Update* pass that made three amendments to an already-final spine: AD-12's
Rule was widened from portal-only to any-backend; the operational envelope's `libkeybinder-3.0-0`
clause gained the "hardness precedes the adapter choice" reasoning; the `## Stack` heading note
gained the 2026-08-14 re-verification and the DW-94 carry-forward. The attack is concentrated on
those three and on what they could have loosened, with a lighter sweep elsewhere.

**Grounding.** Every claim below is checked against the shipped tree:
`lib/src/infrastructure/hotkey/x11_global_hotkey.dart`,
`lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`,
`lib/src/infrastructure/hotkey/display_server.dart`,
`lib/src/application/settings_controller.dart`,
`lib/src/domain/hotkey/hotkey_bind_outcome.dart`, `lib/src/domain/tray/tray_port.dart`,
`lib/src/ui/settings/hotkey_status_view.dart`,
`lib/src/infrastructure/system/daemon_startup.dart`, `lib/main.dart`,
`pubspec.yaml`, `pubspec.lock`, `linux/flutter/generated_plugin_registrant.cc`,
`linux/flutter/generated_plugins.cmake`, `test/architecture/sidecar_pin_drift_test.dart`,
`_bmad-output/implementation-artifacts/deferred-work.md`.

**Verdict.** The widening of AD-12 is the wrong shape for the thing it was trying to say, and it
did not merely leave the two carried-open questions where they were — it made one of them worse
and introduced a hard contradiction with the shipped X11 adapter and with the doc comment inside
AD-9's own verbatim-fixed declaration block. Amendments 2 and 3 are directionally right and
contradict nothing, but each ships one forward-looking promise that the tree falsifies.

Seven findings: two critical, two high, two medium, one low.

---

## A-1 (critical) — the widened AD-12 mandates `HotkeyUnavailable` for a refusal the shipped X11 adapter answers as `HotkeyBound`, and AD-10 says it is right to

**Where.** AD-12 Rule 1, second sentence; `x11_global_hotkey.dart:239-260` (`_refusedBeforeBackend`).

AD-12's widened Rule reads:

> **any** backend's refusal to hold the hotkey resolves to AD-9's `HotkeyUnavailable`, never an
> exception — `bind()` never throws and never rejects. The refusals are: a portal `CreateSession`
> or `BindShortcuts` that fails; **a key `HotkeyKeyCatalogue` finds unrepresentable *before* the
> backend is touched**; an X11 grab the backend refuses; and a session that identifies no display
> server […]

Parsed as written: refusal R resolves to `HotkeyUnavailable`; the enumerated set of refusals
includes the unrepresentable-key case; therefore the unrepresentable-key case resolves to
`HotkeyUnavailable`.

The shipped adapter does the opposite, deliberately, and documents why at length
(`x11_global_hotkey.dart:216-238`). `_refusedBeforeBackend` returns `HotkeyUnavailable` **only when
`_effective == null`**. When a combination is genuinely still grabbed, it returns
`HotkeyBound(HotkeyRegistration(effective: <the previously-held combination>, authority:
application))` and logs the abandonment. Its stated reason is AD-10:

> Answering `HotkeyUnavailable` regardless would say "the hotkey is inactive" while the old
> combination was still grabbed and still opening the panel — `SettingsController.changeHotkey`
> stores the new preference either way, so the settings screen and the tray would both show no
> shortcut while the previous one kept firing for the rest of the session.

**The adversarial pair.** Two implementors, one level down, each obeying every AD to the letter:

- *Implementor X* reads AD-12 Rule 1 literally. `HotkeyKeyCatalogue.usbHidUsageFor` returns null →
  `return HotkeyUnavailable(message: …)`, unconditionally. Fully compliant with AD-12. Nothing in
  AD-12 conditions the arrow on whether anything is still held.
- *Implementor Y* reads AD-10 ("the settings screen renders the `HotkeyRegistration` inside the
  returned `HotkeyBound`" / `effective` is "what is actually in effect") and returns
  `HotkeyBound(previous)`. Fully compliant with AD-10. This is what shipped.

They are not merely different, they are user-visibly incompatible on the same action. On
implementor X's build, a user who rebinds to `Tab` while `Ctrl+Shift+G` is working gets: the tray
swaps to `unavailableIconAsset` and appends "Global hotkey unavailable — use this menu to open the
panel" (`tray_manager_tray.dart:71-72, 164, 184-187`), the settings screen prints AD-12's
degradation sentence (`hotkey_status_view.dart:58, 126-130`), `SettingsController.changeHotkey`
persists `Tab` as the preference (`settings_controller.dart:148-152`) — and `Ctrl+Shift+G` keeps
opening the panel for the rest of the X session, because nothing released it. That is the exact
misreport AD-10 exists to prevent and AD-12's own Prevents clause ("a silently dead hotkey")
gestures at from the other side.

**This is new.** Before the amendment AD-12 was portal-only, so it said nothing about the catalogue
path and AD-10 governed it alone — no conflict existed. The widening created it. The spine as it now
stands instructs a wrong implementation, and the correct one is a spine violation.

**Charitable reading, and why it does not rescue the AD.** One can read Rule 1 as being *about* the
never-throws property, with the enumeration as a list of things that must not escape as exceptions
rather than a mapping onto `HotkeyUnavailable`. That reading is available. So is the literal one.
Both live in one sentence whose grammatical subject-verb is "resolves to `HotkeyUnavailable`" and
whose appositive "The refusals are:" attaches directly to it. A single sentence supporting two
readings that produce incompatible builds is precisely the hole this lens hunts, and the AD is a
build substrate — a reader gets no second sentence to disambiguate it.

**Hole to close.** Tighten AD-12 Rule 1 to split the two properties it currently fuses:

1. *No refusal ever escapes as an exception* — this is the universal half, and it is correct as
   widened. `bind()` never throws and never rejects, on every adapter, on every path, including
   paths not enumerated.
2. *Which value a refusal resolves to is decided by AD-10, not by AD-12* — a refusal resolves to
   `HotkeyUnavailable` **only when nothing is left in effect**. When a combination is still
   genuinely held (a rebind refused before the backend was touched; a rebind whose release or
   session-Close the backend refused), the outcome is `HotkeyBound` naming the combination that is
   actually in effect, and the abandonment is logged. State that the AD-12 message is reached only
   on the nothing-held arm.

Without (2) written down, the correct behaviour is reachable only by an implementor who reads
AD-10 harder than AD-12, and the spine gives no reason to.

---

## A-2 (high) — the widening made carried-open question (b) worse, and newly self-contradictory against AD-9's fixed declaration block

The run's memlog carries this as deliberately unresolved: `HotkeyUnavailable` means "no backend,
never retry" on `bind()`'s return but "a working binding was revoked" when it arrives on
`bindingChanges`. **This pass made it worse.** Three grounds, in ascending order of hardness.

**(i) The bind-side meaning count went from one to four.** Before the widening, AD-12 was
portal-only, so `HotkeyUnavailable` on `bind()`'s return meant one thing on the AD's own terms: a
compositor with no GlobalShortcuts backend. After it, AD-12 itself enumerates four causes, three of
which are not "no backend": an unrepresentable key on a *working* X11 backend, a single refused
grab on a *working* X11 backend, and a guessed-wrong display server. The tree already produces more
than four (`_shutDownDuringBind` on both adapters, `_deadConnection`, `_unusableBusAddress`,
`_malformedReply`, the documented empty-subset discard, `daemon_startup.dart:222-226`'s
contract-breach absorber). So the pass did not document an existing single meaning; it blessed a
value that is now overloaded across two adapters and at least eight causes, with the only
discriminator being the free-text `message`.

**(ii) That free text is contractually un-inspectable.** `HotkeyUnavailable` carries `message` and
nothing else (`hotkey_bind_outcome.dart`), and AD-9 fixes those fields as "the fixed part" — no
kind, no retryability flag, no cause discriminant may be added without amending AD-9.
`SettingsController._bind` explicitly refuses to put the message anywhere but the surface
(`settings_controller.dart:402-415`: "adapter-authored free text […] would leak through the one
context value in this layer that is not reduced to a type"). So no consumer can branch on cause,
by construction. The widening enlarged the meaning set of a value whose fixed shape forbids
distinguishing the meanings.

**(iii) The hard part: AD-12's Rule now contradicts the doc comment inside AD-9's verbatim-fixed
block.** AD-9 pins the declarations and says "the declared fields and constructors above are the
fixed part". Inside that block, verbatim in the spine and verbatim in shipped
`domain/hotkey/hotkey_bind_outcome.dart`:

```dart
/// No backend could bind at all. The tray menu keeps the app usable (AD-12).
final class HotkeyUnavailable extends HotkeyBindOutcome {
```

`settings_state.dart` restates it: "`HotkeyUnavailable` means no backend could bind at all."
AD-12 as amended now says that an unrepresentable key with a fully working keybinder grab
underneath it, and a single refused grab on a working X11 backend, are both `HotkeyUnavailable`.
Those are not "no backend could bind at all". **The spine now contradicts itself between AD-9 and
AD-12**, and the contradiction is in the one place AD-9 declares immutable. That is not the
carried-open question left as it was; it is the carried-open question promoted from "two channels
disagree about one value's meaning" to "the document defines the value two incompatible ways."

**The adversarial pair.** Two implementors of the *tray*, one level down:

- *Implementor P* implements `TrayPort`'s declared contract (`tray_port.dart`: "Shows or clears the
  visible 'global hotkeys unavailable on this compositor' state (AD-12)") plus AD-9's doc comment.
  A `true` therefore means "this desktop has no global shortcuts". Reasonable label text: "Global
  hotkeys are not available on this desktop."
- *Implementor Q* implements the widened AD-12, under which `true` arrives for a refused key label
  on a working backend. It cannot say "this desktop", so it says something generic.

Shipped code is Q, and it had to fight the spine to get there. `hotkey_status_view.dart:104-114`
documents the fight explicitly:

> **Nothing is claimed about the desktop, either.** This state is reached from four different places
> and only one of them is a desktop with no global shortcuts at all. A single refused key label
> (`the key "Tab" is not one this build can register…`) comes back here from a *working* X11
> backend, and a compositor dropping one shortcut […] comes back here from a *working* portal — so a
> preamble reading "global shortcuts are unavailable on this desktop" was false on both […]

The shipped UI is right and the spine's own port doc is wrong. A reader building the settings
screen from the spine alone builds implementor P and prints a false sentence on three of the four
refusals AD-12 enumerates.

**Hole to close.** Either (a) amend AD-9's doc comment in the fixed block — "No binding is in
effect and none can be established by this request; the message says what happened" — and amend
`TrayPort`'s contract to drop "on this compositor"; or (b) if the distinction is genuinely needed
by the surfaces (see A-3, which argues AD-12's own Rule 2 needs it), add a cause discriminant to
`HotkeyUnavailable` in AD-9's fixed block and state which causes each surface renders how. Doing
neither leaves a value whose spine-declared meaning and spine-mandated production are disjoint.

---

## A-3 (high) — Rule 1 was widened and Rule 2 was not, so AD-12 now has an any-backend premise and a portal-only conclusion

**Where.** AD-12 Rule 2, and the heading. Untouched by this pass.

The prompt records that Binds (CAP-1, CAP-13), Prevents, and the heading were deliberately left
alone. Rule 2 — the rendering rule — appears to have been left alone by omission rather than by
decision, and it is the one that had to move with Rule 1:

> the tray icon and settings screen render that state: **on a compositor with no backend**, that
> global hotkeys are unavailable *there*; **otherwise** the `HotkeyUnavailable` message names what
> was refused, so the user can act on it.

This is a two-way branch keyed on cause. Rule 1 just widened the cause set to four (eight in the
tree) and A-2(ii) established that the value carries no cause discriminant. So Rule 2 now demands a
branch that Rule 1's own value space makes undecidable. Concretely, the surfaces cannot take it:

- `TrayPort.setHotkeyUnavailable(bool)` — a **boolean**. There is no channel for "which of the
  four" at all, and widening the port is an AD-9-adjacent change nobody was told to make.
- `hotkey_status_view.dart` receives the whole outcome but can only pattern-match
  `HotkeyUnavailable(:final message)` and print it, which it does, and it documents refusing the
  first arm of Rule 2 as a correctness requirement.

Worse, the "otherwise" arm is now false on a path the widening itself created and on one it did
not. Rule 2 requires the message to "name what was refused". `_shutDownDuringBind` on both adapters
produces "the hotkey backend has already been shut down, so no global shortcut is registered", with
the source comment "Not a refusal by the session, and worded so nobody goes looking for one"
(`x11_global_hotkey.dart:262-270`). Nothing was refused; the message names no refusal, correctly.
Rule 2 says it must.

**The adversarial pair.** Two settings screens, both AD-12-compliant:

- One implements Rule 2 as written — branch on the compositor-with-no-backend case, print the
  "unavailable *there*" sentence for it, print the message otherwise. It has no way to detect the
  case, so it must guess, and every plausible proxy is wrong: adapter identity is invisible above
  infrastructure (AD-1), and since the widening the X11 adapter also produces `HotkeyUnavailable`,
  so even a leaked adapter identity no longer discriminates.
- One implements the shipped reading — never claim anything about the desktop, print the message
  and say that no regime is known.

Both cite AD-12. Only one is truthful, and the spine names the other.

**Hole to close.** Rewrite Rule 2 to match the widened Rule 1: the surfaces render *the message*,
which every adapter must author as a sentence that names what happened and names the tray as the
way in; no surface infers, claims, or branches on the display server or the cause, because the
value carries neither. If a per-cause branch is genuinely wanted, it needs the discriminant from
A-2(b) first. Also retitle the AD — "A compositor with no portal backend degrades visibly" is now
a subcase of what the AD governs, and a reader who navigates by headings will not look here for the
X11 refusal rules that now live in it.

---

## A-4 (medium) — AD-12's fourth enumerated refusal names a state AD-9 makes unrepresentable, and inviting it back breaks "two adapters, chosen once"

**Where.** AD-12 Rule 1, fourth refusal; `display_server.dart`; AD-9 Rule; AD-17 part 3.

The fourth refusal is "a session that identifies no display server, where AD-9's X11 fallback may
have guessed wrong". `DisplayServer.fromEnvironment` is total over two values and has no third:

> X11 is the fallback rather than an error because a session that reports nothing is far more often
> a bare X server than a Wayland compositor hiding its socket — and AD-12 makes a wrong guess a
> visible `HotkeyUnavailable`, not a crash.

So there is no point in the shipped model at which "no display server" is a distinguishable
refusal. A session that identifies nothing gets the X11 adapter, and if the guess was wrong the
observable is a *refused grab* — the third enumerated refusal. The fourth is either a restatement
of the third or a request for a state that does not exist.

**The adversarial pair.** Implementor R reads four distinct refusals and implements four: a third
`DisplayServer` value (`unknown`), and a refusal for it. Now the composition root has an adapter
choice that is not total, and AD-17 part 3's startup order (`AD-14 → AD-13 → AD-9 → AD-5`) needs a
no-adapter branch — either a third null-object `GlobalHotkey` adapter, which breaks AD-9's "two
adapters" literally, or a nullable hotkey port threaded through `DaemonStartup.bindHotkey` and
`SettingsController`, which changes the port's shape. Implementor S reads it as the third refusal
restated and ships `display_server.dart` as it stands. R's build and S's build have different
composition roots and different port nullability from one AD sentence.

**Hole to close.** Either delete the fourth refusal (it is the third, observed one layer up), or
state explicitly that the display-server guess is never itself a refusal — the fallback is total by
design, and a wrong guess surfaces as whatever the fallback backend refuses. Say which, because the
current phrasing supports both and they produce different composition roots.

**Related, same sentence.** The enumeration reads closed ("The refusals are: …"). The shipped X11
adapter's own doc lists **five** — "an unrepresentable key, a refused grab, **a refused release**, a
channel that is gone and a disposed adapter" — and the Wayland adapter's lists nine. A refused
release, a dead `package:dbus` connection, a malformed portal reply, and the documented
empty-subset discard are all absent from AD-12's four. An implementor who reads the list as
exhaustive may reasonably conclude that a refusal *not* on it is outside AD-12 and may therefore
throw, which is exactly the unhandled-async-error-in-a-resident-daemon failure the amendment's own
final clause exists to prevent. One word fixes it: make the list explicitly illustrative
("including"), and put the universal claim first — *no* path out of `bind()` throws, whatever
refuses.

---

## A-5 (high) — the envelope's new "it rejoins the degrading set" promise is unsatisfiable under AD-9's own one-file rule

**Where.** Operational envelope, `libkeybinder-3.0-0` bullet, final clause; AD-9's closing
paragraph; the `## Stack` `hotkey_manager` note; `linux/flutter/generated_plugin_registrant.cc`;
`linux/flutter/generated_plugins.cmake`; `pubspec.yaml`; DW-39.

**First, the question asked: does the clause contradict AD-9's "two adapters, chosen once at
startup" or the Stack note's "bound here for the X11 adapter only"? No.** Those are claims about
which *adapter* uses the package; the envelope's claim is about which *hosts* must have the shared
object present. Both are true simultaneously, and the amendment reconciles them in its own text
("despite the `(X11 hotkey)` annotation above and AD-9 binding `hotkey_manager` for the X11 adapter
only"). Verified in the tree: `generated_plugin_registrant.cc` calls
`hotkey_manager_linux_plugin_register_with_registrar` unconditionally, and
`generated_plugins.cmake` puts `hotkey_manager_linux` in `FLUTTER_PLUGIN_LIST`, which
`target_link_libraries` links into the runner. The reasoning is sound and the amendment is an
improvement.

**What it did introduce** is a forward-looking promise the same reasoning falsifies:

> and only meanwhile: DW-39's `dart:ffi` registrar `dlopen`s the library itself, at which point its
> absence becomes a caught error and it rejoins the degrading set.

That holds only if `hotkey_manager` leaves `pubspec.yaml`. While the dependency is declared, the
plugin is registered and linked unconditionally — which is the amendment's *own* argument — so
`libkeybinder-3.0.so.0` stays a `DT_NEEDED` of the plugin `.so` resolved before `main()`, and a
`dlopen` in Dart changes nothing about whether the process starts.

**The adversarial pair, and both sides are following instructions.** AD-9 says replacing
`hotkey_manager` is "a one-file change". DW-39's ratified decision says the same, in more detail:
"Under AD-9 and this story's seam that is **one file** — `hotkey_manager_registrar.dart` swapped for
a `keybinder_registrar.dart`, with `X11GlobalHotkey` and everything above it untouched", and claims
it "closes four entries" including DW-40 ("a missing library becomes a caught error instead of a
loader failure before `main()`").

- *Implementor T* does exactly the one file. `hotkey_manager` stays in `pubspec.yaml` because
  nothing told them to remove it and AD-9 promised one file. The registrant and cmake list are
  unchanged, the loader hardness is unchanged, DW-40 is **not** closed, and the envelope's promise
  does not arrive. The build looks correct: every test passes, `X11GlobalHotkey` is untouched,
  the new registrar `dlopen`s successfully because the loader already mapped the library.
- *Implementor U* also drops the pubspec dependency, which regenerates the registrant and the cmake
  list and changes the packaging dependency list — three files outside the promised one — and
  actually delivers the degradation.

T's build is indistinguishable from U's on every developer machine that has keybinder installed,
including this container (DW-40 records keybinder 0.3.2 present here). The difference only appears
on the target host that lacks it, which is the one case the whole clause exists for. That is a
silent-until-shipped divergence produced by an AD sentence and a ledger decision that agree with
each other and disagree with the build system.

**Hole to close.** Tighten AD-9's "one-file change" claim to name its boundary: replacing the X11
backend is one file *behind the `HotkeyRegistrar` seam*, and retiring the loader hardness
additionally requires removing the `hotkey_manager` dependency from `pubspec.yaml` — which
regenerates `linux/flutter/generated_plugin_registrant.cc` and `generated_plugins.cmake` and
changes the packaging dependency list. State that the two are separable and that only the second
one makes the envelope's promise true, so a story that does the first must not close DW-40.

---

## A-6 (critical) — the pin-renegotiation paragraph does not merely reason from a stale row; its claim about the current dependency graph is false, and its revisit trigger has already fired

**Where.** `## Stack` heading note; the pin-renegotiation paragraph's final sentence;
`pubspec.yaml`; `pubspec.lock`.

**The question asked: can a reader now build something incompatible from a table the document
itself labels partly stale, and does the note contradict the paragraph below it? Yes to both, and
the contradiction is sharper than the note admits.**

The note is careful and honest about the row: `drift_flutter 0.3.1` is no longer a dependency,
`pubspec.yaml` addresses the divergence by name and instructs a reader not to re-add it, DW-94 owns
the removal. All verified — `pubspec.yaml` carries exactly that instruction, and `drift_flutter`
appears nowhere in `pubspec.lock`.

But the note's closing clause says DW-94 also owns "the pin-renegotiation paragraph below that
reasons from it", and the paragraph's actual content is not a stale *inference* — it is a false
*assertion about the tree*:

> Also noted: `drift_flutter 0.3.1` transitively resolves `sqlite3_flutter_libs 0.6.0+eol` /
> `sqlcipher_flutter_libs 0.7.0+eol` — end-of-life native sqlite builds; revisit when the drift
> slice lands or at the next Stack review.

Measured against `pubspec.lock`: `sqlite3_flutter_libs` and `sqlcipher_flutter_libs` are **both
absent from the graph entirely**. They left with `drift_flutter`. `pubspec.yaml` says so
explicitly — "dropping it also takes sqlite3_flutter_libs, sqlcipher_flutter_libs and the
transitive jni FFI plugin out of the graph. Native sqlite now comes from sqlite3 3.5.1's Dart build
hooks."

So the paragraph tells a reader that this build ships end-of-life native sqlite libraries. It does
not. And "revisit when the drift slice lands" is a trigger the note's own second sentence reports as
already fired ("The persistence work dropped it").

**The adversarial pair.** Two implementors picking up the persistence or packaging work:

- *Implementor V* reads the Stack section top to bottom. The heading note says the table is
  authoritative with exactly one known-stale row, and the paragraph below flags EOL native sqlite
  as an outstanding concern. V acts on the flagged concern the obvious way — pins
  `sqlite3_flutter_libs` to a non-EOL version and adds it to `pubspec.yaml`, since the app must get
  native sqlite from somewhere and the spine says the current source is EOL. The result is two
  native sqlite providers in one build: `sqlite3 3.5.1`'s Dart build hooks *and* the Flutter plugin's
  bundled library, which is a duplicate-symbol / wrong-library-wins failure that appears at runtime
  on some hosts and not others.
- *Implementor W* reads `pubspec.yaml` first, follows its instruction, and changes nothing.

Both obeyed a document that told them to. V's build is broken by the spine.

This is materially worse than the `drift_flutter` row itself, which is labelled, guarded by a
pubspec comment, and harmless if left alone. The paragraph is *not* labelled — the heading note
labels the row and mentions the paragraph only as something that "reasons from it", which reads as
"this paragraph's premise is stale" rather than "this paragraph's conclusion is false and acting on
it will break your build."

**Two aggravating factors.**

1. **No gate covers it.** The note cites `test/architecture/sidecar_pin_drift_test.dart` as the
   mechanical backstop, but that test covers only the two *citation* rows (Flutter and
   `claude_agent_sdk`) plus reader-function unit tests; `drift_flutter` appears in it only as a
   synthetic fixture proving the reader answers null for a missing row. No gate compares any other
   Stack row against `pubspec.yaml`/`pubspec.lock`. The "Re-verified 2026-08-14 … Every row matches
   the shipped dependency graph" claim is a hand check with a documented exception and no backstop,
   which is exactly how the next row rots unnoticed.
2. **"One known exception" undercounts.** `pubspec.yaml` flags a second divergence in its own words:
   `test: 1.31.0` is a direct dev dependency and "Not in the spine Stack table". Whether a dev
   dependency absent from a pin table counts as an "exception" is arguable, but pubspec itself
   frames it as a spine divergence, and the note's emphatic "**one** known exception" tells a reader
   to stop looking after the first.

**Hole to close.** Three edits, all small. (i) Delete or rewrite the EOL sentence — the packages are
gone; if the concern is now "native sqlite comes solely from `sqlite3 3.5.1`'s Dart build hooks and
that is a newer, less-travelled mechanism", say *that*, because it is true and it is the thing a
packaging story needs to know. (ii) Replace the expired "revisit when the drift slice lands" trigger
with the actual next decision point. (iii) Either add a gate that pins every non-citation Stack row
against `pubspec.yaml`, or downgrade the note's "every row matches" to what it is — a dated hand
check — so the next reader knows the table's authority is asserted, not enforced.

---

## A-7 (medium) — carried-open question (a) is left as it was; the residual, and one cross-product with (b) that is now easier to reach

**Asked: does the widening make (a) — `bindingChanges` and `bind()` being two paths into one piece
of state with no stated precedence — worse? No. It leaves it as it was.** Stated plainly because
that is a useful negative:

- The widening adds no new writer to `SettingsState.hotkeyBindOutcome`. The writers are the same
  three as before: `changeHotkey`, `applyStartupOutcome`, `_onBindingChanged`.
- AD-9 still pins the X11 adapter's `bindingChanges` to "an empty stream that closes", and
  `x11_global_hotkey.dart:93-94` ships exactly that. So the widening does not open a second channel
  on the adapter it newly brought under AD-12. The precedence question stays Wayland-only, exactly
  as wide as it was.

**The residual, unchanged and still real.** `applyStartupOutcome` is a guarded *seed* and documents
the hazard precisely ("the Wayland adapter subscribes to `ShortcutsChanged` inside `bind()`, so a
compositor-originated change can reach `bindingChanges` and land here before `bindHotkey`'s own
answer is handed over. Overwriting unconditionally would replace that newer fact with an older
one"). `changeHotkey` has no such guard: it `await`s `_bind`, then `await`s `_writeChange`, then
assigns `hotkeyBindOutcome: outcome` unconditionally (`settings_controller.dart:147-169`). A
`ShortcutsChanged` landing in that window is silently overwritten by the older bind answer, and
nothing emits again to correct it. One controller applies seed semantics and the other assignment
semantics to one field, which is the two-owners-of-one-entity shape this lens exists to name — it
is just not something this pass touched.

**One cross-product with (b) that the widening makes easier to reach.** On Wayland,
`_onBindingChanged` can land `HotkeyUnavailable("your desktop no longer holds this shortcut")` — a
genuine revocation, question (b)'s second meaning — and then `changeHotkey`'s trailing `_setState`
overwrites it with `_closeSessionBeforeRebinding`'s abandoned-rebind
`HotkeyBound(effective: null, authority: compositor)`. The user's shortcut is genuinely gone and the
surface says a shortcut is bound. Pre-existing, not created here; but A-2 established that the
widening enlarged the set of blessed routes into `HotkeyUnavailable` without adding any way to tell
them apart, which makes this class of overwrite harder to reason about from the spine than it was.

**Note also, for the record, an equality interaction with AD-9 worth one sentence in whichever AD
closes (a).** On Wayland every `HotkeyBound` is `HotkeyBound(HotkeyRegistration(effective: null,
authority: compositor))`, and AD-9 mandates value equality over exactly those fields with dedupe as
the stated justification. So every compositor-side rebind is `==` to every other and to the bind
answer. A consumer that dedupes — which AD-9's own rationale invites — collapses them all. Today
nothing visible is lost, because `HotkeyStatusView` renders one identical sentence either way; but
it means a precedence rule for (a) cannot be expressed as "prefer the newer value" and be checkable,
since newer and older are indistinguishable. Whatever closes (a) should say so, or the rule will be
unimplementable. **Low** on its own; recorded here rather than as its own finding.

---

## Lighter sweep elsewhere — nothing new

The unamended ADs were re-attacked for pair-construction at lower intensity. Nothing found that this
pass introduced or loosened:

- **AD-2 / AD-3 / AD-16 / AD-19** — the provider seam holds. AD-3's three rules jointly pin the
  event sequence, the delta semantics (incremental, not cumulative) and the authority of
  `CorrectionCompleted` over accumulated deltas; AD-16's per-adapter escape is scoped and does not
  reach AD-3. Two adapters built from these interoperate.
- **AD-7** — single-writer is stated explicitly ("`CorrectionController` is the **sole caller** of
  `CorrectionRepository.save`"), which is the shape A-2 and A-7 are missing elsewhere. The
  `suggestions[]`-onto-two-tables projection has one owner and one write.
- **AD-5 / AD-15 / AD-17** — provider selection has exactly one home, and AD-17 names the four parts
  and which half of the knowledge each holds. No second owner constructible.
- **AD-9's `bindingChanges` doc** — "Changes the **backend** originated — never an answer to a call
  this app made" is the right constraint and is what keeps the X11 adapter's empty stream honest
  rather than an unimplemented member.
- **The `(X11 hotkey)` annotation** in the envelope's runtime-dependency bullet is left standing and
  is now explicitly contradicted by the bullet below it ("The hardness is not X11-scoped"). A reader
  who skims the list and not the prose gets the wrong answer. **Low** — one parenthetical edit
  (`(X11 hotkey backend; required on every host — see below)`) retires it, and leaving a known-wrong
  annotation in place to be corrected two paragraphs later is a small instance of the same pattern
  A-6 flags at scale.

---

## Summary of holes to close

| # | Severity | AD | Hole |
| --- | --- | --- | --- |
| A-1 | critical | AD-12 R1 | Mandates `HotkeyUnavailable` for a refusal AD-10 requires be `HotkeyBound(previous)`; shipped X11 adapter contradicts the spine. Split "never throws" from "which value", and condition the value on whether anything is still in effect. |
| A-6 | critical | Stack | Pin-renegotiation paragraph asserts EOL native sqlite libs that are absent from `pubspec.lock`; its revisit trigger already fired. A reader acting on it double-links sqlite. |
| A-2 | high | AD-9 / AD-12 | Widening put AD-12's Rule in direct contradiction with the doc comment in AD-9's verbatim-fixed block ("No backend could bind at all"), making carried-open question (b) worse and newly self-contradictory. |
| A-3 | high | AD-12 R2 | Rule 1 widened, Rule 2 and the heading not: an any-backend premise with a portal-only rendering conclusion that the value space cannot support. |
| A-5 | high | AD-9 / envelope | "It rejoins the degrading set" is unsatisfiable under AD-9's and DW-39's "one file"; the loader hardness needs the pubspec dependency gone, which is three more files. |
| A-4 | medium | AD-12 R1 | Fourth enumerated refusal names a state `DisplayServer` makes unrepresentable; implementing it literally breaks AD-9's "two adapters". Enumeration also reads closed and is under-inclusive. |
| A-7 | medium | AD-10 / AD-13 | Question (a) left as it was (correctly reported as such); `changeHotkey` still assigns where `applyStartupOutcome` seeds, and AD-9's value equality will make any "prefer the newer" rule uncheckable on Wayland. |

**Two most important.** A-1, because the spine now instructs a wrong implementation whose failure
mode is a user-visible lie about a shortcut that is still firing. A-2, because the pass was told not
to resolve carried-open question (b) and instead made it worse in the one way that matters — the
document now defines `HotkeyUnavailable` two incompatible ways, in the block AD-9 declares fixed.

---

## Disposition — 2026-09-26

This records current source and the regenerated architecture; the original verdict above remains a 2026-08-14 finding. No native hotkey behavior was observed for this note.

| Finding | Status | Current evidence and limit |
| --- | --- | --- |
| A-1 | Accepted; source-level closure | AD-12 now separates the never-throw rule from value selection: `HotkeyUnavailable` only when nothing is held, `HotkeyBound(previous)` when a granted binding survives. `X11GlobalHotkey._refusedBeforeBackend` and `_abandonedRebind` implement that distinction (`lib/src/infrastructure/hotkey/x11_global_hotkey.dart`). |
| A-2 | Accepted in the spine; stale source comment remains | AD-9 now declares `HotkeyUnavailableCause { noBackend, keyRefused, revoked }`, and AD-12 uses the cause to choose the screen message. `lib/src/domain/hotkey/hotkey_bind_outcome.dart` implements the field, but its class comment still begins “No backend could bind a global hotkey,” which is false for `keyRefused` and `revoked`. The original field-shape ambiguity is closed; that comment needs correction. |
| A-3 | Accepted; source-level closure | AD-12 now calls for a neutral tray state and a cause-specific screen line, without inferring all failures are compositor-wide. `HotkeyStatusView._causeLine` switches on all three causes; `DaemonGraph._publishHotkeyStatus` passes status to the tray (`lib/src/ui/settings/hotkey_status_view.dart`, `lib/src/application/composition/daemon_graph.dart`). The separate tray-host absence remains deferred by AD-12. |
| A-4 | Still open as wording | `DisplayServer.fromEnvironment` still chooses X11 when no display-server variable identifies Wayland (`lib/src/infrastructure/hotkey/display_server.dart`). AD-12's illustrative list still calls “a session that identifies no display server” a refusal, though a wrong fallback guess is only discovered by the selected adapter's later bind result. Its list is now explicitly non-exhaustive, which closes the other half of this finding. |
| A-5 | Accepted; source-level closure | AD-9 and the Stack now name `X11KeyGrabRegistrar` over libX11 FFI and say the `hotkey_manager`/keybinder loader path was removed. `pubspec.yaml` no longer declares `hotkey_manager`; `linux/flutter/generated_plugins.cmake` has no hotkey-manager plugin. This is dependency inspection, not a fresh missing-library launch observation. |
| A-6 | Accepted; source-level closure | The Stack no longer lists `drift_flutter` or EOL native sqlite packages, includes `test`, and describes `sqlite3` build hooks. `pubspec.yaml` and `pubspec.lock` contain no `drift_flutter`, `sqlite3_flutter_libs`, or `sqlcipher_flutter_libs`. No new dependency gate was added. |
| A-7 | Accepted with a remaining timing risk | AD-9 now orders an observed `bindingChanges` event ahead of the in-flight `bind()` answer. `SettingsController.changeHotkey` stamps `_backendChangeGeneration` and preserves a newer outcome (`lib/src/application/settings_controller.dart`); `WaylandPortalGlobalHotkey._recordBindAnswer` avoids replacing a newer cached status. AD-9 Deferred still records an event/cache interleaving and the post-read-back subscription window; neither was reproduced on a compositor here. |

The earlier low-severity annotation and publication-date comments are historical: the hotkey-manager dependency they described no longer ships. This disposition does not refresh upstream release facts.

## Post-plan closure — 2026-09-26

**A-2's stale source comment is closed.** Commit `9514e54` changes `HotkeyUnavailable`'s class comment to “No global hotkey is held” (`lib/src/domain/hotkey/hotkey_bind_outcome.dart:83`), covering `noBackend`, `keyRefused`, and `revoked` without altering their fields. The prior A-2 row remains the record of the stale comment at the 02-22 commit point.

**A-4's phantom peer refusal is closed in the generated spine.** Commit `68eb358` updated the BMAD memlog and regenerated AD-12 (`ARCHITECTURE-SPINE.md:348`): absent session hints select the X11 fallback, and only a subsequent failed `XOpenDisplay` makes the bind report `noBackend`. `DisplayServer.fromEnvironment` remains total over X11 and Wayland (`lib/src/infrastructure/hotkey/display_server.dart:27-44`). The owner reports three focused reviewers passed and existing fallback tests passed 10/10. This establishes the source/contract relation; it is not a native display-server observation.
