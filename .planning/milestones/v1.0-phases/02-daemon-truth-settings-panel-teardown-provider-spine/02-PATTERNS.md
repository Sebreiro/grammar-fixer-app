# Phase 02: Daemon Truth — Pattern Map

**Mapped:** 2026-09-24  
**Scope:** all 40 roadmap IDs, Waves A–F  
**Source rule:** analogs below are git-tracked source, not generated or runtime mirrors. File names for new seams are provisional; preserve the existing one-public-type-per-file convention.

## File Classification

| New or modified file/group | Role | Data flow | Closest tracked analog | Match |
|---|---|---|---|---|
| `lib/src/application/settings_controller.dart`, `settings_state.dart` | controller/model | event-driven, CRUD | `settings_controller.dart`, `settings_state.dart` | exact |
| `lib/src/infrastructure/config/json_config_store.dart`, `default_app_config.dart`, `lib/src/domain/config/app_config.dart` | store/config/model | file-I/O, CRUD | `json_config_store.dart` | exact |
| `lib/src/infrastructure/tray/tray_manager_tray.dart`, tray port/menu/icon | service/port | event-driven | `tray_manager_tray.dart` | exact |
| `lib/src/ui/settings/settings_screen.dart`, status/notice widgets | component | event-driven | `settings_screen.dart`, `hotkey_status_view.dart` | exact |
| `lib/main.dart`, `lib/src/application/composition/daemon_graph.dart` | composition/config | request-response | same files | exact |
| `lib/src/ui/panel/correction_panel.dart`, `suggestion_card.dart`, `suggestion_list.dart` | component | streaming, event-driven | same files | exact |
| `lib/src/application/correction_controller.dart`, `correction_state.dart` | controller/model | streaming, event-driven | same files | exact |
| `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`, `panel_window.dart` | service/port | event-driven | same files | exact |
| `test/fakes/fake_panel_window.dart` | test fake | event-driven | same file | exact; fixture repair only |
| `lib/src/infrastructure/system/daemon_startup.dart`, `daemon_lifecycle.dart`, `lib/main.dart` | service/composition | event-driven | same files | exact |
| `lib/src/infrastructure/correction/openai_compatible/*` | provider/utility | streaming, request-response | `claude_agent_sdk_correction_provider.dart`, `register_tagged_stream_parser.dart` | role match; HTTP/SSE has no exact analog |
| `lib/src/domain/correction/secret_store.dart` (provisional), infrastructure keyring implementation | port/service | request-response | `correction_provider.dart`, `json_config_store.dart` | role match; Secret Service has no exact analog |
| `lib/src/infrastructure/correction/provider_registry.dart`, `active_correction.dart`, application composition providers | config/service | request-response | same files | exact |
| Frozen source spec and companions, architecture spine, deferred ledger, story/checklist records | documentation | batch | existing respective documents | exact; update through mandated generators where required |

The phase contract prohibits new tests, gates, and CI work; the existing `FakePanelWindow` is the only named fixture repair. Do not infer additional test files from general repository practice. The phase contract takes precedence over AGENTS.md §7 here.

## Pattern Assignments

### Settings, config, and tray — Wave A

**Config analog:** `lib/src/infrastructure/config/json_config_store.dart:59-89`. Validation precedes the serialized file queue; writes broadcast the committed immutable value. Extend this queue for file/UI races and keep the current snapshot authoritative:

```dart
Future<void> write(AppConfig config) async {
  final problem = validationProblem(config);
  if (problem != null) {
    throw ArgumentError.value(config, 'config', problem);
  }
  await _serialized(() async {
    await _writeFile(config);
    _loaded = config;
    if (!_changes.isClosed) _changes.add(config);
  });
}
```

`json_config_store.dart:183-193` writes through a unique temp file and rename. Preserve that atomic file-I/O pattern. `settings_controller.dart:175-188` already binds first and derives the config change through `config.copyWith`; `:555-580` reads `ConfigStore.current` and maps failure to a user-facing value. Apply those patterns to provider fields, hotkey effective/preferred reporting, and tray status fan-out. The config key write conflict in RESEARCH.md remains a planning decision: do not silently rewrite or remove a hand-placed secret.

**UI analog:** `lib/src/ui/settings/settings_screen.dart` and `hotkey_status_view.dart` for state-driven Settings controls and status. Add Base URL/Model validation and a source-only secret line through the same controller state. Keep the preset prompt and model paired. **Tray analog:** `lib/src/infrastructure/tray/tray_manager_tray.dart` for native menu rebuilding; status text belongs below the existing Open action while the action stays enabled.

### Panel geometry, selection, and copy — Wave B

**Widget analog:** `lib/src/ui/panel/suggestion_card.dart:1-4,59-115` uses package Flutter import, relative domain/widget imports, and a pure `StatelessWidget`. Its `Card(color: selected ? theme.colorScheme.primaryContainer : null)` is the current selection cue; add the check mark and card-local copy status in this row, without I/O in `build()`. The `IconButton` is enabled by `actionable`, preserving copy from every completed variant.

**Controller analog:** `lib/src/application/correction_controller.dart:211-223,240-279`. The current same-card branch clears selection; replace it with an idempotent return. The `_copyToken` guard discards stale feedback but does not serialize actual clipboard writes; extend it with ordered writes and last-request-wins state. Preserve the `_disposed` and current-token guards around async completions. `:479-500` resets run state and invokes the selected provider; use this boundary to clear copy feedback on a new correction. `lib/main.dart` owns initial warm-window geometry; avoid pointer/window I/O in the hotkey show path.

