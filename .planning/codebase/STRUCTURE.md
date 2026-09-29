# Codebase Structure

**Analysis Date:** 2026-08-30

## Directory Layout

```
hotkey-grammar-corrector/
├── lib/
│   ├── main.dart                           # Composition root (outside lib/src to bypass AD-1 lint)
│   └── src/
│       ├── domain/                         # Pure Dart, no plugins or vendor SDKs
│       │   ├── correction/
│       │   │   ├── correction_event.dart
│       │   │   ├── correction_outcome.dart
│       │   │   ├── correction_provider.dart  # Port interface: text in, stream out
│       │   │   ├── correction_record.dart
│       │   │   ├── preset.dart              # Prompt + model, bound as one unit
│       │   │   ├── suggestion.dart
│       │   │   └── suggestion_register.dart # enum: formal, casual, shorter
│       │   ├── hotkey/
│       │   │   ├── global_hotkey.dart       # Port interface
│       │   │   ├── hotkey_bind_outcome.dart # sealed: HotkeyBound | HotkeyUnavailable
│       │   │   └── hotkey_binding.dart
│       │   ├── panel/
│       │   │   └── panel_visibility.dart    # Port interface: sync state + async show/hide
│       │   ├── clipboard/
│       │   │   └── clipboard_port.dart      # Port interface: read/write
│       │   ├── history/
│       │   │   └── correction_repository.dart # Port interface: persist
│       │   ├── tray/
│       │   │   └── tray_port.dart           # Port interface: menu items, quit requests
│       │   ├── config/
│       │   │   ├── app_config.dart          # Immutable config value type
│       │   │   ├── config_load_result.dart
│       │   │   ├── config_store.dart        # Port interface: load, validate, persist
│       │   │   └── provider_config.dart
│       │   ├── clock.dart                   # Port interface: current time
│       │   ├── logger.dart                  # Port interface: structured logging
│       │   └── collection_equality.dart     # Helpers for value equality
│       │
│       ├── application/                     # Use-case orchestration, Riverpod state
│       │   ├── composition/
│       │   │   ├── daemon_graph.dart        # Riverpod container holder, eager build
│       │   │   ├── port_providers.dart      # Port interface overrides (seams)
│       │   │   └── controller_providers.dart # Controller construction
│       │   ├── correction_controller.dart   # Owns session: seed, run, stream, retry, persist
│       │   ├── correction_state.dart        # Immutable state for correction UI
│       │   ├── panel_controller.dart        # Toggle visibility, dispatch hotkey
│       │   ├── settings_controller.dart     # Read/write config with write-through
│       │   └── settings_state.dart          # Immutable settings UI state
│       │
│       ├── infrastructure/                  # Port implementations, vendor adapters
│       │   ├── correction/
│       │   │   ├── active_correction.dart      # Resolves (provider, preset) pair from config
│       │   │   ├── provider_registry.dart      # id -> factory lookup, no switch
│       │   │   ├── unconfigured_correction_provider.dart # Placeholder when no provider set
│       │   │   └── claude_agent_sdk/          # One directory per provider
│       │   │       ├── claude_agent_sdk_correction_provider.dart
│       │   │       ├── register_tagged_stream_parser.dart # Pure Dart, unit-tested
│       │   │       ├── sidecar_host_paths.dart
│       │   │       └── sidecar_protocol.dart  # JSON line protocol shapes
│       │   ├── hotkey/
│       │   │   ├── display_server.dart          # XDG_SESSION_TYPE detection
│       │   │   ├── x11_global_hotkey.dart       # X11 adapter over the registrar seam
│       │   │   ├── wayland_portal_global_hotkey.dart # D-Bus GlobalShortcuts portal
│       │   │   ├── hotkey_registrar.dart        # Port interface: platform-agnostic registrar
│       │   │   ├── x11_key_grab_registrar.dart  # X11 concrete impl (dart:ffi)
│       │   │   ├── hotkey_grab.dart             # Process group management
│       │   │   ├── hotkey_key_catalogue.dart    # USB HID keycodes ↔ labels
│       │   │   └── xdg_shortcut_trigger.dart    # Preferred trigger string for Wayland
│       │   ├── panel/
│       │   │   ├── window_manager_panel_visibility.dart # window_manager adapter
│       │   │   ├── window_manager_panel_window.dart     # Window setup
│       │   │   └── panel_window.dart                    # Port interface
│       │   ├── clipboard/
│       │   │   └── system_clipboard.dart    # Xclip/native clipboard adapter
│       │   ├── persistence/
│       │   │   ├── app_database.dart        # Drift schema + table definitions
│       │   │   ├── app_database.g.dart      # Generated drift code (do not edit)
│       │   │   └── drift_correction_repository.dart # SQLite adapter
│       │   ├── config/
│       │   │   ├── json_config_store.dart   # JSON file adapter
│       │   │   ├── app_paths.dart           # XDG paths resolver
│       │   │   └── default_app_config.dart  # Bootstrap defaults
│       │   ├── tray/
│       │   │   ├── tray_manager_tray.dart        # tray_manager plugin adapter
│       │   │   ├── tray_manager_tray_icon.dart   # Icon registration
│       │   │   ├── tray_icon.dart                # Port interface
│       │   │   └── tray_menu_entry.dart          # Menu entry description
│       │   ├── system/
│       │   │   ├── daemon_startup.dart      # Pre-Flutter startup order (AD-14, 13, 9, 5)
│       │   │   ├── daemon_lifecycle.dart    # Runtime shutdown sequence with timeouts
│       │   │   ├── single_instance_lock.dart # Abstract namespace socket lock
│       │   │   ├── stderr_logger.dart       # Structured logging to stderr
│       │   │   └── system_clock.dart        # Unix millis UTC clock
│       │   └── (legacy, test-support)
│       │       └── correction/ (fakes_smoke_test support)
│       │
│       └── ui/                              # Flutter widgets
│           ├── daemon_app.dart              # Root widget, DaemonHome
│           ├── daemon_home.dart             # App structure
│           ├── panel/
│           │   ├── correction_panel.dart       # Main correction display
│           │   ├── correction_error_notice.dart # Inline error + Retry button
│           │   ├── original_text_pane.dart     # Display original unchanged text
│           │   ├── suggestion_list.dart        # Three columns for formal/casual/shorter
│           │   ├── suggestion_card.dart        # One suggestion variant with copy button
│           │   ├── register_key_slot.dart      # Register slot (formal=1, casual=2, etc.)
│           │   └── ... (other panel widgets)
│           └── settings/
│               ├── settings_screen.dart          # Tab: hotkey + provider selection
│               ├── preset_choice_list.dart      # Dropdown of available presets
│               ├── hotkey_status_view.dart      # Display effective hotkey + authority
│               ├── hotkey_preference_field.dart # Input new hotkey
│               ├── hotkey_binding_label.dart    # Human-readable hotkey label
│               ├── settings_failure_notice.dart # Error display
│               └── settings_pending_notice.dart # Status during rebind
│
├── test/
│   ├── fakes/
│   │   ├── fake_correction_provider.dart
│   │   ├── fake_global_hotkey.dart
│   │   ├── fake_panel_visibility.dart
│   │   ├── fake_clipboard_port.dart
│   │   ├── fake_config_store.dart
│   │   ├── fake_tray_port.dart
│   │   ├── fake_clock.dart
│   │   └── fake_logger.dart
│   ├── support/
│   │   └── fake_claude_cli/
│   │       ├── fixtures/
│   │       └── main.dart
│   ├── architecture/
│   │   ├── ad1_import_rule_test.dart   # Enforces AD-1 dependency direction
│   │   ├── composition_wiring_test.dart
│   │   ├── sidecar_pin_drift_test.dart # Verifies sidecar version pins
│   │   └── ... (architecture invariant tests)
│   ├── domain/
│   │   ├── correction/
│   │   ├── hotkey/
│   │   ├── config/
│   │   └── ... (pure Dart unit tests, no Flutter binding)
│   ├── application/
│   │   ├── correction_controller_test.dart
│   │   ├── panel_controller_test.dart
│   │   └── settings_controller_test.dart
│   ├── infrastructure/
│   │   ├── hotkey/
│   │   ├── correction/
│   │   │   └── claude_agent_sdk/
│   │   │       ├── register_tagged_stream_parser_test.dart
│   │   │       ├── sidecar_fake_cli_test.dart
│   │   │       └── claude_agent_sdk_sidecar_live_test.dart
│   │   ├── persistence/
│   │   ├── config/
│   │   └── ...
│   ├── ui/
│   │   ├── panel/
│   │   └── settings/
│   ├── composition/
│   ├── platform/
│   └── fakes_smoke_test.dart
│
├── assets/
│   └── sidecar/
│       ├── claude_agent_sdk_sidecar.py # Python sidecar: transport shim only
│       └── requirements.txt             # Pinned claude_agent_sdk version
│
├── linux/
│   ├── flutter/
│   │   ├── generated_plugins.cmake
│   │   └── generated_plugin_registrant.cc
│   ├── runner/
│   │   ├── my_application.cc            # Realize but don't show the window
│   │   └── ...
│   └── packaging/
│       └── com.divertedriver.HotkeyGrammarCorrector.desktop # Required for Wayland app_id
│
├── tool/
│   ├── provision_sidecar.sh             # Build .venv-sidecar with claude_agent_sdk
│   └── install_desktop_entries.sh       # Install .desktop files
│
├── pubspec.yaml                         # Flutter/Dart dependencies (pinned to spine)
├── pubspec.lock
├── analysis_options.yaml                # Linter: flutter_lints + strict-casts, strict-raw-types
├── README.md                            # Developing the app
├── AGENTS.md                            # Coding rules (read first)
├── PLAN.md                              # Roadmap and decisions made
└── .github/workflows/ci.yml             # CI pipeline, Flutter version pinned here

# Ignored in this scan:
# - _bmad/ _bmad-output/ .bmad-loop/ — Agent tooling, auto-generated
# - .claude/ .planning/ — Claude environment and planning artifacts
# - build/ .dart_tool/ .venv-sidecar/ — Build artifacts
# - .git/ — Version control
```

