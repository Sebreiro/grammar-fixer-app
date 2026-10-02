import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/clock.dart';
import '../../domain/config/app_config.dart';
import '../../domain/logger.dart';
import 'log_line_encoder.dart';
import 'stderr_logger.dart';

/// Serializes asynchronous writes to one cyclic file while retaining stderr.
final class FileLogger implements Logger {
  FileLogger({required Clock clock, IOSink? stderrSink})
    : _encoder = LogLineEncoder(clock: clock),
      _stderr = StderrLogger(clock: clock, sink: stderrSink);

  final LogLineEncoder _encoder;
  final StderrLogger _stderr;
  RandomAccessFile? _file;
  String? _path;
  int _length = 0;
  int _maxBytes = AppConfig.defaultLogMaxBytes;
  bool _fileFailed = false;
  Future<void> _operations = Future<void>.value();
  Future<void>? _closing;
  final Completer<void> _configured = Completer<void>();

  Future<void> open(String path) async {
    if (_path == path) return;
    if (_path != null) throw StateError('The log file is already opened.');
    _path = path;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final handle = await file.open(mode: FileMode.append);
      _file = handle;
      _length = await handle.length();
    } on Object catch (error) {
      _reportFileFailure(error);
    }
  }

  /// Receives the immutable, validated configuration through the app graph.
  void configureMaxBytes(int maxBytes) {
    _maxBytes = maxBytes;
    if (!_configured.isCompleted) _configured.complete();
    if (_closing != null) return;
    _operations = _operations.then((_) => _guard(_resetOversizedFile));
  }

  @override
  void info(String message, {Map<String, Object?>? context}) =>
      _write('info', message, context);

  @override
  void warning(String message, {Map<String, Object?>? context}) =>
      _write('warning', message, context);

  @override
  void error(String message, {Map<String, Object?>? context}) =>
      _write('error', message, context);

  void _write(String level, String message, Map<String, Object?>? context) {
    _writeStderr(
      () => switch (level) {
        'info' => _stderr.info(message, context: context),
        'warning' => _stderr.warning(message, context: context),
        _ => _stderr.error(message, context: context),
      },
    );
    if (_closing != null || _fileFailed) return;
    final line = _encoder.encode(level, message, context);
    _operations = _operations.then((_) => _guard(() => _writeLine(line)));
  }

  Future<void> _writeLine(String line) async {
    // Startup diagnostics wait for the configured limit, so opening a larger
    // retained log cannot accidentally reset it using the default limit.
    await _configured.future;
    final file = _file;
    if (file == null || _fileFailed) return;
    final bytes = _boundedLine(line);
    if (_length + bytes.length > _maxBytes) await _reset();
    await file.writeFrom(bytes);
    _length += bytes.length;
  }

  List<int> _boundedLine(String line) {
    final bytes = utf8.encode('$line\n');
    if (bytes.length <= _maxBytes) return bytes;
    final entry = jsonDecode(line) as Map<String, Object?>;
    final message = entry['message'] as String;
    return utf8.encode(
      '${jsonEncode({
        ...entry,
        'message': message.length > 128 ? message.substring(0, 128) : message,
        'context': {'entry_truncated': true, 'original_bytes': bytes.length},
      })}\n',
    );
  }

  Future<void> _resetOversizedFile() async {
    if (_length > _maxBytes && !_fileFailed) await _reset();
  }

  Future<void> _reset() async {
    final file = _file;
    if (file == null) return;
    await file.truncate(0);
    await file.setPosition(0);
    _length = 0;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (!_configured.isCompleted) _configured.complete();
    await _operations;
    final file = _file;
    if (file == null) return;
    try {
      await _guard(() async => file.flush());
    } finally {
      await _guard(() async => file.close());
      _file = null;
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      _reportFileFailure(error);
    }
  }

  void _reportFileFailure(Object error) {
    if (_fileFailed) return;
    _fileFailed = true;
    _writeStderr(
      () => _stderr.error(
        'the log file is unavailable; diagnostics continue on stderr',
        context: {'path': _path, 'error_type': error.runtimeType.toString()},
      ),
    );
  }

  void _writeStderr(void Function() emit) {
    try {
      emit();
    } on Object {
      // A broken terminal must not prevent the file from receiving the line.
    }
  }
}
