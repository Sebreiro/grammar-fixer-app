<!-- refreshed: 2026-08-30 -->
# Architecture

**Analysis Date:** 2026-08-30

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                              UI (Flutter Widgets)                             │
│     ┌────────────────────────┬──────────────┬──────────────────────────┐     │
│     │ CorrectionPanel        │ SettingsScreen│    DaemonApp (root)     │     │
│     │ `ui/panel/`            │ `ui/settings/` │   `ui/daemon_app.dart` │     │
│     └────────────────────────┴──────────────┴──────────────────────────┘     │
└──────────────────┬───────────────────────────────────────────────────────────┘
                   │ reads/updates state via Riverpod
┌──────────────────▼───────────────────────────────────────────────────────────┐
│                      Application (Controllers + Riverpod)                     │
│     ┌──────────────────┬──────────────────┬──────────────────────────────┐   │
│     │ CorrectionCtrl   │ PanelController  │ SettingsController          │   │
│     │ `correction...`  │ `panel_ctrl.dart`│ `settings_ctrl.dart`        │   │
│     └──────────────────┴──────────────────┴──────────────────────────────┘   │
│          ↑          ↑        ↑                                                │
│     composition/ port providers, controller providers, daemon_graph          │
└──────────┬──────────┬────────┬────────────────────────────────────────────────┘
           │          │        │ delegates to ports
┌──────────▼──────────▼────────▼────────────────────────────────────────────────┐
│                     Domain (Value Types + Ports)                              │
│  ┌─────────────┬──────────────┬─────────────┬────────────┬─────────┐         │
│  │ Suggestion  │ CorrectionProvider (port) │ GlobalHotkey│ Config  │ Clock  │
│  │ Preset      │ (text in, stream out)     │ (port)      │ (port)  │ (port) │
│  │ CorrectionEvent / sealed hierarchy      │ Panel...    │ Clipboard        │
│  └─────────────┴──────────────┴─────────────┴────────────┴─────────┘         │
│  `domain/correction/` `domain/hotkey/` `domain/config/` `domain/clipboard/`  │
└──────────┬────────────────────────────────────────────────────────────────────┘
           │ implemented by
┌──────────▼────────────────────────────────────────────────────────────────────┐
│           Infrastructure (Port Implementations + Platform Adapters)           │
│  ┌─────────────────────┬──────────────────┬──────────────┬──────────────┐   │
│  │ ClaudeAgentSdk...   │ X11GlobalHotkey  │ DriftCorrect │ JsonConfig  │   │
│  │ (sidecar spawner)   │ Wayland...       │ Repository   │ Store       │   │
│  └─────────────────────┴──────────────────┴──────────────┴──────────────┘   │
│  `infrastructure/correction/` `infrastructure/hotkey/` `infrastructure/...`  │
└──────────────────────────────────────────────────────────────────────────────┘
           ▲
           │
┌──────────┴───────────────────────────────────────────────────────────────────┐
│    Composition Root (AD-17: Vendor seams wired here only)                    │
│  ┌────────────────┐  ┌──────────────────────────────┐  ┌────────────────┐   │
│  │   main.dart    │  │ application/composition/     │  │ daemon_startup │   │
│  │ (outside src)  │  │ - port_providers.dart       │  │ (system setup) │   │
│  │ Platform setup │  │ - controller_providers.dart │  │                │   │
│  │ Lifecycle mgmt │  │ - daemon_graph.dart         │  │ active_correct │   │
│  └────────────────┘  └──────────────────────────────┘  └────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| **CorrectionController** | Owns one correction session: clipboard seeding, provider call, streaming to UI, persistence | `lib/src/application/correction_controller.dart` |
| **PanelController** | Toggle visibility: reads sync visibility state, calls show/hide, handles hotkey activations | `lib/src/application/panel_controller.dart` |
| **SettingsController** | Reads/writes config, syncs in-app settings to disk (write-through to ConfigStore) | `lib/src/application/settings_controller.dart` |
| **CorrectionProvider** | Port interface: text in, stream of events (deltas + terminal event) out. Stateless. | `lib/src/domain/correction/correction_provider.dart` |
| **GlobalHotkey** | Port interface: register/query hotkey binding, stream press events | `lib/src/domain/hotkey/global_hotkey.dart` |
| **PanelVisibility** | Port interface: sync visibility state + async show/hide calls | `lib/src/domain/panel/panel_visibility.dart` |
| **ConfigStore** | Port interface: load/validate config, persist changes atomically | `lib/src/domain/config/config_store.dart` |
| **ClaudeAgentSdk...** | Concrete: spawns Python sidecar per correction, decodes register-tagged response stream | `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` |
| **X11GlobalHotkey** | Concrete: X11 global key grab via `X11KeyGrabRegistrar` (dart:ffi to libX11.so.6) | `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` |
| **WaylandPortal...** | Concrete: XDG GlobalShortcuts portal via D-Bus (AD-11 call sequence) | `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` |
| **DriftCorrectionRepository** | Concrete: SQLite persistence via drift ORM | `lib/src/infrastructure/persistence/drift_correction_repository.dart` |
| **DaemonGraph** | Riverpod container holder: builds controllers, owns disposal order | `lib/src/application/composition/daemon_graph.dart` |

