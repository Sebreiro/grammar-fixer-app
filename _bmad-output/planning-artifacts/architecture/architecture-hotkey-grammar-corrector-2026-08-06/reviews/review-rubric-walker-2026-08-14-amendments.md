# Rubric-walker review — ARCHITECTURE-SPINE.md, Update pass (three amendments)

- **Target:** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
- **Pass:** Update, 2026-08-14. Three amendments, per the run memlog's last three `(decision)` entries (`.memlog.md:95`, `:96`, `:97`).
- **Reviewed against:** the good-spine checklist; the shipped brownfield tree under `/workspace/lib/`; `pubspec.yaml` / `pubspec.lock`; the release bundle at `build/linux/x64/release/bundle/`; the vendored plugin sources in `~/.pub-cache`; the deferred-work ledger.
- **Diff basis:** `git diff HEAD` on the spine — 4 insertions, 3 deletions, in exactly three hunks. Nothing outside the three amendments moved.

## Verdict

**Pass with findings to carry.** All three amendments are factually accurate — I re-derived every measurable claim independently and each one holds — and all three are precisely scoped to what the pass was authorised to touch. The defect they share is not in what they assert but in what they left standing beside it: **AD-12's Rule was generalised from portal-only to every-adapter while the framing around the Rule stayed portal-shaped.** The heading and *Prevents* were frozen by instruction, so that half is a carry; but the same portal-era framing also leaked into the *new* second Rule bullet, which is not frozen and which the shipped tray and settings surfaces do not satisfy. Two high findings are fixable inside this pass's own new text; one is the instructed carry.

Mechanical invariants: **all pass, no breach.**

---

## Mechanical invariants

| Invariant | Result |
| --- | --- |
| Exactly 19 `### AD-` headings | **Pass** — 19. |
| Ids `AD-1`..`AD-19`, monotonic, none missing | **Pass** — lines 66, 73, 143, 151, 158, 164, 170, 202, 235, 302, 308, 321, 328, 334, 340, 354, 361, 373, 381. Strictly ascending, no gaps, no duplicates, no renumbering. |
| Exactly 13 `\| CAP-` rows | **Pass** — 13. |
| Capability text and *Governed by* columns unchanged | **Pass** — the diff touches no line in the Capability → Architecture Map. Verified by absence from `git diff HEAD`, not by eye. |
| `3.44.8` absent from the file | **Pass** — 0 occurrences. (It is present at `pubspec.yaml:9` as the `flutter:` constraint, which is exactly what the Stack note now discloses as a further hand-maintained copy. Consistent.) |
| `0.2.132` absent from the file | **Pass** — 0 occurrences. |
| `status: final` | **Pass** — line 8. |
| `updated: '2026-08-14'` | **Pass** — line 10. |

Incidental consistency check: frontmatter `binds` lists 13 capabilities (CAP-1..CAP-14 less CAP-6), matching the 13 map rows exactly. No drift.

---

## Amendment 1 — AD-12's Rule widened (`ARCHITECTURE-SPINE.md:325-326`)

### What the pass did

The single Rule bullet became two. The first now opens "**any** backend's refusal to hold the hotkey resolves to AD-9's `HotkeyUnavailable`, never an exception — `bind()` never throws and never rejects", then enumerates four refusals. The second carries the visible-degradation requirement, reworded into two branches. Heading, *Binds* and *Prevents* are byte-identical to HEAD, as required.

This closes the OPEN question carried from the previous pass (`reviews/review-rubric-walker-2026-08-14.md`, finding H-2), which correctly identified that the code obeyed an invariant the spine did not state.

### Is the widened Rule enforceable?

**Yes, but by construction and backstop rather than by gate — and the spine does not say so.**

The obligation "`bind()` never throws" is not mechanically checkable: no analyzer rule or architecture test can prove a `Future` never rejects. What makes it real in the shipped tree is a two-layer arrangement the spine never mentions:

1. **Structural per adapter.** Each adapter's `bind()` body ends in a single `catch (Object)`. `wayland_portal_global_hotkey.dart:356` documents this explicitly — "This arm is what makes the promise structural instead of a claim about the paths a reader happened to check". `x11_global_hotkey.dart` does the same.
2. **Caller-side backstops.** `DaemonStartup.requestBinding` (`lib/src/infrastructure/system/daemon_startup.dart:208-228`) and `SettingsController._bind` (`lib/src/application/settings_controller.dart:393-437`) each catch `Object` around the `bind()` call and synthesize a `HotkeyUnavailable`. `requestBinding` is deliberately a named static so the breach it absorbs is reachable by a test.

Contrast AD-1, which names its mechanism in a dedicated **Mechanism** line and explains why no analyzer route exists. AD-12 states an equally ungateable obligation with no mechanism line at all. `test/architecture/` contains nine gates; none covers AD-12.

