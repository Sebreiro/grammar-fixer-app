import 'panel_activation.dart';

/// Presents the existing window with permission supplied by the desktop.
abstract interface class PanelActivationPresenter {
  Future<void> present(PanelActivation? activation);

  /// Releases desktop resources installed for the warm window.
  Future<void> dispose();
}
