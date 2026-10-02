# Quick Task 261002-4z2 — Research

## Findings
- The GlobalShortcuts Activated options include activation_token. The current adapter validates sender/session/id but drops that token. Preserve it only after those filters, before notifying activation listeners, without awaiting I/O.
- Plasma sends ProvideXdgActivationToken to the StatusNotifierItem before forwarding its menu click. The pinned tray_manager library uses libayatana-appindicator 0.5.93, which exports no handler for it.
- Ayatana obtains its session connection with g_bus_get. A narrowly scoped GDBus message filter on that same shared connection can implement this missing method without replacing or forking the tray package. Plasma calls the method directly; no introspection gate is present in the inspected source.
- GDBus filters run on a worker thread. Protect pending token storage with a mutex; do not touch GTK there. Consume a token only during presentation, never when it arrives. Scope the filter to the StatusNotifierItem interface, method, and Ayatana indicator path.
- GTK 3.24.41 gdk_wayland_window_focus steals the display startup_notification_id before issuing xdg_activation_v1.activate. Supply the external token with gdk_wayland_display_set_startup_notification_id immediately before gtk_window_present. This avoids manufacturing a token from this background client's obsolete serial.

## Integration
Use a one-use infrastructure activation context injected into portal/tray adapters and the visibility adapter. Snapshot it when show intent is expressed, before queued native I/O; a hide consumes/discards it. Pass that snapshot to PanelWindow.focus. A native method channel selects the portal token or pending tray token and presents the already-realized GTK window. Maintain window_manager event forwarding and existing domain interfaces.

## Verification
Real private-bus tests must exercise the missing tray method, reject malformed/unrelated messages, and prove one-use token consumption. Existing Dart/Flutter tests cover filtering, queued supersession, focus-loss, and toggle behavior. Build the Linux runner and run analyzer and headless suites. A container bus test cannot establish compositor focus or latency; retain explicit KDE UAT steps.

## Primary sources
- https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
- https://github.com/KDE/plasma-workspace/blob/master/applets/systemtray/statusnotifieritemsource.cpp
- https://raw.githubusercontent.com/AyatanaIndicators/libayatana-appindicator/0.5.93/src/app-indicator.c
- https://raw.githubusercontent.com/GNOME/gtk/3.24.41/gdk/wayland/gdkwindow-wayland.c

Research performed inline under the skill adapter's spawn restriction.
