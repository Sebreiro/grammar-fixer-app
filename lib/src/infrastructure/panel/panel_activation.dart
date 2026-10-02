/// Fresh desktop permission to present the warm panel, scoped to one request.
final class PanelActivation {
  const PanelActivation.portal(this.token) : fromTray = false;
  const PanelActivation.tray() : token = null, fromTray = true;

  final String? token;
  final bool fromTray;
}