This is a documentation gap rather than an enforceability failure — the arrangement is sound and shipped. But a reader adding the `dart:ffi` adapter AD-9 announces (DW-39) learns from the spine that they must not throw, and not that the way to guarantee it is a terminal `catch (Object)` plus the two backstops that already exist to absorb their mistake. **Low-severity; noted, see F-4's fix note.**

### Is the enumerated set complete against the shipped adapters?

**No.** See **F-4**. The leading "**any** backend's refusal" sentence rescues the Rule's *intent*, but "The refusals are:" reads as a closed list, and as a closed list it covers roughly half the shipped `HotkeyUnavailable` production sites while one of its four items is not a distinct refusal at all.

### The heading / *Prevents* mismatch

See **F-1**. This is the instructed carry and, in my judgement, the correct call — but it is also the *root cause* of F-2 and F-4 rather than an independent cosmetic issue, and the report below says why.

---

## Amendment 2 — the `libkeybinder-3.0-0` envelope clause (`ARCHITECTURE-SPINE.md:581`)

### Every claim independently re-verified

| Claim | Verification | Result |
| --- | --- | --- |
| `libkeybinder-3.0.so.0` is a `DT_NEEDED` of the plugin library | `readelf -d build/linux/x64/release/bundle/lib/libhotkey_manager_linux_plugin.so` | **Holds** — `NEEDED libkeybinder-3.0.so.0` present. |
| The executable does **not** carry it | `readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector` | **Holds** — 22 `NEEDED` entries, `libhotkey_manager_linux_plugin.so` among them, `libkeybinder` absent. The "chain is one hop" qualification is exact. |
| Registration is unconditional, no display-server guard | `linux/flutter/generated_plugin_registrant.cc:15-17` | **Holds** — `hotkey_manager_linux_plugin_register_with_registrar` called unconditionally in `fl_register_plugins`; no guard anywhere in the file. |
| Plugin version is `hotkey_manager_linux 0.2.0` | `pubspec.lock:310-316`; `~/.pub-cache/hosted/pub.dev/hotkey_manager_linux-0.2.0/` | **Holds** — transitive under the direct `hotkey_manager` pin. |

The conclusion the clause draws — that the whole chain resolves before `main()`, therefore before `DisplayServer.fromEnvironment` chooses an adapter, therefore a Wayland-only host that will never call keybinder still cannot start — follows from those four facts. **The envelope dimension is factually sound.**

### It is also correctly *bounded*, which is worth recording

I checked whether the clause overreaches, since "the plugin loads on every host" invites the stronger claim that keybinder is *initialised* on every host (which would require an X server and would make the clause false on a pure-Wayland session with no Xwayland). It does not overreach: `keybinder_init()` is called at **bind** time, inside the method-channel handler, at `~/.pub-cache/hosted/pub.dev/hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:95` — not at registration. So on a Wayland host the library is *loaded and never initialised*, and the clause claims exactly and only the load-time failure ("the dynamic loader fails before `main()` runs"). The prescription that follows — "Package it for every host, not just X11 ones" — is the right prescription for a load-time dependency. **No finding; the clause says precisely what the evidence supports.**

### Internal consistency

The clause explicitly names both of the two places that would mislead a reader — the `(X11 hotkey)` annotation in the bullet above it and AD-9/Stack's "bound here for the X11 adapter only" — and overrides them in prose rather than silently contradicting them. That is the right instinct and the memlog shows it was a deliberate choice. But the two misleading strings remain in place, one of them ~130 lines away. See **F-7** (low).

### Is the envelope dimension now *complete*?

Not quite, and the gap is the one the checklist most cares about. See **F-3**: the envelope's list of "runtime dependencies the app cannot supply itself" omits a StatusNotifier / AppIndicator host, and the tray's absence on a host-less session is the one dependency failure that is neither hard-blocking nor visibly degrading — it is *silent*, and it silently falsifies AD-12's fallback promise. That failure mode appears nowhere in the envelope, nowhere under Deferred, and nowhere in AD-12.

---

## Amendment 3 — the `## Stack` heading note (`ARCHITECTURE-SPINE.md:425`)

### Every claim independently re-verified

- **`drift_flutter 0.3.1` is no longer a dependency at all.** Holds. `grep drift_flutter pubspec.yaml pubspec.lock` returns exactly one hit: `pubspec.yaml:16`, inside the comment block.
- **`pubspec.yaml` addresses the divergence to this document by name and forbids re-adding.** Holds, and more forcefully than the note conveys. `pubspec.yaml:11-23` names `ARCHITECTURE-SPINE.md`, explains the removal, and ends "Do not re-add it to 'match the spine' — the divergence is recorded in the deferred-work ledger for the spine to absorb."
- **Ledger entry DW-94 owns the removal.** Holds — `_bmad-output/implementation-artifacts/deferred-work.md:61-69`.

