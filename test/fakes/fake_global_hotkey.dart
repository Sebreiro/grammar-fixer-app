import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_status.dart';

import 'cancel_failing_stream.dart';

final class FakeGlobalHotkey implements GlobalHotkey {
  FakeGlobalHotkey({this.onBind});

  /// Scripts the [bind] outcome, so AD-10's and AD-12's scenarios are
  /// testable: a compositor picking a different combination, a backend that
  /// cannot report the effective binding (null), or one with no global
  /// shortcuts at all ([HotkeyUnavailable]). When null, [bind] echoes the
  /// request as [HotkeyBound] with [BindingAuthority.application].
  HotkeyBindOutcome Function(HotkeyBinding binding)? onBind;

  /// When set, [bind] rejects instead of resolving. AD-12 says unavailability
  /// is a value, so this models an adapter breaking that contract.
  Object? bindError;

  /// When set, [bind] waits on it before answering — the Wayland portal dialog
  /// a user can leave up for seconds (AD-11), which is what makes a mutation
  /// observably *in flight*.
  Completer<void>? bindGate;

  /// When set, cancelling a subscription to [activations] rejects — the
  /// teardown a controller's `dispose()` has to survive.
  Object? cancelError;

  /// The same for [bindingChanges], and separately, so a test can prove the two
  /// cancels are guarded independently of each other.
  Object? bindingChangesCancelError;

  /// The backend's own wording for what is in effect, as the Wayland portal's
  /// `trigger_description` reaches [current] — null on an X11-shaped backend,
  /// which is the default because the port's other adapter authors no text.
  ///
  /// Recorded onto [current] by [bind] and by [emitBindingChange], the same two
  /// paths a real adapter records it from, so a consumer cannot read a
  /// description that no outcome ever arrived with.
  String? backendDescription;

  /// Every requested binding, in order, for assertions.
  final List<HotkeyBinding> bindCalls = [];

  bool disposed = false;

  /// Single-subscription, matching what adapters return: the port has one
  /// consumer (the panel controller), and AD-4-style teardown semantics are
  /// what tests must replicate.
  final StreamController<void> _activations = StreamController<void>();

  /// Broadcast, as the port declares: [bindingChanges] carries what the
  /// *backend* originated, and the settings surface is not promised to be its
  /// only consumer.
  final StreamController<HotkeyBindOutcome> _bindingChanges =
      StreamController<HotkeyBindOutcome>.broadcast();

  /// Simulates one press of the bound combination. Pressing after [dispose]
  /// is fake misuse and throws.
  void press() {
    if (disposed) {
      throw StateError(
        'FakeGlobalHotkey.press() called after dispose(); '
        'a disposed hotkey can never activate',
      );
    }
    _activations.add(null);
  }

  /// Pushes an error onto [activations] — an adapter breaking the port's
  /// promise of a plain event stream.
  void emitActivationsError(Object error) => _activations.addError(error);

  /// Simulates a change the *backend* originated: the desktop rebinding the
  /// shortcut, or dropping it. Nothing here answers a `bind()` call.
  void emitBindingChange(HotkeyBindOutcome outcome) {
    _record(outcome);
    _bindingChanges.add(outcome);
  }

  /// Pushes an error onto [bindingChanges] — an adapter breaking the port's
  /// promise of a plain value stream, which the surface must survive.
  void emitBindingChangesError(Object error) => _bindingChanges.addError(error);

  /// The last outcome this fake produced, as a real adapter's cached field —
  /// null until [bind] or [emitBindingChange] has produced one.
  @override
  HotkeyStatus? get current => _current;

  HotkeyStatus? _current;

  /// The one place [current] is written, so the fake cannot drift into
  /// answering a status no outcome arrived with.
  HotkeyBindOutcome _record(HotkeyBindOutcome outcome) {
    _current = HotkeyStatus(
      outcome: outcome,
      // As the adapters do: nothing is in effect on an unavailable outcome, so
      // there is nothing for a description to be about.
      backendDescription: outcome is HotkeyBound ? backendDescription : null,
    );
    return outcome;
  }

  @override
  Stream<void> get activations =>
      CancelFailingStream<void>(_activations.stream, () => cancelError);

  @override
  Stream<HotkeyBindOutcome> get bindingChanges =>
      CancelFailingStream<HotkeyBindOutcome>(
        _bindingChanges.stream,
        () => bindingChangesCancelError,
      );

  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) async {
    bindCalls.add(binding);
    final gate = bindGate;
    if (gate != null) {
      await gate.future;
    }
    final error = bindError;
    if (error != null) {
      throw error;
    }
    final script = onBind;
    if (script != null) {
      return _record(script(binding));
    }
    return _record(
      HotkeyBound(
        HotkeyRegistration(
          effective: binding,
          authority: BindingAuthority.application,
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _activations.close();
    await _bindingChanges.close();
  }
}
