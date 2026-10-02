# Quick task 261001-cfz — Provider settings

Gathered: 2026-10-01. Status: Ready for planning.

## Task boundary

Add API-key entry for the OpenAI-compatible provider and a single provider choice
with conditional settings. Additional provider implementations remain deferred.

## Locked decisions

- User: entered keys must be saved to the system keyring.
- User: keep inactive provider configurations and filter presets to the chosen provider.
- Keep one active preset/provider pair, stateless streaming and existing credential precedence.
- Do not write newly entered credentials to config, logs, or history.

## Implementation discretion

- Separate key saving from endpoint/model saving; blank input leaves the existing key alone.
- Configured provider choices activate a complete existing preset. First-time URL setup
  requires saving URL/model before activation; retain the current preset's prompt.
- Show keyring failures inline and leave a retryable draft. Key entry is masked and never
  prefilled from credential lookup. Existing source label remains visible.
- Run the workflow inline as required by the skill's Codex spawn restriction.

## Canonical references

- AGENTS.md, PLAN.md, SPEC.md and llm-provider-contract.md.
- Existing SettingsController mutation ownership and ConfigStore conflict retry.
- Existing SecretStore read-only port remains narrow; add an independent write port.
