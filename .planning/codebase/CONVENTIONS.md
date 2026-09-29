# Coding Conventions

**Analysis Date:** 2026-08-30

## Naming Patterns

**Files:**
- Snake_case matching the primary type: `correction_provider.dart`, `hotkey_binding.dart`
- One public type per file (AGENTS.md §3)
- Test files: `*_test.dart`

**Classes and Types:**
- PascalCase for type names: `CorrectionProvider`, `HotkeyBinding`, `Suggestion`
- `final class` for value types with immutable fields
- `sealed class` for sum types (discriminated unions): `CorrectionEvent`, `HotkeyBindOutcome`
- `abstract interface class` for ports/contracts/abstract definitions: `CorrectionProvider`, `Logger`, `ClipboardPort`
- Private classes: leading underscore `_Run`, `_Harness`

**Functions and Methods:**
- camelCase: `submit()`, `editText()`, `copySuggestion()`
- Private methods: leading underscore `_setState()`, `_seedFromClipboard()`
- Boolean getters named descriptively: `_isCurrent()`, not `isOk()`

**Variables:**
- camelCase: `submittedText`, `editorText`, `sessionToken`
- Private fields: leading underscore `_state`, `_clipboard`, `_disposed`
- Enums and enum values: camelCase `CorrectionFailureKind.providerError`

**Type Parameters and Generics:**
- Single capital letter or descriptive PascalCase: `<T>`, `<E extends CorrectionEvent>`

## Code Style

**Formatting:**
- `dart format` output only - no hand-formatting arguments
- Merge gate: a clean `dart analyze` is required (AGENTS.md §6)
- Line length: no enforcement, `dart format` decides

**Linting:**
- Base: `flutter_lints` package
- Stricter settings in `analysis_options.yaml`:
  - `strict-casts: true`
  - `strict-raw-types: true`
  - `unawaited_futures: true` (custom rule)
- Every `ignore` comment requires a one-line justification
- No `dynamic` unless unavoidable with detailed justification

**Immutability:**
- `final` fields by default: `final String id`
- `const` constructors wherever possible: `const Suggestion({required this.text})`
- `const` widgets in build trees
- Immutable state objects use `copyWith()` for updates (never mutate in place)
- `late final` for fields that are assigned once, lazily (e.g., controllers, subscriptions)

**Modern Language Features:**
- Sealed classes + exhaustive `switch` expressions for states/events
  ```dart
  switch (event) {
    case SuggestionDelta() => _onDelta(event, run),
    case CorrectionCompleted() => _onCompleted(event, run),
    case CorrectionFailed() => _onFailed(event, run),
  }
  ```
- Records for small tuples instead of classes: `({String text, Preset preset})`
- Pattern matching over `is`-chains and null-checks
- Exhaustive switches are compiler protection when a case is added

## Import Organization

**Order (within a file):**
1. `dart:` libraries first (`dart:async`, `dart:io`)
2. `package:flutter/` imports if applicable
3. Third-party package imports (`package:flutter_riverpod/`)
4. Relative imports by depth:
   - `import '../../domain/...';` (up levels first, sorted)
   - `import '../sibling/...';`
   - `import './local.dart';` (same directory)

**Grouping:**
- Blank line between each category
- Within a category, sort alphabetically
- Group by semantic layer: domain imports together, then application, then infrastructure

**Example from `correction_controller.dart`:**
```dart
import 'dart:async';

import '../domain/clipboard/clipboard_port.dart';
import '../domain/clock.dart';
import '../domain/correction/correction_event.dart';
// ... more domain imports (alphabetical)
import 'correction_state.dart';  // local sibling
```

**In Tests:**
- `package:` imports of the code under test first
- `package:test/test.dart` or `package:flutter_test/flutter_test.dart`
- Relative imports of fakes and test support last

## Null Safety

**Sound null safety, honestly:**
- No `!` to silence the analyzer (AGENTS.md §6)
- No `dynamic`
- No `late` as a workaround for unclear lifecycles
- Model absence explicitly: if a value can be null, declare `String?`
- Use `final String? value = ...` when a field may be absent

