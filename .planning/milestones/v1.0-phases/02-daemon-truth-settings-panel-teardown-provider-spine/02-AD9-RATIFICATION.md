# AD-9 ratification and generator input (D-19)

## Decision and provenance

The owner ratified the shipped Phase 1 plan 01-09 change on 2026-09-24 in
[`02-CONTEXT.md` decision D-19](02-CONTEXT.md): `HotkeyBinding` copies the
caller-supplied `modifiers` into an unmodifiable set, and its constructor is
no longer `const`. Preserve this behavior when regenerating AD-9 for ARCH-06.

This is distinct from the earlier answer recorded in
[`01-09-SUMMARY.md`](../01-hotkey-truth/01-09-SUMMARY.md) and
[`01-GATE-ANSWERS.md`](../01-hotkey-truth/01-GATE-ANSWERS.md): the orchestrator
selected `defensive-copy` on 2026-09-02 under the instruction to complete
Phase 1 unattended. That answer was explicitly **not human ratification**.
D-19 is the later owner decision that supplies the missing authority. Keep
both events visible in the generated record and ledger disposition; do not
rewrite the earlier provenance as though the owner made the 2026-09-02 choice.

## Exact AD-9 constructor reconciliation

The shipped declaration in `lib/src/domain/hotkey/hotkey_binding.dart` is:

```dart
final class HotkeyBinding {
  HotkeyBinding({required Set<HotkeyModifier> modifiers, required this.key})
    : modifiers = Set<HotkeyModifier>.unmodifiable(modifiers);

  final Set<HotkeyModifier> modifiers;
  final String key;
}
```

The frozen `ARCHITECTURE-SPINE.md` AD-9 block still says:

```dart
const HotkeyBinding({required this.modifiers, required this.key});
```

For the authorized generator in plan 02-21, replace that constructor line
with the shipped non-`const` constructor and initializer above. Keep the
`modifiers` and `key` fields and AD-9's unordered set equality/hash rule.
This is API hardening against a future caller retaining and mutating its set;
plan 01-09 identified no live defect. A `const` constructor cannot perform
the defensive `Set.unmodifiable` copy, so retaining `const` would contradict
the owner-ratified behavior.

This file is generator input only. The frozen architecture spine and the
shipped Dart implementation are not edited by plan 02-20.

## Phase 1 hand-off for Wave F

Use the append-only `deferred-work.md` Phase 1 ARCH-06 hand-off entries whose
`source_spec` values are `01-01-PLAN.md` and `01-10-PLAN.md`. The first was a
prediction; the second records shipped names, corrects the constructor
prediction, and is the operative source for the generator. Preserve both
entries' history. Alongside D-19's newly owner-ratified constructor, carry:

1. **Current status accessor (HOTKEY-06).** Add the synchronous,
   cached `HotkeyStatus? get current` to AD-9's `GlobalHotkey` member list.
   `HotkeyStatus` carries a non-null `HotkeyBindOutcome outcome` and a nullable
   `String backendDescription`. It is null before any backend request. This
   member was already human-ratified as `status-type` on 2026-09-01; D-19 does
   not re-decide it. Source: `global_hotkey.dart`, `hotkey_status.dart`.
2. **Unavailable cause (HOTKEY-08).** Add
   `HotkeyUnavailableCause { noBackend, keyRefused, revoked }` and change the
   AD-9 `HotkeyUnavailable` declaration to
   `const HotkeyUnavailable({required this.cause, required this.message});`.
   The cause is required with no default; retain `message`, and compare/hash
   both fields. This field-list edit was already human-ratified on
   2026-09-01 (plan 01-04). Source: `hotkey_bind_outcome.dart`.
3. **Effective binding and localized description (HOTKEY-03 / AD-10).** Keep
   `HotkeyRegistration`'s `effective` and `authority` fields exactly as
   declared. `effective` is the backend-reported combination when one can be
   read; it remains null on Wayland because the portal supplies no
   machine-readable combination. The compositor's localized
   `trigger_description` is carried as `HotkeyStatus.backendDescription`,
   displayed as the desktop's wording, and never parsed into an effective
   `HotkeyBinding`. This is part of the already-ratified status-type addition,
   not a third `HotkeyRegistration` field. Source: plan 01-06 and the Phase 1
   hand-off correction.
4. **Bind/change precedence.** Add the shipped port rule beside AD-9/AD-10:
   a `bindingChanges` event observed after `bind()` was issued supersedes
   that bind's answer, including a same-turn event. A consumer's listener
   observation establishes the order. Plan 01-08 added this rule in the port
   documentation; it changes no frozen field or constructor. Source:
   `global_hotkey.dart` and the Phase 1 hand-off correction.
5. **Conditional portal registration (AD-11).** Reconcile AD-11 step 1 with
   the shipped `PortalAppIdRegime`: an unsandboxed build calls
   `org.freedesktop.host.portal.Registry.Register` before the other portal
   calls; a sandboxed build skips that host registration. This follows the
   three-format packaging decision and is outside AD-9's declarations.
   Source: plan 01-05 and the same Phase 1 ledger hand-off.

The frozen spine's existing `HotkeyRegistration.effective` field must not be
presented as newly added. The only newly ratified item in this brief is the
non-`const` defensive-copy constructor (D-19); the other Phase 1 behavior
and decisions already have their own provenance. Plan 02-21 consumes this
list when it regenerates the spine and disposes the ledger debt.
