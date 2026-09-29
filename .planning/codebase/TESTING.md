# Testing Patterns

**Analysis Date:** 2026-08-30

## Test Framework

**Test Runner:**
- `test` package (v1.31.0 in pubspec.yaml dev_dependencies)
- Pure Dart tests: `dart test` command (no Flutter binding)
- Widget/Platform tests: `flutter test` command

**Assertion Library:**
- Built into `test` package: `expect()`, matchers like `isTrue`, `equals()`, `findsOneWidget`
- `flutter_test` for widget matching and interaction

**Run Commands:**
```bash
dart test                           # Run all Dart tests (no Flutter binding)
flutter test                        # Run all tests including widget tests
dart test --tags=live --run-skipped  # Run live/integration tests (container-skipped)
dart test --tags=-live              # Skip live tests (default)
```

**Configuration File:** `dart_test.yaml`

## Test Configuration

**File:** `/workspace/dart_test.yaml`

**Key Settings:**
```yaml
tags:
  live:
    skip: >-
      spawns the real Python sidecar, claude_agent_sdk and the `claude` CLI —
      opt in deliberately with `dart test --tags=live --run-skipped`

concurrency: 1
```

**Why concurrency: 1?**
- Two test suites that bind a unix socket simultaneously will conflict
- `SingleInstanceLock` (AD-14) binds `ServerSocket` on abstract namespace
- The Dart VM allows exactly one abstract socket per **process**
- `single_instance_lock_test.dart` and `daemon_startup_test.dart` both bind one
- Serial execution is the only setting both `dart test` and `flutter test` honour

**Analysis Options:** `analysis_options.yaml`
- Includes `flutter_lints` for lint rules
- Strict language settings: `strict-casts`, `strict-raw-types`
- Custom rule: `unawaited_futures` (catch dropped futures inside async bodies)
- Every ignore comment requires a one-line justification

## Test Organization

**Directory Structure:**
```
test/
├── domain/                    # Pure Dart domain logic (no Flutter binding)
├── application/               # Controllers and state management
├── ui/                        # Widget tests (harnesses, flows)
│   ├── panel/                # Panel widget tests
│   └── settings/             # Settings screen widget tests
├── platform/                  # Platform-specific adapters
│   ├── *_live_test.dart      # Runtime observations (skipped in container)
│   └── *_test.dart           # Adapter logic tests (with mocks/fakes)
├── infrastructure/            # Persistence, config, hotkey, tray adapters
│   ├── config/
│   ├── correction/
│   ├── hotkey/
│   ├── panel/
│   ├── persistence/
│   ├── system/
│   └── tray/
├── architecture/              # Architectural rule enforcement
├── composition/               # Dependency injection and wiring
├── fakes/                     # Fake implementations of domain ports
└── support/                   # Test utilities and helpers
```

**Test File Naming:**
- `*_test.dart` for standard tests
- `*_live_test.dart` for tests that require real runtime (X11/Wayland session, etc.)
- `*_test.dart` files with `skip: 'reason'` for unobservable claims (documented in skip reason)

**Corresponding Paths:**
- Domain: `lib/src/domain/` ↔ `test/domain/`
- Application: `lib/src/application/` ↔ `test/application/`
- UI: `lib/src/ui/` ↔ `test/ui/`
- Infrastructure: `lib/src/infrastructure/` ↔ `test/infrastructure/`

## Test Naming

**Test names read as behaviour, not method names:**

Bad:
```dart
test('test_readText', () { ... });
test('testEditorTextUpdate', () { ... });
```

Good:
```dart
test('CAP-2: readText resolves to the plain text the clipboard holds', () { ... });
test('CAP-3: the user can edit the text after a submission', () { ... });
```

**Pattern:** Start with SPEC CAP id or AGENTS.md section, then describe the **observable outcome** in plain English

**Examples from the codebase:**
- `'CAP-2: a show after a dismissal re-seeds the editor from the current clipboard'`
- `'CAP-3: a late clipboard read does not overwrite what the user already typed'`
- `'AD-18: a clipboard read that lands after a newer show does not seed the new session'`

## Test Structure

**Basic Shape:**
```dart
import 'package:test/test.dart';
import 'package:hotkey_grammar_corrector/src/domain/...dart';
import '../fakes/fake_*.dart';

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  group('session lifecycle', () {
    test('CAP-2: description of behaviour', () async {
      // Arrange
      harness.clipboard.text = 'initial';
      
      // Act
      await harness.show();
      
      // Assert
      expect(harness.state.editorText, equals('initial'));
    });
  });
}
```

**Grouping Tests:**
- `group()` for related scenarios (e.g., "seeding a session", "streaming deltas")
- Each `group()` has a `setUp`/`tearDown` if needed
- One test per specific behaviour