**Example:**
```dart
/// Null when no completion yet (CAP-7).
final CorrectionFailed? failure;

final String? copyFailure;  // null = no error to display
```

## Error Handling

**Exceptions vs. Values:**
- Expected failures (provider error, bad config, no clipboard) are **modelled as values**
  - Represent with sealed classes: `CorrectionFailed`, or result-like types
  - The UI renders them without exception handling
- Exceptions are for **programmer error only**
- Never catch broadly and swallow: `on Object catch` is the floor, never bare `catch`

**Pattern:**
```dart
try {
  await _clipboard.writeText(text);
} on Object catch (error) {
  // Catch everything for robustness, but log the type only
  _log(() => _logger.error('the clipboard write failed', context: _errorContext(error)));
  _setState(_state.copyWith(copyFailure: 'could not be copied'));
  return;
}
```

**Logging Errors:**
- Never log `error.toString()` — vendor exceptions carry the payload that caused them
  - `SqliteException` appends the failing statement and parameters (which may include clipboard content)
- Log only `error.runtimeType` and application-authored context
  ```dart
  Map<String, Object?> _errorContext(Object error) {
    return {'error_type': error.runtimeType.toString()};
  }
  ```
- Never let an exception cross an abstraction boundary as a vendor type
- Convert to application types or model failures as events

**Port Errors (Domain Contracts):**
- Every port (interface) failure is caught and guarded internally
- Provider returns `Stream<CorrectionEvent>` that includes `CorrectionFailed` event, never throws
- Clipboard read returns `Future<String?>` (null is absence, not error) or throws only on infrastructure failure

## Async and Futures

**Every future must be awaited or explicitly discarded:**
- `await future;` if you need the result
- `unawaited(future);` if the future runs in the background
  - Import: `import 'dart:async';` (provides `unawaited()`)
  - Use when: fire-and-forget work, logger calls, subscriptions
  - `unawaited(_changes.cancel());` `unawaited(_controller.changeHotkey(binding));`
- Never drop a future without one of these: analyzer rule `unawaited_futures` catches it

**Widget Controllers & Subscriptions:**
- Declare in `StatefulWidget`: `late final StreamSubscription<T> _subscription;`
- Assign in `initState()`: `_subscription = controller.changes.listen(...);`
- Dispose in `dispose()`: `await _subscription.cancel();`
- Never allocate controllers or subscriptions in `build()` — allocate once, dispose once

**No `Future.delayed` to paper over races:**
- If timing matters, structure the code to make it clear (model state, use latches, etc.)
- See `CorrectionController._dismissalStands` for an explicit state latch instead of timing

## Logging

**Framework:** `Logger` interface (injected, not a singleton)

**Location:** `lib/src/domain/logger.dart` defines the interface

**Rules (AGENTS.md §6, Logger docs):**
- Never log `input_text`, suggestion bodies, or clipboard content — the daemon reads user input
- Log ids, kinds, latencies, and structure instead
- `logger.info()`, `logger.warning()`, `logger.error()` with optional context map
- Context is `Map<String, Object?>`: structured, safe to write to stderr

**Example:**
```dart
// Good:
_logger.error('the provider threw', context: {'preset_id': _preset.id, 'error_type': error.runtimeType.toString()});

// Bad:
logger.error('error: $error');  // Leaks payload
logger.error('provider threw for text: $text');  // Logs clipboard content
```

**Guarding Logger Calls:**
```dart
void _log(void Function() emit) {
  try {
    emit();
  } on Object {
    // Logging failed; nowhere left to report it
  }
}
```

## Comments

**When to Comment:**
- Explain **why**, never **what** — the code shows what it does
- Example: `// Wayland gives no key grabs, so this routes through the portal` ✓
- Bad: `// increment counter` ✗

**What to avoid:**
- No dead code (git remembers it)
- No commented-out code (remove it)
- No `TODO` without a concrete follow-up note (delete the line or cite a ticket/issue)
- Every `ignore` comment needs a one-line reason explaining the override

