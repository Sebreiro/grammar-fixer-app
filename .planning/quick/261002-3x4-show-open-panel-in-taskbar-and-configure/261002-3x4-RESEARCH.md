# Targeted research

## Findings

- main.dart prepares the warm window with setSkipTaskbar(true). Set this property false at startup; no show-path I/O is added. GTK hide removes the unmapped window from the running-window list, while minimize retains a normal taskbar entry.
- Installed window_manager 0.5.2 maps setSkipTaskbar to gtk_window_set_skip_taskbar_hint (linux/window_manager_plugin.cc:555), a property setter. GTK describes it as a desktop hint: https://docs.gtk.org/gtk3/method.Window.set_skip_taskbar_hint.html. Real dock behavior needs a desktop session check on X11 and Wayland.
- Keep setPreventClose(true): the native close event is asynchronous and destroying GTK immediately would bypass cancellation and history drainage.
- PanelVisibility should expose close requests separately from visibility changes. A pure-Dart PanelCloseController can read the already-loaded ConfigStore.current when a request arrives, choose hide or emit quit, and expose the quit event to main.dart's existing shutdown handler.
- SettingsController._writeChange owns retry-on-conflict, echo suppression, file persistence, and live config changes. Reuse it and _finishSettingsMutation for closeBehavior; keep failure ownership separate from preset/provider/hotkey mutations.
- AppConfig equality and hashCode must include the new enum so file watcher deduplication and write conflict detection observe it.
- JSON decoder must default only an absent key, reject explicit null/unknown values, and use enum names rather than ordinal values.

## Verification

Use pure Dart tests for defaults, round trips, corrupt input, writes/failures, close policy, and subscription disposal; Flutter widget tests for the setting and graph wiring; existing full non-live suites and fatal-info analysis. Record compositor-only dock checks as manual rather than claiming live desktop verification.
