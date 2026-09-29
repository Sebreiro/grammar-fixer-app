import 'tray_menu_entry.dart';

/// The system tray indicator, as the tray adapter needs it: an image, a menu,
/// and the stream of picks that come back.
///
/// An infrastructure-private seam, and the second abstraction in this project
/// with a single implementation — which AGENTS.md §4.2 warns against unless
/// there is a real test need. There is one, and it is the same one
/// `PanelWindow` carries: `trayManager` is a singleton behind a private method
/// channel, reachable only through a mocked channel and therefore only with a
/// Flutter binding, while the logic worth testing here — which entries exist,
/// what a pick maps to, and when a menu is deliberately *not* pushed — is pure
/// decision-making that AGENTS.md §7 wants in the binding-free set. The seam
/// also confines `package:tray_manager` to one file, which is what makes AD-1
/// mechanically checkable (`test/architecture/tray_confinement_test.dart`).
abstract interface class TrayIcon {
  /// Puts [assetPath]'s image on the indicator, creating the indicator if this
  /// is the first call.
  ///
  /// [assetPath] is a path *inside* `flutter_assets`: on an ordinarily
  /// installed Linux build `tray_manager` joins it onto
  /// `<executable dir>/data/flutter_assets`, so the file must be declared under
  /// `flutter: assets:` in `pubspec.yaml` or the indicator is created pointing
  /// at nothing. That is the branch this project ships.
  ///
  /// It is not the only branch. `tray_manager` also detects a sandbox
  /// (`FLATPAK_ID`, `SNAP`, `container`, `/.dockerenv`) and then passes the
  /// argument through **unjoined**, as a freedesktop icon *name* to be resolved
  /// from the app's manifest rather than as a path. An asset path would not
  /// resolve as a name, so a sandboxed package needs a different argument here.
  /// Deliberately not implemented: the spine defers the packaging format, and
  /// choosing one is what decides whether this branch is ever reached.
  ///
  /// What the tests observe is the *argument* handed to `tray_manager`, not
  /// which of those branches a shipped build takes — and they cannot observe
  /// the choice: `TrayManager.setIcon` switches on `defaultTargetPlatform`,
  /// which `flutter test` forces to `TargetPlatform.android`, so the Linux
  /// sandbox check never runs under test. The joined path is asserted because
  /// it is the value the shipped non-sandboxed branch produces; the sandbox
  /// branch is covered by neither this seam nor its tests, by decision.
  Future<void> setIcon(String assetPath);

  /// Replaces the menu with [entries], in order.
  ///
  /// **Never call this before [setIcon].** On Linux `set_context_menu` calls
  /// `app_indicator_set_menu(indicator, …)` with no null check, and only
  /// `set_icon` creates that indicator
  /// (`tray_manager-0.5.3/linux/tray_manager_plugin.cc:105-129, :143-152`), so
  /// a menu pushed first dereferences a null pointer in native code rather
  /// than failing as a Dart error.
  Future<void> setMenu(List<TrayMenuEntry> entries);

  /// The [TrayMenuEntry.key] of every entry the user picks. Broadcast, so the
  /// seam imposes no one-listener rule of its own.
  Stream<String> get selections;

  /// Deregisters from the tray, removes the indicator and closes [selections].
  /// Idempotent.
  Future<void> dispose();
}
