import 'package:flutter/services.dart';

import 'panel_activation.dart';
import 'panel_activation_presenter.dart';

/// The runner applies activation context on GTK's thread immediately before
/// presenting, so another native call cannot consume the one-use token first.
final class GtkPanelActivationPresenter implements PanelActivationPresenter {
  const GtkPanelActivationPresenter();

  static const _channel = MethodChannel(
    'com.divertedriver.HotkeyGrammarCorrector/panel_activation',
  );

  Future<void> initialize() => _channel.invokeMethod<void>('initialize');

  @override
  Future<void> present(PanelActivation? activation) {
    return _channel.invokeMethod<void>('present', <String, Object?>{
      'token': activation?.token,
      'fromTray': activation?.fromTray ?? false,
    });
  }
}
