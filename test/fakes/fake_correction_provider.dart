import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';

/// Replays a scripted event sequence, or hands the test a run it drives by
/// hand, as the single-subscription stream that AD-3/AD-4 require of every
/// provider.
final class FakeCorrectionProvider implements CorrectionProvider {
  /// Emits [script] in order on every [correct] call, then closes.
  FakeCorrectionProvider({required List<CorrectionEvent> this._script});

  /// Every [correct] call returns a [FakeCorrectionRun] the test drives:
  /// nothing is emitted until the test says so and the stream stays open
  /// until it closes it. Scenarios that turn on *when* an event lands —
  /// AD-4's cancellations, a correction terminating while the panel is
  /// hidden — need that timing under the test's control.
  FakeCorrectionProvider.manual() : _script = null;

  /// Null in manual mode.
  final List<CorrectionEvent>? _script;

  /// Every call, in order, for assertions.
  final List<({String text, Preset preset})> correctCalls = [];

  /// One entry per [correct] call in manual mode, in call order. Empty in
  /// scripted mode.
  final List<FakeCorrectionRun> runs = [];

  /// When set, [correct] throws it instead of returning a stream. AD-3 says
  /// no exception escapes `correct()`, so this models an adapter breaking
  /// that contract before a single event exists.
  Object? correctError;

  @override
  Stream<CorrectionEvent> correct({
    required String text,
    required Preset preset,
  }) {
    correctCalls.add((text: text, preset: preset));
    final error = correctError;
    if (error != null) {
      throw error;
    }
    final script = _script;
    if (script != null) {
      return Stream.fromIterable(script);
    }
    final run = FakeCorrectionRun();
    runs.add(run);
    return run.events;
  }
}

/// One in-flight correction in manual mode: the events go in here, and
/// whether the consumer cancelled comes back out.
final class FakeCorrectionRun {
  FakeCorrectionRun() {
    _controller = StreamController<CorrectionEvent>(
      onCancel: () {
        // Closing the run also ends the subscription, so only a cancel that
        // beats the close is the consumer exercising AD-4.
        if (!_closed) {
          cancelledByConsumer = true;
        }
        final error = cancelError;
        if (error != null) {
          throw error;
        }
      },
    );
  }

  late final StreamController<CorrectionEvent> _controller;
  bool _closed = false;

  /// True once the consumer cancelled its subscription mid-run (AD-4).
  bool cancelledByConsumer = false;

  /// When set, `cancel()` on the consumer's subscription returns a rejected
  /// future. Under AD-19 that cancel is the sidecar's process-group kill, so
  /// a teardown that cannot complete is a real failure mode — and the one
  /// that would otherwise escape as an unhandled zone error, since AD-8 and
  /// AD-4 both discard the cancel future rather than awaiting it.
  Object? cancelError;

  Stream<CorrectionEvent> get events => _controller.stream;

  void emit(CorrectionEvent event) => _controller.add(event);

  /// A provider breaking AD-3 by letting an error cross the boundary.
  void emitError(Object error) => _controller.addError(error);

  void close() {
    _closed = true;
    unawaited(_controller.close());
  }
}
