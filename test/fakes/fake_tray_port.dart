import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/tray/tray_port.dart';
import 'package:hotkey_grammar_corrector/src/domain/tray/hotkey_tray_status.dart';

final class FakeTrayPort implements TrayPort {
  bool installed = false;

  /// Last value passed to [setHotkeyUnavailable]; null before the first call.
  bool? hotkeyUnavailable;
  HotkeyTrayStatus? hotkeyStatus;
  Object? hotkeyStatusError;
  final List<HotkeyTrayStatus> statuses = [];

  /// Broadcast, matching the port's documented flavor: a user-event
  /// notification stream that may have multiple independent listeners.
  final StreamController<void> _panelRequests =
      StreamController<void>.broadcast();

  /// The tray's other user-event stream, broadcast for the same reason.
  ///
  /// Held rather than answered with an empty stream because [dispose] has to
  /// close it: the port declares it, so a fake that skipped it would stop
  /// compiling. It has no driver of its own — nothing here needs to simulate a
  /// Quit pick, and a trigger with no callers would read as coverage that does
  /// not exist.
  final StreamController<void> _quitRequests =
      StreamController<void>.broadcast();

  /// Simulates the user opening the panel from the tray menu.
  void requestPanel() => _panelRequests.add(null);

  @override
  Future<void> install() async {
    installed = true;
  }

  @override
  Stream<void> get panelRequests => _panelRequests.stream;

  @override
  Stream<void> get quitRequests => _quitRequests.stream;

  @override
  Future<void> setHotkeyUnavailable(bool unavailable) async {
    if (hotkeyStatus != null) {
      return;
    }
    hotkeyUnavailable = unavailable;
  }

  @override
  Future<void> setHotkeyStatus(HotkeyTrayStatus status) async {
    final error = hotkeyStatusError;
    if (error != null) throw error;
    statuses.add(status);
    hotkeyStatus = status;
    hotkeyUnavailable = status.unavailable;
  }

  /// Closes both request streams. Test teardown only — not part of the port.
  void dispose() {
    unawaited(_panelRequests.close());
    unawaited(_quitRequests.close());
  }
}
