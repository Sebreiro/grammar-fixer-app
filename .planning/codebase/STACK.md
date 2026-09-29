# Technology Stack

**Analysis Date:** 2026-08-30

## Languages

**Primary:**
- Dart 3.12.2+ - Application logic, UI, and domain layer
- C/C++ - Linux desktop integration (GTK3, tray integration via native plugins)

**Supporting:**
- Python 3.11+ - Sidecar process for Claude Agent SDK integration
- Shell (Bash) - Build scripts and deployment tools

## Runtime

**Environment:**
- Flutter 3.44.8 - Cross-platform UI framework (Linux build target)
- Dart VM - Executes Dart/Flutter code

**Platform:**
- Linux (GTK3 desktop environment) - Production deployment target
- X11 and Wayland display servers - Window/input management

**Package Manager:**
- `pub` (Dart package manager) - Manages dependencies in `pubspec.yaml`
- Lockfile: `pubspec.lock` - Pinned dependency versions
- Python `pip` - Manages Python sidecar dependencies (`assets/sidecar/requirements.txt`)

## Frameworks

**Core:**
- Flutter 3.44.8 - UI framework for tray daemon and correction panel
- Flutter Riverpod 3.4.2 - Reactive state management and dependency injection

**Database:**
- Drift 2.34.3 - Dart-native ORM with type-safe SQL generation
- SQLite3 3.5.1 - Embedded relational database for history persistence

**System Integration:**
- dbus 0.7.14 - D-Bus communication with Linux system services
- tray_manager 0.5.3 - System tray icon and context menu
- window_manager 0.5.2 - Window lifecycle and visibility management

**Testing:**
- flutter_test - Flutter widget and integration testing framework
- test 1.31.0 - Dart unit testing framework (pure Dart, no Flutter binding)

**Build/Dev:**
- build_runner 2.15.1 - Code generation and build orchestration
- drift_dev 2.34.0 - Drift ORM code generation
- flutter_lints 6.0.0 - Dart/Flutter linting rules and analysis

## Key Dependencies

**Critical:**
- flutter_riverpod 3.4.2 - Entire application dependency injection and state management; used for all controllers and port overrides in `lib/src/application/composition/`
- drift 2.34.3 - History persistence; all read/write of past corrections flows through `DriftCorrectionRepository` in `lib/src/infrastructure/persistence/`
- ffi 2.2.0 - `calloc`/`Utf8` for the X11 FFI seam in `x11_key_grab_registrar.dart`; without it CAP-1 (hotkey toggle) and AD-8 (hotkey binding) are non-functional on X11. Replaced hotkey_manager 0.2.3 in phase 1
- tray_manager 0.5.3 - System tray rendering; without it the daemon is invisible and unreachable except by hotkey

**Infrastructure:**
- dbus 0.7.14 - Enables Wayland portal integration and D-Bus system service communication
- window_manager 0.5.2 - Hidden window lifecycle; toggling visibility and responding to window close events
- sqlite3 3.5.1 - SQLite driver; compiled from native C code with Dart FFI bindings
- flutter 3.44.8 (from SDK) - Flutter embedder, GTK bindings, and platform channels to the Linux native layer

## Configuration

**Environment:**
- Configuration stored in JSON file (platform-specific location via `AppPaths.fromEnvironment()`)
- Environment variables read at startup for corrections sidecar path resolution
- `dart_test.yaml` - Test suite configuration, concurrency settings, and tag definitions
- `analysis_options.yaml` - Dart analyzer rules and linting configuration

**Build:**
- `pubspec.yaml` - Dart/Flutter project manifest with all dependencies pinned
- `pubspec.lock` - Lock file ensuring reproducible builds
- `.github/workflows/ci.yml` - GitHub Actions CI pipeline (merge gate: `dart analyze` + `dart test`)
- `.devcontainer/devcontainer.json` + `.devcontainer/Dockerfile` - VS Code dev container configuration

## Platform Requirements

**Development:**
- Linux host or Linux container (devcontainer)
- Flutter SDK 3.44.8 with Linux build toolchain:
  - clang, cmake, ninja-build
  - libgtk-3-dev, libayatana-appindicator3-dev, pkg-config (libkeybinder-3.0-dev dropped in phase 1; libX11 comes in via libgtk-3-dev)
- Dart SDK 3.12.2+ (bundled with Flutter)
- Python 3.11+ with pip (for `claude-agent-sdk` sidecar)
- Node.js 20.x (for dev tooling; Claude Code CLI requires npm)
- Git, GitHub CLI (`gh`), fzf, zsh, vim, nano

**Production:**
- Linux desktop environment (GTK3-based: GNOME, KDE Plasma, XFCE, etc.)
- D-Bus system bus (for Wayland portal integration)
- X11 or Wayland display server
- Python 3.11+ runtime (for sidecar process)
- Claude API access (via `claude-agent-sdk` sidecar)

## Build Artifacts

**Generated:**
- `lib/src/infrastructure/persistence/app_database.g.dart` - Drift ORM generated code (from `pubspec.yaml` include directive pointing to `history.drift`)
- `.dart_tool/` - Dart build cache
- `build/` - Flutter build output (Linux desktop binary, data assets)
- `.venv-sidecar/` - Python virtual environment (untracked, created by `tool/provision_sidecar.sh`)

**Output:**
- Linux desktop binary at `build/linux/x64/release/bundle/hotkey_grammar_corrector`
- Data assets bundled at `<binary dir>/data/flutter_assets/`

---

*Stack analysis: 2026-08-30*
