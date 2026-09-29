import 'dart:async';

import 'package:tray_manager/tray_manager.dart';

import 'tray_icon.dart';
import 'tray_menu_entry.dart';

/// [TrayIcon] over `tray_manager` — the one file in `lib/` that names the
/// package (AD-1).
///
/// The import is `package:tray_manager/tray_manager.dart` alone even though
/// `Menu` and `MenuItem` come from `menu_base`: `tray_manager.dart` re-exports
/// that package, and naming it directly would be an undeclared dependency
/// (`depend_on_referenced_packages`) as well as a second vendor package
/// crossing this seam.
///
/// **Why the listener and not `MenuItem.onClick`.** `tray_manager 0.5.3`
/// dispatches one inbound `onTrayMenuItemClick` call to the clicked item's
/// `onClick` *and* to every registered [TrayListener]
/// (`lib/src/tray_manager.dart:56-71`). Either route reaches Dart; the listener
/// is used because it survives a menu being replaced, which
/// [setMenu] does on every state change.
///
/// **`setToolTip` is deliberately never called.** The Linux handler implements
/// only `destroy`, `setIcon`, `setTitle` and `setContextMenu`
/// (`linux/tray_manager_plugin.cc:152-171`); anything else answers
/// `notImplemented`, which reaches Dart as a rejection.
///
/// The listener is registered in the constructor, so a click delivered before
/// this type exists reaches no one — the same shape as
/// `WindowManagerPanelWindow`.
final class TrayManagerTrayIcon with TrayListener implements TrayIcon {
  TrayManagerTrayIcon() {
    trayManager.addListener(this);
  }

  /// Broadcast so the seam does not impose a one-listener rule of its own.
  final StreamController<String> _selections =
      StreamController<String>.broadcast();

  bool _disposed = false;

  @override
  Stream<String> get selections => _selections.stream;

  @override
  Future<void> setIcon(String assetPath) async {
    if (_disposed) {
      return;
    }
    await trayManager.setIcon(assetPath);
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    if (_disposed) {
      return;
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          for (final entry in entries)
            MenuItem(
              key: entry.key,
              label: entry.label,
              disabled: !entry.enabled,
            ),
        ],
      ),
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (_disposed) {
      return;
    }
    final key = menuItem.key;
    if (key == null) {
      // `MenuItem.key` is nullable in `menu_base`, but every item this seam
      // builds carries one. An item without one is not ours to route.
      return;
    }
    _selections.add(key);
  }

  /// Deregisters, removes the indicator, and closes [selections].
  ///
  /// `destroy` is what sets the indicator passive; without it the icon outlives
  /// a daemon that has already let go of its stream.
  ///
  /// [selections] closes in a `finally` rather than after the `destroy`. The
  /// `_disposed` latch is already set by then, so a rejecting `destroy` that
  /// skipped the close would strand the stream open *and* make the second
  /// `dispose()` a no-op that cannot reach it — two of the three things this
  /// doc promises, undone by the one step that is allowed to fail. The
  /// rejection still propagates; `TrayManagerTray` is what reduces it to a log
  /// line on the shutdown path.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } finally {
      await _selections.close();
    }
  }
}
