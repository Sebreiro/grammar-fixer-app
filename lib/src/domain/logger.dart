/// Structured diagnostics to stderr and the config-adjacent log file.
///
/// NEVER log `input_text` or suggestion bodies — the daemon reads the
/// clipboard, so log payloads would leak whatever the user last copied.
/// Log ids, kinds, and latencies instead.
///
/// That rule extends to **caught exceptions: never log an error's
/// `toString()`**. A vendor exception routinely carries the payload that
/// caused it — `package:sqlite3`'s `SqliteException` appends `Causing
/// statement: … , parameters: …` whenever a statement fails during
/// execution, and for the history write (AD-7) those parameters are the
/// corrected text and every suggestion body. Log `error.runtimeType` and the
/// values the caller authored itself; a resident daemon writes these lines
/// to stderr all day.
/// Provider response diagnostics must be sanitized in the adapter before
/// reaching this port: redact credentials and echoed request/response text.
abstract interface class Logger {
  void info(String message, {Map<String, Object?>? context});

  void warning(String message, {Map<String, Object?>? context});

  void error(String message, {Map<String, Object?>? context});
}
