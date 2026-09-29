import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/composition/controller_providers.dart';
import '../application/composition/port_providers.dart';
import '../application/correction_controller.dart';
import '../application/correction_state.dart';
import '../application/panel_controller.dart';
import '../domain/logger.dart';
import 'panel/correction_panel.dart';
import 'settings/settings_screen.dart';

/// What the daemon's one window shows: the correction panel, or the settings
/// screen (CAP-1, CAP-12).
///
/// **A swap, not a stack.** The two views replace each other rather than layering,
/// because everything the panel holds lives in `CorrectionController` —
/// unmounting it costs nothing, and remounting is also what brings the caret back
/// to the editor. It is also not a route: a dialog or a second toplevel would
/// take focus away from a window whose own focus loss hides it (CAP-14), and no
/// widget in this ring may show or hide anything (AD-4, AD-8).
///
/// The Settings control sits in a reserved right gutter beside the editor.
/// The panel keeps its measured height while every point inside the outlined
/// editor remains a text-field hit target (PANEL-07).
///
/// **Any summon returns to the panel, and that takes two signals rather than
/// one.** CAP-1 promises the hotkey summons the *correction panel*; a window that
/// comes up showing settings breaks that. A summon that begins a session raises
/// [CorrectionState.isFreshSession], which is also the signal the panel uses to
/// bring focus back — but a show of a window that is already *visible* produces
/// no session at all, because `PanelVisibility.changes` emits on a transition.
/// That case is not hypothetical: it is AD-14's second launch and AD-12's tray
/// "open the panel" entry, so without a second signal the tray route raised a
/// window still showing settings, on a screen printing "the tray menu still opens
/// the panel". `PanelController.showRequests` covers it, and the two together
/// mean every route the *user* asks with — hotkey, tray, second launch — ends at
/// the panel. Both call the same idempotent swap.
///
/// **A window-manager restore is deliberately not one of those routes (DW-30).**
/// A de-iconify raises no show request and, because the panel came back to the
/// session it left rather than a new one, no fresh session either — so a restore
/// with settings up stays on settings. That is where the user left the window,
/// and CAP-1 is about what a *summon* opens.
///
/// **A half-typed hotkey is discarded on a view swap.** Settings owns that
/// draft only while mounted; returning to Settings creates a capture field from
/// the controller's current effective binding. Native focus loss resets the
/// field through the same widget lifecycle while keeping Settings on screen.
/// The panel's editor and correction remain in `CorrectionController` (AD-4).
class DaemonHome extends ConsumerStatefulWidget {
  const DaemonHome({super.key});

  @override
  ConsumerState<DaemonHome> createState() => _DaemonHomeState();
}

class _DaemonHomeState extends ConsumerState<DaemonHome> {
  /// Read once, for the reason `CorrectionPanel` documents: the provider is a
  /// plain `Provider` whose value never changes in today's graph, and reading it
  /// is what guarantees a session exists at all.
  late final CorrectionController _controller;
  late final PanelController _panelController;

  /// The one port this widget reaches for, and only to report a stream that
  /// errors or ends — the same single sanction the panel has.
  late final Logger _logger;

  late final StreamSubscription<CorrectionState> _changes;

  /// The show that carries no session with it — a later launch or the tray
  /// raising a window that is already visible (AD-12, AD-14).
  late final StreamSubscription<void> _showRequests;

  bool _showingSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(correctionControllerProvider);
    _panelController = ref.read(panelControllerProvider);
    _logger = ref.read(loggerProvider);
    _changes = _controller.changes.listen(
      _onStateChanged,
      onError: _onStateStreamError,
      onDone: _onStateStreamClosed,
    );
    _showRequests = _panelController.showRequests.listen(
      (_) => _returnToPanel(),
      // The same AD-15 backstop the other subscription has: a broken producer
      // must not take this window's only link to a summon down with it.
      onError: (Object error) =>
          _report('the panel show-request stream errored', error),
    );
  }

  @override
  void dispose() {
    _panelController.setSettingsVisible(false);
    unawaited(_changes.cancel());
    unawaited(_showRequests.cancel());
    super.dispose();
  }

  void _onStateChanged(CorrectionState state) {
    if (!state.isFreshSession) {
      // An ordinary session update. Guarded rather than acted on unconditionally
      // so a keystroke does not rebuild this widget on every character.
      return;
    }
    _returnToPanel();
  }

  /// Brings the panel back, whichever signal asked (CAP-1).
  ///
  /// Idempotent, and both callers rely on that: a summon of a hidden window
  /// raises *both* signals — the show request and the fresh session it starts —
  /// and the second one must be free.
  void _returnToPanel() {
    if (!_showingSettings) {
      return;
    }
    _panelController.setSettingsVisible(false);
    setState(() => _showingSettings = false);
  }

  void _openSettings() {
    if (_showingSettings) {
      return;
    }
    _panelController.setSettingsVisible(true);
    setState(() => _showingSettings = true);
  }

  void _onStateStreamError(Object error) {
    // Which view is showing is not something this stream's health says anything
    // about, so the view stays put and the line is for an operator.
    _report('the home view state stream errored', error);
  }

  void _onStateStreamClosed() {
    // Only `CorrectionController.dispose()` closes it, during shutdown with the
    // window already unmapped. There is no summon left to return to the panel
    // for, and nothing truer to show than whatever is showing.
    _report(
      'the home view state stream closed while the window was mounted',
      null,
    );
  }

  /// Emits a line without letting the logger's own failure escape — the ui-ring
  /// instance of the swallow `correction_controller.dart` documents.
  void _report(String message, Object? error) {
    try {
      _logger.error(
        message,
        // Type only: a caught error's `toString()` routinely carries the payload
        // that caused it, and here that payload is the user's text.
        context: error == null
            ? null
            : {'error_type': error.runtimeType.toString()},
      );
    } on Object {
      // Nowhere left to report this: the reporting channel is what broke.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showingSettings) {
      return SettingsScreen(onBack: _returnToPanel);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 200) {
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _SettingsAffordance(onPressed: _openSettings),
                ),
              ),
              const Expanded(child: CorrectionPanel()),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            const CorrectionPanel(editorTrailingInset: 48),
            Positioned(
              top: 0,
              right: 0,
              child: _SettingsAffordance(onPressed: _openSettings),
            ),
          ],
        );
      },
    );
  }
}

/// The gutter control that opens the settings screen.
///
/// Labelled, because an unlabelled icon is the whole affordance for a user who
/// cannot see it — the tooltip is what carries the label to assistive technology
/// as well as to a pointer. Keyboard-reachable for the same reason the panel is
/// driven from the keyboard: this is a surface summoned by a hotkey, and a
/// control only a mouse can reach is a control half the users of this app do not
/// have.
class _SettingsAffordance extends StatelessWidget {
  const _SettingsAffordance({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Open settings',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.settings, size: 18),
    );
  }
}