## Pattern Overview

**Overall:** Hexagonal architecture (ports and adapters) with one-way dependency flow and lazy binding.

**Key Characteristics:**
- **Four rings** with enforced import direction: domain (pure Dart) ← application ← infrastructure, ui ← application
- **Port abstraction for every platform/vendor seam**: corrections never see HTTP, processes, or SDK types; all leakage is adapter-private
- **Exactly one active (CorrectionProvider, Preset) pair** at startup, injected into controllers; no runtime provider selection (no fallback, no cascade)
- **Stateless correction sessions**: every correction is fresh, with no accumulated context
- **Streaming over batching**: progressive rendering via `SuggestionDelta` events before terminal `CorrectionCompleted`
- **Error as value, not exception**: expected failures (no clipboard, provider unavailable, malformed response) are modelled `CorrectionEvent` variants
- **Riverpod state only in application and ui**: domain logic is pure and testable without a binding

## Layers

**Domain:**
- Purpose: Core business logic, value types, port interfaces
- Location: `lib/src/domain/`
- Contains: Correction types (`Suggestion`, `Preset`, `CorrectionEvent`, `CorrectionProvider`), hotkey types (`HotkeyBinding`, `GlobalHotkey`), config/clipboard/panel/tray/history/clock/logger ports
- Depends on: Only `dart:` libraries
- Used by: Application (to orchestrate) and infrastructure (to implement)

**Application:**
- Purpose: Use-case orchestration, state management with Riverpod, controller lifecycle
- Location: `lib/src/application/`
- Contains: Three controllers (`CorrectionController`, `PanelController`, `SettingsController`), Riverpod provider graph (`application/composition/`), immutable state classes
- Depends on: Domain, Riverpod (flutter_riverpod)
- Used by: UI (reads state), composition root (builds and disposes)

**Infrastructure:**
- Purpose: Concrete port implementations, platform/vendor adaptation, system integration
- Location: `lib/src/infrastructure/`
- Contains: Claude Agent SDK sidecar spawner, X11/Wayland hotkey adapters, drift SQLite, JSON config, window/tray/clipboard system adapters, lifecycle managers
- Depends on: Domain, vendor packages (dbus, drift, window_manager, tray_manager, ffi, sqlite3)
- Used by: Composition root (wired in) only; never imports application or ui

**UI:**
- Purpose: Flutter widget tree, presentation
- Location: `lib/src/ui/`
- Contains: Panel (correction display + editor), settings screen (hotkey + provider selection), daemon root widget
- Depends on: Application (for state and actions), domain read-only types
- Used by: runApp in main.dart

**Composition Root (AD-17 — four parts):**
1. `main.dart` — Constructs adapters, sets up error handlers, sequences platform-dependent startup/shutdown, owns pre-lifecycle abort
2. `application/composition/` — Riverpod provider graph that declares seams and wires controllers
3. `infrastructure/system/daemon_startup.dart` — Pre-Flutter startup order (AD-14 lock → AD-13 config → AD-9 hotkey → AD-5 provider resolution)
4. `infrastructure/correction/active_correction.dart` — Resolves active `(CorrectionProvider, Preset)` pair from config

## Data Flow

### Primary Request Path (Hotkey → Show → Correct → Save)

1. **Hotkey pressed** → `GlobalHotkey.activations` stream event (`infrastructure/hotkey/*`)
2. **PanelController.onHotkeyActivated()** reads sync `PanelVisibility.isVisible` (no await needed — in-process mirror) → calls `show()` or `hide()`
3. **Panel shown** → triggers `PanelVisibility.changes` stream watched by `CorrectionController`
4. **CorrectionController._onVisibilityChanged()** seeds clipboard via `ClipboardPort.read()` → emits initial state to UI
5. **User edits and submits** → `CorrectionController.onSubmitCorrection(editedText)` called from UI
6. **Controller calls provider** → `CorrectionProvider.correct(text: "...", preset: active)` returns `Stream<CorrectionEvent>`
7. **SuggestionDelta events stream** → controller emits state updates to UI, UI renders each register slot progressively
8. **Terminal event arrives** (`CorrectionCompleted` or `CorrectionFailed`) → controller persists via `CorrectionRepository.save(record)`
9. **Retry pressed** → `CorrectionController.onRetry()` replays the captured submitted text (not current editor state)
10. **Panel closed** → correction in-flight still completes and persists (hide does not cancel; only Retry and new correction do)