**Harness Pattern:**
- Encapsulates the system under test
- Holds fakes, controllers, state
- Provides helper methods: `show()`, `hide()`, `submitCorrection()`, etc.
- Example: `test/application/correction_controller_test.dart` uses `_Harness`

## Test Types

**Pure Dart Domain Tests (no Flutter binding):**
- Location: `test/domain/`
- Run with: `dart test` (no `flutter test`)
- Examples:
  - Value equality (AD-2 check): `test/domain/collection_equality_test.dart`
  - Import rules (AD-1 check): `test/architecture/ad1_import_rule_test.dart`
  - Config validation, preset matching, event handling
- Reason: domain code imports only `dart:` libraries, so no Flutter binding needed

**Application/Controller Tests:**
- Location: `test/application/`
- Uses fakes for all domain ports
- Examples: `correction_controller_test.dart`, `settings_controller_test.dart`, `panel_controller_test.dart`
- Test session lifecycle, state transitions, retry logic
- No Flutter binding required (controller is pure Dart, reads state, calls ports)

**Widget/UI Tests:**
- Location: `test/ui/`
- Run with: `flutter test`
- Uses `testWidgets()` and `WidgetTester`
- Examples: `daemon_app_test.dart`, `daemon_home_test.dart`
- Test: layout, theming, widget tree structure
- Uses harnesses like `PanelHarness` and `SettingsHarness`

**Platform/Infrastructure Tests:**
- Location: `test/platform/` and `test/infrastructure/`
- Two kinds:
  1. **Mocked tests** (most): mock the platform layer, test adapter logic
     - Example: `system_clipboard_test.dart` mocks `SystemChannels.platform`
     - Example: `window_manager_panel_visibility_test.dart` mocks channel calls (the hotkey equivalent was removed in phase 1 with the plugin it drove)
  2. **Live tests** (skipped in container):
     - Example: `x11_hotkey_live_test.dart` — needs real X11 session
     - Example: `tray_live_test.dart` — needs real StatusNotifier host
     - Marked with `skip: 'reason'` — documents why not observable here

**Architecture Tests:**
- Location: `test/architecture/`
- Enforce architectural rules as automated checks
- Examples:
  - `ad1_import_rule_test.dart` — domain imports only `dart:`
  - `composition_wiring_test.dart` — all ports are wired
  - `desktop_entries_test.dart` — packaging files are correct

## Fakes and Mocking

**Fakes (preferred for domain/application tests):**
- Location: `test/fakes/`
- Every domain port has a fake implementation

**Fake Patterns:**

1. **Scripted Mode** (replays a preset sequence):
   ```dart
   FakeCorrectionProvider(script: [
     SuggestionDelta(register: formal, textDelta: 'Corrected'),
     CorrectionCompleted(suggestions: [...]),
   ])
   ```

2. **Manual Mode** (test drives timing and events):
   ```dart
   final provider = FakeCorrectionProvider.manual();
   provider.runs[0].emit(SuggestionDelta(...));
   provider.runs[0].close();
   expect(provider.runs[0].cancelledByConsumer, isTrue);  // AD-4 check
   ```

**Fake Lifecycle Tracking:**
- `FakeCorrectionProvider.correctCalls` — every call with args
- `FakeCorrectionProvider.runs` — every run in manual mode
- `FakeCorrectionRun.cancelledByConsumer` — whether consumer cancelled AD-4
- `FakeCorrectionRun.cancelError` — to model a cancel() rejection

**Examples from `test/fakes/`:**
- `fake_correction_provider.dart` — implements `CorrectionProvider`, runs scripted or manual
- `fake_clipboard_port.dart` — implements `ClipboardPort`, supports gated reads for timing tests
- `fake_panel_visibility.dart` — implements `PanelVisibility`, emits visibility state
- `fake_config_store.dart` — implements `ConfigStore`, holds current config
- `fake_logger.dart` — implements `Logger`, captures messages for assertion

**Mocking (for platform/channel tests):**
- Use Flutter's `TestDefaultBinaryMessenger` to mock platform channels
- Example from `system_clipboard_test.dart`:
  ```dart
  TestWidgetsFlutterBinding.ensureInitialized();
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    platformCalls.add(call);
    return <String, Object?>{'text': 'hello'};
  });
  ```

## Test Fixtures and Test Data

**Fixture Pattern:**
- Reusable test data created in test setup
- Example from `correction_controller_test.dart`:
  ```dart
  const preset = Preset(
    id: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    systemPrompt: 'correct the text',
  );
  ```

**No Shared Constants Across Tests (Important!):**
- Every test that needs a value should **build it independently**
- Reason: `const` values are canonicalised in Dart — identical constants share an object
- This hides bugs in value equality: `expect(const X(1), const X(1))` compares an object to itself
- All positive rows in `domain/collection_equality_test.dart` rebuild values per call
- Comment: **"Every positive row here goes through expectSameValue, and nothing in this file is built with const"**

