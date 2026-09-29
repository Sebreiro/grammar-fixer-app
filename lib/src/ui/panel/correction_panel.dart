import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/composition/controller_providers.dart';
import '../../application/composition/port_providers.dart';
import '../../application/correction_controller.dart';
import '../../application/correction_state.dart';
import '../../domain/correction/suggestion_register.dart';
import '../../domain/logger.dart';
import 'correction_error_notice.dart';
import 'original_text_pane.dart';
import 'register_key_slot.dart';
import 'suggestion_list.dart';

/// The panel: the original above its register variants, or the inline failure
/// in their place (CAP-3, CAP-4, CAP-5, CAP-10, CAP-13).
///
/// One surface, one owner. Everything that outlives a keystroke —
/// the editor text, the streamed suggestions, the highlight, the failure —
/// belongs to `CorrectionController`; this widget reads its state, calls its
/// methods, and owns nothing but two focus nodes and its subscription
/// (Consistency Conventions, "State mutation").
///
/// Nothing here shows or hides the window. AD-8's hotkey toggle owns
/// visibility, AD-4 makes hiding not a cancellation, and the window is mapped
/// and unmapped underneath a widget tree that is always built — so the panel
/// has no visibility call to make and no close control to offer (CAP-14).
///
/// The keyboard, which the spine's Deferred section leaves to the widgets.
/// Focus starts in the editor and returns there on **every** new session, not
/// just the first: the tree is never rebuilt under AD-8, so a `TextField`'s
/// `autofocus` fires once in the daemon's life and a second summon would
/// otherwise open with the caret parked wherever the last session left it —
/// silently eating the first keystroke of a panel CAP-1 promises is focused.
/// The 1/2/3 keys are scoped to the suggestions region, so `2` typed in the
/// editor stays text (CAP-3 would otherwise be broken by CAP-4), and the
/// `Ctrl+Enter` accelerator is scoped to the editor, so it cannot re-run and
/// discard a correction the user is reading. Submitting moves focus to the
/// variants, so the digits are in reach the moment there is something to
/// select. There is no `Escape` — hiding is the toggle's and the focus-loss
/// hide's, not the ui ring's.
///
/// CAP-10's "both readable at once" is claimed at and above
/// [minimumPanelHeightFor] — the floor scaled to the reader's text size, not the
/// bare [minimumPanelHeight]. Startup prefers a 480×360 minimum and adds room
/// for surrounding controls, but a smaller display can force a smaller
/// window. Below this content floor the panel scrolls as a whole rather than
/// clipping its editor, Correct action, or suggestion cards.
class CorrectionPanel extends ConsumerStatefulWidget {
  const CorrectionPanel({this.editorTrailingInset = 0, super.key});

  /// Horizontal room reserved when Settings shares the editor's top edge.
  final double editorTrailingInset;

  /// The smallest height at which CAP-10 actually holds **at text scale 1.0**:
  /// both panes fit, and the original is *readable* rather than merely present.
  ///
  /// Measured, not guessed, and measured against the right claim. "No overflow"
  /// is reached at 240, but the editor's share there is 7.2 logical pixels — a
  /// sliver that satisfies "non-zero height" and no reader. The editor gains
  /// 8 px per 20 px of panel, so a full line of its 16 px text arrives at 300
  /// (31.2 px). Below the floor the panel scrolls as a whole; at and above it
  /// the two panes split the surface.
  ///
  /// This number alone is not the floor — see [minimumPanelHeightFor].
  static const double minimumPanelHeight = 300;

  /// The floor at [textScaler]: [minimumPanelHeight] grows with the text,
  /// because everything it was measured against does.
  ///
  /// The caption, the button, the card labels and the hints all scale while a
  /// fixed floor does not, so the editor's share *shrinks* as the text grows:
  /// probe-measured at 480×300, the editor gets 31.2 px at 1.0×, 23.2 at 1.5×
  /// and 15.2 at 2.0× — against a line that is 24 px and 32 px tall there. From
  /// roughly 1.45× up, a constant floor certifies CAP-10 at a height where the
  /// original cannot show one line, and GNOME's large-text range is 1.25–1.5×.
  /// Scaling the floor with the text keeps the claim true rather than making
  /// the number bigger for everyone: 450 at 1.5× leaves the editor 47 px.
  static double minimumPanelHeightFor(TextScaler textScaler) =>
      minimumPanelHeight *
      textScaler.scale(_measuredAtFontSize) /
      _measuredAtFontSize;

