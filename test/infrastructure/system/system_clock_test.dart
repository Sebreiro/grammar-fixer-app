import 'package:hotkey_grammar_corrector/src/infrastructure/system/system_clock.dart';
import 'package:test/test.dart';

/// `SystemClock` is the only implementation of the [Clock] port that reads
/// real time, so the only thing worth asserting is that it reads *the* real
/// time, in the unit the Consistency Conventions fix.
void main() {
  test('AD-7: nowMillis returns unix milliseconds bracketed by the caller own '
      'readings', () {
    const clock = SystemClock();

    final before = DateTime.now().millisecondsSinceEpoch;
    final now = clock.nowMillis();
    final after = DateTime.now().millisecondsSinceEpoch;

    expect(now, greaterThanOrEqualTo(before));
    expect(now, lessThanOrEqualTo(after));
  });

  test('AD-7: successive readings never go backwards', () {
    const clock = SystemClock();

    final first = clock.nowMillis();
    final second = clock.nowMillis();

    expect(second, greaterThanOrEqualTo(first));
  });
}
