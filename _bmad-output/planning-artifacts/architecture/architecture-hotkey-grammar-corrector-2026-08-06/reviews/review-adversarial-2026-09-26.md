# Adversarial seams review — Architecture Spine, 2026-09-26

**Lens.** Put two independently built units one level below the spine at each shared boundary. If each can follow the written ADs yet disagree about a shared shape, owner, or state transition, the spine has not fixed that boundary. I also checked the updated claims against the shipped Dart tree and the product SPEC. This is a read-only review of source; no implementation or spine file was changed.

**Verdict: changes requested.** AD-2's event fields and AD-8's attributed visibility states now provide useful fixed vocabulary. AD-9/10 still split one Wayland fact across an event and a separate mutable cache; AD-11 leaves a signal gap; AD-18 does not order a late clipboard seed against a user's empty edit. More directly, AD-15's three-step provider promise and transport boundary disagree with the provider settings that ship. Three high, one medium, and two source-drift findings follow. The first four are architectural seams; the last two are direct spine/source conflicts to resolve while this gate is open.

## High — A1: AD-15 gives a provider-specific setting two incompatible owners

**Spine:** AD-15, lines 363–373, says HTTP fields and credentials stay behind infrastructure adapters, and a new provider integrates by exactly one adapter file, one config entry plus preset, and one registry entry, with no change to domain, application, or UI. AD-13, lines 351–355, makes Settings and config two synchronized surfaces. **SPEC:** lines 48–50 and 89–90 require switching providers from either surface and reaching every user-facing setting from both.

**Adversarial pair.** A provider implementor adds a local-model adapter with a required endpoint in its opaque `ProviderConfig.settings`, adds the preset, and registers its factory. That follows AD-15 exactly. A Settings implementor follows the existing Settings interface, which edits only the OpenAI-compatible provider's URL and model. The new endpoint can be set in JSON and the provider works, but the in-app surface cannot edit it. If the Settings implementor adds the endpoint editor, they must change UI/application (and likely the validation owner), which AD-15 expressly forbids. Both sides cannot satisfy AD-15's integration recipe and the SPEC's two-surface setting rule for the same provider.

**Shipped evidence:** `lib/src/ui/settings/settings_screen.dart:313–353` hardcodes the OpenAI-compatible section; `lib/src/application/settings_controller.dart:373–412` rejects any other active provider in `_withProviderSettings`; `lib/src/domain/config/provider_config.dart:17–38` knows the OpenAI provider id, `baseUrl` field, and `Uri` validation despite AD-15's transport boundary; `lib/src/infrastructure/config/json_config_store.dart:108–134` has a provider-id-specific credential rewrite. These are present source paths, not hypothetical future work. `ProviderRegistry` adds its adapter entry at `lib/src/infrastructure/correction/provider_registry.dart:21–43`, but that entry alone does not make the settings surface generic.

**Impact:** the next provider with editable transport settings forces a choice between an incomplete Settings surface and changes the spine calls a broken seam. The domain's URL validation also creates a direct dependency on one provider's HTTP vocabulary.

**Close the hole:** specify an owner and a provider-neutral settings descriptor/validation contract that Settings can render without importing adapter transport types, or narrow the three-step claim and explicitly list permitted Settings extensions. Keep the `CorrectionProvider` port itself text-in/stream-out as AGENTS.md requires. Reconcile the currently shipped OpenAI path with whichever rule is chosen.

## High — A2: AD-11 requires a period in which a compositor change can be lost

**Spine:** AD-11, lines 329–338, says to await `BindShortcuts` and read its shortcuts before subscribing to `ShortcutsChanged` in step 4. AD-9, lines 301–319, says the event stream and cached `current` let Settings reflect compositor-originated changes; AD-10, lines 323–327, requires that reflection. **SPEC:** CAP-12, lines 64–67, requires a compositor rebind to appear without restarting.

**Adversarial pair.** A Wayland adapter completes step 3, reads binding A, then follows step 4 and subscribes. A compositor changes the shortcut to B between the read-back and subscription. A Settings controller subscribes to `bindingChanges` and reads `current` exactly as AD-9/10 instruct. There was no listener for that signal, so it sees A indefinitely. Both units followed their assigned ADs; neither has a way to infer B. Subscribing first would contradict AD-11's prescribed order, and `current` cannot recover an event the adapter never saw.

**Shipped evidence:** the adapter awaits `_bindShortcut` at `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:466–467`, then starts `_listenForShortcutSignals` at lines 540–550; the `ShortcutsChanged` listener is constructed at lines 1206–1212. Its later `_readBackDescription` is conditional on a missing description (lines 544–550), so a successful read-back containing A does not close this race. `SettingsController` receives only the stream and cached status (`lib/src/application/settings_controller.dart:543–558,607–620`). No claim is made that this interleaving has been observed on a particular compositor; it is allowed by the written ordering.

**Impact:** CAP-12 can show a stale combination even though the portal accepted a rebind. This is most likely at initial bind or session recreation, where step-4 subscriptions do not already exist.

**Close the hole:** allow signal subscription before the final read-back, or require an unconditional reconciliation read after subscription and use it to update `current` and publish any difference. Specify the order that makes this race impossible while preserving session and sender filtering.

## High — A3: AD-9's change event cannot carry the Wayland display value it changed

