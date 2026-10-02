---
status: passed
depth: quick
---

# Code review — 261001-cfz

Reviewed inline under the Codex spawn restriction. Scope: this quick task's source
and tests, including its new files. No outstanding blocker or security finding.

## Findings fixed before completion

- Existing Secret Service lookup searches every collection; creating only in the
  default collection could leave an older matching key eligible for lookup. Search
  first and replace matching items with SetSecret. A private-bus test covers this.
- Endpoint saves and key saves need distinct mutation identities so a successful
  endpoint change cannot retire a failed keyring save. A controller test covers it.
- Source-label refresh must not delay draft clearing or erase a newly typed draft.
  Refresh runs independently and clearing checks the submitted draft.
- Prompt timeout/invalid signals must dismiss unfinished prompts and release the
  subscription. Cleanup has its own bounds and cannot leak vendor errors.

## Reviewed constraints

- CorrectionProvider, stateless streaming, cancellation and suggestion/history schema unchanged.
- One active pair remains derived from activePresetId; no fallback or backend race added.
- New credentials reach only ProviderKeyWriter and Secret Service; no config/log/history writes.
- Settings use the existing controller mutation owner and config conflict retry.
- URL/model drafts follow external edits without overwriting an in-progress edit.
- Additional provider implementations remain out of scope.

## Evidence limits

Private D-Bus tests exercise the real protocol adapter. Actual GNOME/KWallet UI and
unlock prompts have not been observed on a desktop in this environment.