### May a spine stamped `status: final` legitimately carry a row it labels stale?

**Yes, and this instance is a well-formed carry rather than an evasion.** Four things make it so, and I state them because the general answer is *no*:

1. **`final` is an editorial state, not a freshness warranty.** It means the decisions at this altitude are closed. The Stack table is the one section that is a *report on the world* rather than a decision, which is why it carries a verification date at all — and a dated report can be simultaneously final and known-stale in a named cell.
2. **The staleness is labelled at the point of reading**, in bold, in the section heading note, before the table. A reader cannot reach the row without passing the label.
3. **It cannot cause two units to diverge**, which is the checklist's actual test. The only harmful action available to a reader — re-adding the package to match the table — is blocked at the point of action by `pubspec.yaml`'s own counter-comment. The divergence is bidirectionally documented: the spine points at the ledger, the manifest points back at the spine. That is stronger than correcting the row silently would have been, because it also stops the *next* reader re-adding it.
4. **Ownership is named.** DW-94 is a real, open entry whose `reason:` matches the divergence.

**Caveat:** the carry is ungated. See **F-6** (low).

### Do the note and the pin-renegotiation paragraph read coherently together?

**Partly — and this is the real weakness of amendment 3.** See **F-5**. The note correctly flags the *row* as stale and correctly observes that the pin-renegotiation paragraph "reasons from it". What it does not say is that the paragraph's *conclusion* is now false on two counts, and DW-94 — which the note cites as the owner — spells both out. A reader who stops at the note and reads on to line 451 encounters what reads as a live, unresolved risk.

---

## Findings

### F-1 — AD-12's heading and *Prevents* now under-describe a Rule that governs every adapter (**high**, carry not fix)

`ARCHITECTURE-SPINE.md:321` (heading), `:324` (*Prevents*), against `:325` (widened Rule).

The heading reads "**A compositor with no portal backend degrades visibly**". *Prevents* reads "a crash or a silently dead hotkey on **wlroots compositors (Sway, Hyprland, Niri)**, which ship no GlobalShortcuts implementation — only GNOME and KDE do". Both are portal- and compositor-scoped. The Rule beneath them now governs an X11 grab refusal, a key the catalogue rejects before any backend is touched, and a mis-detected session — none of which involve a portal, a compositor backend, or wlroots.

This is not cosmetic, for two reasons.

**It is a discoverability defect that reintroduces the divergence the widening closed.** ADs are navigated by heading. An engineer implementing the `dart:ffi` keybinder registrar that AD-9 line 300 explicitly announces as coming ("**This changes when DW-39's `dart:ffi` keybinder registrar lands**"), looking for the rule that governs what their `bind()` does when `dlopen` fails or a keyval will not resolve, scans nineteen headings, sees one about compositors with no portal backend, and moves on. The Rule that governs them is inside it. The previous pass's finding H-2 was exactly "the code obeys an invariant the spine does not state"; the risk now is the narrower but same-shaped "the spine states an invariant under a sign that hides it".

**It breaks the checklist's own test instrument.** The rubric tests each Rule by asking whether it prevents its stated divergence. AD-12's Rule now prevents strictly *more* than its *Prevents* states, so *Prevents* can no longer be used to measure the Rule's completeness. That is not an abstract loss — it is the mechanism by which **F-4** happened. The four-item enumeration had nothing to be complete *against*, because the only statement of scope in the AD still describes wlroots. Freezing *Prevents* while generalising the Rule removed the one check that would have caught a short list.

**Reported as a carry, per instruction — the pass was forbidden the heading, *Binds* and *Prevents*.** Recording it here rather than fixing it is correct: a heading change is a cross-document concern (the Capability map, six code sites and three prior reviews cite AD-12 by number, though none by title).

**Smallest legal future fix**, for whoever is authorised:
- Heading → **"AD-12 — Any refusal to hold the hotkey degrades visibly"**. Drops "compositor" and "portal", keeps the verb and the adverb that carry the AD's meaning, and stays a one-line edit.
- *Prevents* → prepend one clause generalising the divergence, retaining the wlroots sentence verbatim as the worked example: *"a crash or a silently dead hotkey whenever any backend will not hold the combination — most visibly on wlroots compositors (Sway, Hyprland, Niri), which ship no GlobalShortcuts implementation …"*.
- *Binds* needs no change: CAP-1 and CAP-13 remain exactly right.

No renumbering, no new AD, no retirement, and nothing AD-12 forbade becomes permitted.