**Spine:** AD-9, lines 289–308, defines `HotkeyStatus(outcome, backendDescription)` but `bindingChanges` emits only `HotkeyBindOutcome`. Line 317 makes two `HotkeyBound` values equal when their registrations are equal. AD-10, line 327, says the shipped Wayland adapter's `effective` is null and the localized `trigger_description` is the displayed combination. Thus two different compositor bindings can produce equal events with different display text.

**Adversarial pair.** A compliant adapter emits `HotkeyBound(HotkeyRegistration(effective: null, authority: compositor))` for a rebind from `Ctrl+Shift+G` to `Super+Space`, updates `current.backendDescription` to the new wording, and emits the same value shape on a later rebind. A consumer reasonably deduplicates the value-equal outcome stream, or handles an asynchronously delivered first outcome after the adapter's cache has advanced to a second description. In the former case the UI never updates; in the latter it temporarily pairs one event's outcome with another event's wording. AD-9 fixes neither an atomic payload nor a revision that lets the consumer join the two facts. The consumer must know an unwritten rule: every apparently identical outcome event is meaningful, and a separate cache read may be newer than that event.

**Shipped evidence:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:232–233` uses an asynchronous broadcast `StreamController<HotkeyBindOutcome>`; lines 1331–1368 assign `_backendDescription`, record `current`, and add only the outcome to the stream. `lib/src/application/settings_controller.dart:543–558` builds state from that outcome and a separate `_backendDescription()` call, which reads `_hotkey.current` at lines 607–620. The shipped controller currently does not deduplicate, but that is an implementation choice rather than a spine guarantee.

**Impact:** the type that is supposed to report a compositor-side rebind does not itself distinguish the rebind. A second consumer can obey the declared port yet show an old or mismatched CAP-12 label.

**Close the hole:** emit one immutable `HotkeyStatus` per backend change, including outcome and description, with `current` holding the same snapshot; alternatively add a monotonic revision and specify the join. Update the fixed AD-9 declaration and the event precedence rule together.

## Medium — A4: AD-18 does not say whether a pending clipboard seed may overwrite an empty user edit

**Spine:** AD-18, lines 397–402, requires clipboard seeding after show and requires the edited text to be the submitted text. **SPEC:** CAP-2, lines 26–28, promises a usable blank editor after an absent read, and CAP-3, lines 30–32, gives the user's edits priority over original clipboard content once modified. The asynchronous interval is not assigned an owner or ordering rule.

**Adversarial pair.** The visibility adapter emits `shown` immediately so CAP-1 stays fast. The clipboard adapter takes time to answer. In that interval the user types a draft and deletes it, deliberately leaving the editor empty. A controller that treats empty editor plus idle status as permission to seed writes the old clipboard text over that edit. A controller that tracks whether the user edited this session leaves it empty. Both seed after `shown` and both satisfy AD-18's literal timing rule, but only the second preserves CAP-3's user edit.

**Shipped evidence:** `CorrectionController.editText` writes text without an edit revision (`lib/src/application/correction_controller.dart:145–148`); `_beginSession` launches the read at lines 447–452; `_seedFromClipboard` decides with `editorText.isNotEmpty || status != idle` at lines 454–485 and writes the result at line 510. Typing and then deleting returns those guards to their initial values. Existing tests cover stale sessions and nonempty edits, but the text value is not evidence that no edit occurred.

**Impact:** a late clipboard read can replace a deliberate blank editor; a subsequent Correct would operate on content the user removed.

**Close the hole:** state that seeding is allowed only if the current session has had no user edit, even when the editor is empty. A session-scoped edit revision or untouched flag makes that rule testable.

## Source drift — D1 (medium): AD-12's exact unavailable layout is not what ships

AD-12, spine line 348, requires the settings screen to render `HotkeyUnavailable.message` verbatim and append **exactly one** line of its own. `lib/src/ui/settings/hotkey_status_view.dart:125–171` instead renders a cause-specific line, then the adapter message, then the ownership line. The cause line is useful and reflects the newly typed `HotkeyUnavailableCause`, but it is an additional screen-authored line and so violates the exact-count rule. Two Settings implementations following spine versus source render materially different guidance. Decide whether cause-specific guidance is part of the contract, then make spine and tests state the same count and wording ownership. This is a direct drift, not a claim that both layouts obey the current AD.

## Source drift — D2 (medium): AD-16's fixed output grammar has already changed

AD-16, spine lines 378–382, fixes **exactly three** tagged lines and says completion occurs on stream end. The checked-in shipped prompt at `lib/src/infrastructure/config/default_app_config.dart:23–38` requires **four** lines: the three tags followed by `RegisterTaggedStreamParser.endSentinel`. A new provider or fake implementing the spine's exact three-line grammar can be rejected by the shipped parser. This is a shared wire shape, so reconcile AD-16 with the current prompt/parser and state whether the sentinel is required or merely accepted. This observation is independent of the four primary seams above.

## Gate summary

| Tier | Finding | Boundary to fix |
| --- | --- | --- |
| High | A1 | Provider transport configuration and Settings ownership |
| High | A2 | Portal read-back versus signal subscription order |
| High | A3 | Atomic shape of compositor status and its change stream |
| Medium | A4 | Clipboard seed versus session edit ordering |
| Medium | D1 | AD-12 unavailable layout versus shipped UI |
| Medium | D2 | AD-16 tagged-line grammar versus shipped prompt |

AD-2's `Suggestion` and event fields, AD-8's four visibility states, and AD-18's dismissal/focus-loss distinction produced no additional counterexample in this pass. That narrower result does not waive the pending-read ordering in A4.
