# Research — API key config fallback

## Findings

- `SecretServiceSecretStore` models inaccessible, locked, dismissed, and timed-out writes as `SecretWriteResult.unavailable`; it already bounds prompts and cleans up sessions. Keep that adapter responsible only for Secret Service.
- A `ProviderKeyWriter` decorator in infrastructure can prefer keyring, then write through `ConfigStore`, without exposing secret field names to application/UI code or opening the file twice.
- `JsonConfigStore.write` currently strips newly supplied API keys and preserves only previously loaded keys. Remove that obsolete policy so the requested fallback can persist the immutable config value.
- `JsonConfigStore` already serializes operations, detects external changes with `ConfigWriteConflict`, uses atomic rename, creates private scratch files, and preserves stricter owner-only permissions. Reuse all of that.
- `ApiKeyResolver` already reads keyring, then environment, then config. Its read behavior needs no change.
- SettingsController reads the latest config when finishing key saves. Its external-config listener skips a config already rendered; explicitly notify the daemon when a key writer changed config, or the active provider would retain the old config until restart.
- The existing source label and plaintext notice show the winning credential source. Replace the field's keyring-only success sentence with destination-neutral success feedback.

## Implementation guidance

Keep config transformation pure and immutable. Re-derive from the latest current value after a bounded conflict retry. Catch expected failures at the credential boundary and return unavailable. Do not include key values or caught error payloads in logs or UI.

## Validation

Fake-port tests cover preferred writes, missing/throwing keyring, empty input, conflicts, config failure, and preservation. Real-file integration proves restart persistence, owner-only permissions, replacement, and immediate daemon config notification. Widget tests cover source/notice refresh, masked entry, clearing only after success, and retry after both destinations fail.

No new packages or external integration are needed; findings are based on the installed repository implementation.
