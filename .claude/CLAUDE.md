<!-- GSD:project-start source:PROJECT.md -->

## Project

**Hotkey Grammar Corrector**

A Linux tray-resident Flutter daemon that turns text you already wrote into polished,
native-sounding English. A global hotkey summons a panel pre-filled with the clipboard,
an LLM provider streams back three register variants (formal, casual, shorter), and every
correction is kept in a local SQLite history. It is for non-native English writers who want
a correction pass available from any application without switching windows or waiting on a
cold start.

The MVP is built and shipping: 11 BMAD stories closed, all 14 capabilities of the frozen
SPEC implemented, on both X11 and the Wayland XDG GlobalShortcuts portal.

**Core Value:** The daemon corrects text reliably on both display servers and never loses, corrupts, or
leaks the user's text — a correction that silently truncates or a history file every local
account can read is worse than no daemon at all.

### Constraints

- **Tech stack**: Flutter/Dart on Linux with GTK3, X11 and Wayland — fixed by the frozen SPEC and the shipped code; no Electron, no webview
- **Architecture**: Hexagonal, four rings, one-way imports; vendor types never cross a port boundary and seams are wired only at the composition root (AD-1, AD-17) — enforced by an analyzer rule and architecture tests
- **Contract**: `ARCHITECTURE-SPINE.md`'s 19 ADs and the SPEC's 14 capabilities are frozen; several ledger items exist precisely because a fix would require editing a verbatim-fixed port declaration, which is a human-gated decision
- **Ledger discipline**: `deferred-work.md` is append-only — closing an entry flips `status:` and adds `resolution:`; entries are never deleted (DW-13 and DW-108 both record violations of this rule)
- **Display servers**: Every hotkey and panel behavior must hold on both X11 and Wayland, where the compositor — not the app — owns the binding; the two backends diverge and the map flags that divergence as fragile
- **Privacy**: Input text and suggestion bodies are never logged; history holds user plaintext, which makes file permissions and retention correctness issues rather than polish

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Dart 3.12.2+ - Application logic, UI, and domain layer
- C/C++ - Linux desktop integration (GTK3, tray integration via native plugins)
- Python 3.11+ - Sidecar process for Claude Agent SDK integration
- Shell (Bash) - Build scripts and deployment tools

## Runtime

- Flutter 3.44.8 - Cross-platform UI framework (Linux build target)
- Dart VM - Executes Dart/Flutter code
- Linux (GTK3 desktop environment) - Production deployment target
- X11 and Wayland display servers - Window/input management
- `pub` (Dart package manager) - Manages dependencies in `pubspec.yaml`
- Lockfile: `pubspec.lock` - Pinned dependency versions
- Python `pip` - Manages Python sidecar dependencies (`assets/sidecar/requirements.txt`)

## Frameworks

- Flutter 3.44.8 - UI framework for tray daemon and correction panel
- Flutter Riverpod 3.4.2 - Reactive state management and dependency injection
- Drift 2.34.3 - Dart-native ORM with type-safe SQL generation
- SQLite3 3.5.1 - Embedded relational database for history persistence
- dbus 0.7.14 - D-Bus communication with Linux system services
- tray_manager 0.5.3 - System tray icon and context menu
- window_manager 0.5.2 - Window lifecycle and visibility management
- flutter_test - Flutter widget and integration testing framework
- test 1.31.0 - Dart unit testing framework (pure Dart, no Flutter binding)
- build_runner 2.15.1 - Code generation and build orchestration
- drift_dev 2.34.0 - Drift ORM code generation
- flutter_lints 6.0.0 - Dart/Flutter linting rules and analysis

## Key Dependencies

- flutter_riverpod 3.4.2 - Entire application dependency injection and state management; used for all controllers and port overrides in `lib/src/application/composition/`
- drift 2.34.3 - History persistence; all read/write of past corrections flows through `DriftCorrectionRepository` in `lib/src/infrastructure/persistence/`
- ffi 2.2.0 - `calloc`/`Utf8` for the X11 FFI seam; without it CAP-1 (hotkey toggle) and AD-8 (hotkey binding) are non-functional on X11. Replaced hotkey_manager 0.2.3 in phase 1, whose Linux plugin discarded `keybinder_bind`'s result and put libkeybinder-3.0.so.0 in the runner's link set
- tray_manager 0.5.3 - System tray rendering; without it the daemon is invisible and unreachable except by hotkey
- dbus 0.7.14 - Enables Wayland portal integration and D-Bus system service communication
- window_manager 0.5.2 - Hidden window lifecycle; toggling visibility and responding to window close events
- sqlite3 3.5.1 - SQLite driver; compiled from native C code with Dart FFI bindings
- flutter 3.44.8 (from SDK) - Flutter embedder, GTK bindings, and platform channels to the Linux native layer

## Configuration

- Configuration stored in JSON file (platform-specific location via `AppPaths.fromEnvironment()`)
- Environment variables read at startup for corrections sidecar path resolution
- `dart_test.yaml` - Test suite configuration, concurrency settings, and tag definitions
- `analysis_options.yaml` - Dart analyzer rules and linting configuration
- `pubspec.yaml` - Dart/Flutter project manifest with all dependencies pinned
- `pubspec.lock` - Lock file ensuring reproducible builds
- `.github/workflows/ci.yml` - GitHub Actions CI pipeline (merge gate: `dart analyze` + `dart test`)
- `.devcontainer/devcontainer.json` + `.devcontainer/Dockerfile` - VS Code dev container configuration