### Secondary Flow: Settings Change (User modifies hotkey or provider)

1. **Settings screen renders** active hotkey and provider from `SettingsController.state`
2. **User changes hotkey** → `SettingsController.updateHotkey()` writes to `ConfigStore` (write-through)
3. **ConfigStore persists** → emits new `AppConfig`
4. **SettingsController.**watches config changes → rebuilds hotkey UI
5. **New hotkey takes effect** → `GlobalHotkey.bind()` called (not automatic; happens next session or on explicit rebind request)

### State Management

- **Immutable state objects** with `copyWith` pattern; held in controller fields and exposed as Riverpod providers
- **State updates** only happen inside controllers; UI reads them (no direct widget-state mutations)
- **Riverpod** manages provider graph, eager controller construction in `DaemonGraph.build()`, cleanup in `DaemonGraph.dispose()`
- **No global state or service locators** in domain code; all dependencies injected through constructors

## Key Abstractions

**CorrectionProvider (AD-2, AD-3):**
- Purpose: Abstract away provider implementation (local process, remote API, in-process library)
- Examples: `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` (sidecar), `lib/src/infrastructure/correction/unconfigured_correction_provider.dart` (no provider available)
- Pattern: Port interface (in domain) + concrete adapters (in infrastructure). Stream-based (not HTTP), stateless (no context accumulation), failure as modelled event

**GlobalHotkey (AD-9, AD-10, AD-12):**
- Purpose: Abstract X11 key grabs and Wayland portal registration behind one interface
- Examples: `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` (dart:ffi to libX11.so.6), `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` (D-Bus + XDG GlobalShortcuts)
- Pattern: Display-server adapter choice happens once at startup in `daemon_startup.dart`, never switches at runtime. Binding outcome is a value (not exception). Composition and user can change the binding on Wayland (advisory); application has authority on X11.

**PanelVisibility (AD-8):**
- Purpose: Synchronous in-process visibility state (avoids IPC on hotkey show path)
- Examples: `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`
- Pattern: Sync getter `isVisible` + async show/hide + `changes` stream. Toggle reads sync state without await.

**ConfigStore (AD-13):**
- Purpose: Central config authority — load, validate, persist
- Examples: `lib/src/infrastructure/config/json_config_store.dart`
- Pattern: One owner, all mutations go through it. Malformed files yield defaults + warning (never fail startup).

**CorrectionRepository (AD-7):**
- Purpose: Persist corrections to history database
- Examples: `lib/src/infrastructure/persistence/drift_correction_repository.dart`
- Pattern: Single caller (`CorrectionController` at terminal event). One write, one transaction. Schema mirrors `suggestions[]` structure.

## Entry Points

**main.dart** (`lib/main.dart`):
- Location: Outside `lib/src/`, so it doesn't trigger AD-1's import lint
- Triggers: Program start (Flutter engine initialization)
- Responsibilities: 
  - Install error handlers before anything runs
  - Create adapters (hotkey registrar, tray icon, panel visibility)
  - Run `DaemonStartup.begin()` (AD-14 lock, AD-13 config, AD-9 hotkey bind attempt, AD-5 provider resolution)
  - Build Riverpod container and `DaemonGraph`
  - Install signal handlers (SIGTERM, SIGINT, SIGHUP)
  - Sequence finalization: create hidden window, run Flutter app, await first frame, install tray, finalize hotkey bind
  - Own pre-lifecycle abort path (if startup fails after lock is taken)

**DaemonApp** (`lib/src/ui/daemon_app.dart`):
- Triggers: `runApp()` in main.dart
- Responsibilities: Root widget tree, passes Riverpod container to children

## Architectural Constraints

- **Dependency direction:** `domain` imports only `dart:*`; `application` never imports `infrastructure` or ui; `ui` never imports `infrastructure`; only composition root knows both sides (mechanically enforced by `test/architecture/ad1_import_rule_test.dart`)

