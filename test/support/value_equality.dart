import 'package:test/test.dart';

/// Asserts that [a] and [b] are two distinct objects holding the same value.
///
/// The `identical` guard is the load-bearing line. Dart canonicalises identical
/// constant expressions to a single instance, so `expect(const X(1), const X(1))`
/// compares an object with itself and passes with no `operator==` declared at
/// all. An earlier revision of the equality suites was written that way, and
/// neutering `Suggestion`, `HotkeyRegistration`, `HotkeyBound`,
/// `HotkeyUnavailable` and `CorrectionFailed` to identity equality left every
/// binding-free test green. Routing each positive row through here is what
/// stops those suites degrading into identity checks that pass however the
/// types are declared.
///
/// The corollary for callers: build each side separately and without `const`,
/// including the nested values a list or map comparison walks into — a shared
/// constant element makes a collection comparison pass without ever consulting
/// the element's own `==`.
void expectSameValue(Object a, Object b) {
  expect(
    identical(a, b),
    isFalse,
    reason:
        'both sides collapsed to one instance, so this row would pass with '
        'no operator== declared — build each side separately, without const',
  );
  expect(a, b);
  expect(
    a.hashCode,
    b.hashCode,
    reason:
        'hashCode must agree with ==, or every Set and Map keyed by this '
        'type silently holds duplicates',
  );
}