## Platform Requirements

- Linux host or Linux container (devcontainer)
- Flutter SDK 3.44.8 with Linux build toolchain:
- Dart SDK 3.12.2+ (bundled with Flutter)
- Python 3.11+ with pip (for `claude-agent-sdk` sidecar)
- Node.js 20.x (for dev tooling; Claude Code CLI requires npm)
- Git, GitHub CLI (`gh`), fzf, zsh, vim, nano
- Linux desktop environment (GTK3-based: GNOME, KDE Plasma, XFCE, etc.)
- D-Bus system bus (for Wayland portal integration)
- X11 or Wayland display server
- Python 3.11+ runtime (for sidecar process)
- Claude API access (via `claude-agent-sdk` sidecar)

## Build Artifacts

- `lib/src/infrastructure/persistence/app_database.g.dart` - Drift ORM generated code (from `pubspec.yaml` include directive pointing to `history.drift`)
- `.dart_tool/` - Dart build cache
- `build/` - Flutter build output (Linux desktop binary, data assets)
- `.venv-sidecar/` - Python virtual environment (untracked, created by `tool/provision_sidecar.sh`)
- Linux desktop binary at `build/linux/x64/release/bundle/hotkey_grammar_corrector`
- Data assets bundled at `<binary dir>/data/flutter_assets/`

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Naming Patterns

- Snake_case matching the primary type: `correction_provider.dart`, `hotkey_binding.dart`
- One public type per file (AGENTS.md §3)
- Test files: `*_test.dart`
- PascalCase for type names: `CorrectionProvider`, `HotkeyBinding`, `Suggestion`
- `final class` for value types with immutable fields
- `sealed class` for sum types (discriminated unions): `CorrectionEvent`, `HotkeyBindOutcome`
- `abstract interface class` for ports/contracts/abstract definitions: `CorrectionProvider`, `Logger`, `ClipboardPort`
- Private classes: leading underscore `_Run`, `_Harness`
- camelCase: `submit()`, `editText()`, `copySuggestion()`
- Private methods: leading underscore `_setState()`, `_seedFromClipboard()`
- Boolean getters named descriptively: `_isCurrent()`, not `isOk()`
- camelCase: `submittedText`, `editorText`, `sessionToken`
- Private fields: leading underscore `_state`, `_clipboard`, `_disposed`
- Enums and enum values: camelCase `CorrectionFailureKind.providerError`
- Single capital letter or descriptive PascalCase: `<T>`, `<E extends CorrectionEvent>`

## Code Style

- `dart format` output only - no hand-formatting arguments
- Merge gate: a clean `dart analyze` is required (AGENTS.md §6)
- Line length: no enforcement, `dart format` decides
- Base: `flutter_lints` package
- Stricter settings in `analysis_options.yaml`:
- Every `ignore` comment requires a one-line justification
- No `dynamic` unless unavoidable with detailed justification
- `final` fields by default: `final String id`
- `const` constructors wherever possible: `const Suggestion({required this.text})`
- `const` widgets in build trees
- Immutable state objects use `copyWith()` for updates (never mutate in place)
- `late final` for fields that are assigned once, lazily (e.g., controllers, subscriptions)
- Sealed classes + exhaustive `switch` expressions for states/events
- Records for small tuples instead of classes: `({String text, Preset preset})`
- Pattern matching over `is`-chains and null-checks
- Exhaustive switches are compiler protection when a case is added

## Import Organization

- Blank line between each category
- Within a category, sort alphabetically
- Group by semantic layer: domain imports together, then application, then infrastructure
- `package:` imports of the code under test first
- `package:test/test.dart` or `package:flutter_test/flutter_test.dart`
- Relative imports of fakes and test support last

## Null Safety

- No `!` to silence the analyzer (AGENTS.md §6)
- No `dynamic`
- No `late` as a workaround for unclear lifecycles
- Model absence explicitly: if a value can be null, declare `String?`
- Use `final String? value = ...` when a field may be absent

## Error Handling

- Expected failures (provider error, bad config, no clipboard) are **modelled as values**
- Exceptions are for **programmer error only**
- Never catch broadly and swallow: `on Object catch` is the floor, never bare `catch`
- Never log `error.toString()` — vendor exceptions carry the payload that caused them
- Log only `error.runtimeType` and application-authored context
- Never let an exception cross an abstraction boundary as a vendor type
- Convert to application types or model failures as events
- Every port (interface) failure is caught and guarded internally
- Provider returns `Stream<CorrectionEvent>` that includes `CorrectionFailed` event, never throws
- Clipboard read returns `Future<String?>` (null is absence, not error) or throws only on infrastructure failure

## Async and Futures

- `await future;` if you need the result
- `unawaited(future);` if the future runs in the background
- Never drop a future without one of these: analyzer rule `unawaited_futures` catches it
- Declare in `StatefulWidget`: `late final StreamSubscription<T> _subscription;`
- Assign in `initState()`: `_subscription = controller.changes.listen(...);`
- Dispose in `dispose()`: `await _subscription.cancel();`
- Never allocate controllers or subscriptions in `build()` — allocate once, dispose once
- If timing matters, structure the code to make it clear (model state, use latches, etc.)
- See `CorrectionController._dismissalStands` for an explicit state latch instead of timing

