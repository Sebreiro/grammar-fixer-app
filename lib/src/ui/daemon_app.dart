import 'package:flutter/material.dart';

import 'daemon_home.dart';
import 'daemon_theme.dart';

/// The root widget of a daemon whose window is only mapped by the hotkey
/// toggle (AD-8).
///
/// The widget tree is built once at startup and stays built, so the toggle only
/// ever changes the visibility of an already-warm window inside CAP-1's 100 ms
/// — the panel is *behind* a hidden window rather than constructed on demand.
/// Nothing here shows or hides anything: the window is mapped and unmapped
/// underneath this tree by the `PanelVisibility` adapter.
///
/// The home is [DaemonHome] rather than the panel itself, because the window has
/// two views: the panel and the settings screen (CAP-12). Which one is showing
/// is that widget's to decide; a summon always ends at the panel (CAP-1).
class DaemonApp extends StatelessWidget {
  const DaemonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotkey Grammar Corrector',
      // The panel is small and every pixel of it is content. A DEBUG ribbon
      // painted across its corner would ship in the debug artifact the build
      // gate produces and cover part of a variant.
      debugShowCheckedModeBanner: false,
      theme: DaemonTheme.light,
      // A panel summoned over whatever the user is writing in has no business
      // being the one bright window on a dark desktop.
      darkTheme: DaemonTheme.dark,
      themeMode: ThemeMode.system,
      home: const DaemonHome(),
    );
  }
}
