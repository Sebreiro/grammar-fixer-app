import 'package:hotkey_grammar_corrector/src/domain/logger.dart';

final class FakeLogger implements Logger {
  /// Every logged line, in order, for assertions.
  final List<({String level, String message, Map<String, Object?>? context})>
  lines = [];

  @override
  void info(String message, {Map<String, Object?>? context}) {
    lines.add((level: 'info', message: message, context: context));
  }

  @override
  void warning(String message, {Map<String, Object?>? context}) {
    lines.add((level: 'warning', message: message, context: context));
  }

  @override
  void error(String message, {Map<String, Object?>? context}) {
    lines.add((level: 'error', message: message, context: context));
  }
}