## Logging

- Never log `input_text`, suggestion bodies, or clipboard content — the daemon reads user input
- Log ids, kinds, latencies, and structure instead
- `logger.info()`, `logger.warning()`, `logger.error()` with optional context map
- Context is `Map<String, Object?>`: structured, safe to write to stderr

## Comments

- Explain **why**, never **what** — the code shows what it does
- Example: `// Wayland gives no key grabs, so this routes through the portal` ✓
- Bad: `// increment counter` ✗
- No dead code (git remembers it)
- No commented-out code (remove it)
- No `TODO` without a concrete follow-up note (delete the line or cite a ticket/issue)
- Every `ignore` comment needs a one-line reason explaining the override
- `///` for public APIs (classes, methods, fields)
- Explain the contract, not the implementation
- Cite SPEC CAP ids and AGENTS.md section numbers when relevant
- Example from `CorrectionController`:

## Function Design

- Keep functions short enough to read without scrolling (roughly ≤ 20 lines is the norm)
- Exceptions: long `switch` expressions and widget build trees
- If you need "and" to describe a function, split it — one job per function
- Avoid deep nesting (3+ levels inside a function is a smell)
- Prefer early returns and guard clauses
- Example:
- Keep parameter lists short (~3 arguments)
- Past ~3, pass a named record or a small value class
- No boolean flag parameters (`correct(text, retry: true)`) — write two named functions instead
- A function either returns a value OR causes an effect, not both (wherever practical)
- Streams return a value (the stream); callbacks return void
- No side effects hiding in getters
- Pure functions (decision-making): no I/O, no side effects, testable without fakes
- Thin functions (effects): call ports, write to streams, short and straightforward
- Never mix in the same function (AD-15 backstop discipline)

## Value Equality

- Override `operator ==` and `hashCode` when a type needs value comparison
- Reason: `Riverpod.select()` and `Stream.distinct()` need value deduplication
- Reason: `Set<T>` and `Map<T, V>` keying needs consistent equality
- State events that stream once and are never deduplicated (e.g., `SuggestionDelta`)
- Classes used only as builders, never in collections
- Always comment why: `// Both are streamed once, never deduplicated`

## Module/File Design

- Private helper types (e.g., `_Run`, internal classes) are fine
- Export only what the caller needs
- No barrel files (index files that re-export everything)
- `lib/src/domain/` imports only `dart:` libraries
- No `flutter`, no vendor SDKs, no `package:http`
- Enforced by `test/architecture/ad1_import_rule_test.dart`
- This keeps domain code testable without a Flutter binding
- Interface lives in domain: `abstract interface class CorrectionProvider`
- Implementations live at edges: `lib/src/infrastructure/correction/...`
- Ports are narrow (one job each)
- No singletons in domain; dependencies injected via constructor

## Widget Conventions

- Reach for `StatefulWidget` only if the widget genuinely owns state
- Extract widgets into named classes rather than `_buildFoo()` helper methods
- No I/O, no `async`
- No allocation of controllers or subscriptions
- No side effects
- Dispose everything in `dispose()` that was created in `initState()` or `didChangeDependencies()`
- One approach, chosen at the architecture step, used consistently
- This codebase uses Riverpod for dependency injection and state
- Never two competing patterns (Riverpod + Provider + setState all in one codebase)
- Never business logic in widget `setState` — push it to a controller/notifier

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

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

- **Four rings** with enforced import direction: domain (pure Dart) ← application ← infrastructure, ui ← application
- **Port abstraction for every platform/vendor seam**: corrections never see HTTP, processes, or SDK types; all leakage is adapter-private
- **Exactly one active (CorrectionProvider, Preset) pair** at startup, injected into controllers; no runtime provider selection (no fallback, no cascade)
- **Stateless correction sessions**: every correction is fresh, with no accumulated context
- **Streaming over batching**: progressive rendering via `SuggestionDelta` events before terminal `CorrectionCompleted`
- **Error as value, not exception**: expected failures (no clipboard, provider unavailable, malformed response) are modelled `CorrectionEvent` variants
- **Riverpod state only in application and ui**: domain logic is pure and testable without a binding

## Layers

- Purpose: Core business logic, value types, port interfaces
- Location: `lib/src/domain/`
- Contains: Correction types (`Suggestion`, `Preset`, `CorrectionEvent`, `CorrectionProvider`), hotkey types (`HotkeyBinding`, `GlobalHotkey`), config/clipboard/panel/tray/history/clock/logger ports
- Depends on: Only `dart:` libraries
- Used by: Application (to orchestrate) and infrastructure (to implement)
- Purpose: Use-case orchestration, state management with Riverpod, controller lifecycle
- Location: `lib/src/application/`
- Contains: Three controllers (`CorrectionController`, `PanelController`, `SettingsController`), Riverpod provider graph (`application/composition/`), immutable state classes
- Depends on: Domain, Riverpod (flutter_riverpod)
- Used by: UI (reads state), composition root (builds and disposes)
- Purpose: Concrete port implementations, platform/vendor adaptation, system integration
- Location: `lib/src/infrastructure/`
- Contains: Claude Agent SDK sidecar spawner, X11/Wayland hotkey adapters, drift SQLite, JSON config, window/tray/clipboard system adapters, lifecycle managers
- Depends on: Domain, vendor packages (dbus, drift, window_manager, tray_manager, ffi, sqlite3)
- Used by: Composition root (wired in) only; never imports application or ui
- Purpose: Flutter widget tree, presentation
- Location: `lib/src/ui/`
- Contains: Panel (correction display + editor), settings screen (hotkey + provider selection), daemon root widget
- Depends on: Application (for state and actions), domain read-only types
- Used by: runApp in main.dart