### F-2 — the new second Rule bullet's two-branch surfacing requirement is unsatisfiable by the shipped `TrayPort` and is contradicted by the shipped settings screen (**high**, fixable in this pass's own text)

`ARCHITECTURE-SPINE.md:326` (new text, not frozen), against `lib/src/domain/tray/tray_port.dart:14`, `lib/src/infrastructure/tray/tray_manager_tray.dart:71`, `lib/src/ui/settings/hotkey_status_view.dart:94-113`.

The new bullet requires: "the tray icon **and** settings screen render that state: on a compositor with no backend, that global hotkeys are unavailable *there*; otherwise the `HotkeyUnavailable` message names what was refused".

Both surfaces fail it, and in both cases **the code is right and the amended Rule is wrong.**

**The tray physically cannot implement either branch.** `TrayPort.setHotkeyUnavailable(bool unavailable)` takes a boolean and nothing else — no message crosses the port. The shipped adapter renders one fixed string for all cases: `_hotkeyUnavailableLabel = 'Global hotkey unavailable — use this menu to open the panel'` (`tray_manager_tray.dart:71-72`), plus a desaturated icon. It therefore cannot "name what was refused" in the *otherwise* branch, and it deliberately does not say "there"/"on this compositor" in the first branch. The neutral wording is correct — it is true in all four cases — but it is neither of the two branches the Rule now prescribes.

**The settings screen actively rejects the first branch as false.** `hotkey_status_view.dart:104-113` reasons this out at length and is worth quoting because it is the code refuting the Rule: "**Nothing is claimed about the desktop, either.** This state is reached from four different places and only one of them is a desktop with no global shortcuts at all. A single refused key label (`the key "Tab" is not one this build can register…`) comes back here from a *working* X11 backend, and a compositor dropping one shortcut (`your desktop no longer holds this shortcut…`) comes back here from a *working* portal — so a preamble reading 'global shortcuts are unavailable on this desktop' was false on both."

So the amendment carried the portal-era compositor framing forward into the widened Rule and thereby re-imported into AD-12 precisely the over-scoped claim the widening existed to remove. The first Rule bullet says the degradation arm is universal; the second immediately re-privileges the compositor case as the default thing to say about it. This is F-1's defect surfacing in text the pass *was* free to change.

Note the port doc carries a residue of the same over-scoping — `tray_port.dart:12-13` still says "the visible 'global hotkeys unavailable **on this compositor**' state (AD-12)" while the implementation is neutral. That is a code-side nit for the ledger, not a spine finding, but it shows the framing propagating.

**Fix** (one bullet, no other section affected): drop the two-branch split and require only that each surface state the degradation in terms true of the case at hand — *"the tray icon and settings screen both render that state: the tray with a fixed entry that names the menu as the way in, the settings screen with the `HotkeyUnavailable` message itself, which names what was refused. Neither surface claims anything about the desktop, because only one of the refusals is a desktop with no global shortcuts at all. The tray menu can still open the panel."* That is what ships, and it keeps the visible-degradation requirement fully intact.

### F-3 — the amendment strengthened AD-12's fallback promise to "in every one of those cases" while the tree records that fallback as unverifiable on a host-less session, and the envelope omits the dependency (**high**)

`ARCHITECTURE-SPINE.md:326` and `:580` (envelope dependency list), against `lib/main.dart:199-208`.

The old Rule ended "The tray menu can still open the panel, so the app remains usable." The new one ends "**so the app remains usable in every one of those cases**" — a universal quantifier added over a set the same amendment had just widened from two portal calls to every adapter.

`lib/main.dart:199-208` records, in the tree, that the promise is not established:

> "A session with no StatusNotifier host is **not** among them and never will be through this package: the Linux `set_icon` handler never checks `app_indicator_new`'s result and answers a bare `true` regardless (`tray_manager-0.5.3/linux/tray_manager_plugin.cc:118-129`), so `install()` resolves and this catch does not run. **That the indicator is silent on a host-less session is a real gap in AD-12's degradation story and is filed as deferred work**".

I verified the vendored plugin source: `~/.pub-cache/hosted/pub.dev/tray_manager-0.5.3/linux/tray_manager_plugin.cc:118-129` assigns `app_indicator_new(...)` with no null check and returns `fl_method_success_response_new(fl_value_new_bool(true))` unconditionally. The claim is exact.

The consequence is the worst shape a failure can take in this design. On a session with no StatusNotifier host the daemon starts, `install()` reports success, no tray appears, and if the hotkey also failed to bind there is **no way to reach the panel at all** — while AD-12, the AD whose entire purpose is that degradation be visible rather than silent, now asserts usability "in every one of those cases".

Two dimension-level gaps compound it:

