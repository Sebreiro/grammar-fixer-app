import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/correction/correction_event.dart';
import '../../../domain/correction/correction_provider.dart';
import '../../../domain/correction/preset.dart';
import '../../../domain/logger.dart';
import '../shared/register_tagged_stream_parser.dart';
import 'sidecar_protocol.dart';

/// The shipped default provider (AD-19): hosts the Claude Agent SDK in a
/// Python sidecar, one child process per correction, never reused.
///
/// The stream honours AD-3 — zero or more [SuggestionDelta], exactly one
/// terminal, then close, never a thrown error — and AD-4: it is
/// single-subscription, and cancelling it tears down the whole sidecar
/// process group so the SDK's `claude` CLI grandchild dies too.
///
/// Both paths and the timeout come from `ProviderConfig.settings` (AD-15); a
/// missing or non-executable host is reported as `providerUnavailable` on the
/// first correction and never blocks construction or daemon startup.
///
/// A run whose sidecar stalls — no output, no EOF, no exit — is bounded by
/// the configured timeout: it fails as `CorrectionFailureKind.timeout` and
/// its process group is killed, so a hung network call cannot pin a
/// correction open for the rest of the day. The deadline is total wall clock
/// for the run, measured from the moment the stream is listened to.
final class ClaudeAgentSdkCorrectionProvider implements CorrectionProvider {
  const ClaudeAgentSdkCorrectionProvider({
    required this._interpreterPath,
    required this._sidecarPath,
    required this._logger,
    this._timeout = defaultTimeout,
  });

  /// The registry id and the `ProviderConfig.settings` keys live here, in
  /// one place, so config, registry, and tests cannot drift apart on a
  /// string literal (AD-15: a typo must not become a silent "no such
  /// provider" at runtime).
  static const String providerId = 'claude-agent-sdk';
  static const String interpreterSettingsKey = 'interpreter';
  static const String sidecarSettingsKey = 'sidecar';
  static const String timeoutSettingsKey = 'timeoutMillis';

  /// Used when the settings map carries no usable [timeoutSettingsKey].
  /// Generous, because the deadline exists to bound a stalled transport, not
  /// to police a slow model.
  static const Duration defaultTimeout = Duration(seconds: 60);

  final String _interpreterPath;
  final String _sidecarPath;
  final Logger _logger;
  final Duration _timeout;

  static const _parser = RegisterTaggedStreamParser();

  @override
  Stream<CorrectionEvent> correct({
    required String text,
    required Preset preset,
  }) {
    // A fresh run per call is what keeps the provider stateless: every
    // correction gets its own process, streams, and parse state (AD-19).
    final run = _SidecarRun(
      interpreterPath: _interpreterPath,
      sidecarPath: _sidecarPath,
      logger: _logger,
      parser: _parser,
      timeout: _timeout,
      request: SidecarRequest(
        text: text,
        model: preset.model,
        systemPrompt: preset.systemPrompt,
      ),
    );
    return run.events;
  }
}

/// One correction's process lifecycle: spawn, one request line in, NDJSON
/// out, exactly one terminal event, group teardown.
final class _SidecarRun {
  _SidecarRun({
    required this.interpreterPath,
    required this.sidecarPath,
    required this.logger,
    required this.parser,
    required this.timeout,
    required this.request,
  }) {
    _output = StreamController<CorrectionEvent>(
      onListen: () => unawaited(_start()),
      // Backpressure: a paused consumer must pause the sidecar's output
      // instead of buffering it unboundedly (mirrors the parser's wrapper).
      // The flag covers the async spawn gap, when no subscription exists yet.
      onPause: () {
        _consumerPaused = true;
        _stdoutLines?.pause();
      },
      onResume: () {
        _consumerPaused = false;
        _stdoutLines?.resume();
      },
      onCancel: _onCancel,
    );
  }

  final String interpreterPath;
  final String sidecarPath;
  final Logger logger;
  final RegisterTaggedStreamParser parser;

  /// Total wall clock for the whole run, not idle time between deltas: a
  /// correction that has streamed for this long has stopped being useful
  /// whatever the transport is still doing (AD-19).
  final Duration timeout;

  final SidecarRequest request;

  /// SIGTERM first is what lets the SDK abort its network call cleanly;
  /// SIGKILL after this grace is the guarantee the group actually dies.
  static const _killGrace = Duration(seconds: 2);

  /// setsid exit codes for "could not exec the interpreter at all" —
  /// a host problem the user fixes in settings, not a provider fault.
  static const _execFailureExitCodes = {126, 127};

  /// Sentinel for "stdout closed but the process is still alive"; no real
  /// exit status is negative.
  static const _exitUnknown = -1;