## Data Flow

### Primary Request Path (Hotkey → Show → Correct → Save)

### Secondary Flow: Settings Change (User modifies hotkey or provider)

### State Management

- **Immutable state objects** with `copyWith` pattern; held in controller fields and exposed as Riverpod providers
- **State updates** only happen inside controllers; UI reads them (no direct widget-state mutations)
- **Riverpod** manages provider graph, eager controller construction in `DaemonGraph.build()`, cleanup in `DaemonGraph.dispose()`
- **No global state or service locators** in domain code; all dependencies injected through constructors

## Key Abstractions

- Purpose: Abstract away provider implementation (local process, remote API, in-process library)
- Examples: `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` (sidecar), `lib/src/infrastructure/correction/unconfigured_correction_provider.dart` (no provider available)
- Pattern: Port interface (in domain) + concrete adapters (in infrastructure). Stream-based (not HTTP), stateless (no context accumulation), failure as modelled event
- Purpose: Abstract X11 key grabs and Wayland portal registration behind one interface
- Examples: `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` (dart:ffi to libX11.so.6), `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` (D-Bus + XDG GlobalShortcuts)
- Pattern: Display-server adapter choice happens once at startup in `daemon_startup.dart`, never switches at runtime. Binding outcome is a value (not exception). Composition and user can change the binding on Wayland (advisory); application has authority on X11.
- Purpose: Synchronous in-process visibility state (avoids IPC on hotkey show path)
- Examples: `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`
- Pattern: Sync getter `isVisible` + async show/hide + `changes` stream. Toggle reads sync state without await.
- Purpose: Central config authority — load, validate, persist
- Examples: `lib/src/infrastructure/config/json_config_store.dart`
- Pattern: One owner, all mutations go through it. Malformed files yield defaults + warning (never fail startup).
- Purpose: Persist corrections to history database
- Examples: `lib/src/infrastructure/persistence/drift_correction_repository.dart`
- Pattern: Single caller (`CorrectionController` at terminal event). One write, one transaction. Schema mirrors `suggestions[]` structure.

## Entry Points

- Location: Outside `lib/src/`, so it doesn't trigger AD-1's import lint
- Triggers: Program start (Flutter engine initialization)
- Responsibilities: 
- Triggers: `runApp()` in main.dart
- Responsibilities: Root widget tree, passes Riverpod container to children

## Architectural Constraints