- **The envelope's dependency list is incomplete.** Line 580 enumerates "runtime dependencies the app cannot supply itself": `libkeybinder-3.0-0`, `xdg-desktop-portal` plus a GNOME/KDE backend, Python 3.11+ with `claude_agent_sdk`, and the `claude` CLI. A StatusNotifier/AppIndicator host is equally a dependency the app cannot supply, and it is the *only* one whose absence is neither hard-blocking nor visibly degrading — the two categories line 581 partitions the list into. Amendment 2 sharpened that partition considerably; this omission is what stops it being exhaustive. The checklist singles out the operational envelope as the dimension most often left silent, and this is a silent corner of it.
- **It is not under Deferred either.** The Deferred section's six bullets do not mention it. `main.dart` says it "is filed as deferred work", so the ledger holds it — but a spine reader has no route to it from the spine.

**Fix** (two small edits, both in text this pass already owns):
1. Add a StatusNotifier/AppIndicator host to line 580's dependency list, and to line 581 note that it is the third category — a dependency whose absence is *silent* today, because `tray_manager 0.5.3` reports a successful install regardless (cite the plugin source and the ledger entry).
2. Soften the new Rule bullet's closer from "in every one of those cases" to a claim that holds — the tray menu is the way in *wherever a tray is present* — with a pointer to the filed gap. Losing the flourish costs nothing; keeping it makes a `final` spine guarantee something the tree says is untrue.

### F-4 — the enumerated refusal set is incomplete, and one of its four items is not a distinct refusal (**medium**)

`ARCHITECTURE-SPINE.md:325`, against `lib/src/infrastructure/hotkey/`.

"The refusals are:" reads as a closed list. As a closed list it is wrong in both directions.

**One listed item is not a refusal.** Item 4 — "a session that identifies no display server, where AD-9's X11 fallback may have guessed wrong" — has no corresponding production site, because no such session exists in the model. `DisplayServer.fromEnvironment` (`display_server.dart:19-35`) is total: it returns `x11` or `wayland` and never a third thing or an error. Its doc says only that "AD-12 makes a wrong guess a visible `HotkeyUnavailable`, not a crash" — i.e. a wrong guess surfaces *through* item 3 (the X11 grab the backend refuses). Item 4 is a **cause** of item 3, not a peer of it. The list is therefore three refusals presented as four, which makes it look more complete than it is.

**At least four real production paths are missing.** The Wayland adapter's own class doc (`wayland_portal_global_hotkey.dart:51-56`) enumerates the shipped set for that adapter alone — "an unparsable bus address, an absent session bus, an absent portal, a compositor with no GlobalShortcuts backend (every wlroots one), a dismissed dialog, a malformed reply, a discarded bind and a disposed adapter". Mapping those plus the X11 adapter against AD-12's three, these are not covered:

1. **An unreadable or absent `DBUS_SESSION_BUS_ADDRESS`.** Decided in the factory before any portal call (`wayland_portal_global_hotkey.dart:86-110`, surfacing at `:269` as `_unusableBusAddress`). `DBusClient.session()` raises `FormatException` for any value without a `transport:` prefix — including an empty string and the bare socket path people write by hand. Not item 1: `CreateSession` is never called. Not item 3 or 4: the session identified Wayland correctly. A dead or lost bus mid-session is the same category (`:247`, `:263`, `:948`, via `_recordDeadConnection`).
2. **A `BindShortcuts` that *succeeds* while discarding the shortcut.** The sharpest omission, because AD-12's word is "**fails**". `wayland_portal_global_hotkey.dart:21-29`: the response's `shortcuts` list is documented as possibly "the empty set", so "a portal that discards the request answers *successfully* with our shortcut missing. That is how GNOME reports a bind it dropped because the application id has no installed `.desktop` entry." This is not a hypothetical — it is GNOME's actual behaviour on the exact failure AD-11's step-3 read-back and its `.desktop` hard requirement exist to catch. The refusal AD-11 spends a paragraph on is the one AD-12's enumeration excludes by its choice of verb.
3. **A disposed adapter mid-bind.** `_shutDownDuringBind()` at `x11_global_hotkey.dart:302` and `wayland_portal_global_hotkey.dart:1061`, reached from four guarded points. Both carry the comment "**Not a refusal** by the session/portal, and worded so nobody goes looking for one" — so AD-12's framing ("any backend's *refusal* to hold the hotkey") excludes it by construction, while it is a shipped `HotkeyUnavailable`. Also in this shape: a refused *release* of the previous grab with nothing held (`x11_global_hotkey.dart:265`) — a refusal of a release, not of a bind.
4. **A compositor-originated drop, which does not come from `bind()` at all.** `_onShortcutsChanged` pushes `HotkeyUnavailable` onto `bindingChanges` (`wayland_portal_global_hotkey.dart:855-868`) when the compositor reports the session no longer holds the shortcut. AD-12's Rule is phrased wholly about `bind()` ("`bind()` never throws and never rejects") and never mentions `bindingChanges`, so a degradation arriving *after* a successful bind is outside the Rule's stated surface — even though AD-9:288 and the settings view both treat it as an AD-12 degradation. The Rule governs one of the port's two `HotkeyBindOutcome` channels.

