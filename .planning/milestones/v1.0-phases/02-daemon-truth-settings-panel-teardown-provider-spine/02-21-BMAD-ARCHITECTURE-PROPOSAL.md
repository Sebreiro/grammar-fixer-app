# 02-21 BMAD architecture update proposal

The 19-AD `ARCHITECTURE-SPINE.md` remains unchanged. This is input for its
authorized `bmad-architecture` update workflow, after plan 02-19 finishes.
Append each accepted change to the architecture `.memlog.md`, then re-derive
the spine. Preserve all 19 AD identifiers and the domain dependency direction.

## Invariant corrections

- **AD-2 and AD-9:** State value equality for `Map` collections beside the
  existing `List` and `Set` rules. AD-9 must use the owner-ratified D-19
  non-`const` `HotkeyBinding` constructor that defensively copies modifiers.
  Carry the remaining Phase 1 handoffs exactly as listed in
  `02-AD9-RATIFICATION.md`: cached `current` status, required unavailability
  cause, Wayland localized description with nullable machine-readable
  effective binding, bind/change event precedence, and conditional AD-11
  host registration.
- **AD-8 and AD-18:** Replace the old toggle and “every show reseeds” snippets
  with the shipped distinction: dismissal ends a session; a new summon seeds
  from current readable plain-text clipboard; iconify and focus-return preserve
  the session and read no clipboard. The hotkey decision remains synchronous
  and does no I/O on the CAP-1 show path. Use
  `application/panel_controller.dart`, `application/correction_controller.dart`,
  and the updated CAP-2 decision in the product `.memlog.md` as evidence.
- **AD-10 and AD-11:** Submit a Wayland preference and persist a structured
  effective binding if one is reported (D-18). The current portal supplies a
  localized `trigger_description`, not a parseable binding, so Wayland
  `effective` remains null and the configured binding remains the restart
  seed. Present the description as compositor-authored status without
  inventing a machine-readable combination.
- **AD-15:** Keep transport, credentials, and vendor types out of
  `CorrectionProvider`. Make the narrow shipped exception for Settings model
  text and the infrastructure `SecretStore`/key-resolution edge, without
  implying that domain or UI owns provider transport. Record unknown provider
  id as a startup warning plus an unconfigured provider, never a failed
  startup or fallback (PROVIDER-03).

## Currency and seed

- **Runtime dependencies:** Name a StatusNotifier/AppIndicator host and its
  silent absence; correct the obsolete `hotkey_manager`/`libkeybinder`
  hard-dependency prose to the shipped X11 FFI registrar and its caught
  degradation. Confirm against `pubspec.yaml`, `linux/`, and
  `infrastructure/hotkey/x11_key_grab_registrar.dart`.
- **Stack:** Use the pinned Dart SDK in `pubspec.yaml` (`^3.12.2`) and remove
  the now-false EOL warning. Reconcile any other stack row against the pinned
  package manifest before re-derivation.
- **Structural Seed:** Compare every tracked `lib/src/**/*.dart` with the
  seed, add omitted shipped files, and keep the two prose-normative names
  `sidecar_protocol.dart` and `active_correction.dart` at their actual paths.
  The seed is a current file map, not a proposed implementation.
- **Source citations:** After regeneration, replace the two stale spine
  example citations in `default_app_config.dart` and
  `hotkey_key_catalogue.dart` with accurate current references or direct
  statements. This changes comments only.

## Review boundary

Review the generated diff against the product SPEC, D-16 through D-19,
`02-AD9-RATIFICATION.md`, and shipped source. Do not claim native compositor,
live endpoint, or keyring behavior was observed. Do not alter the history
schema, add tests or gates, or broaden the 19 ADs. This proposal does not
authorize direct edits to the frozen spine.
