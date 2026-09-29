import 'package:hotkey_grammar_corrector/src/domain/clock.dart';

final class FakeClock implements Clock {
  FakeClock({this.millis = 0});

  /// The value [nowMillis] returns; settable per test.
  int millis;

  void advance(int byMillis) => millis += byMillis;

  @override
  int nowMillis() => millis;
}