## Directory Purposes

**lib/src/domain/**
- **Purpose:** Portable, testable core logic and abstractions
- **Contains:** Value types, port interfaces, sealed enums, pure functions
- **Key files:** `correction_provider.dart` (the load-bearing port), `global_hotkey.dart`, `config_store.dart`
- **Constraints:** Zero imports from `package:flutter`, no vendor SDK types, no database dependencies

**lib/src/application/**
- **Purpose:** Use-case orchestration and application state
- **Contains:** Controllers (one per major feature), Riverpod provider graph, immutable state classes
- **Key files:** `correction_controller.dart` (session lifecycle), `composition/daemon_graph.dart` (container holder)
- **Constraints:** Never imports infrastructure; keeps state immutable; one Riverpod approach used consistently

**lib/src/infrastructure/**
- **Purpose:** Platform and vendor adaptation
- **Contains:** Concrete implementations of all ports, system integration, vendor SDK wrappers
- **Key files:** Provider implementations (one directory per provider), hotkey adapters (X11 vs Wayland), SQLite via drift
- **Constraints:** Only place vendor SDK types appear; adapters are swappable via composition root; no imports of application code

**lib/src/ui/**
- **Purpose:** Flutter widget presentation layer
- **Contains:** Widgets for correction panel and settings screen
- **Key files:** `panel/correction_panel.dart`, `settings/settings_screen.dart`
- **Constraints:** Never touches database, never calls network directly, reads state from Riverpod, emits actions to controllers

**lib/main.dart (composition root, outside lib/src/)**
- **Purpose:** Wire all seams; not testable by tests (needs binding, window, display)
- **Contains:** Adapter construction, error handler setup, startup/shutdown sequencing
- **Constraints:** Outside AD-1's import lint so it can know both infrastructure and application

**test/fakes/**
- **Purpose:** Test doubles for all ports
- **Contains:** One fake per domain port interface
- **Pattern:** Implements the port interface, used by unit tests instead of real adapters

**test/architecture/**
- **Purpose:** Verify structural invariants
- **Contains:** `ad1_import_rule_test.dart` (enforces dependency direction), `composition_wiring_test.dart`, sidecar version checks
- **Run:** `dart test test/architecture/` (no Flutter binding needed)

**test/domain/**
- **Purpose:** Pure Dart unit tests
- **Run:** `dart test test/domain/` (no Flutter binding)
- **Pattern:** Test correction parsing, hotkey binding outcomes, config validation in isolation

**test/infrastructure/**
- **Purpose:** Adapter behavior tests (using fakes for external ports)
- **Examples:** `claude_agent_sdk/register_tagged_stream_parser_test.dart` (pure Dart parsing), `config/` (JSON loading)
- **Special:** `claude_agent_sdk/sidecar_fake_cli_test.dart` requires sidecar provisioning; skipped without it

**assets/sidecar/**
- **Purpose:** Python transport shim for Claude Agent SDK
- **Contains:** `claude_agent_sdk_sidecar.py` (JSON in, NDJSON out), `requirements.txt` (pinned SDK version)
- **Rule:** Transport only — no prompt assembly, no register parsing, no retry logic (all in Dart)

**linux/packaging/**
- **Purpose:** XDG desktop integration
- **Contains:** `.desktop` file (required by Wayland app_id binding)

## Key File Locations

**Entry Points:**
- `lib/main.dart` — Program start; composition root, platform setup, lifecycle
- `lib/src/ui/daemon_app.dart` — Root Flutter widget
- `test/fakes_smoke_test.dart` — Quick sanity check (runs without live network)

**Core Abstractions:**
- `lib/src/domain/correction/correction_provider.dart` — Load-bearing port
- `lib/src/domain/hotkey/global_hotkey.dart` — Platform-agnostic hotkey interface
- `lib/src/domain/config/config_store.dart` — Config access port
- `lib/src/domain/panel/panel_visibility.dart` — Window state port

**Controller Logic:**
- `lib/src/application/correction_controller.dart` — Session orchestration (seed, run, retry, persist)
- `lib/src/application/panel_controller.dart` — Hotkey-triggered toggle
- `lib/src/application/settings_controller.dart` — Config sync (write-through)

**Provider Implementations:**
- `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` — Sidecar spawner
- `lib/src/infrastructure/correction/provider_registry.dart` — Provider id → factory lookup
- `lib/src/infrastructure/correction/active_correction.dart` — Resolve active pair from config

**Hotkey Adapters:**
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — X11 binding over the FFI registrar
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — D-Bus GlobalShortcuts portal
- `lib/src/infrastructure/hotkey/display_server.dart` — Runtime detection and choice

**Data Persistence:**
- `lib/src/infrastructure/persistence/app_database.dart` — Drift schema (corrections + suggestions tables)
- `lib/src/infrastructure/persistence/drift_correction_repository.dart` — SQLite adapter

**Configuration:**
- `lib/src/infrastructure/config/json_config_store.dart` — JSON file loader/writer
- `lib/src/infrastructure/config/app_paths.dart` — XDG path resolution
- `lib/src/domain/config/app_config.dart` — Immutable config value type

**Startup and Shutdown:**
- `lib/src/infrastructure/system/daemon_startup.dart` — Pre-Flutter initialization (lock → config → hotkey → provider)
- `lib/src/infrastructure/system/daemon_lifecycle.dart` — Ordered shutdown with timeouts
- `lib/src/application/composition/daemon_graph.dart` — Riverpod container + eager controller build

## Naming Conventions

**Files:**
- One public type per file
- Filename is snake_case version of the public type: `correction_provider.dart`, `global_hotkey.dart`
- Test files mirror source: `lib/src/domain/correction/suggestion.dart` → `test/domain/correction/suggestion_test.dart`
- Fakes live in `test/fakes/` and are named `fake_<interface>.dart`: `fake_correction_provider.dart`

**Directories:**
- Domain ports grouped by concern: `domain/correction/`, `domain/hotkey/`, `domain/config/`, `domain/clipboard/`
- One infrastructure directory per port: `infrastructure/correction/`, `infrastructure/hotkey/`, `infrastructure/panel/`
- One provider implementation per subdirectory: `infrastructure/correction/claude_agent_sdk/`, leaves room for `infrastructure/correction/openai/` or similar later

**Types:**
- **Ports:** Role nouns without `I` prefix: `CorrectionProvider`, `GlobalHotkey`, `PanelVisibility`, `ConfigStore`
- **Adapters:** `<Technology><Port>`: `ClaudeAgentSdkCorrectionProvider`, `X11GlobalHotkey`, `WaylandPortalGlobalHotkey`, `JsonConfigStore`, `DriftCorrectionRepository`
- **Fakes:** `Fake<Port>`: `FakeCorrectionProvider`, `FakeGlobalHotkey`
- **Values and outcomes:** `<NounPhrase>`: `Suggestion`, `Preset`, `CorrectionEvent`, `HotkeyBinding`, `HotkeyBound`, `HotkeyUnavailable`
- **State classes:** `<FeatureName>State`: `CorrectionState`, `SettingsState`
- **Controllers:** `<FeatureName>Controller`: `CorrectionController`, `PanelController`, `SettingsController`

**Enums (persisted):**
- Always stored by `.name`, never by index
- Examples: `SuggestionRegister`, `CorrectionFailureKind`, `BindingAuthority`

**Variables and Fields:**
- Mutable state: avoid; if necessary, prefix with underscore (`_state`)
- Immutable fields: no prefix (`state`)
- Ports in constructors: `_provider`, `_clipboard`, `_repository`
- Streams: `_changes`, `activations`, `changes` (depending on broadcast vs single-subscription)

## Where to Add New Code

### New Provider (e.g., OpenAI, local model server)

1. **Add one adapter file:** `lib/src/infrastructure/correction/openai/openai_correction_provider.dart`
   - Implements `CorrectionProvider` interface
   - Spawns process or opens connection, decodes response, emits events
   - Translates failure to `CorrectionFailureKind`
   - No vendor types leak out
   
2. **Register in composition root:** Edit `lib/main.dart` or create `infrastructure/correction/provider_registry.dart` entry

3. **Add one config entry:** Include provider id + default preset in `default_app_config.dart`

4. **Add a fake:** `test/fakes/fake_openai_correction_provider.dart` for tests

5. **Add tests:** `test/infrastructure/correction/openai/` mirroring the adapter's structure

### New UI Feature (e.g., history view, analytics panel)

1. **Add state and controller:** Create `lib/src/application/<feature>_controller.dart` with immutable `<Feature>State`

2. **Wire in Riverpod:** Add providers to `lib/src/application/composition/controller_providers.dart`

3. **Add widgets:** `lib/src/ui/<feature>/` with stateless or simple stateful widgets reading state via `WidgetRef`

4. **Add port if needed:** If the feature needs to talk to an adapter (storage, system integration), define port in `lib/src/domain/<feature>/`; implement in `lib/src/infrastructure/<feature>/`

### New Hotkey Backend (e.g., if Wayland changes)

1. **Add implementation:** `lib/src/infrastructure/hotkey/<platform>_global_hotkey.dart` implementing `GlobalHotkey`

2. **Update display-server detector:** Edit `lib/src/infrastructure/hotkey/display_server.dart` to recognize the platform

3. **Wire in daemon_startup:** Update `lib/src/infrastructure/system/daemon_startup.dart` provider choice

4. **Add fake:** `test/fakes/fake_global_hotkey.dart` (reused if interface unchanged)

5. **Test both paths:** Existing tests should still pass; add platform-specific tests as needed

### New Database Query or Schema Change

1. **Update drift schema:** `lib/src/infrastructure/persistence/app_database.dart`
   - Add table or column
   - Drift auto-generates queries

2. **Update repository:** `lib/src/infrastructure/persistence/drift_correction_repository.dart`
   - Add method to `CorrectionRepository` interface (in domain if it's a new query)
   - Implement in drift adapter

3. **Update controller:** If persistence logic changes, update `CorrectionController` or other caller

4. **Add tests:** Unit test the repository with fakes for other ports

### New Utility or Helper

**Shared helpers:**
- If pure function: `lib/src/domain/<concern>/` (e.g., `lib/src/domain/collection_equality.dart`)
- If uses vendor SDK or platform: `lib/src/infrastructure/<concern>/` (e.g., `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart`)
- Tests: mirror the source path in `test/`

## Special Directories

**build/**
- Purpose: Compiled artifacts (Flutter build output)
- Generated: Yes (by `flutter build` or `flutter run`)
- Committed: No (in .gitignore)

**.dart_tool/**
- Purpose: Dart analyzer cache, generated build files
- Generated: Yes (by Dart/Flutter toolchain)
- Committed: No

**.venv-sidecar/**
- Purpose: Python virtual environment for Claude Agent SDK
- Generated: Yes (by `tool/provision_sidecar.sh`)
- Committed: No
- Required for: Sidecar tests and live corrections

**_bmad-output/**
- Purpose: Spec, architecture spine, planning artifacts (generated by bmad skills)
- Generated: Yes (by `/bmad-spec`, `/bmad-architecture`, etc.)
- Committed: Yes (frozen reference)

---

*Structure analysis: 2026-08-30*
