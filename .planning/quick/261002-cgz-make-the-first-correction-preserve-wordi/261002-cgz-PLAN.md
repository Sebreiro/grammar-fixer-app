---
quick_id: 261002-cgz
mode: quick-full
execution: inline
status: planned
must_haves:
  truths:
    - Suggestion 1 preserves wording and tone while fixing grammar and unnatural phrasing.
    - Suggestion 2 is casual and suggestion 3 is concise, both preserving meaning.
    - Both shipped adapters apply the same rules to fresh and existing presets.
    - The panel labels and keys are Corrected/1, Casual/2, Short/3.
    - Streaming, cancellation, history identity, and prompt/model pairing remain compatible.
  artifacts:
    - lib/src/infrastructure/correction/shared/register_tagged_prompt.dart
    - lib/src/infrastructure/config/default_app_config.dart
    - lib/src/domain/correction/suggestion_register.dart
    - lib/src/ui/panel/suggestion_card.dart
  key_links:
    - Both adapter request paths compose the shared prompt.
    - Fresh configuration reuses the shared prompt contract.
    - Suggestion cards derive readable labels from stable register identities.
---

# Preserve wording, then casual, then short

## Task 1 — Set compatible prompt semantics

**files:** shared/register_tagged_prompt.dart; config/default_app_config.dart; their existing tests; both adapter request tests; integration/correction_prompt_config_flow_test.dart.
**action:** Require minimal grammar/native phrasing changes for FORMAL, a casual rewrite for CASUAL, and a concise meaning-preserving rewrite for SHORTER. Clarify that tags identify slots, and new variant requirements take precedence over conflicting legacy instructions. Reuse this contract in fresh defaults. Retain strict tags and END.
**verify:** Focused pure Dart prompt, defaults, both adapter, and prompt configuration flow tests.
**done:** New defaults and existing configured prompts yield the requested ordered variant instructions with unchanged model, saved prompt, and parser compatibility.

## Task 2 — Label the three panel suggestions

**files:** domain/correction/suggestion_register.dart; ui/panel/suggestion_card.dart; panel streaming/layout/selection-and-copy tests; integration/daemon_workflow_test.dart; README.md.
**action:** Add Corrected/Casual/Short labels while retaining formal/casual/shorter identities and order. Use labels consistently in headings, semantics, selection announcements, and copy tooltips. Update expectations and document the behavior.
**verify:** Panel widget suites and the daemon workflow integration test; dart format and dart analyze --fatal-infos.
**done:** The rendered panel exposes the requested labels and unchanged keys, selection, copy actions, and persisted identifiers.

## Full-mode plan check

Coverage, concrete file links, scope, and all task fields checked inline. Two focused tasks cover the explicit request. No required behavior remains ambiguous. No schema files or new external integrations are in scope.

<threat_model>
ASVS level 1; block high severity. Keep treating input as untrusted text rather than instructions; preserve format enforcement and sentinel validation; never log credentials or correction content. This task adds no permissions, transports, or storage paths.
</threat_model>

<assumption_delta_decision>
Primary identity: ordered suggestion slot. Decision: no-change. Presentation labels and requested tone change; stable stored register identities remain compatible with prior history.
</assumption_delta_decision>

## Limits

Provider-request tests prove which instructions are sent, not subjective model quality. Run the existing live smoke deliberately after changing the default prompt; report dependency or authentication limits accurately.