- **Global state:** No module-level singletons in domain or application. Infrastructure adapters may hold platform-specific state (e.g. `X11KeyGrabRegistrar`'s private X `Display` and worker isolate) but their public interface is behind a port, so swapping is a one-file change.

- **Circular imports:** None. Dependency graph is a DAG.

- **Riverpod graph:** Eager construction in `DaemonGraph.build()` (not lazy) so listeners are attached before the first event. Disposal order: correction controller (drains history writes), panel controller, settings controller, container, then adapters.

- **Concurrency:** Resident daemon runs one hotkey/correction/settings flow at a time; no worker threads or isolates (CAP-1's <100 ms budget is achieved by staying off the show path, not by parallelism).

- **Streaming:** Single-subscription streams from `CorrectionProvider.correct()`. Cancellation tears down provider work (kill child process). Broadcast streams for UI observation (e.g., `CorrectionController._changes`).

- **Persistence:** Every terminal correction event persists exactly once, in one transaction, regardless of panel visibility. Schema is immutable in MVP; drift migrations deferred.

## Anti-Patterns

### Using vendor types above infrastructure boundary

**What happens:** A controller or UI widget imports an HTTP library, an SDK type, a subprocess type, or a database row type.

**Why it's wrong:** Locks in one implementation; makes testing impossible without that dependency; makes swapping backends a refactor instead of a file addition.

**Do this instead:** Define a port interface in domain (e.g., `CorrectionProvider`), let infrastructure implement it, and inject the implementation into controllers. Tests fake the port. Adding a new provider is AD-15's three steps: one file, one config entry, one composition-root map.

### Selecting a provider at runtime

**What happens:** Code inside application or infrastructure contains a `switch (providerId)` or checks which provider is active.

**Why it's wrong:** Violates open/closed principle; forces the seam to stay open in domain/application code instead of being closed at the composition root.

**Do this instead:** Resolve the active provider once at startup (in `active_correction.dart`), inject the single active `(CorrectionProvider, Preset)` pair into `CorrectionController`. No switch, no fallback, no cascade.

### Accumulating state in a provider

**What happens:** `CorrectionProvider` implementation caches results, remembers conversation history, or reuses a session.

**Why it's wrong:** Violates AD-3 (stateless sessions); makes behavior unpredictable when Retry is pressed or provider is swapped.

**Do this instead:** Every correction is fresh. If the provider holds a child process, spawn it, run one correction, kill it. Session-based APIs must be wrapped so each `correct()` call appears session-independent to the caller.

### Logging the input text

**What happens:** `logger.info('correcting: $inputText')` in any adapter.

**Why it's wrong:** The daemon reads the clipboard; a log file is a privacy leak.

**Do this instead:** Never log `inputText` or suggestion bodies. Log only the type of event (`CorrectionCompleted`, `CorrectionFailed`), provider response metadata, and timing.

## Error Handling

**Strategy:** Expected failures are modelled values (part of the return type); programmer errors are exceptions (never cross a boundary as a vendor type).

**Patterns:**

- **Provider failure** → `CorrectionFailed(kind, message)` event emitted by provider, rendered inline in panel with Retry action (not thrown, not swallowed)
- **No clipboard content** → `ClipboardPort.read()` returns empty string; correction runs on empty input or is skipped
- **Config malformed** → `ConfigStore` loads defaults + logs warning; daemon stays up and usable from tray
- **Hotkey bind refused** → `bind()` returns `HotkeyUnavailable(message)` (not exception); tray menu still works as fallback
- **Startup failure** (after lock taken) → `_abort()` in main.dart tears down in order and exits 1
- **Framework error** (widget build fails, async error unhandled) → `FlutterError.onError` + `PlatformDispatcher.onError` forward to logger, daemon stays resident

## Cross-Cutting Concerns

**Logging:**
- Port: `Logger` (`lib/src/domain/logger.dart`)
- Implementation: `StderrLogger` (structured lines to stderr, never user text)
- Access: Injected into controllers and adapters; used for warnings and errors only, never for verbose traces
- Rule: No `inputText` or `suggestionText` in logs (privacy: daemon reads the clipboard)

**Validation:**
- Config validation happens once in `ConfigStore`; never re-parsed
- Preset and provider id validated at composition root (not at correction time)
- Hotkey binding validated per-backend (AD-12: if a key is unrepresentable, that backend is skipped)

**Authentication:**
- No authentication in MVP (resident, single-user desktop daemon)
- Provider credentials flow through config, behind `ConfigStore` write-through (never exposed to UI as a field)
- API keys, if any provider requires them, are loaded from config and passed to the provider adapter only

---

*Architecture analysis: 2026-08-30*
