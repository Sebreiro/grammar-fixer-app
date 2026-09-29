# Reviewer lens: adversarial seams — Update pass, 2026-08-14

**Question:** construct two units one level down that each obey every AD to the letter yet still build incompatibly. Every pair that survives is a hole.

**Target:** `ARCHITECTURE-SPINE.md` (updated 2026-08-14) — Design Paradigm intro + ROOT node, AD-2 equality Rule, AD-9 (`HotkeyBindOutcome`, `bindingChanges`, `bind()` return, serialization prose), AD-10, AD-17 four-part composition root, Stack citations, Structural Seed comment, Operational envelope, CAP-4 / CAP-11 map rows.

**Verdict:** the edits close the seams they set out to close — `bind()` no longer throws, equality is stated rather than left to taste, and `bindingChanges` gives AD-10's second half a home. But `bindingChanges` was added as a *member* without being specified as a *protocol*, and AD-17's four parts were stated without amending the three ADs that already named an owner for the same wiring. **Eleven pairs constructed; nine are live holes.** Two of them (H1, H6) are the kind that produce a working X11 build and a broken Wayland build from the same spine.

Grounding note: this lens judges the spine. Where `lib/` is cited it is only to show that a builder already hit the ambiguity and had to invent an answer the spine does not contain — which is the evidence the hole is real, not a hypothetical.

---

## HIGH

### H1 — `bindingChanges` and `bind()` are two mutation paths into one piece of state, with no precedence and no owner

**The pair.** Unit A is the Wayland adapter. Obeying AD-11 step 4 it subscribes to `ShortcutsChanged` inside `bind()` — it must, because the session handle only exists after `CreateSession`. Obeying AD-10 it republishes each signal on `bindingChanges`. Unit B is `SettingsController`, which obeying AD-10 "renders the `HotkeyRegistration` inside the returned `HotkeyBound`" and, obeying AD-9's new Rule, also listens to `bindingChanges` and renders what arrives.

Now the portal fires `ShortcutsChanged` *before* the `BindShortcuts` `Response` — entirely legal, and likely whenever the user dismisses the portal dialog with a different combination than `preferred_trigger`. Unit B receives the newer compositor fact on the stream, then receives the older `bind()` answer on the future, and assigns both. Unit B's author who writes "future wins, it is the authoritative answer to our own request" and Unit B's author who writes "stream wins, it is the later event" both obey every word of AD-9 and AD-10, and produce opposite UI.

**Why the spine cannot arbitrate.** AD-9 says `bindingChanges` carries changes "the backend originated — never an answer to a call this app made, which `bind` already gives". That is a statement about *provenance*, not about *time*. Nothing anywhere orders the two channels, and nothing names which of them owns the current `HotkeyRegistration`. This is precisely the "two owners of one entity" shape: the adapter holds the live truth, `SettingsState` holds a copy, and the spine names no single writer — while AD-13 does exactly that for config ("one `ConfigStore` … Every settings mutation goes through it") and AD-7 does it for history ("`CorrectionController` is the **sole caller**"). The hotkey registration is the third piece of long-lived state in this system and it is the only one with no named owner.

**Evidence the hole is live.** `/workspace/lib/src/application/settings_controller.dart:280-303` had to invent a first-writer-wins rule — `applyStartupOutcome` is documented as "A **seed**, not an assignment: it applies only while nothing is known yet", explicitly because "a compositor-originated change can reach `bindingChanges` and land here before `bindHotkey`'s own answer is handed over. Overwriting unconditionally would replace that newer fact with an older one, and nothing would emit again to correct it." That is a load-bearing invariant, discovered at implementation time, living only in a doc comment on one method of one controller. A second unit built against the spine will not reproduce it.

**Fix.** AD-9 or AD-10 must state the ordering rule, in one of two forms:
- *Adapter-owns-truth (preferred):* the adapter is the single writer. `bind()`'s future and `bindingChanges` are one totally-ordered sequence per adapter — an outcome is delivered on exactly one of them, never both, and the adapter never delivers a `bind()` answer that its own later signal has already superseded. Consumers apply what arrives, last write wins, and need no reconciliation logic.
- *Consumer-reconciles:* the spine states first-writer-wins (or a monotonic sequence number on `HotkeyBindOutcome`) and names `SettingsController` the sole holder of the current registration.

Either works. The spine currently implies neither.