**Test Data Builders:**
- Simple factories for common test objects
- Example: `_completionEvent()` helper to create a `CorrectionCompleted` with defaults

## Assertions and Matchers

**Common Patterns:**

```dart
expect(value, equals(expected));           // Value equality
expect(value, same(other));                 // Identity (reference)
expect(list, [1, 2, 3]);                   // List literal matching
expect(value, isNull);
expect(value, isNotNull);
expect(bool, isTrue);
expect(bool, isFalse);
expect(() => code, throwsA(isA<ExceptionType>()));  // Exceptions
expect(find.byType(Widget), findsOneWidget);        // Widget finding
expect(find.byType(Widget), findsNothing);
expect(future, completes);                           // Async
```

**Never Assert on Private Internals:**
- Test behaviour, not implementation
- Private fields and methods are internal details
- Good: `expect(harness.state.editorText, equals(...))`  — public state field
- Bad: `expect(controller._state.editorText, equals(...))`  — reaching into private

**SPEC CAP Coverage:**
- Every capability marked "success:" in `SPEC.md` deserves a test
- If the test would fail if the behaviour regressed, that's the right test
- Cite the CAP id in the test name

## Async Testing

**Pattern for Async Operations:**
```dart
test('an async operation completes', () async {
  await harness.show();  // await completion
  expect(harness.state.editorText, equals('seeded'));
});
```

**Waiting for Futures to Resolve:**
```dart
final future = harness.clipboard.readGate = Completer<void>();
await harness.show();  // starts read, parks on gate
harness.controller.editText('user input');  // user acts
future.complete();  // read lands
await pumpEventQueue();  // flush microtasks
expect(harness.state.editorText, equals('user input'));  // user text wins
```

**Streams and StreamSubscription:**
```dart
final events = <CorrectionEvent>[];
final subscription = provider.correct(...).listen(events.add);
expect(events, isEmpty);  // nothing yet
run.emit(SuggestionDelta(...));
await pumpEventQueue();
expect(events, [isA<SuggestionDelta>()]);
await subscription.cancel();
```

**pumpEventQueue():**
- Flushes all pending microtasks and timers
- Used to let async work settle before assertion
- Part of the Dart testing library

## Error Testing

**Testing Failures (Expected Errors):**
```dart
harness.clipboard.readError = Exception('no clipboard');
await harness.show();  // read fails

expect(harness.state.editorText, equals(''));  // editor stays empty
expect(harness.state.failure, isNull);  // not a user-facing failure
```

**Testing Exception Handling:**
```dart
test('AD-3: a provider that throws is reported as malformed', () async {
  final provider = FakeCorrectionProvider.manual();
  provider.correctError = Exception('broke');
  
  harness.submit();  // calls provider.correct()
  await pumpEventQueue();
  
  expect(harness.state.failure, isNotNull);
  expect(harness.state.failure?.kind, equals(CorrectionFailureKind.providerError));
});
```

## Coverage and Test Goals

**No Coverage Number Chasing:**
- AGENTS.md §7: "don't chase coverage numbers"
- Coverage is informational, not a gate
- Write tests for:
  - Every capability that says "success:" in SPEC
  - State transitions (AD-18's three-way rule)
  - Port failures and backstop guards
  - Cancellation (AD-4)
  - Persistence (AD-7)
  - Not: private helpers, trivial getters, framework plumbing

**What to Test:**
- Domain logic (pure functions, state machines)
- Controller transitions (submit → running → completed)
- Error handling paths (provider fails, clipboard unavailable)
- Cancellation and cleanup
- Configuration validation

**What NOT to Test:**
- Flutter framework internals (Flutter team tests those)
- Private implementation details
- Trivial delegating methods
- UI layout (unless a specific capability depends on it, like CAP-1's "no debug ribbon")

## Live Tests and Unobservable Claims

**Why Some Tests Skip:**
- Some claims cannot be verified in a container without a real session/display
- Examples: X11 grab firing under 100ms, tray icon appearing, hotkey working

**Pattern:**
```dart
test('CAP-1: real X11 grab fires in under 100 ms', () {
  fail('this test has no body — see the skip reason');
}, skip: 'not observable in this container. Missing: X11 session, ...');
```

**Why This Matters:**
- Skipped test makes the gap visible in test output
- Skip reason documents what would be owed on a real session
- No false green: a skipped test is not a passing test
- Detailed in: `test/platform/runtime-observation-checklist.md`

**Live Test Tag:**
- Marked with `@Tags(['live'])`
- Run with: `dart test --tags=live --run-skipped`
- Skipped by default: `dart test` runs without `--tags=live`

---

*Testing analysis: 2026-08-30*