- **Dependency direction:** `domain` imports only `dart:*`; `application` never imports `infrastructure` or ui; `ui` never imports `infrastructure`; only composition root knows both sides (mechanically enforced by `test/architecture/ad1_import_rule_test.dart`)
- **Global state:** No module-level singletons in domain or application. Infrastructure adapters may hold platform-specific state (e.g. `X11KeyGrabRegistrar`'s private X `Display` and worker isolate) but their public interface is behind a port, so swapping is a one-file change.
- **Circular imports:** None. Dependency graph is a DAG.
- **Riverpod graph:** Eager construction in `DaemonGraph.build()` (not lazy) so listeners are attached before the first event. Disposal order: correction controller (drains history writes), panel controller, settings controller, container, then adapters.
- **Concurrency:** Resident daemon runs one hotkey/correction/settings flow at a time. **CAP-1's <100 ms budget is achieved by staying off the show path, not by parallelism** — that rule is unchanged and is what the following exception is bounded by. Exactly one worker isolate exists: `X11KeyGrabRegistrar` pumps its private X11 connection from one, because `XNextEvent` is a blocking read that must not run on the isolate rendering the panel. It is an adapter-private implementation detail confined behind the `HotkeyRegistrar` port (AD-9, AGENTS.md §4.2), so nothing above the seam knows it exists, and it is deliberately **off** the hotkey show path: the isolate only posts a press message, and every decision about showing the panel stays on the main isolate. Do not add a second isolate to make something faster — that is the reasoning this line exists to protect.
- **Streaming:** Single-subscription streams from `CorrectionProvider.correct()`. Cancellation tears down provider work (kill child process). Broadcast streams for UI observation (e.g., `CorrectionController._changes`).
- **Persistence:** Every terminal correction event persists exactly once, in one transaction, regardless of panel visibility. Schema is immutable in MVP; drift migrations deferred.

## Anti-Patterns

### Using vendor types above infrastructure boundary

### Selecting a provider at runtime

### Accumulating state in a provider

### Logging the input text

## Error Handling

- **Provider failure** → `CorrectionFailed(kind, message)` event emitted by provider, rendered inline in panel with Retry action (not thrown, not swallowed)
- **No clipboard content** → `ClipboardPort.read()` returns empty string; correction runs on empty input or is skipped
- **Config malformed** → `ConfigStore` loads defaults + logs warning; daemon stays up and usable from tray
- **Hotkey bind refused** → `bind()` returns `HotkeyUnavailable(message)` (not exception); tray menu still works as fallback
- **Startup failure** (after lock taken) → `_abort()` in main.dart tears down in order and exits 1
- **Framework error** (widget build fails, async error unhandled) → `FlutterError.onError` + `PlatformDispatcher.onError` forward to logger, daemon stays resident

## Cross-Cutting Concerns

- Port: `Logger` (`lib/src/domain/logger.dart`)
- Implementation: `StderrLogger` (structured lines to stderr, never user text)
- Access: Injected into controllers and adapters; used for warnings and errors only, never for verbose traces
- Rule: No `inputText` or `suggestionText` in logs (privacy: daemon reads the clipboard)
- Config validation happens once in `ConfigStore`; never re-parsed
- Preset and provider id validated at composition root (not at correction time)
- Hotkey binding validated per-backend (AD-12: if a key is unrepresentable, that backend is skipped)
- No authentication in MVP (resident, single-user desktop daemon)
- Provider credentials flow through config, behind `ConfigStore` write-through (never exposed to UI as a field)
- API keys, if any provider requires them, are loaded from config and passed to the provider adapter only

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| bmad-advanced-elicitation | 'Push the LLM to reconsider, refine, and improve its recent output. Use when user asks for deeper critique or mentions a known deeper critique method, e.g. socratic, first principles, pre-mortem, red team.' | `.claude/skills/bmad-advanced-elicitation/SKILL.md` |
| bmad-agent-analyst | Strategic business analyst and requirements expert. Use when the user asks to talk to Mary or requests the business analyst. | `.claude/skills/bmad-agent-analyst/SKILL.md` |
| bmad-agent-architect | System architect and technical design leader. Use when the user asks to talk to Winston or requests the architect. | `.claude/skills/bmad-agent-architect/SKILL.md` |
| bmad-agent-builder | Builds, edits or analyzes Agent Skills through conversational discovery. Use when the user requests to "Create an Agent", "Analyze an Agent" or "Edit an Agent". | `.claude/skills/bmad-agent-builder/SKILL.md` |
| bmad-agent-dev | Senior software engineer for story execution and code implementation. Use when the user asks to talk to Amelia or requests the developer agent. | `.claude/skills/bmad-agent-dev/SKILL.md` |
| bmad-agent-pm | Product manager for PRD creation and requirements discovery. Use when the user asks to talk to John or requests the product manager. | `.claude/skills/bmad-agent-pm/SKILL.md` |
| bmad-agent-tech-writer | Technical documentation specialist and knowledge curator. Use when the user asks to talk to Paige or requests the tech writer. | `.claude/skills/bmad-agent-tech-writer/SKILL.md` |
| bmad-agent-ux-designer | UX designer and UI specialist. Use when the user asks to talk to Sally or requests the UX designer. | `.claude/skills/bmad-agent-ux-designer/SKILL.md` |
| bmad-architecture | 'Produce the architecture: a lean spine of invariants that keeps everything built from it consistent, projected into whatever format the work needs. Use when the user says "create the architecture", "create technical architecture", "architecture spine", or "create a solution design".' | `.claude/skills/bmad-architecture/SKILL.md` |
| bmad-bmb-setup | Sets up BMad Builder module in a project. Use when the user requests to 'install bmb module', 'configure BMad Builder', or 'setup BMad Builder'. | `.claude/skills/bmad-bmb-setup/SKILL.md` |
| bmad-brainstorming | Facilitate a brainstorming session using diverse creative techniques. Use when the user says 'help me brainstorm' or 'help me ideate'. | `.claude/skills/bmad-brainstorming/SKILL.md` |
| bmad-check-implementation-readiness | 'Validate PRD, UX, Architecture and Epics specs are complete. Use when the user says "check implementation readiness".' | `.claude/skills/bmad-check-implementation-readiness/SKILL.md` |
| bmad-checkpoint-preview | 'LLM-assisted human-in-the-loop review. Make sense of a change, focus attention where it matters, test. Use when the user says "checkpoint", "human review", or "walk me through this change".' | `.claude/skills/bmad-checkpoint-preview/SKILL.md` |
| bmad-cis-agent-brainstorming-coach | Elite brainstorming specialist for facilitated ideation sessions. Use when the user asks to talk to Carson or requests the Brainstorming Specialist. | `.claude/skills/bmad-cis-agent-brainstorming-coach/SKILL.md` |
| bmad-cis-agent-creative-problem-solver | Master problem solver for systematic problem-solving methodologies. Use when the user asks to talk to Dr. Quinn or requests the Master Problem Solver. | `.claude/skills/bmad-cis-agent-creative-problem-solver/SKILL.md` |
| bmad-cis-agent-design-thinking-coach | Design thinking maestro for human-centered design processes. Use when the user asks to talk to Maya or requests the Design Thinking Maestro. | `.claude/skills/bmad-cis-agent-design-thinking-coach/SKILL.md` |
| bmad-cis-agent-innovation-strategist | Disruptive innovation oracle for business model innovation and strategic disruption. Use when the user asks to talk to Victor or requests the Disruptive Innovation Oracle. | `.claude/skills/bmad-cis-agent-innovation-strategist/SKILL.md` |
| bmad-cis-agent-presentation-master | Visual communication and presentation expert for slide decks, pitch decks, and visual storytelling. Use when the user asks to talk to Caravaggio or requests the Presentation Expert. | `.claude/skills/bmad-cis-agent-presentation-master/SKILL.md` |
| bmad-cis-agent-storyteller | Master storyteller for compelling narratives using proven frameworks. Use when the user asks to talk to Sophia or requests the Master Storyteller. | `.claude/skills/bmad-cis-agent-storyteller/SKILL.md` |
| bmad-cis-design-thinking | 'Guide human-centered design processes using empathy-driven methodologies. Use when the user says "lets run design thinking" or "I want to apply design thinking"' | `.claude/skills/bmad-cis-design-thinking/SKILL.md` |
| bmad-cis-innovation-strategy | 'Identify disruption opportunities and architect business model innovation. Use when the user says "lets create an innovation strategy" or "I want to find disruption opportunities"' | `.claude/skills/bmad-cis-innovation-strategy/SKILL.md` |
| bmad-cis-problem-solving | 'Apply systematic problem-solving methodologies to complex challenges. Use when the user says "guide me through structured problem solving" or "I want to crack this challenge with guided problem solving techniques"' | `.claude/skills/bmad-cis-problem-solving/SKILL.md` |
| bmad-cis-storytelling | 'Craft compelling narratives using story frameworks. Use when the user says "help me with storytelling" or "I want to create a narrative through storytelling"' | `.claude/skills/bmad-cis-storytelling/SKILL.md` |
| bmad-code-review | 'Adversarial code review using parallel review layers and structured triage. Use when the user says "run code review" or "review this code"' | `.claude/skills/bmad-code-review/SKILL.md` |
| bmad-correct-course | 'Manage significant changes during sprint execution. Use when the user says "correct course" or "propose sprint change"' | `.claude/skills/bmad-correct-course/SKILL.md` |
| bmad-create-architecture | 'Deprecated — forwards to bmad-architecture (create intent).' | `.claude/skills/bmad-create-architecture/SKILL.md` |
| bmad-create-epics-and-stories | 'Break requirements into epics and user stories. Use when the user says "create the epics and stories list"' | `.claude/skills/bmad-create-epics-and-stories/SKILL.md` |
| bmad-create-prd | 'Deprecated — forwards to bmad-prd (create intent).' | `.claude/skills/bmad-create-prd/SKILL.md` |
| bmad-create-story | 'Creates a dedicated story file with all the context the agent will need to implement it later. Use when the user says "create the next story" or "create story [story identifier]"' | `.claude/skills/bmad-create-story/SKILL.md` |
| bmad-customize | Authors and updates customization overrides for installed BMad skills. Use when the user says 'customize bmad', 'override a skill', 'change agent behavior', or 'customize a workflow'. | `.claude/skills/bmad-customize/SKILL.md` |
| bmad-deep-recon | 'Decision-grade research, three ways: draft a deep-research prompt for the user to run in their own tool (ChatGPT, Gemini, Grok, Perplexity, …), process a finished research report — file it, distill a succinct cited summary with metadata that downstream skills consume without reprocessing — or run the research here through web fan-out. Shipped type packs: market, domain, technical, competitive, user-voice, academic-lit — plus a select shape for choose-between decisions and custom types via overrides. Use when the user says "deep recon", "research this", "draft a research prompt", "process this research report", "market research", "domain research", "technical research", "competitor research", "literature review", or "help me choose between".' | `.claude/skills/bmad-deep-recon/SKILL.md` |
| bmad-dev-auto | 'One iteration of an unattended development loop. Use when invoked by name.' | `.claude/skills/bmad-dev-auto/SKILL.md` |
| bmad-dev-story | 'Execute story implementation following a context filled story spec file. Use when the user says "dev this story [story file]" or "implement the next story in the sprint plan"' | `.claude/skills/bmad-dev-story/SKILL.md` |
| bmad-document-project | 'Document brownfield projects for AI context. Use when the user says "document this project" or "generate project docs"' | `.claude/skills/bmad-document-project/SKILL.md` |
| bmad-domain-research | 'Deprecated — forwards to bmad-deep-recon (domain type).' | `.claude/skills/bmad-domain-research/SKILL.md` |
| bmad-edit-prd | 'Deprecated — forwards to bmad-prd (update intent).' | `.claude/skills/bmad-edit-prd/SKILL.md` |
| bmad-editorial-review | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-editorial-review/SKILL.md` |
| bmad-editorial-review-prose | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-editorial-review-prose/SKILL.md` |
| bmad-editorial-review-structure | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-editorial-review-structure/SKILL.md` |
| bmad-eval-runner | Run a skill's evals and report results. Use when the user wants to evaluate a skill, run evals, benchmark a skill, validate triggers, optimize a description, or grade skill outputs. | `.claude/skills/bmad-eval-runner/SKILL.md` |
| bmad-forge-idea | Pressure-test an idea through persona-driven interrogation until it hardens, proves out, or dies cheaply. Use when the user says 'forge an idea', 'pressure-test this idea', 'stress-test my thinking', or 'harden this idea'. | `.claude/skills/bmad-forge-idea/SKILL.md` |
| bmad-generate-project-context | 'Create project-context.md with AI rules. Use when the user says "generate project context" or "create project context"' | `.claude/skills/bmad-generate-project-context/SKILL.md` |
| bmad-help | 'Analyzes current state and user query to answer BMad questions or recommend the next skill(s) to use. Use when user asks for help, bmad help, what to do next, or what to start with in BMad.' | `.claude/skills/bmad-help/SKILL.md` |
| bmad-loop-resolve | 'Interactive escalation-resolution workflow for the bmad-loop orchestrator. A bmad-loop run paused on a CRITICAL escalation (a contradiction or gap a dev/review session could not safely resolve alone); you and the human disambiguate the frozen spec so the story can be re-driven. Invoked as /bmad-loop-resolve <story-key>. Unlike the automated dev/review sessions this session is interactive — a human is present and you SHOULD ask.' | `.claude/skills/bmad-loop-resolve/SKILL.md` |
| 'bmad-loop-setup' | Sets up BMAD Loop Skills module in a project. Use when the user requests to 'install bmad-loop module', 'configure BMAD Loop Skills', or 'setup BMAD Loop Skills'. | `.claude/skills/bmad-loop-setup/SKILL.md` |
| bmad-loop-sweep | 'Triage the deferred-work ledger for the bmad-loop orchestrator: verify every open entry against the actual codebase and return a machine-readable partition (bundles, already-resolved, blocked, skip, human decisions). Also migrates legacy pre-DW-format ledgers when invoked with --migrate. Automation-only — invoked by bmad-loop sweep runs, not by humans.' | `.claude/skills/bmad-loop-sweep/SKILL.md` |
| bmad-market-research | 'Deprecated — forwards to bmad-deep-recon (market type).' | `.claude/skills/bmad-market-research/SKILL.md` |
| bmad-module-builder | Plans, creates, and validates BMad modules. Use when the user requests to 'ideate module', 'plan a module', 'create module', 'build a module', or 'validate module'. | `.claude/skills/bmad-module-builder/SKILL.md` |
| bmad-party-mode | 'Orchestrates lively group discussions between installed BMAD agents or custom personas, and helps author custom parties. Use when the user requests party mode, a roundtable, or multiple agent perspectives — or wants to create/configure a party, define personas, or build an AI focus-group panel.' | `.claude/skills/bmad-party-mode/SKILL.md` |
| bmad-prd | Create, update, or validate a PRD. Use when the user wants help producing, editing, or validating a PRD. | `.claude/skills/bmad-prd/SKILL.md` |
| bmad-prfaq | Working Backwards PRFAQ challenge that stress-tests a product concept customer-first. Use when the user requests to 'create a PRFAQ', 'work backwards', or 'run the PRFAQ challenge'. | `.claude/skills/bmad-prfaq/SKILL.md` |
| bmad-product-brief | Create, update, or validate a product brief. Use when the user wants help producing, editing, or validating a brief. | `.claude/skills/bmad-product-brief/SKILL.md` |
| bmad-qa-generate-e2e-tests | 'Generate end to end automated tests for existing features. Use when the user says "create qa automated tests for [feature]"' | `.claude/skills/bmad-qa-generate-e2e-tests/SKILL.md` |
| bmad-quick-dev | 'Implements any user intent, requirement, story, bug fix or change request by producing clean working code artifacts that follow the project''s existing architecture, patterns and conventions. Use when the user wants to build, fix, tweak, refactor, add or modify any code, component or feature.' | `.claude/skills/bmad-quick-dev/SKILL.md` |
| bmad-retrospective | 'Post-epic review to extract lessons and assess success. Use when the user says "run a retrospective" or "lets retro the epic [epic]"' | `.claude/skills/bmad-retrospective/SKILL.md` |
| bmad-review | 'Multi-lens review over any diff, doc, spec, or artifact — whichever installed lenses fit the content, run singly or together. Shipped lenses include adversarial, edge-case, verification-gap, structure, and prose. Use when the user says "review this", "critical review", "editorial review", "hunt edge cases", "review the structure", or "review the prose".' | `.claude/skills/bmad-review/SKILL.md` |
| bmad-review-adversarial-general | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-review-adversarial-general/SKILL.md` |
| bmad-review-edge-case-hunter | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-review-edge-case-hunter/SKILL.md` |
| bmad-review-verification-gap | 'Deprecated — forwards to bmad-review.' | `.claude/skills/bmad-review-verification-gap/SKILL.md` |
| bmad-spec | Distill any intent input into the SPEC kernel + companions — the canonical, preservation-validated machine contract for downstream work. Use when the user says "create a spec", "distill this into a spec", "validate this spec", "update the spec", or "break this into stories". | `.claude/skills/bmad-spec/SKILL.md` |
| bmad-sprint-planning | 'Generate sprint status tracking from epics. Use when the user says "run sprint planning" or "generate sprint plan"' | `.claude/skills/bmad-sprint-planning/SKILL.md` |
| bmad-sprint-status | 'Summarize sprint status and surface risks. Use when the user says "check sprint status" or "show sprint status"' | `.claude/skills/bmad-sprint-status/SKILL.md` |
| bmad-tea | Master Test Architect and Quality Advisor. Use when the user asks to talk to Murat or requests the Test Architect. | `.claude/skills/bmad-tea/SKILL.md` |
| bmad-teach-me-testing | 'Teach testing progressively through structured sessions. Use when user says "lets learn testing" or "I want to study test practices"' | `.claude/skills/bmad-teach-me-testing/SKILL.md` |
| bmad-technical-research | 'Deprecated — forwards to bmad-deep-recon (technical type).' | `.claude/skills/bmad-technical-research/SKILL.md` |
| bmad-testarch-atdd | 'Generate red-phase acceptance test scaffolds using the TDD cycle. Use when the user says "lets write acceptance tests" or "I want to do ATDD"' | `.claude/skills/bmad-testarch-atdd/SKILL.md` |
| bmad-testarch-automate | 'Expand test automation coverage for codebase. Use when user says "lets expand test coverage" or "I want to automate tests"' | `.claude/skills/bmad-testarch-automate/SKILL.md` |
| bmad-testarch-ci | 'Scaffold CI/CD quality pipeline with test execution. Use when the user says "lets setup CI pipeline" or "I want to create quality gates"' | `.claude/skills/bmad-testarch-ci/SKILL.md` |
| bmad-testarch-framework | 'Initialize test framework with Playwright or Cypress. Use when the user says "lets setup test framework" or "I want to initialize testing framework"' | `.claude/skills/bmad-testarch-framework/SKILL.md` |
| bmad-testarch-nfr | 'Audit NFR evidence for performance, security, reliability, and scalability. Use when implementation evidence exists and the user says "audit NFR evidence", "audit NFRs", or "evaluate non-functional requirements"' | `.claude/skills/bmad-testarch-nfr/SKILL.md` |
| bmad-testarch-test-design | 'Create system-level or epic-level test plans. Use when the user says "lets design test plan" or "I want to create test strategy"' | `.claude/skills/bmad-testarch-test-design/SKILL.md` |
| bmad-testarch-test-review | 'Review test quality using best practices validation. Use when user says "lets review tests" or "I want to evaluate test quality"' | `.claude/skills/bmad-testarch-test-review/SKILL.md` |
| bmad-testarch-trace | 'Generate traceability matrix and quality gate decision. Use when the user says "lets create traceability matrix" or "I want to analyze test coverage"' | `.claude/skills/bmad-testarch-trace/SKILL.md` |
| bmad-ux | Plan UX patterns and design specifications. Use when the user says "lets create UX design" or "create UX specifications" or "help me plan the UX" | `.claude/skills/bmad-ux/SKILL.md` |
| bmad-validate-prd | 'Deprecated — forwards to bmad-prd (validate intent).' | `.claude/skills/bmad-validate-prd/SKILL.md` |
| bmad-workflow-builder | Builds, edits, and analyzes workflows and skills. Use when the user requests to "build a workflow", "modify a workflow", "quality check workflow", or "analyze skill". | `.claude/skills/bmad-workflow-builder/SKILL.md` |
| memory | Session state backend for WDS. Called by wrap, start, and handoff tools — never directly by users. Writes to progress/ in the project repo. | `.claude/skills/memory/SKILL.md` |
| sync | Syncs WDS skills from the current project (_bmad/wds/) to ~/.claude/commands/ so they work in any project. Called automatically on every agent activation. | `.claude/skills/sync/SKILL.md` |
| wds-0-alignment-signoff | "Create alignment around your idea before starting the project" | `.claude/skills/wds-0-alignment-signoff/SKILL.md` |
| wds-0-project-setup | "Project onboarding - determine project type, complexity, tech stack, and route to correct phase" | `.claude/skills/wds-0-project-setup/SKILL.md` |
| wds-1-project-brief | "Establish project context - foundation for all design work" | `.claude/skills/wds-1-project-brief/SKILL.md` |
| wds-2-trigger-mapping | "Map business goals to user psychology through structured workshops" | `.claude/skills/wds-2-trigger-mapping/SKILL.md` |
| wds-3-scenarios | "Create UX scenario outlines from Trigger Map through structured micro-steps" | `.claude/skills/wds-3-scenarios/SKILL.md` |
| wds-4-ux-design | "Transform ideas into detailed visual specifications through scenario-driven design" | `.claude/skills/wds-4-ux-design/SKILL.md` |
| wds-5-agentic-development | "AI-assisted development, testing, and reverse engineering through structured agent collaboration" | `.claude/skills/wds-5-agentic-development/SKILL.md` |
| wds-6-asset-generation | "Generate visual and text assets from specifications through AI-powered creative production" | `.claude/skills/wds-6-asset-generation/SKILL.md` |
| wds-7-design-system | "Create, import, browse, and maintain design system components and tokens" | `.claude/skills/wds-7-design-system/SKILL.md` |
| wds-8-product-evolution | "Brownfield improvements — the full WDS pipeline in miniature for existing products" | `.claude/skills/wds-8-product-evolution/SKILL.md` |
| wds-agent-freya-ux | Strategic UX designer and design thinking partner for WDS. Use when the user asks to talk to Freya or requests the WDS designer. | `.claude/skills/wds-agent-freya-ux/SKILL.md` |
| wds-agent-mimir-builder | Implementation agent. Owns the tech audit, the PRD, and the build. Reads Freya's Work Orders and turns them into working code — one verified task at a time. | `.claude/skills/wds-agent-mimir-builder/SKILL.md` |
| wds-agent-saga-analyst | Strategic business analyst and product discovery partner for WDS. Use when the user asks to talk to Saga or requests the WDS analyst. | `.claude/skills/wds-agent-saga-analyst/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