### H2 — `HotkeyUnavailable` means two different things depending on which member it arrives on, and AD-12 defines only one of them

**The pair.** Unit A is the Wayland adapter. The portal session drops, or the app id stops resolving; obeying AD-12 ("a failed `CreateSession` or `BindShortcuts` resolves to a `HotkeyUnavailable` state, never an exception") and AD-9's typing of `bindingChanges` as `Stream<HotkeyBindOutcome>`, it emits `HotkeyUnavailable` on the stream. Unit B is the settings/tray surface. Obeying AD-10 ("a returned `HotkeyUnavailable` is rendered as AD-12's degradation") and AD-12 ("The tray icon and settings screen state that global hotkeys are unavailable **on this compositor**"), it renders permanent degradation and stops.

But the two are not the same fact. AD-12's `HotkeyUnavailable` is *structural* — this compositor ships no GlobalShortcuts backend, wlroots, nothing will ever work, do not retry. A `HotkeyUnavailable` arriving on `bindingChanges` is *situational* — we had a binding a moment ago and the desktop revoked it, or the user cleared it in GNOME Settings. The correct response to the first is "tell the user to use the tray menu forever". The correct response to the second is arguably "offer to rebind" and certainly not "this compositor does not support global hotkeys", which is a false statement the user can disprove by looking at their own settings panel.

Two units will diverge on whether a revocation is recoverable, and on whether the app attempts a rebind. Both obey the letter.

**Aggravating factor.** AD-9's own doc block on `HotkeyBindOutcome` says "What a **bind request** resolved to", and on `HotkeyUnavailable` says "**No backend could bind at all.**" Neither sentence describes a revocation. So the spine's prose says a value can only appear as the answer to a bind, while its type says the value flows on a stream that by construction never answers a bind. The type and the prose disagree.

**Evidence.** `/workspace/lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:819-865` already emits `HotkeyUnavailable` on `bindingChanges` for a vanished app id, with the reasoning ("The id is gone") living in a comment. Nothing in the spine sanctions or forbids it.

**Fix.** Either (a) state in AD-9 that `HotkeyUnavailable` on `bindingChanges` means *revocation of an existing binding* and is distinct from AD-12's structural unavailability — and give AD-12 a rule for which message the surfaces show in each case; or (b) add a third variant (`HotkeyRevoked`) so the sealed switch forces every consumer to decide. Option (b) is cheaper to enforce and matches the spine's own "Errors are modelled values" convention.

### H3 — AD-10's "republish `ShortcutsChanged`" contradicts AD-9's "never an answer to a call this app made"

**The pair.** Unit A reads AD-10 literally: "Subscribe to `ShortcutsChanged` and republish it on AD-9's `bindingChanges`." It republishes every signal. Unit B reads AD-9 literally: `bindingChanges` carries changes "the backend originated — **never** an answer to a call this app made, which `bind` already gives." It suppresses the signal that the portal emits as an echo of our own `BindShortcuts`, and republishes only unsolicited ones.

Both are conformant readings of the spine. They differ on every startup: Unit A emits one `bindingChanges` event per app-initiated bind, Unit B emits zero. A consumer written against Unit B's behaviour, that treats any `bindingChanges` arrival as "the user changed this outside the app" and (say) clears the pending-mutation flag or shows a toast, misfires on every single bind against Unit A.

This is not a subtle reading. Portals do emit `ShortcutsChanged` after a successful `BindShortcuts` on some backends; the echo case is the common case, not the exotic one. The spine gives two rules that answer it oppositely and does not say which governs.

**Fix.** AD-10's rule needs the qualifier AD-9 already implies: "republish `ShortcutsChanged` **that this app did not cause** on `bindingChanges`" — plus a word on how the adapter identifies its own echo (compare against the outcome `bind()` is about to return; suppress if equal, using the new value equality, which is exactly what the AD-9 equality Rule was added to make possible). Say that out loud; it is currently an inference across two ADs.

### H4 — a broadcast stream with no replay does not satisfy CAP-12's second half

**The pair.** Unit A is the adapter: `bindingChanges` is broadcast, per AD-9. Unit B is the settings screen, which per AD-17's ring rules is `ui/` over `application/`, and which — like every other screen in a tray daemon — is constructed when the user opens it and disposed when they close it.