Roughly half the shipped production sites therefore fall outside the enumeration. The leading "**any** backend's refusal" sentence keeps the *invariant* correct — nothing here is a licence to throw — so this is medium, not high. But the checklist asks whether the Rule prevents its stated divergence, and a new-adapter author checking their case against a list that reads closed will find three of their four real cases absent.

**Fix** (one bullet):
- Change "The refusals are:" to "**The refusals include:**", making the universal first sentence the contract and the list illustrative — the previous pass's finding H-2 recommended exactly the universal form, and the closed list is a narrowing of it.
- Add the three real omissions in a clause: a bus this build cannot reach or read, a bind the portal accepted and discarded (the missing-`.desktop` case AD-11 guards), and an adapter torn down mid-bind. Fold item 4 into item 3 as its cause, so the list stops double-counting.
- Extend the Rule's surface from `bind()` to "either channel of AD-9's port", so a compositor-side drop on `bindingChanges` is covered by the AD the code already cites for it.
- Optionally, add a short **Mechanism** line in AD-1's style, naming what makes the promise real — a terminal `catch (Object)` in each adapter, plus the `DaemonStartup.requestBinding` / `SettingsController._bind` backstops that absorb a breach — since no gate can check it and the DW-39 adapter's author will need to know.

### F-5 — the pin-renegotiation paragraph still presents a resolved, never-real risk as live (**medium**)

`ARCHITECTURE-SPINE.md:451` (untouched), against `:425` (new note), `pubspec.lock`, and `deferred-work.md:66-69`.

The paragraph closes: "Also noted: `drift_flutter 0.3.1` transitively resolves `sqlite3_flutter_libs 0.6.0+eol` / `sqlcipher_flutter_libs 0.7.0+eol` — end-of-life native sqlite builds; **revisit when the drift slice lands or at the next Stack review.**"

Three things are now wrong with that sentence, and the new note flags none of them:

1. **The packages are gone.** `grep 'sqlite3_flutter_libs\|sqlcipher\|jni' pubspec.lock` returns nothing. Native sqlite comes from `sqlite3 3.5.1`'s Dart build hooks (`pubspec.yaml:19-22`).
2. **The risk was never real.** DW-94's `note_on_the_closed_eol_item` (`deferred-work.md:69`): the `+eol` packages "**were never a live hazard** — deliberately empty tombstones published by drift's own author … they carry **no native code**. Native sqlite already came from `sqlite3 3.5.1`'s Dart build hooks either way."
3. **The revisit trigger has already fired.** "Revisit when the drift slice lands" — the drift slice is what landed and removed `drift_flutter`.

DW-94's `reason:` names this second half of the divergence in its own words: "and **the pin-renegotiation paragraph still describes the EOL transitive resolution as current**." So the ledger knows; the spine's new note describes the paragraph only as one that "reasons from" the stale row. Under-describing it that way leaves a reader who stops at the note — which is what a note that says "the table's status is now clear" invites — to meet an EOL warning at line 451 that reads live, act on it, and discover both that it is moot and that it was never real.

The severity is not the stale fact but the *live-sounding open risk* in a document stamped `final`. The row itself is labelled and inert; this paragraph is neither.

**Fix** (still inside amendment 3's own scope, and it does not touch the row or the paragraph's substance): extend the note's last sentence to say what the paragraph gets wrong, e.g. *"…because ledger entry **DW-94** owns its removal — and with it the pin-renegotiation paragraph below, whose closing EOL note is moot on both counts: those packages left the graph with `drift_flutter`, and DW-94 records they were empty tombstones carrying no native code in the first place."* Alternatively tag the sentence at line 451 with `— resolved, see DW-94`, which is a smaller edit but arguably touches text DW-94 owns.

### F-6 — the carry is ungated; so is the envelope's re-measure trigger (**low**)

Both amendments 2 and 3 rest on facts that will drift silently.

- **The `drift_flutter` carry depends on a comment nobody checks.** What makes the stale row harmless is `pubspec.yaml:11-23`'s counter-comment forbidding the re-add. Nothing asserts that comment survives. `test/architecture/sidecar_pin_drift_test.dart` covers the two *cited* rows only — and, per memlog `:90`, was hardened this run precisely because a cell can silently regain a second writable home. Delete the pubspec comment and the spine's stale row becomes silently authoritative again, with the failure landing on whoever next re-adds a package the tree deliberately dropped. A one-assertion gate — pubspec references the spine by name and does not depend on `drift_flutter` — would close it, and would be the natural companion to the gate that already exists next door.
- **"Re-measure when the plugin version moves" has no trigger.** `hotkey_manager_linux 0.2.0` is a *transitive* pin under the direct `hotkey_manager 0.2.3`, so it can move on a resolve of the parent without anyone editing a version this document names. The clause's whole evidential basis is version-scoped and its re-measure condition is invisible to CI.