  /// The editor's font size, which is what the floor was measured against.
  static const double _measuredAtFontSize = 16;

  @override
  ConsumerState<CorrectionPanel> createState() => _CorrectionPanelState();
}

class _CorrectionPanelState extends ConsumerState<CorrectionPanel> {
  /// Config changes retain this controller. An explicit provider invalidation
  /// can still replace it, so the listener below moves this widget to the new
  /// instance before another editor action can reach the disposed one.
  late CorrectionController _controller;
  late final ProviderSubscription<CorrectionController> _controllerChanges;

  /// The one port this widget reaches for, and only to report the two things
  /// that would otherwise be silent: a state stream that errors or ends.
  late final Logger _logger;

  StreamSubscription<CorrectionState>? _changes;

  CorrectionState _state = CorrectionState.empty;

  /// The editor's node lives here, not in [OriginalTextPane], because a
  /// *session* is what decides where the caret belongs and this widget is the
  /// only one that sees a session begin.
  final FocusNode _editorFocus = FocusNode(debugLabel: 'panel editor');

  /// The digit keys' scope. Held here rather than in [SuggestionList] because
  /// submitting is what moves focus into it, and the node has to outlive the
  /// swap between the variants and the inline error.
  final FocusNode _suggestionsFocus = FocusNode(
    debugLabel: 'panel suggestions',
  );