**Doc Comments:**
- `///` for public APIs (classes, methods, fields)
- Explain the contract, not the implementation
- Cite SPEC CAP ids and AGENTS.md section numbers when relevant
- Example from `CorrectionController`:
  ```dart
  /// Owns one panel session at a time: seed, run, stream, retry, persist.
  ///
  /// Two monotonic tokens carry the lifecycle rules that would otherwise be
  /// special cases. Each session bumps the session token (AD-18)...
  final class CorrectionController {
  ```

## Function Design

**Size:**
- Keep functions short enough to read without scrolling (roughly ≤ 20 lines is the norm)
- Exceptions: long `switch` expressions and widget build trees
- If you need "and" to describe a function, split it — one job per function

**Nesting:**
- Avoid deep nesting (3+ levels inside a function is a smell)
- Prefer early returns and guard clauses
- Example:
  ```dart
  void copySuggestion(SuggestionRegister register) async {
    final text = _completedTextOf(register);
    if (_disposed || text == null) {
      return;  // Early return, no else pyramid
    }
    // ... rest of logic
  }
  ```

**Parameters:**
- Keep parameter lists short (~3 arguments)
- Past ~3, pass a named record or a small value class
- No boolean flag parameters (`correct(text, retry: true)`) — write two named functions instead

**Return Values:**
- A function either returns a value OR causes an effect, not both (wherever practical)
- Streams return a value (the stream); callbacks return void
- No side effects hiding in getters

**Pure vs. Thin Functions:**
- Pure functions (decision-making): no I/O, no side effects, testable without fakes
- Thin functions (effects): call ports, write to streams, short and straightforward
- Never mix in the same function (AD-15 backstop discipline)

## Value Equality

**Explicit Equality for Value Types:**
- Override `operator ==` and `hashCode` when a type needs value comparison
- Reason: `Riverpod.select()` and `Stream.distinct()` need value deduplication
- Reason: `Set<T>` and `Map<T, V>` keying needs consistent equality

**Pattern:**
```dart
@override
bool operator ==(Object other) {
  if (identical(this, other)) return true;
  return other is Suggestion &&
      register == other.register &&
      text == other.text;
}

@override
int get hashCode => Object.hash(register, text);
```

**When to skip:**
- State events that stream once and are never deduplicated (e.g., `SuggestionDelta`)
- Classes used only as builders, never in collections
- Always comment why: `// Both are streamed once, never deduplicated`

## Module/File Design

**One public type per file:**
- Private helper types (e.g., `_Run`, internal classes) are fine
- Export only what the caller needs
- No barrel files (index files that re-export everything)

**Domain Code (no Framework Leakage):**
- `lib/src/domain/` imports only `dart:` libraries
- No `flutter`, no vendor SDKs, no `package:http`
- Enforced by `test/architecture/ad1_import_rule_test.dart`
- This keeps domain code testable without a Flutter binding

**Ports and Implementations:**
- Interface lives in domain: `abstract interface class CorrectionProvider`
- Implementations live at edges: `lib/src/infrastructure/correction/...`
- Ports are narrow (one job each)
- No singletons in domain; dependencies injected via constructor

## Widget Conventions

**StatelessWidget is the default:**
- Reach for `StatefulWidget` only if the widget genuinely owns state
- Extract widgets into named classes rather than `_buildFoo()` helper methods
  - Better rebuild scoping
  - Better readability
  - Example:
    ```dart
    class CorrectionPanel extends StatelessWidget {  // not _buildPanel()
      @override Widget build(...) { ... }
    }
    ```

**build() is pure and cheap:**
- No I/O, no `async`
- No allocation of controllers or subscriptions
- No side effects
- Dispose everything in `dispose()` that was created in `initState()` or `didChangeDependencies()`

**State Management:**
- One approach, chosen at the architecture step, used consistently
- This codebase uses Riverpod for dependency injection and state
- Never two competing patterns (Riverpod + Provider + setState all in one codebase)
- Never business logic in widget `setState` — push it to a controller/notifier

---

*Convention analysis: 2026-08-30*
