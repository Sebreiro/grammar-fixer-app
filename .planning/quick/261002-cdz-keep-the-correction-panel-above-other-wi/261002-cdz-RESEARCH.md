# Quick Task 261002-cdz — Research

## Evidence and approach

- The current hidden-window setup keeps taskbar eligibility enabled but sets no
  keep-above property. `window_manager` implements its setter with GTK.
- GTK 3's Wayland `gdk_wayland_window_set_keep_above` implementation is empty;
  adding only `setAlwaysOnTop(true)` would leave the user's KDE issue unresolved.
- KWin's documented scripting API exposes writable `keepAbove`,
  `workspace.activeWindow`, window identity, visibility and attention signals.
  A small runtime script can keep only this application's normal windows above,
  activate on mapping/unminimizing/denied activation, and clear taskbar attention.
  It must not reactivate on focus loss, which would break CAP-14.
- Load and run through KWin's session D-Bus scripting API at startup. Perform
  bounded calls on a worker, not GTK's thread or the summon path. Keep the script
  temporary and unload on normal teardown; unload the same owned name before
  loading to recover from a previous crash. No persistent KWin settings changes.
- Plasma 6 uses `/Scripting/Script{id}`, Plasma 5 uses `/{id}`. Select the
  compatible script path by introspection rather than restarting all scripts.
- Retain the existing one-use portal/tray activation-token path. On X11, prepare
  GTK keep-above before any show. Other Wayland compositors retain their existing
  token-based presentation path without KWin integration.

## Primary sources

- GTK Wayland backend: https://raw.githubusercontent.com/GNOME/gtk/gtk-3-24/gdk/wayland/gdkwindow-wayland.c
- KWin API: https://develop.kde.org/docs/plasma/kwin/api/
- KWin script lifecycle: https://raw.githubusercontent.com/KDE/kwin/master/src/scripting/scripting.cpp
- Plasma 5 path: https://raw.githubusercontent.com/KDE/kwin/Plasma/5.27/src/scripting/scripting.cpp

## Verification boundary

Use behavioral JavaScript tests, a real private D-Bus with a KWin fake, existing
panel lifecycle suites, analyzer, native compilation, and Xvfb/openbox smoke
checks. The container has no KWin executable; real KDE foreground/latency checks
remain a manual verification item. Rebuild the current local AppImage with the
changed native runner as well as the AOT code.