Low because neither is wrong today — both were verified this run — and gate work is legitimately out of a documentation pass's scope. Recording them so the ledger can pick them up.

### F-7 — amendment 2's two misleading scopings are corrected in prose rather than in place (**low**)

`ARCHITECTURE-SPINE.md:580` (`(X11 hotkey)`) and `:449` (Stack's `hotkey_manager` note), against `:581`.

The clause names both and overrides them, which is honest. But the strings remain, and the reader most affected reads the wrong one. The envelope's bullet 2 is the dependency list — the thing a packager extracts — and it annotates `libkeybinder-3.0-0` as `(X11 hotkey)`. The correction lives in bullet 3, after a sentence about `readelf`. A packager who reads the list and stops ships an X11-only dependency and breaks every Wayland install, which is the exact outcome the amendment was written to prevent.

The Stack note at line 449 ("It is bound here for the X11 adapter only") is the same shape, ~130 lines from its correction, and in a section a reader consults for pins rather than for load semantics.

**Fix:** two parentheticals. Line 580 → `` `libkeybinder-3.0-0` (X11 hotkey — but loaded on every host; see below) ``. Line 449 → append *"…for the X11 adapter only, though the plugin is linked and loaded on every host regardless — see the operational envelope."* Prose correction at a distance is weaker than correction in place when the misleading string is the one a reader extracts.

---

## Lighter sweep of the rest

Per the Update-pass instruction, swept rather than walked. Nothing new surfaced beyond the findings above.

- **Divergence points for the level below.** The three the previous pass identified as fixed remain fixed. AD-2 and AD-9's equality clauses (memlog `:92`) close the collection-identity trap in both directions — contents-compared *and* hashed to match — which is the form that actually holds; `test/domain/value_equality_test.dart` exists. AD-16's per-adapter escape hatch keeps CAP-5 honest for a non-streaming provider. AD-19's kill-the-process-*group* rule remains the sharpest single invariant in the document.
- **Deferred.** Six bullets; none could let two units diverge. Each either has no consumer yet (second provider, migrations beyond v1), is genuinely below this altitude (panel visuals), or names the AD it will disturb (packaging → AD-11's `Registry.Register`, correctly flagged for the Flatpak sandbox case). The one thing missing from Deferred is F-3's tray-host gap, which belongs there or in the envelope.
- **Named tech verified-current.** `reviews/review-currency-check-2026-08-14.md` re-verified every row; I spot-confirmed the pins that matter to the amendments (`hotkey_manager 0.2.3` direct, `hotkey_manager_linux 0.2.0` transitive, `dbus 0.7.14`, `drift 2.34.3`, `sqlite3 3.5.1`) against `pubspec.lock`. `drift_flutter 0.3.1` is the one labelled exception, handled under F-5/F-6.
- **Ratifies rather than contradicts the brownfield tree.** Broadly yes, and unusually well — the spine and the code cite each other by AD number throughout, and the six sites memlog `:95` lists as citing AD-12 for non-portal refusals all check out. The two contradictions found are both inside amendment 1's new text (**F-2**, **F-3**), and in both the code is the party that is right.
- **Driving spec's capabilities.** All 13 bound capabilities map to an AD and a directory; the map's *Governed by* column is untouched this pass and still resolves. The CAP-12 per-display-server split remains ratified and flagged in "Ratified Divergence from the SPEC", with the `/bmad-spec` re-derivation still outstanding — a carry from earlier, not this pass.
- **Dimensions owned by this altitude.** Boundary rules (AD-1, AD-17), error model (AD-3, AD-12, the Errors convention row), concurrency and cancellation (AD-4), shared-data ownership (AD-7, AD-13), process topology (AD-14, AD-19), state mutation, naming, time, ids, logging (Consistency Conventions), and the operational envelope are all present and decided. No dimension is silent. The envelope has one silent *corner* — F-3 — rather than a silent dimension.

## Summary of findings

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| F-1 | high | AD-12's heading and *Prevents* under-describe a Rule now governing every adapter; the frozen *Prevents* is also why F-4's list went unchecked | **Carry** — heading/*Prevents* forbidden this pass; smallest legal fix given |
| F-2 | high | The new second Rule bullet's two-branch surfacing requirement is unsatisfiable by the bool-only `TrayPort` and is expressly rejected by the settings view as false on non-portal paths | Fixable — the bullet is this pass's own new text |
| F-3 | high | The Rule's new "in every one of those cases" guarantees a tray fallback the tree records as silently absent on a host-less session; the envelope omits the StatusNotifier dependency | Fixable — two small edits |
| F-4 | medium | The enumerated refusal set reads closed but omits ≥4 shipped paths (unreadable bus, a *successful* discarded bind, a disposed adapter, a `bindingChanges` drop) while item 4 duplicates item 3's cause | Fixable — one bullet |
| F-5 | medium | The untouched pin-renegotiation paragraph still reads as a live EOL risk that is both resolved and, per DW-94, never real; its revisit trigger has already fired | Fixable — one clause in the new note |
| F-6 | low | The `drift_flutter` carry and the envelope's re-measure trigger are both ungated | Ledger |
| F-7 | low | `(X11 hotkey)` and Stack's "X11 adapter only" corrected at a distance rather than in place | Fixable — two parentheticals |

## Disposition — 2026-09-26

The historical verdict and bundle measurements above remain dated 2026-08-14 observations. The current checks below are against the regenerated AD text and checked-in source only.

| Finding | Current disposition | Evidence and limit |
| --- | --- | --- |
| F-1, portal-shaped AD-12 title and *Prevents* | **Accepted, resolved.** | AD-12 now says “Any refusal to hold the hotkey degrades visibly” and its *Prevents* covers all backend paths, with wlroots as a worked example (`ARCHITECTURE-SPINE.md`, AD-12). |
| F-2, false two-branch presentation requirement | **Superseded; current wording mismatches remain open.** | AD-12 removed the old two-branch demand. The shipped tray now has both a startup boolean and later typed `setHotkeyStatus` path with cause-specific menu lines (`lib/src/domain/tray/tray_port.dart:23-33`; `lib/src/infrastructure/tray/tray_manager_tray.dart:134-181`). Settings renders three lines (`hotkey_status_view.dart:164-182`). AD-12's current surface Rule still describes only a neutral boolean tray and a message-plus-one-line Settings view. `TrayPort`'s boolean-setter comment still says “on this compositor,” although refusal can be per-key. Those current wordings remain to be reconciled. |
| F-3, unconditional tray fallback and missing host dependency | **Accepted, still open as an operational limit.** | AD-12 and the Operational envelope now identify the StatusNotifier/AppIndicator host and the `tray_manager` 0.5.3 silent-success behavior. `lib/main.dart:381-390` retains the source-level caveat. No native host-less session was observed here; the missing-host fallback is not claimed fixed. |
| F-4, closed and incomplete refusal list | **Accepted, resolved for the stated contract.** | AD-12 says refusals “include, and are not limited to” the listed paths, covers after-the-fact revocation in *Prevents*, and AD-9 routes compositor changes through `bindingChanges`. `DisplayServer.fromEnvironment` still chooses an X11 fallback rather than a third display-server state; AD-12 now ties a failed fallback bind to `noBackend`. |
| F-5, obsolete EOL warning | **Accepted, resolved.** | The Stack and pin-renegotiation text say `drift_flutter` and its old native sqlite transitive packages are removed; `pubspec.yaml` is the checked-in dependency authority. |
| F-6, ungated stale carry and plugin re-measure | **Superseded.** | The stale `drift_flutter` row and `hotkey_manager`/keybinder loader clause are gone. Their proposed gates no longer cover a shipped dependency. This is no claim that every remaining Stack fact has an automated gate. |
| F-7, misleading X11-only keybinder scope | **Superseded.** | The Stack and Operational envelope describe the current libX11 FFI registrar and explicitly say the old keybinder plugin chain no longer ships. |

### Closure follow-up — 2026-09-26

**F-2's later AD-12/`TrayPort` wording mismatch is resolved.** The generated AD-12 Rule now describes the startup boolean and later cause-specific tray status, plus Settings' cause/message/status lines (`606ba50`, `ARCHITECTURE-SPINE.md`, AD-12). `TrayPort.setHotkeyUnavailable` now calls its startup notice neutral and points to the later typed status (`89b4487`, `lib/src/domain/tray/tray_port.dart:23-33`). The `noBackend` UI and tray wording now describe unavailability to this app, rather than asserting desktop-wide incapacity (`21c26bd`, `hotkey_status_view.dart`, `tray_manager_tray.dart`, `hotkey_bind_outcome.dart`). These are source and document closures, not native observations.

**F-3 remains open as the documented host limit.** AD-12 and the Operational envelope still warn that a missing StatusNotifier host can leave the tray fallback silently absent. No host-less session was observed in this follow-up; the changed wording does not make that fallback reliable.
