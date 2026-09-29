/// One line of the tray menu, described in terms the tray port already has.
///
/// A plain value rather than a vendor `MenuItem`, so nothing above
/// `tray_manager_tray_icon.dart` sees a `Menu`, a `MenuItem` or a channel
/// (AD-1). [key] is what comes back when the user picks the line, so it is the
/// adapter's own identifier and never a label the user could read.
final class TrayMenuEntry {
  const TrayMenuEntry({
    required this.key,
    required this.label,
    required this.enabled,
  });

  /// Echoed back on selection. Stable, and not derived from [label].
  final String key;

  /// What the user reads.
  final String label;

  /// Whether the line can be picked. A disabled line is how AD-12's
  /// unavailability statement is shown without offering an action behind it.
  final bool enabled;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayMenuEntry &&
        key == other.key &&
        label == other.label &&
        enabled == other.enabled;
  }

  @override
  int get hashCode => Object.hash(key, label, enabled);

  @override
  String toString() =>
      'TrayMenuEntry($key, "$label", ${enabled ? 'enabled' : 'disabled'})';
}
