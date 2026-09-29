# External Integrations

**Analysis Date:** 2026-08-30

## APIs & External Services

**Claude AI (via Agent SDK):**
- Claude API - AI-powered English grammar correction
  - SDK/Client: `claude-agent-sdk==0.2.132` (Python)
  - Model: `claude-sonnet-5` (shipped default, configurable per preset in `DefaultAppConfig.shippedModel`)
  - Implementation: Python sidecar launched as subprocess
  - Communication: JSON-lines over stdin/stdout
  - Location: `lib/src/infrastructure/correction/claude_agent_sdk/`
  - Auth: API key managed by `claude-agent-sdk` (not exposed to Dart app)

**Anthropic Claude Python SDK:**
- Package: `claude-agent-sdk==0.2.132` pinned in `assets/sidecar/requirements.txt`
- Installed into: `.venv-sidecar/` (Python virtual environment, untracked)
- Provisioning: `tool/provision_sidecar.sh` verifies installation and pin matches
- Entry point: Sidecar script (path resolved by `DefaultAppConfig.sidecarPath()`)
- Verification test: `test/architecture/sidecar_pin_drift_test.dart` ensures pins stay in sync

## Data Storage

**Databases:**
- SQLite3 3.5.1
  - Purpose: Correction history persistence (CAP-7)
  - Connection: `NativeDatabase.createInBackground()` from Drift
  - Client: Drift 2.34.3 ORM
  - Schema: `lib/src/infrastructure/persistence/history.drift` (Drift declarative SQL)
  - Location: Platform-specific via `AppPaths.fromEnvironment()` (typically `~/.cache/hotkey_grammar_corrector/` or similar XDG path)
  - Opened: `AppDatabase.file(File file)` in `lib/src/infrastructure/persistence/app_database.dart`
  - Schema version: 1 (tracked in `AppDatabase.schemaVersion`)
  - Foreign keys: Enabled via `PRAGMA foreign_keys = ON` in migration strategy
  - Tables (AD-7): Two tables with one index, schema in `history.drift`

**File Storage:**
- Configuration file (JSON): Platform-specific location via `AppPaths.fromEnvironment()`
  - Readable/writable by `JsonConfigStore`
  - Contains: correction presets, hotkey bindings, provider settings
  - Generated on first run with defaults from `DefaultAppConfig.build()`

**Assets:**
- Tray icons: `assets/tray/` - bundled with app binary
- Sidecar script: `assets/sidecar/` - Python requirements and entry point
- Both shipped as Flutter assets bundle in `data/flutter_assets/`

**Caching:**
- None - all corrections are stateless; each runs in fresh sidecar process

## Authentication & Identity

**Auth Provider:**
- Custom - No user authentication
- Claude API key: Managed entirely by `claude-agent-sdk` Python package
  - Key resolution: Environment variables (`ANTHROPIC_API_KEY` by convention)
  - Not exposed to Dart layer
  - Sidecar handles auth failures internally, reports as `CorrectionFailureKind.providerError`

**Authorization:**
- File access: Standard Linux file permissions (user home directory)
- D-Bus: System D-Bus for Wayland portal access (no explicit auth needed)

## Monitoring & Observability

**Error Tracking:**
- None - application-managed error handling
- Errors logged to stderr via `Logger` port
- Error categories defined in `lib/src/domain/correction/correction_event.dart` as `CorrectionFailureKind`

**Logs:**
- Destination: stderr (structured logging)
- Implementation: `StderrLogger` in `lib/src/infrastructure/system/stderr_logger.dart`
- Rotation: Handled by system log manager (systemd journal when autostarted)
- Sensitive data: Never logged (text input/suggestions excluded per Logger port contract)
- Parser errors: Sidecar stderr forwarded to daemon log with warning level
- Sidecar process lifecycle: Spawned/reaped events logged

## CI/CD & Deployment

**Hosting:**
- None - standalone Linux desktop daemon
- Distributed as: Single-file executable + data assets
- Installation: XDG autostart entry (`linux/packaging/autostart/`) for session startup

**CI Pipeline:**
- GitHub Actions (`.github/workflows/ci.yml`)
- Trigger: Push to `main`, pull requests, manual `workflow_dispatch`
- Status: Never executed (no GitHub runner in dev environment)
- Merge gate requirements:
  - `dart analyze --fatal-infos` passes (zero INFO/WARNING/ERROR)
  - `dart test --exclude-tags=live` passes (unit/integration/architecture tests only)
  - Sidecar provisioning succeeds (`tool/provision_sidecar.sh`)
- Excluded from gate: `flutter test` (slower), `test/composition/` (needs Flutter), live smoke tests

**Build Commands:**
- `flutter pub get` - Fetch dependencies
- `dart analyze --fatal-infos` - Static analysis (merge gate)
- `dart test --exclude-tags=live test/...` - Run binding-free test suites
- `tool/provision_sidecar.sh` - Set up Python sidecar environment
- `flutter build linux --release` - Build production binary (not in CI)

## Environment Configuration

**Required env vars:**
- `ANTHROPIC_API_KEY` (read by `claude-agent-sdk` sidecar, not by daemon)
  - Standard Anthropic SDK convention
  - Can be set in environment or via sidecar configuration

**Secrets location:**
- `~/.anthropic/api_key` or environment variable (handled by `claude-agent-sdk`)
- Configuration file location: Platform-specific XDG directory (read by `AppPaths`)
- No secrets stored in code; all environment-specific

**Build-time configuration:**
- Flutter version pinned: 3.44.8 (`.devcontainer/Dockerfile`, `.github/workflows/ci.yml`, `pubspec.yaml`)
- Flutter SHA256 checksum: Verified in Dockerfile (`FLUTTER_SHA256`)
- Python version requirement: 3.11+ (documented in `tool/provision_sidecar.sh`)

## Webhooks & Callbacks

**Incoming:**
- Single instance lock with show/hide signals via `SingleInstanceLock` (`lib/src/infrastructure/system/single_instance_lock.dart`)
  - Via abstract namespace Unix socket
  - Used for multi-instance prevention (AD-14)
  - User can launch daemon again to toggle visibility

**Outgoing:**
- Platform channels to Linux native layer:
  - Window manager: visibility, lifecycle, properties
  - Hotkey manager: bind/unbind global hotkeys
  - Tray manager: icon, menu, events
  - D-Bus portal: XDG shortcuts (Wayland), system dialog integration
- Sidecar process communication:
  - Parent daemon spawns sidecar with `Process.start('setsid', [interpreter, sidecar_path])`
  - Request: JSON-line format on stdin
  - Response: NDJSON stream on stdout
  - Lifecycle: Sidecar torn down after correction completes or times out

## Process Architecture

**Daemon Process:**
- Type: GTK3-based Tray daemon
- Lifecycle: Starts at user login (XDG autostart), resident until logout/stop signal
- Signals handled: SIGTERM (systemctl stop), SIGINT (Ctrl-C), SIGHUP (terminal close)
- Exit triggers: SIGTERM, SIGHUP, tray Quit menu entry

**Sidecar Process (spawned per correction):**
- Type: Python interpreter running `claude-agent-sdk`
- Lifecycle: Created fresh for each correction, torn down on completion
- Session leader: Uses `setsid` to create process group (AD-19)
- Cleanup: Process group killed with SIGTERM + grace period, then SIGKILL if needed
- Timeout: Configurable per preset (default 60 seconds wall clock)

**No external services:**
- No network services listened on
- No background threads/isolates beyond Riverpod container and Drift background isolate
- All corrections stateless; each uses dedicated sidecar subprocess

---

*Integration audit: 2026-08-30*
