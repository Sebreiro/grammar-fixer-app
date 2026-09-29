/// The single source of the current time.
///
/// Every timestamp in the system is unix milliseconds UTC obtained from this
/// port — never `DateTime.now()` outside the clock adapter.
abstract interface class Clock {
  int nowMillis();
}