  late final StreamController<CorrectionEvent> _output;
  final StreamController<String> _parserInput = StreamController<String>();
  StreamSubscription<String>? _stdoutLines;
  StreamSubscription<String>? _stderrLines;
  StreamSubscription<CorrectionEvent>? _parserEvents;
  Timer? _deadline;
  Process? _process;
  bool _terminated = false;
  bool _consumerPaused = false;

  /// True once the sidecar has been reaped. After that point its pgid may
  /// already belong to an unrelated process, so no signal may be sent.
  bool _processExited = false;

  /// True once the sidecar spoke its own last word (`done` or `error`), so
  /// EOF/exit-code translation knows the protocol was completed.
  bool _sawSidecarTerminalLine = false;

  Stream<CorrectionEvent> get events => _output.stream;

  Future<void> _start() async {
    // Armed before the spawn so the deadline covers a host that hangs while
    // starting, not just one that hangs while answering.
    _deadline = Timer(timeout, _onDeadline);
    final missing = _missingDependencyMessage();
    if (missing != null) {
      _emit(_failure(CorrectionFailureKind.providerUnavailable, missing));
      return;
    }
    final Process process;
    try {
      // setsid makes the sidecar a session (and process-group) leader, so
      // teardown can signal the whole chain — sidecar plus its `claude`
      // CLI child — with one negative-pid kill (AD-19).
      process = await Process.start('setsid', [interpreterPath, sidecarPath]);
    } on ProcessException catch (error) {
      // Name what actually failed to launch (usually a missing `setsid`
      // host utility) instead of blaming the user's provider settings.
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'failed to launch "${error.executable}": ${error.message}',
        ),
      );
      return;
    }
    _process = process;
    unawaited(process.exitCode.then((_) => _processExited = true));
    if (_terminated) {
      // Cancelled while spawning: onCancel ran before _process existed, so
      // this path owns killing the process that just appeared.
      await _teardown();
      return;
    }
    _attachParser();
    _attachStdout(process);
    _attachStderr(process);
    await _writeRequest(process);
  }

  /// The stalled-transport terminal (AD-19): no output, no EOF, no exit.
  /// It goes through the same [_emit] funnel as every other terminal, so
  /// teardown — including the process-group kill — happens exactly once.
  void _onDeadline() {
    _emit(
      _failure(
        CorrectionFailureKind.timeout,
        'the provider produced no result within ${timeout.inMilliseconds} ms',
      ),
    );
  }

  /// Pure decision, checked before spawning: `setsid` swallows a missing
  /// interpreter into an exit code, so probing the paths up front is what
  /// keeps "not installed" distinguishable from "crashed" (AD-19).
  String? _missingDependencyMessage() =>
      _pathProblem(
        ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey,
        interpreterPath,
      ) ??
      _pathProblem(
        ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey,
        sidecarPath,
      );

  /// An unset setting and a wrong path are different user mistakes and get
  /// different messages. Only explicit paths are probed — a bare command
  /// name like `python3` is left to PATH resolution at spawn time.
  String? _pathProblem(String settingsKey, String path) {
    if (path.isEmpty) {
      return 'provider settings key "$settingsKey" is not configured';
    }
    if (path.contains(Platform.pathSeparator) && !File(path).existsSync()) {
      return 'sidecar $settingsKey not found at "$path" — '
          'check the provider settings';
    }
    return null;
  }

  void _attachParser() {
    // The parser owns the happy-path terminal and malformedResponse; its
    // events flow through the same one-terminal funnel as everything else.
    _parserEvents = parser.parse(_parserInput.stream).listen(_emit);
  }

  void _attachStdout(Process process) {
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onStdoutLine,
          onError: (Object error) => _emit(
            _failure(
              CorrectionFailureKind.providerError,
              'sidecar output unreadable: $error',
            ),
          ),
          onDone: () => unawaited(_translateEndOfOutput(process)),
        );
    _stdoutLines = lines;
    // A consumer that paused during the spawn gap had nothing to pause;
    // honour it now that the subscription exists.
    if (_consumerPaused) {
      lines.pause();
    }
  }

  void _attachStderr(Process process) {
    // The chain is three processes deep (daemon → Python → CLI). Its stderr
    // can quote draft text, so record only that an error occurred.
    _stderrLines = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (_) => logger.warning('sidecar reported an error'),
          // An errored stderr pipe (broken on teardown, OS read failure) must
          // not become an unhandled async error in an all-day daemon.
          onError: (Object error) => logger.warning(
            'sidecar stderr unreadable',
            context: {'errorType': error.runtimeType.toString()},
          ),
        );
  }

  Future<void> _writeRequest(Process process) async {
    try {
      process.stdin.writeln(request.toJsonLine());
      await process.stdin.close();
    } on IOException catch (error) {
      // A sidecar that died before reading its request surfaces through the
      // exit/EOF path; the broken pipe itself is only worth a log line.
      logger.warning(
        'sidecar stdin write failed',
        context: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  void _onStdoutLine(String line) {
    // Anything after a terminal — ours or the sidecar's — is dead protocol.
    if (_terminated || _sawSidecarTerminalLine) {
      return;
    }
    final SidecarLine parsed;
    try {
      parsed = SidecarLine.parse(line);
    } on FormatException catch (error) {
      _emit(
        _failure(
          CorrectionFailureKind.providerError,
          'malformed sidecar output: ${error.message}',
        ),
      );
      return;
    }
    switch (parsed) {
      case SidecarTextLine(:final text):
        _parserInput.add(text);
      case SidecarDoneLine():
        // done ≠ success: closing the parser's input makes the parser rule —
        // CorrectionCompleted or malformedResponse (AD-19).
        _sawSidecarTerminalLine = true;
        unawaited(_parserInput.close());
      case SidecarErrorLine(:final kind, :final message):
        _sawSidecarTerminalLine = true;
        _emit(_failure(kind, message));
    }
  }

  /// EOF without `done`/`error` breaks the protocol whatever the exit code
  /// says; the exit code only names the likelier culprit. Decided at stdout
  /// EOF, not at process exit, so an in-flight `error` line always wins over
  /// its own exit code.
  Future<void> _translateEndOfOutput(Process process) async {
    if (_terminated || _sawSidecarTerminalLine) {
      return;
    }
    // A sidecar that closes stdout but never exits must not hang the
    // correction: the terminal is owed either way, so the wait is bounded and
    // teardown (which escalates to SIGKILL) collects the corpse.
    final exitCode = await process.exitCode.timeout(
      _killGrace,
      onTimeout: () => _exitUnknown,
    );
    if (exitCode == _exitUnknown) {
      _emit(
        _failure(
          CorrectionFailureKind.providerError,
          'sidecar closed its output without a done or error line '
          'and did not exit',
        ),
      );
      return;
    }
    if (exitCode == 0) {
      _emit(
        _failure(
          CorrectionFailureKind.providerError,
          'sidecar closed its output without a done or error line',
        ),
      );
      return;
    }
    _emit(
      _failure(
        _execFailureExitCodes.contains(exitCode)
            ? CorrectionFailureKind.providerUnavailable
            : CorrectionFailureKind.providerError,
        'sidecar exited with code $exitCode before a done or error line',
      ),
    );
  }

  /// The single funnel to the listener (AD-3): the first terminal wins;
  /// everything after it — parser output, exit codes, stray lines — drops.
  void _emit(CorrectionEvent event) {
    if (_terminated) {
      return;
    }
    switch (event) {
      case SuggestionDelta():
        _output.add(event);
      case CorrectionCompleted() || CorrectionFailed():
        _terminated = true;
        _output.add(event);
        unawaited(_output.close());
        unawaited(_teardown());
    }
  }

  Future<void> _onCancel() {
    // AD-4: cancellation is silent. The flag falls first so lines and parser
    // events already in flight are dropped, then the group goes down.
    _terminated = true;
    return _teardown();
  }

  Future<void> _teardown() async {
    _deadline?.cancel();
    _deadline = null;
    await _stdoutLines?.cancel();
    _stdoutLines = null;
    await _stderrLines?.cancel();
    _stderrLines = null;
    await _parserEvents?.cancel();
    _parserEvents = null;
    if (!_parserInput.isClosed) {
      unawaited(_parserInput.close());
    }
    await _killProcessGroup();
  }

  Future<void> _killProcessGroup() async {
    final process = _process;
    _process = null;
    if (process == null) {
      return;
    }
    // Never signal a reaped pid: the kernel may already have handed that
    // pgid to an unrelated process, and killing a stranger's process group
    // is worse than the orphan this method exists to prevent.
    if (_processExited) {
      return;
    }
    // Negative pid signals the whole group (AD-19): the SDK's `claude` CLI
    // grandchild dies with the sidecar instead of being orphaned mid-call.
    Process.killPid(-process.pid, ProcessSignal.sigterm);
    final exitedInGrace = await process.exitCode
        .then((_) => true)
        .timeout(_killGrace, onTimeout: () => false);
    if (!exitedInGrace) {
      Process.killPid(-process.pid, ProcessSignal.sigkill);
    }
    // Always await the exit: reaping is what keeps a daemon that runs all
    // day from accumulating zombies across Retries (AD-19).
    await process.exitCode;
  }

  CorrectionFailed _failure(CorrectionFailureKind kind, String message) =>
      CorrectionFailed(kind: kind, message: message);
}
