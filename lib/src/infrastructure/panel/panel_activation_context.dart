import 'panel_activation.dart';

/// Keeps desktop provenance below the domain's platform-independent ports.
/// Show intent takes the context before native calls enter the window queue.
final class PanelActivationContext {
  PanelActivation? _pending;

  void preparePortal(String? token) {
    _pending = PanelActivation.portal(token);
  }

  void prepareTray() {
    _pending = const PanelActivation.tray();
  }

  PanelActivation? take() {
    final activation = _pending;
    _pending = null;
    return activation;
  }
}