### Panel event reconciliation — Wave C

**Analog:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` is the existing single owner of native show, hide, blur, focus, timeout, and disposal events. Its event queue and reconciliation logic (`:411-453`, `:519-632`, `:944-1078`, `:1278-1359`) should be amended together, retaining request/session identity until delayed native events settle. `lib/src/application/panel_controller.dart` consumes the resulting visibility state. Update only the existing `test/fakes/fake_panel_window.dart` iconify behavior as the phase spec permits.

### Startup and teardown — Wave D

**Analog:** `lib/src/infrastructure/system/daemon_lifecycle.dart:261-277,313-342` caches `shutdown()` as one future and runs named, bounded steps. Copy the one-future join and per-step failure isolation into pre-lifecycle abort and startup-stop handling:

```dart
Future<void> shutdown() => _shutdown ??= _run();

Future<void> _step(String what, Future<void> Function() run) async {
  var timedOut = false;
  try {
    await run().timeout(_stepTimeout, onTimeout: () { timedOut = true; });
  } on Object catch (error) {
    _log(() => _logger.error('$what failed',
      context: {'error_type': error.runtimeType.toString()}));
    return;
  }
  // Report timeout, then continue to the next step.
}
```

`daemon_startup.dart` owns the bind and failed-start release; `main.dart` owns resources created before lifecycle construction. Ensure a stop during the portal bind joins startup before graph disposal. The excerpt above is a pattern, not a wholesale replacement for existing longer cleanup.

### Provider, secret, and composition — Wave E

**Provider analog:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart:29-78`. Keep adapter-owned ID/settings keys, implement `CorrectionProvider`, and allocate a fresh run per `correct()` call:

```dart
@override
Stream<CorrectionEvent> correct({required String text, required Preset preset}) {
  final run = _SidecarRun(
    parser: _parser,
    timeout: _timeout,
    request: SidecarRequest(
      text: text, model: preset.model, systemPrompt: preset.systemPrompt,
    ),
  );
  return run.events;
}
```

Use the run ownership/cancellation pattern at `:83-151,386-408`, but replace process transport with per-call `HttpClient` and SSE decoding. `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` is the shared pure parser: feed decoded `choices[0].delta.content` into it. Require complete SSE framing and successful terminal markers before treating output as complete. HTTP failures map to the four existing `CorrectionFailureKind` values; never expose HTTP or key types at the domain port.

**Registry analog:** `lib/src/infrastructure/correction/provider_registry.dart:1-38` maps IDs to factories and returns null for unknown IDs; add one factory entry at this edge, not a switch in the correction pipeline. `active_correction.dart` and `lib/src/application/composition/daemon_graph.dart` resolve the selected provider and prompt/model preset. Snapshot both per run so later settings changes cannot alter an in-flight correction or its history record.

**Secret port:** follow the narrow port form of `lib/src/domain/correction/correction_provider.dart` and put OS/keyring work in infrastructure. No tracked Secret Service implementation is a close analog. Return only source/availability to Settings; the provider edge receives the secret. Resolution is keyring, then environment, then hand-placed config. Never log a key, request body, response body, or exception string.

### Documentation reconciliation — Wave F

The architecture spine and frozen source SPEC are analogs for their own changes. Regenerate the product SPEC through `/bmad-spec` and the spine through `/bmad-architecture`, following `AGENTS.md` and `PLAN.md`; do not hand-edit generated source contracts. Update the deferred-work ledger append-only by changing `status:` and adding `resolution:` for each of the 40 IDs. Reconcile CAP-2, AD-9 and other named stale records only after implementation evidence exists.

## Shared Patterns

- **Imports and boundaries:** UI widgets import Flutter and relative domain types (`suggestion_card.dart:1-4`). Infrastructure imports the domain port (`provider_registry.dart:1-4`). Domain remains pure Dart and vendor-independent.
- **State/error values:** `settings_controller.dart:555-580` converts expected config failures into `SettingsFailure`; `correction_controller.dart:498-510` catches a provider contract breach and funnels it to the existing inline failure path. Log only safe error type/context, as `daemon_lifecycle.dart:322-327` does.
- **Async ownership:** `daemon_lifecycle.dart:261-277` joins repeated shutdown requests; `claude_agent_sdk_correction_provider.dart:83-151` owns each stream run and cancellation. Use both for HTTP and startup teardown.
- **Privacy:** no auth middleware exists. API-key handling is a local secret resolution concern at infrastructure/composition, not a controller auth pattern.

## No Analog Found

| New seam | Role | Data flow | Planner source |
|---|---|---|---|
| OpenAI-compatible SSE frame decoder | utility | streaming | 02-RESEARCH.md and 02-AI-SPEC.md; reuse tagged parser only after SSE decode |
| Secret Service keyring adapter | service | request-response | 02-RESEARCH.md; implement behind new narrow `SecretStore` port |
| Cross-display pointer geometry on Wayland | service | event-driven | 02-RESEARCH.md feasibility conflict D-01; resolve before Wave B |

## Metadata

**Search scope:** tracked `lib/`, `test/fakes/`, Phase 02 contracts and frozen documentation.  
**Verification:** analog paths checked with `git ls-files`; no install/runtime mirrors named.  
**Important unresolved decisions:** D-01 pointer-display placement against hotkey-path and Wayland limits; D-13 hand-placed config key on unrelated writes; preferred versus effective hotkey persistence. Preserve these for the planner.
