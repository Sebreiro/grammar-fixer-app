---
quick_id: 261001-cfz
mode: quick-full
status: planned
must_haves:
  - Entered API keys are masked and saved only to the system keyring.
  - Exactly one provider is selected through a complete preset and config persistence.
  - Only selected-provider fields and presets are visible; inactive configs survive.
  - Fresh installs can configure the URL provider through settings.
  - Failures remain inline and retryable; external config updates reach settings.
  - Analyzer and appropriate headless tests pass.
---

# API key in system keyring and exclusive AI provider settings

## Task 1 — Keyring storage and provider configuration

Files: domain/config/provider_key_writer.dart, domain/config/secret_write_result.dart,
infrastructure/correction/secret_service_provider_key_writer.dart,
application/settings_controller.dart, application/composition/daemon_graph.dart,
main.dart, settings_state.dart, integration and application tests.

Action: Add a narrow write port and Secret Service adapter using the existing item
attributes. Support replacement, unlock/create prompts, dismissal, timeout and cleanup.
Wire it at the composition root. Save keys as an independent serialized settings mutation;
report generic inline failure and return the save result for draft clearing/source refresh.
Provide first-time compatible-provider configuration and whole-preset provider switching.

Verify: private D-Bus round-trip read/write, replacement, failure/prompt/session cleanup;
controller fake tests prove no config write and serialized retryable failures.

Done: keyring-only persistence and provider configuration work through owned interfaces.

## Task 2 — Exclusive provider settings UI

Files: application/settings_state.dart, application/settings_controller.dart,
ui/settings/settings_screen.dart, provider_choice_list.dart,
compatible_provider_form.dart, api_key_field.dart, preset_choice_list.dart,
UI and controller/composition tests.

Action: Radio group for Claude and URL plus existing configured IDs. Resolve selected
provider through active preset. Filter presets and conditionally mount provider forms.
First-time URL selection opens setup; saving creates a full preset using entered model
and retained prompt, writes config and activates it. Extract existing field draft sync.
Masked key entry has its own save action; preserve drafts on failure, clear on success.

Verify: fresh setup, both radio directions, filtered presets, retained configs, failed
writes, disabled controls, external edits, key masking and successful clearing.

Done: user can configure and switch either existing provider, with one active pair.

## Task 3 — Verify and record

Files: quick SUMMARY/VERIFICATION/REVIEW, .planning/STATE.md.

Action: review diff, format Dart, run analyzer and configured headless suites plus new
integration tests; record exact outcomes and native keyring observation limits.

Verify: must_haves are covered by working code/tests; commit code tasks atomically and
commit planning/state documentation separately. Leave ROADMAP and frozen specs untouched.

Done: validated implementation with tracked completion and no unrelated changes.

## Coverage and threat model

External API coverage is limited to the explicitly requested Secret Service credential
write flow. Reads stay unchanged. Unlock, CreateItem(replace), SetSecret, prompts and cleanup are
covered; deleting credentials and managing collections are outside this task. Missing
default keyring produces actionable failure. No additional AI backend or protocol is built.

Secrets never enter config/history/logs, the entry is masked, and service failure never
falls back to plaintext storage. The writer closes its D-Bus client/session on all paths.

## Plan check

PASS (inline): all requested outcomes map to tasks and tests; source paths/seams are
confirmed; three tasks stay within scope; locked keyring/filtering decisions are honored.
