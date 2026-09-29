import '../../domain/clock.dart';

/// The only place in `lib/` that calls `DateTime.now()` (Consistency
/// Conventions): every other timestamp comes from the [Clock] port, which is
/// what keeps time injectable and every test deterministic.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;
}