The compositor rebind happens while settings is closed. A broadcast `StreamController` drops events with no listener. The user opens settings; Unit B subscribes, receives nothing, and per AD-10 renders "the `HotkeyRegistration` inside the returned `HotkeyBound`" — the one from the startup `bind()`, now wrong. CAP-12's requirement, quoted in AD-9's own Rule ("a rebind made in the compositor updates the UI"), fails, and every unit obeyed every AD.

Unit A's author could instead have used a replay/`BehaviorSubject`-shaped stream, or the adapter could expose a synchronous current-registration getter the way AD-8 does for `PanelVisibility.isVisible`. Nothing in the spine chooses. The two designs are not interchangeable to Unit B.

**Note the inconsistency with AD-8.** AD-8 solved the identical shape — a UI that needs current state plus a change feed — by pairing a **synchronous `isVisible` field** with a `changes` stream, and it says why ("Synchronous in-process mirror. Never an IPC query."). AD-9 shipped only the stream half. The asymmetry is unexplained and a builder cannot tell whether it is deliberate.

**Fix.** Give `GlobalHotkey` the AD-8 shape: a synchronous `HotkeyBindOutcome? get current` (or `HotkeyRegistration?`) alongside `bindingChanges`, and state in AD-10 that the settings screen renders `current`, not a remembered `bind()` return. This also dissolves half of H1 — a single synchronous holder inside the adapter is the single writer H1 asks for.

### H5 — AD-5 and AD-17 now name different owners for provider resolution, and AD-15 names a third

Three rules, unamended by the update, that assign the same wiring to three places:

- **AD-5:** "`main.dart` reads `AppConfig`, resolves the single active `(CorrectionProvider, Preset)` pair, and injects it."
- **AD-17 part 4:** "`infrastructure/correction/active_correction.dart` — AD-5's `(CorrectionProvider, Preset)` pair resolution."
- **AD-17 part 3:** `daemon_startup.dart` holds "the pre-Flutter startup order (AD-14 → AD-13 → AD-9 → **AD-5**)" — i.e. it also owns AD-5's step.
- **AD-15 step 3:** "register it in **the composition root's provider table** (a `Map<String, CorrectionProvider Function(ProviderConfig)>`)" — and the Structural Seed puts that at `infrastructure/correction/provider_registry.dart`, which AD-17's four parts never mention.

**The pair.** Unit A adds a second provider by following AD-5 and AD-15 — one file, one config entry, one line in `provider_registry.dart`, resolution in `main.dart`. Unit B adds it by following AD-17 — resolution in `active_correction.dart`, sequenced by `daemon_startup.dart`. Both claim the composition root. Merge them and there are two code paths that turn a `providerId` into a `CorrectionProvider`, and the "one active pair" AD-5 exists to guarantee has two constructors. Worse, AD-5's whole point — "Nothing below the composition root selects a provider" — becomes unverifiable, because the update moved two-thirds of the composition root *into* `infrastructure/`, where "below the composition root" and "inside infrastructure" are now the same directory.

**Fix.** AD-5's rule must be restated to defer to AD-17: "the composition root (AD-17) resolves the single active pair; part 4 is where the resolution lives and part 3 is where it is sequenced." And AD-17 must either absorb `provider_registry.dart` into part 4 or say explicitly that the registry is the lookup table part 4 consults. Right now part 4 and AD-15 step 3 describe the same map without acknowledging each other.

### H6 — teardown has two owners across a ring boundary AD-1 forbids crossing

**The rules.** AD-17 part 2: `daemon_graph.dart` (in `application/composition/`) "eagerly builds them and **owns controller dispose order**." AD-17 part 3: `daemon_lifecycle.dart` (in `infrastructure/system/`) is "**the runtime teardown order**." AD-1: `lib/src/application/**` never imports `lib/src/infrastructure/**`, and the ring table says infrastructure "Never imports: application, ui."

**The pair.** Unit A writes `daemon_lifecycle.dart` as the top-level teardown sequencer — it holds the adapters and the graph, and disposes in order. To dispose the controllers it must reach `daemon_graph`, i.e. infrastructure importing application: an AD-1 violation that `ad1_import_rule_test.dart` fails at the merge gate. Unit B writes `daemon_graph.dart` as the sequencer, but the graph has no handle on the adapters (they are constructed by `main.dart` and `daemon_startup.dart`, per parts 1 and 3), so it cannot order adapter teardown against controller teardown at all.