  /// `Ctrl+Enter`, mapped once: `Shortcuts` rebuilds cheaply and this map is
  /// the same on every frame.
  ///
  /// `includeRepeats: false` for the same reason it is false below, and a
  /// sharper one: `SingleActivator` accepts key *repeats* by default, and
  /// `submit()` cancels the in-flight run before starting the next (AD-4), so a
  /// held accelerator would kill and re-spawn the correction it is waiting for
  /// once per repeat event.
  ///
  /// Both Enters, for the reason every selection slot has a keypad twin: the
  /// keypad reports `numpadEnter`, a different logical key, so a user who
  /// submits from the pad pressed a key that did nothing at all.
  static final Map<ShortcutActivator, Intent> _submitShortcuts = {
    for (final key in const [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      SingleActivator(key, control: true, includeRepeats: false):
          const _CorrectIntent(),
  };

  /// AD-6's key mapping, derived rather than written out: the activator for
  /// register *n* comes from its index, on the digit row and on the keypad.
  ///
  /// `includeRepeats: false` because selecting is a *toggle*: with the default
  /// a held digit flips the highlight once per auto-repeat event and lands
  /// wherever the release's parity leaves it.
  static final Map<ShortcutActivator, Intent> _selectionShortcuts = {
    for (final register in SuggestionRegister.values)
      for (final key in _selectionKeysFor(register))
        SingleActivator(key, includeRepeats: false): _SelectRegisterIntent(
          register,
        ),
  };

  late final Map<Type, Action<Intent>> _correctActions = {
    _CorrectIntent: CallbackAction<_CorrectIntent>(
      onInvoke: (_) {
        _correct();
        return null;
      },
    ),
  };

  late final Map<Type, Action<Intent>> _selectionActions = {
    _SelectRegisterIntent: CallbackAction<_SelectRegisterIntent>(
      onInvoke: (intent) {
        _select(intent.register);
        return null;
      },
    ),
  };

  void _select(SuggestionRegister register) {
    if (_controller.state.selectedRegister == register) {
      return;
    }
    _controller.selectSuggestion(register);
  }

  KeyEventResult _onSuggestionsKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    for (final register in SuggestionRegister.values) {
      final index = SuggestionRegister.values.indexOf(register);
      if (index >= 9) {
        break;
      }
      if (event.physicalKey ==
          PhysicalKeyboardKey(PhysicalKeyboardKey.digit1.usbHidUsage + index)) {
        _select(register);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _logger = ref.read(loggerProvider);
    _controllerChanges = ref.listenManual(
      correctionControllerProvider,
      (_, next) => _bindController(next),
      onError: (error, _) =>
          _report('the panel controller changed with an error', error),
    );
    _bindController(_controllerChanges.read());
  }

  void _bindController(CorrectionController controller) {
    final previousSubscription = _changes;
    if (previousSubscription != null && identical(controller, _controller)) {
      return;
    }
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
      // An unexpected graph replacement must not discard text being edited.
      if (controller.state.editorText.isEmpty && _state.editorText.isNotEmpty) {
        controller.editText(_state.editorText);
      }
    }
    _controller = controller;
    // Snapshot and subscribe synchronously, so no state emission is missed.
    if (previousSubscription == null) {
      _state = controller.state;
    } else {
      setState(() => _state = controller.state);
    }
    _changes = controller.changes.listen(
      _onStateChanged,
      // The same AD-15 backstop the controller installs on
      // `PanelVisibility.changes`, for the same reason: the producer promises a
      // plain stream, and a broken promise must not take the panel's only link
      // to the session down with it.
      onError: _onStateStreamError,
      onDone: () => _onStateStreamClosed(controller),
    );
  }

  @override
  void dispose() {
    _controllerChanges.close();
    final changes = _changes;
    if (changes != null) {
      unawaited(changes.cancel());
    }
    _editorFocus.dispose();
    _suggestionsFocus.dispose();
    super.dispose();
  }

  void _onStateChanged(CorrectionState state) {
    // A fresh session is the moment the caret has to come back to the editor
    // (CAP-2, CAP-3, AD-18). The predicate lives on the state, because the home
    // view needs the same signal to return to the panel.
    final startedNewSession = state.isFreshSession;
    setState(() => _state = state);
    if (startedNewSession) {
      _editorFocus.requestFocus();
    }
  }

  void _onStateStreamError(Object error) {
    // The last rendered state stays: an error on this stream says nothing about
    // what the session holds, and blanking the panel would discard a
    // correction the user can still copy.
    _report('the panel state stream errored', error);
  }

  void _onStateStreamClosed(CorrectionController controller) {
    if (!identical(controller, _controller)) {
      return;
    }
    // The current controller only closes during shutdown. Keep the last
    // rendered state while the window is being unmapped.
    _report('the panel state stream closed while the panel was mounted', null);
  }

  /// Emits a line without letting the logger's own failure escape — the ui-ring
  /// instance of the swallow `correction_controller.dart` documents: a
  /// `StderrLogger` whose sink is gone throws on write, and a throw from a
  /// stream callback would become an unhandled async error in the daemon's zone.
  void _report(String message, Object? error) {
    try {
      _logger.error(
        message,
        // Type only. A caught error's `toString()` routinely carries the
        // payload that caused it, and here that payload is the user's text.
        context: error == null
            ? null
            : {'error_type': error.runtimeType.toString()},
      );
    } on Object {
      // Nowhere left to report this: the reporting channel is what broke.
    }
  }

  /// DW-3: an editor that trims to empty is not a correction, so the action
  /// that would send it is disabled.
  ///
  /// This is the affordance, **not** the invariant: [_correct] still calls
  /// `submit()` unconditionally so the controller's guard — the one that holds
  /// for every caller and writes the line an operator reads — is what actually
  /// refuses. Two predicates that must agree would be one predicate too many.
  bool get _canCorrect => _state.editorText.trim().isNotEmpty;

  void _correct() {
    _controller.submit();
    if (_controller.state.status == CorrectionStatus.running) {
      // It really started, so the digit keys are worth putting in reach. Asked
      // of the controller rather than re-derived here, so a submit the
      // controller refused cannot move the caret away from the editor the user
      // still has to type in.
      _suggestionsFocus.requestFocus();
    }
  }

  void _copy(SuggestionRegister register) {
    // Visibly discarded (AGENTS.md §6): the write is guarded inside the
    // controller and reports its own verdict through the panel's state, so
    // there is nothing for this call site to await or recover.
    unawaited(_controller.copySuggestion(register));
  }

  @override
  Widget build(BuildContext context) {
    final failure = _state.failure;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight;
          final floor = CorrectionPanel.minimumPanelHeightFor(
            MediaQuery.textScalerOf(context),
          );
          final contentHeight = available.isFinite
              ? available < floor
                    ? floor
                    : available
              : floor;
          // At and above the floor this scroll view has nothing to scroll: the
          // box is exactly the viewport, so the two panes split it as CAP-10
          // requires. Below it the whole panel scrolls, while each pane keeps
          // its own bounded viewport for long editor or suggestion text.
          return SingleChildScrollView(
            child: SizedBox(
              height: contentHeight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // CAP-10: the original and the variants each hold a share
                    // of the surface, so neither scrolls the other out of view.
                    Expanded(
                      flex: 2,
                      child: Shortcuts(
                        // Scoped to the editor: in the variants region
                        // `Ctrl+Enter` would cancel and re-run a correction the
                        // user is reading (AD-4), discarding the answer.
                        shortcuts: _submitShortcuts,
                        child: Actions(
                          actions: _correctActions,
                          child: Padding(
                            // Settings occupies the panel's top-right 48 px;
                            // reserving a gutter keeps its hit box off the
                            // outlined editor without reducing pane height.
                            padding: EdgeInsets.only(
                              right: widget.editorTrailingInset,
                            ),
                            child: OriginalTextPane(
                              text: _state.editorText,
                              focusNode: _editorFocus,
                              onChanged: _controller.editText,
                              onCorrect: _canCorrect ? _correct : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 3,
                      child: Shortcuts(
                        shortcuts: _selectionShortcuts,
                        child: Actions(
                          actions: _selectionActions,
                          child: Focus(
                            focusNode: _suggestionsFocus,
                            onKeyEvent: _onSuggestionsKeyEvent,
                            // The region's own height, because the notice below
                            // is bounded by a share of it.
                            child: LayoutBuilder(
                              builder: (context, region) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // CAP-5's other half: between the submit and
                                  // the first delta there is nothing to render,
                                  // and a panel that looks idle invites a second
                                  // Correct press that cancels the run being
                                  // waited for (AD-4). Real progress only — no
                                  // placeholder text, which the SPEC forbids.
                                  //
                                  // Announced, or it fixes "running looks like
                                  // idle" for sighted users only and leaves the
                                  // second-Correct-press trap fully open for
                                  // everyone else.
                                  if (_state.status == CorrectionStatus.running)
                                    Semantics(
                                      liveRegion: true,
                                      child: const Padding(
                                        padding: EdgeInsets.only(bottom: 8),
                                        child: LinearProgressIndicator(
                                          semanticsLabel: 'correcting',
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: failure == null
                                        ? SuggestionList(
                                            texts: _state.suggestionTexts,
                                            selectedRegister:
                                                _state.selectedRegister,
                                            // AD-3: nothing is actionable until
                                            // the answer is authoritative.
                                            completed:
                                                _state.status ==
                                                CorrectionStatus.completed,
                                            copyRegister: _state.copyRegister,
                                            copyPending: _state.copyPending,
                                            copySucceeded: _state.copySucceeded,
                                            copyFailure: _state.copyFailure,
                                            onSelect: _select,
                                            onCopy: _copy,
                                          )
                                        : CorrectionErrorNotice(
                                            message: failure.message,
                                            onRetry: _controller.retry,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Every key that selects [register]: its digit-row key and its keypad twin,
/// both derived from the register's index (AD-6). Empty past the digit row.
Iterable<LogicalKeyboardKey> _selectionKeysFor(SuggestionRegister register) {
  final index = SuggestionRegister.values.indexOf(register);
  return [?digitKeyForIndex(index), ?numpadKeyForIndex(index)];
}

/// Highlight one register (CAP-4). Never a copy — that is CAP-11's button.
final class _SelectRegisterIntent extends Intent {
  const _SelectRegisterIntent(this.register);

  final SuggestionRegister register;
}

/// Submit the editor's content for correction (CAP-3).
final class _CorrectIntent extends Intent {
  const _CorrectIntent();
}
