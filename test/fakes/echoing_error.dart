/// An error whose own `toString()` carries the payload that caused it.
///
/// This is not a hypothetical: `package:sqlite3`'s `SqliteException` appends
/// `Causing statement: … , parameters: …` for any statement that fails during
/// execution, so stringifying a caught history-write error puts the user's
/// clipboard text on stderr. A `FileSystemException` does the smaller version
/// of the same thing with the absolute path it failed on.
///
/// Injecting one of these is the only way a test can tell the difference
/// between a guard that logs the error's *type* and one that stringifies the
/// error itself — the two are indistinguishable under a hand-written
/// `StateError`, whose `toString()` carries nothing worth hiding.
final class EchoingError implements Exception {
  const EchoingError(this._summary, this._payload);

  final String _summary;
  final String _payload;

  @override
  String toString() => 'SqliteException: $_summary, parameters: $_payload';
}

/// The [ArgumentError] shape of [EchoingError].
///
/// A config store refuses a value by throwing `ArgumentError.value(config,
/// …)`, and the controller tells that arm apart by type — so a leak test for
/// the refusal path needs an error that both *is* an `ArgumentError` and
/// carries something a test can look for. The real store's own rejection
/// stringifies to `Instance of 'AppConfig'`, which is why the plain shape
/// cannot detect the leak it is meant to.
final class EchoingArgumentError extends ArgumentError {
  EchoingArgumentError(this._payload) : super('the value was refused');

  final String _payload;

  @override
  String toString() => 'ArgumentError: the value was refused: $_payload';
}