The escape is that `main.dart` sits "outside `lib/src/`, and so outside AD-1's ring gate" (AD-17's last Rule) and therefore must be the thing that calls both — but AD-17 part 1's list of `main.dart` responsibilities does not include teardown sequencing. It includes "the signal handlers", which is the *trigger* for teardown, and part 3 owns the *order*, and part 2 owns a *sub-order*. Three parts each hold a fragment of one sequence, and the spine never composes them.

**What breaks, concretely.** The order between "adapters torn down" and "controllers disposed" is undefined. Dispose the `GlobalHotkey` adapter first and `activations` / `bindingChanges` close under a `SettingsController` that is still subscribed — whose `onDone` (per H7 below) is itself unspecified. Dispose the controllers first and an in-flight `CorrectionController.save` (AD-7: one write, at the terminal event, in a transaction) can race a closed drift database. AD-4 names "daemon shutdown" as one of exactly three cancellation triggers but does not say who fires it or where in the teardown order it sits.

**Fix.** AD-17 needs one sentence naming the single teardown sequencer and the order across rings — e.g. "`main.dart` fires teardown on signal; `daemon_lifecycle.dart` holds the order and calls `daemon_graph`'s dispose (which owns controller order) **before** disposing adapters, so no controller outlives a port it is subscribed to." Whatever the answer, it must name one owner and one direction, and it must be consistent with AD-1's ring rule rather than tacitly relying on `main.dart`'s exemption without saying so.

---

## MEDIUM

### M1 — `activations` still has no subscription model, and the edit made the silence louder

AD-9's amended block states `bindingChanges` is "Broadcast." It states nothing about `activations`, one member above it. AD-4 states single-subscription for `correct()`. A builder applying the obvious inference (the spine says broadcast where it means broadcast) reads `activations` as single-subscription.

**The pair.** Unit A implements `activations` with a non-broadcast `StreamController`. Unit B is the daemon graph, which wires `PanelController` to it — and a debug/diagnostic surface, or a future "recent activations" panel, or simply `daemon_lifecycle`'s own shutdown listener, subscribes second and throws `Bad state: Stream has already been listened to` at runtime. There is no compile-time signal and no test that fails until two consumers coexist.

Second divergence in the same member: a hotkey press that arrives *during* startup, before the graph subscribes. Broadcast drops it; single-subscription buffers it. AD-9 promises "One event per press of the currently bound combination" — Unit A honours that literally by buffering, Unit B by dropping. CAP-1's 100 ms budget makes a buffered stale activation actively wrong (the panel appears seconds after the press), and a dropped one merely disappointing. The spine chooses neither.

Both current adapters in `lib/` chose broadcast, which is one author's consistency, not the spine's.

**Fix.** One clause on `activations`: "Broadcast. Presses that arrive before a subscriber exists are dropped — a stale activation is worse than a missed one under CAP-1."

### M2 — what it means for `bindingChanges` to close is defined for one adapter and undefined for the other

AD-9 says an adapter whose backend cannot originate a change "implements it as an empty stream that closes." So on X11 the stream is closed at subscription time: a listener's `onDone` fires immediately, at startup. The spine never says whether a *live* adapter's stream closes, or when — presumably at `dispose()`, but that is inference.

**The pair.** Unit A (settings controller) treats `onDone` on `bindingChanges` as "the hotkey subsystem is finished" and renders a terminal state, or cancels its own registration-tracking. On Wayland that is correct (it only fires at teardown). On X11 it fires one microtask after startup and the settings screen renders "hotkey subsystem gone" on a perfectly working X11 daemon. Unit B ignores `onDone` entirely and leaks a subscription past `dispose()`. Both obey AD-9.

The same closed-vs-never-closes asymmetry means a unit cannot use stream completion as a teardown barrier — which interacts directly with H6, where teardown ordering is already unowned.

**Fix.** State that `bindingChanges` closes only on `dispose()`, that the X11 empty-stream case is the degenerate instance of that (already closed because nothing can ever arrive), and that closure carries no meaning a consumer should render.

### M3 — value equality over a mutable, reference-held collection, with no hashCode ordering rule

AD-9's new Rule fixes the semantics of `HotkeyBinding.modifiers` for `==` — "compares as a **set**" — and stops there. Two gaps survive, both of which produce units that agree on `==` and disagree in practice:

**(a) hashCode is not constrained to be order-independent.** A unit implementing the Rule as written can reasonably write `int get hashCode => Object.hash(key, Object.hashAll(modifiers));`. `Object.hashAll` is order-*dependent*. So `HotkeyBinding(modifiers: {control, shift}, key: 'G')` and `HotkeyBinding(modifiers: {shift, control}, key: 'G')` are `==` but have different hash codes — a direct violation of the Dart hashCode contract, which nothing in the spine names. Unit A (the domain type) ships this; Unit B (a settings surface, or an adapter caching `Map<HotkeyBinding, Registration>`, or a `Set<HotkeyBinding>` used to dedupe) silently gets two entries for one combination. The bug is invisible in every equality test and appears only in hash containers.

The Rule went out of its way to specify set semantics for `==`. Specifying it for `==` and not for `hashCode` is worse than specifying neither, because it reads as complete.

**(b) the set is held by reference and is mutable.** `HotkeyBinding` has a `const` constructor storing whatever `Set` it is handed; `Set<HotkeyModifier>` is a mutable interface. Unit A (settings controller) builds a working set, passes it into a `HotkeyBinding`, stores the binding in `SettingsState`, then adds a modifier to *its own* set as the user toggles a checkbox. The binding inside the immutable state object silently changes. Worse, the Consistency Conventions' "Immutable state objects with `copyWith`" and AD-9's stated purpose for the equality ("a state comparing by identity cannot be deduped by any consumer") both now work *against* correctness: `copyWith` produces a new state whose binding is `==` to the old one — because both point at the same mutated set — so the dedupe suppresses the rebuild and the UI never updates.

**Fix.** AD-9's Rule needs two more clauses: `hashCode` over a set field must be order-independent (`Object.hashAll(sorted)`, an XOR fold, or a helper stated once); and `HotkeyBinding` takes an unmodifiable copy of `modifiers` at construction — or the field is typed as an unmodifiable set and the constructor documents that callers must not retain the argument. Note this forces a decision about the `const` constructor, which cannot defensively copy. That decision belongs in the spine, not in whichever unit hits it first.

*(AD-2's parallel Rule is clean by luck: none of `Suggestion`, `Preset`, `CorrectionFailed` has a collection field, and `CorrectionCompleted` — the one that does — deliberately keeps identity equality. The Rule as phrased would not have protected them if any of them grew a `List` field, so the same clause is worth adding there for durability.)*

### M4 — the diagram and the Structural Seed still describe a two-part composition root

The update restated AD-17 as four parts and updated `main.dart`'s seed comment, but not the two places that show the root's shape:

- The mermaid `ROOT` node reads `composition root — main.dart + application/composition` — parts 1 and 2 only. Parts 3 and 4 live in `infrastructure/`, and the graph's edges (`ROOT --> INF`) then say the composition root points *at* infrastructure while being partly *inside* it. A reader trying to place `daemon_startup.dart` on this diagram cannot.
- The Structural Seed's tree does not list `infrastructure/system/daemon_startup.dart`, `infrastructure/system/daemon_lifecycle.dart`, or `infrastructure/correction/active_correction.dart` — three of AD-17's four parts. It does list `provider_registry.dart`, which AD-17 does not mention (see H5).
- The Seed's `domain/hotkey/` lists only `hotkey_binding.dart` and `global_hotkey.dart # port + HotkeyRegistration + BindingAuthority`. AD-9's amended block declares `// domain/hotkey/hotkey_bind_outcome.dart` as its own file. A builder following the Seed puts `HotkeyBindOutcome` in `global_hotkey.dart`, contradicting AD-9's own path comment; a builder following AD-9 creates a file the Seed does not have.

**The pair** is mundane but real: two units place the same three-to-four types in different files, and every import path in every subsequent story diverges. The Seed exists precisely to prevent that.

Related, unresolved: the Consistency Conventions say "One public type per file", while AD-9's `hotkey_bind_outcome.dart` holds three public types (`HotkeyBindOutcome`, `HotkeyBound`, `HotkeyUnavailable`) and AD-2's `correction_event.dart` holds five. The Seed acknowledges the exception inline for `correction_event.dart` (`# sealed CorrectionEvent + CorrectionFailureKind`) and nowhere else. The exception — a sealed family is one file — should be stated in the convention rather than implied by two annotations.

### M5 — the Stack pins one half of one fact by citation and the other half by number

The new paragraph's argument is sound and precisely stated: "A number written here as well would be a second writable copy of one fact, free to disagree with the copy that actually ships." Applied to the Flutter row it works — `.github/workflows/ci.yml` really does hold `flutter-version: 3.44.8`, and `sidecar_pin_drift_test.dart` really does check the citation resolves and fails if the cell reverts to a bare version. Same for `claude_agent_sdk` → `assets/sidecar/requirements.txt` (`claude-agent-sdk==0.2.132`).

But the row directly beneath still reads `Dart SDK | 3.12.2`, and **the Dart SDK version is not an independent fact — it is determined by the Flutter version.** Flutter 3.44.8 ships exactly one Dart SDK. So the table now holds a citation to the one home of the toolchain, plus a hand-written number derived from that same home, free to disagree with it the moment anyone bumps `ci.yml`. That is the second writable copy the paragraph exists to eliminate, one row later.

This is not cosmetic here, because the "Pin renegotiation" paragraph's entire dependency-resolution argument rests on it: "build_runner ≥2.15.2 needs analyzer ≥13.3.0 → meta ^1.18.3 while **the Flutter SDK pins meta 1.18.0**". That constraint is a property of the cited Flutter version. If a future bump changes the bundled meta, the renegotiated `drift_dev` / `build_runner` pins in the table become wrong and nothing in the table records why or fails.

**The pair.** Unit A (a contributor bumping the toolchain) edits `ci.yml` as the citation instructs — "Change the toolchain here and nothing else needs editing," per ci.yml's own comment — and the Dart SDK row plus `pubspec.yaml`'s `sdk: ^3.12.2` now silently describe a different SDK than the build uses. Unit B (a builder setting up locally, who has no runner) reads `Dart SDK | 3.12.2` as the pin and installs a Flutter whose Dart is 3.12.2, which may not be 3.44.8.

**Fix.** Either cite the Dart SDK row the same way (`determined by the pinned Flutter — see .github/workflows/ci.yml`), or state explicitly that 3.12.2 is the *constraint floor* that `pubspec.yaml` declares (`^3.12.2`) rather than the pin, which is the honest reading and makes the two rows non-contradictory. The former is more consistent with the paragraph's own argument. Also worth extending `sidecar_pin_drift_test.dart` to assert the Dart row does not restate a bare version, since it already owns this class of check.

*(Secondary, low: the Flutter citation gives a builder no local install path — `ci.yml` is a CI artifact. A one-line note that `fvm`/`asdf` or the developer's own toolchain should match the cited version would close it. Not a two-unit divergence, so not scored.)*

### M6 — CAP-11's Governed-by omits the AD that actually rules copy behaviour

The updated CAP-11 row reads: `CAP-11 per-suggestion copy button | application/correction_controller.dart, ui/panel, domain/clipboard | **AD-6**`.

AD-6 governs register ordering and persistence by name. The rule that actually decides how a copy button behaves is **AD-18**'s third Rule: "the panel stays open after a copy and every variant remains copyable (CAP-14). Copying is never implicit in selection — selecting with 1/2/3 only highlights." That rule was added by the *previous* adversarial pass specifically because two units diverged on copy-vs-select, and CAP-11 — the row a panel author consults when building the copy button — does not point at it.

**The pair.** Unit A builds the copy button from CAP-11's row, finds AD-6, and implements copy-on-select (the defensible reading of "per-suggestion copy" plus AD-6's 1/2/3 key mapping). Unit B builds selection from CAP-14's row, finds AD-18, and implements highlight-only. The two collide on the same keystroke. The exact seam AD-18 was written to close reopens through a stale map row.

CAP-11 should read `AD-6, AD-18` at minimum, and arguably `AD-2` (it renders `Suggestion`).

---

## LOW

### L1 — CAP-5's "Lives in" path disagrees with the Seed and with AD-16's per-adapter rule

CAP-5's row cites `infrastructure/correction/register_tagged_stream_parser.dart` — top level, implying one shared parser. The Structural Seed puts it at `infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart`, and AD-16 is explicit that register-tagged output is "a **per-adapter** choice, not a system-wide one."

A unit following the map row builds a shared parser at the top of `infrastructure/correction/`, which is where AD-15's rule ("Nothing outside `infrastructure/correction/<provider>/` may name … a model id") stops applying and where a second provider will be tempted to reuse it — reintroducing exactly the system-wide wire-format assumption AD-16's second Rule forbids. Path-only fix; the row should match the Seed.

### L2 — `Default model | claude-sonnet-5` in the Stack reads as a compiled default

AD-15 forbids anything outside `infrastructure/correction/<provider>/` from naming a model id, and AD-5 says the model arrives bound to its prompt inside a `Preset` from config. A Stack row stating a default model, with no "in config" qualifier, invites a unit to hard-code it as a fallback constant. One clause (`shipped in the default config's preset`) closes it. Not a two-unit break on its own, and the AD-19 sidecar protocol example already shows the model arriving over the wire — hence low.

---

## Constructed and found closed

Recorded so a later pass does not re-litigate them.

- **Sealed-hierarchy equality across subclasses.** Attempted: `HotkeyBound` from unit A compares equal to a subclass instance from unit B, or unit B adds a subtype with an extra field that `==` ignores. Prevented by Dart's `final class` modifier on both variants — the spine's verbatim declaration uses `final class`, so the hierarchy is closed and no subtype can exist. Genuinely covered, and covered by the *declaration* rather than by prose, which is the stronger form.
- **`bindingChanges` broadcast vs AD-4's single-subscription rule.** Attempted: a builder reads AD-4's "single-subscription" as a system-wide stream convention and implements `bindingChanges` single-subscription. AD-4 scopes itself explicitly to `correct()` ("`correct()` returns a **single-subscription** stream") and ties the choice to a specific mechanism (cancellation as teardown signal, `onCancel` killing the child process). No contradiction. `activations` is the member that is actually unspecified — see M1.
- **`HotkeyBinding` serialization divergence between adapters.** Attempted: two adapters serialize `{control, shift} + 'G'` differently and a shared helper disagrees with both. AD-9's rewritten serialization prose is unusually good here — it names the exact file per adapter, states the probed GTK output (`<Shift><Control>g`), states the XDG form (`CTRL+SHIFT+g`), and explicitly forbids a Dart-side copy of the accelerator with the reason ("a copy would be a prediction used by nothing and free to drift"). It also flags the DW-39 condition under which this changes. Nothing to attack.
- **AD-19 sidecar protocol.** Attempted: two sidecar implementations disagree on framing or on what `done` means. Closed by the fixed protocol block plus the explicit "`{"type":"done"}` means the text stream ended, **not** that the correction succeeded" clause. Tight.
- **Operational envelope `libkeybinder` claim.** Attempted: a unit treats the missing library as a degradable dependency per AD-12 and writes a catch. The revised bullet states plainly that it is a `DT_NEEDED` entry, that the loader fails before `main()`, and that it is a packaging dependency "and only meanwhile" until DW-39. A unit cannot get this wrong from the text. Good edit.

---

## Where the update left the spine

The Update pass did real work: `bind()` returning a value instead of throwing removes a whole class of divergence, and the two equality Rules convert a taste question into a stated one. The pattern in what remains is consistent — **the update added members and parts without adding the protocols and ownership rules that make them composable.** `bindingChanges` is a member without a protocol (H1–H4, M2). AD-17's four parts are a partition without an owner map (H5, H6). Both equality Rules specify `==` and leave `hashCode` and mutability to the reader (M3). Three of the four surfaces that *show* the spine's shape — the mermaid ROOT node, the Structural Seed, the capability map — were not carried along (M4, M6, L1).

The two that matter most before any hotkey story is written are **H1** (name the single owner of the current registration and order the two channels) and **H6** (name the single teardown sequencer and its cross-ring direction). H2 and H3 are cheap to fix and each takes one clause. M3 will otherwise be found by whoever first puts a `HotkeyBinding` in a `Map`.

---

## Disposition — 2026-09-26

The original review remains above. These statuses compare its claims with the regenerated spine and checked-in source, not a new native runtime pass.

| Finding | Status | Current anchor and limit |
| --- | --- | --- |
| H1 | Accepted; source-level closure | AD-9 now orders a post-issue `bindingChanges` event ahead of a bind answer and provides a synchronous `current` cache. `SettingsController.changeHotkey` uses `_backendChangeGeneration`; `WaylandPortalGlobalHotkey._recordBindAnswer` protects its cache (`lib/src/application/settings_controller.dart`, `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`). AD-9 still defers event/cache interleaving. |
| H2 | Accepted; source-level closure | AD-9 adds `HotkeyUnavailableCause` and AD-12 renders `noBackend`, `keyRefused`, and `revoked` separately. `hotkey_bind_outcome.dart` carries the enum; `HotkeyStatusView._causeLine` switches on it. The old “No backend could bind” source comment remains stale. |
| H3 | Still open as a protocol distinction | AD-9 still says `bindingChanges` carries backend-originated changes, never a call answer; AD-10 says `ShortcutsChanged` feeds it. `WaylandPortalGlobalHotkey._onShortcutsChanged` publishes each readable held-shortcut signal without an explicit app-bind echo filter. The controller's generation rule handles ordering, but the spine does not say whether a portal echo counts as a separate backend change. |
| H4 | Accepted; source-level closure | AD-9 adds a synchronous `GlobalHotkey.current` cache. Both adapters maintain it; the resident `SettingsController` subscribes before startup binding and retains outcome state for a later-mounted screen, while reading `current` for backend description and rebind reconciliation. A post-read-back/pre-subscription Wayland signal can still be missed, explicitly deferred by AD-11. |
| H5 | Accepted | AD-5 names `active_correction.dart` as pair resolver; AD-17 assigns startup sequencing to `DaemonStartup` and the registry stays the AD-15 lookup table. `ActiveCorrection.resolve` is the single pair-resolution call in source. |
| H6 | Accepted; source-level closure | AD-17 assigns controller dispose order to `DaemonGraph` and runtime teardown order to `DaemonLifecycle`, reached by `main.dart` callbacks. `DaemonGraph.disposeControllers` drains the correction controller before the other controllers; the lifecycle composes the outer order (`lib/src/application/composition/daemon_graph.dart`, `lib/src/infrastructure/system/daemon_lifecycle.dart`). |
| M1 | Still open in the spine | The current X11 and Wayland adapters construct broadcast activation controllers (`lib/src/infrastructure/hotkey/x11_global_hotkey.dart`, `wayland_portal_global_hotkey.dart`), but AD-9's `activations` declaration still does not specify subscription/replay semantics. No stale-activation runtime claim is made. |
| M2 | Still open in the spine | AD-9 says X11's empty `bindingChanges` closes; the Wayland adapter closes its stream during `dispose()`. AD-9 still gives no consumer-facing rule about completion meaning, although `SettingsController` cancels its subscription at disposal. |
| M3 | Accepted | AD-9 now requires unordered set hashing and a non-`const` defensive copy, owner-ratified by D-19. `HotkeyBinding` calls `Set.unmodifiable` and `setHash` (`lib/src/domain/hotkey/hotkey_binding.dart`); AD-2 also states collection equality/hash requirements. |
| M4 | Accepted for paths; convention gap open | AD-17's four-part root and the Structural Seed now name the current files, including `hotkey_bind_outcome.dart`. The Consistency Conventions still say “one public type per file” without the sealed-family exception used by `correction_event.dart` and `hotkey_bind_outcome.dart`. |
| M5 | Accepted | The Stack labels `^3.12.2` as the `pubspec.yaml` Dart constraint floor rather than a separate SDK pin; Flutter's CI pin is cited at its executable home. |
| M6 | Accepted | The CAP-11 map row now cites AD-6 and AD-18; `CorrectionController.selectSuggestion` and `copySuggestion` remain separate actions. |
| L1 | Accepted | The CAP-5 map row points to the current `infrastructure/correction/shared/register_tagged_stream_parser.dart`, and AD-16 limits tagged output to adapters using it. |
| L2 | Still open as label ambiguity | The Stack still labels `claude-sonnet-5` “Default model” without “in config.” AD-5 and `default_app_config.dart` make the actual ownership clear, but the row alone can still read as a compiled fallback. |

The review's failed attacks against sealed variants and the sidecar protocol remain historical observations. No new test or gate was added here.

## Post-plan closure — 2026-09-26

**H2's stale source-comment residue is closed.** Commit `9514e54` now describes `HotkeyUnavailable` as “No global hotkey is held” (`lib/src/domain/hotkey/hotkey_bind_outcome.dart:83`), which is valid for all three causes. AD-9 already carries the cause field and AD-12 renders it; the earlier H2 row preserves the source state at the 02-22 commit point. The owner reports analyzer clean and the existing settings widget suite passed 20/20; no native compositor behavior was observed for this closure.
