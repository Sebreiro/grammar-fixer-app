---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 16
subsystem: provider-credentials
tags: [dart, dbus, secret-service, keyring, config, privacy]
requires:
  - phase: 02-15
    provides: OpenAI-compatible transport with an adapter-edge optional key
  - phase: 02-14
    provides: bounded daemon teardown ownership
provides:
  - Read-only Secret Service provider-key lookup with absent and unavailable outcomes
  - Keyring, environment, then hand-placed config source precedence
  - Source-only Settings status and preservation of an existing hand-placed config key
affects: [02-17, 02-18, PROVIDER-02, D-17]
actuals:
  tokens: 4083
  tasks: 2
  commits: 3
commits: 3
plan_head_before: 6d321a355ebf2137fcdb9b3f3f6c6064de05e9ef
tech-stack:
  added: []
  patterns: [bounded read-only D-Bus session, source-only credential status, config-owned preservation]
key-files:
  created:
    - lib/src/domain/config/secret_store.dart
    - lib/src/infrastructure/correction/secret_service_secret_store.dart
    - lib/src/infrastructure/correction/api_key_resolver.dart
    - lib/src/infrastructure/correction/api_key_source.dart
    - lib/src/infrastructure/config/provider_secret_fields.dart
  modified:
    - lib/src/infrastructure/config/json_config_store.dart
    - test/architecture/hotkey_confinement_test.dart
    - test/infrastructure/config/json_config_store_test.dart
key-decisions:
  - Match a Secret Service item by application and provider attributes, read unlocked items only, and treat locked or unavailable service as a lookup miss.
  - Use OPENAI_API_KEY as the documented environment source; a local Ollama endpoint may have no key.
  - Preserve only an API key already read from config on later Settings writes, the explicit D-17 exception to the phase spec literal no-write criterion.
requirements-completed: [PROVIDER-02]
requirements-pending-global: [PROVIDER-02]
coverage:
  - id: D1
    description: A read-only Secret Service adapter distinguishes found, absent, and unavailable credentials while closing its session and bus connection.
    requirement: PROVIDER-02
    verification:
      - kind: other
        ref: dart analyze --fatal-infos and source inspection of secret_service_secret_store.dart
        status: pass
    human_judgment: true
    rationale: No unlocked gnome-keyring or KWallet session was available for a live lookup observation.
  - id: D2
    description: The selected compatible provider key resolves in keyring, environment, config order, and Settings can request its source without receiving the key text.
    requirement: PROVIDER-02
    verification:
      - kind: other
        ref: dart analyze --fatal-infos and source inspection of api_key_resolver.dart
        status: pass
    human_judgment: true
    rationale: Resolution is not wired to the selected provider and Settings until plan 02-18.
  - id: D3
    description: Config writes retain an existing hand-placed key without accepting a newly supplied key field from Settings.
    requirement: PROVIDER-02
    verification:
      - kind: other
        ref: Source inspection of JsonConfigStore._preserveHandPlacedKey and dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: D-17 explicitly waives the phase spec literal no-write criterion for preserving the hand-placed field; no direct persistence assertion was added under the scope restriction.
duration: 11min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 16: Secret Service and API Key Source Summary

**A bounded Secret Service reader and source resolver now select one credential by keyring, environment, then hand-placed config priority, while preserving only a user-authored config key on later saves.**

## Performance

- **Started:** 2026-09-24T17:56:50Z
- **Completed:** 2026-09-24T18:07:58Z
- **Duration:** 11 minutes
- **Tasks:** 2
- **Files changed:** 8

## Accomplishments

- Added a narrow `SecretStore` port. The D-Bus adapter uses `SearchItems`, a plain `OpenSession`, and `GetSecrets`; it does not prompt to unlock, create, or update an item. It closes the session and connection after each lookup and returns absent separately from locked or unavailable.
- Added `ApiKeyResolver` for `keyring → OPENAI_API_KEY → providers.openai-compatible.settings.apiKey`, plus a source-only Settings accessor and labels. A missing key remains valid for a selected local Ollama endpoint.
- Made `JsonConfigStore` retain an already loaded hand-placed key when saving Settings changes while rejecting a newly supplied key field. It never copies a keyring or environment key to config.

## Task Commits

1. **Task 1: Define a narrow read-only SecretStore port and adapter** — `7fec158` (`feat`).
2. **Task 2: Resolve exactly one winning source** — `3751a21` (`feat`).
3. **Existing assertion compatibility fix** — `16d60bb` (`test`).

## Verification

- `dart analyze --fatal-infos` passed after each task and after the assertion fix.
- The focused architecture and config suites passed: 38 tests.
- The existing full Dart suite passed: 982 passed, 2 pre-existing skips. The existing full Flutter suite passed: 165 passed, 7 pre-existing skips.
- The Secret Service lookup, Settings source display, and selected adapter injection are not observed end to end yet. Plan 02-18 wires the resolver into the provider and Settings. No live gnome-keyring, KWallet, OpenAI API, or local Ollama outcome was observed here; interoperability remains unobserved.
- D-17 preserves a hand-placed key in a whole-file rewrite. This is an explicit exception to the Phase 2 SPEC's literal no-write acceptance criterion. Strict compliance is not claimed.

## Decisions Made

- Identify a stored item with public `application=hotkey-grammar-corrector` and `provider=openai-compatible` attributes. Only an unlocked matching item is read; a locked item is not unlocked by the daemon.
- Keep the key string at the credential and adapter edge; Settings receives only `ApiKeySource` and its label.
- Treat an empty key as missing, allowing local Ollama to proceed without a bearer header.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Updated stale boundary assertions**
- **Found during:** Full Dart phase suite after Task 2.
- **Issue:** Two hotkey architecture assertions assumed the Wayland adapter was the only D-Bus user. The config repository assertion matched the new `ApiKeySource.configFile` name as though it opened `config.json`.
- **Fix:** Kept D-Bus confined to the Wayland and Secret Service infrastructure adapters, kept portal names in Wayland, and scanned for actual config path access.
- **Files modified:** `test/architecture/hotkey_confinement_test.dart`, `test/infrastructure/config/json_config_store_test.dart`.
- **Commit:** `16d60bb`.

## Issues Encountered

The first full Dart run stopped on the three obsolete source-scan assertions above. Focused tests and both full suites passed after the correction. No verified live target was available for secret-store or provider interoperability observation.

## Next Phase Readiness

Plan 02-17 can display the source label and preserve the key while editing provider settings. Plan 02-18 must inject the resolver into the selected adapter and Settings, then maintain cancellation and provider selection behavior. PROVIDER-02 remains pending globally until those integrations complete.

## Self-Check: PASSED

- All five created artifact paths and the summary file exist.
- Commits `7fec158`, `3751a21`, and `16d60bb` exist; the ledger measures three plan commits before metadata close-out.
- The changed-file stub scan found no placeholder, TODO, or FIXME markers.
