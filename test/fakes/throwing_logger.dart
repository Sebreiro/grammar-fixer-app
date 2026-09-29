import 'package:hotkey_grammar_corrector/src/domain/logger.dart';

/// A [Logger] whose every method throws.
///
/// The controllers' guards all recover by logging, which makes the logger the
/// one port whose failure cannot be reported. This is not a contrived double:
/// `StderrLogger` writes to a sink that a daemon can outlive — a parent
/// terminal that closed leaves stderr a broken pipe, and the write throws.
/// Without a swallow at every recovery site, each guard becomes the unhandled
/// async error it exists to prevent, and `dispose()` breaks its documented
/// promise never to rethrow.
final class ThrowingLogger implements Logger {
  /// Every call attempted, so a test can prove the guards still tried.
  final List<String> attempts = [];

  Never _fail(String level) {
    attempts.add(level);
    throw StateError('stderr is a broken pipe');
  }

  @override
  void info(String message, {Map<String, Object?>? context}) => _fail('info');

  @override
  void warning(String message, {Map<String, Object?>? context}) =>
      _fail('warning');

  @override
  void error(String message, {Map<String, Object?>? context}) => _fail('error');
}
