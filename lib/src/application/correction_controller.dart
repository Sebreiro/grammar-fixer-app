import 'dart:async';

import '../domain/clipboard/clipboard_port.dart';
import '../domain/clock.dart';
import '../domain/correction/correction_event.dart';
import '../domain/correction/correction_outcome.dart';
import '../domain/correction/correction_provider.dart';
import '../domain/correction/correction_record.dart';
import '../domain/correction/preset.dart';
import '../domain/correction/suggestion.dart';
import '../domain/correction/suggestion_register.dart';
import '../domain/history/correction_repository.dart';
import '../domain/logger.dart';
import '../domain/panel/panel_visibility.dart';
import 'correction_state.dart';

/// Owns one panel session at a time: seed, run, stream, retry, persist.
///
/// Two monotonic tokens carry the lifecycle rules that would otherwise be
/// special cases. Each session bumps the session token (AD-18), and each run
/// holds the session it belongs to; a terminal event is *always* persisted
/// (AD-4: hiding is not a cancellation, and CAP-7 retains the correction),
/// while state is only touched when the run is still the current one — so a
/// correction that lands after the panel re-seeded is recorded and dropped
/// from view, exactly as AD-4 describes.
///
/// Every port call made after construction is guarded: this runs inside a
/// daemon that stays resident all day, so a rejected clipboard read, provider
/// call, history write, or subscription cancel reaches the [Logger] and goes
/// no further. Each guard is a backstop against a port implementation that
/// breaks its contract, never a relocation of AD-15's adapter-owned error
/// translation. Construction itself is deliberately not guarded: subscribing
/// to [PanelVisibility.changes] happens once, at the composition root, where
/// an adapter that cannot even hand over its stream is a startup failure and
/// should be one.
///
/// The active `(CorrectionProvider, Preset)` pair is injected: nothing below
/// the composition root selects a provider (AD-5).
final class CorrectionController {
  CorrectionController({
    required this._clipboard,
    required CorrectionProvider provider,
    required Preset preset,
    required this._repository,
    required this._clock,
    required this._logger,
    required PanelVisibility panelVisibility,
  }) : _activePair = (provider: provider, preset: preset) {
    _visibilityChanges = panelVisibility.changes.listen(
      _onVisibilityChanged,
      // AD-15 backstop: the port promises a plain stream of
      // `PanelVisibilityState`. An adapter that errors instead must not end
      // this subscription — the next `shown` still has to be decided on, and
      // the latch below is what decides it. An error is not a departure either:
      // it says nothing about where the window is, so it must not touch the
      // latch.
      onError: (Object error) => _log(
        () => _logger.error(
          'the panel visibility stream errored',
          context: _errorContext(error),
        ),
      ),
    );
  }

  final ClipboardPort _clipboard;
  ({CorrectionProvider provider, Preset preset}) _activePair;
  final CorrectionRepository _repository;
  final Clock _clock;
  final Logger _logger;

  /// Changes the pair used by future runs without disturbing the current run.
  void useActivePair({
    required CorrectionProvider provider,
    required Preset preset,
  }) {
    if (_disposed) {
      return;
    }
    _activePair = (provider: provider, preset: preset);
  }

  late final StreamSubscription<PanelVisibilityState> _visibilityChanges;

  /// Broadcast: the panel and the tray may both watch a session.
  final StreamController<CorrectionState> _changes =
      StreamController<CorrectionState>.broadcast();

  CorrectionState _state = CorrectionState.empty;

  int _sessionToken = 0;

  // A user can type and clear the editor before a clipboard read returns.
  // Empty text alone cannot tell that the user already chose what to keep.
  int _editorRevision = 0;

  /// Whether a dismissal stands between now and the last summon.
  ///
  /// The whole of the state AD-18's three-way rule needs, and deliberately a
  /// latch rather than "the last state reported". The rule is about whether the
  /// user ever said they were done with this panel, not about which event came
  /// last, and those two answers differ on the sequence that matters: a
  /// dismissal followed by a survivable departure. Remembering only the last
  /// state, a `dismissed` then an `iconified` then a `shown` would hand back the
  /// session the user closed — the mirror image of DW-30.
  ///
  /// The shipped adapter cannot emit that sequence: a departure cannot rename an
  /// absence it did not cause. Its `hide` and `minimize` arms are each gated on
  /// `_visible` for that reason and both gates are pinned (the suite's negative
  /// controls 30 and 31). Its blur arm reaches the same end by a different
  /// route — `_focused` is only ever set while the mirror reads true and is
  /// cleared on every transition down, so a blur over a panel that is already
  /// away has nothing to report; the `!_visible ||` clause in that arm is a
  /// second statement of it rather than the thing enforcing it, which is why
  /// deleting the clause fails no row (control 12).
  ///
  /// But that invariant lives two rings below this rule, spread across two gates
  /// and one field's lifecycle in an infrastructure file. This latch makes the
  /// rule self-sufficient rather than correct by their grace, exactly as
  /// consuming it on a `shown` already makes a duplicate `shown` inert.
  ///
  /// Starts `true`, which is what makes the first summon of the daemon's life a
  /// session without a special case for it.
  bool _dismissalStands = true;

  /// Bumped by each request, new run, and new session. Only its current owner
  /// may report a clipboard outcome.
  int _copyToken = 0;

  /// This tail waits for the platform write itself, including after feedback
  /// times out. The clipboard port cannot cancel a write that is still running.
  Future<void> _copyTail = Future<void>.value();
  final Map<Completer<void>, Timer> _copyFeedbackTimers =
      <Completer<void>, Timer>{};

  static const Duration _copyWriteLimit = Duration(seconds: 8);

  _Run? _activeRun;
  StreamSubscription<CorrectionEvent>? _events;
  bool _disposed = false;

  /// History writes still in flight. Shutdown waits for them: CAP-7 retains
  /// every correction, including one that terminates as the daemon exits.
  final Set<Future<void>> _pendingSaves = <Future<void>>{};

  CorrectionState get state => _state;

  Stream<CorrectionState> get changes => _changes.stream;

  /// The user typed in the micro-editor (CAP-3).
  void editText(String text) {
    _editorRevision++;
    _setState(_state.copyWith(editorText: text));
  }

  /// Corrects the editor's current content and captures it as the session's
  /// submitted text (CAP-3, AD-18).
  ///
  /// A blank editor is not a correction, so a blank submit is a no-op — and
  /// deliberately not one of AD-4's cancellations: it does not touch a
  /// correction that is already streaming. Pressing Correct on an empty
  /// editor is a mistake, and killing the run in progress would punish it.
  void submit() {
    if (_disposed) {
      return;
    }
    final text = _state.editorText;
    if (text.trim().isEmpty) {
      // An all-whitespace editor would spawn a sidecar process (AD-19) and
      // write a CAP-7 row with nothing in it. The guard decides *whether* to
      // run; what gets sent when it passes is the user's text verbatim.
      _log(() => _logger.info('an empty editor was not submitted'));
      return;
    }
    // AD-4: starting a new correction cancels the in-flight one.
    unawaited(_cancelRun());
    _startRun(text);
  }

  /// Re-runs the captured submitted text (CAP-13) — never what the editor
  /// holds now, which the user may have typed into meanwhile (AD-18).
  ///
  /// Needs no empty guard of its own: [submit] is what sets `submittedText`,
  /// and it never sets it to a blank string.
  void retry() {
    final submitted = _state.submittedText;
    if (_disposed || submitted == null) {
      return; // nothing has been submitted in this session
    }
    unawaited(_cancelRun()); // AD-4: Retry cancels the in-flight correction
    _startRun(submitted);
  }

  /// Highlights [register] with its 1/2/3 key (CAP-4).
  ///
  /// Selection highlights and never copies (AD-18), and it lives here rather
  /// than in the panel widget because the Consistency Conventions make one
  /// controller the owner of a surface's state — which also buys AD-18 for
  /// free: `_beginSession`, `_startRun` and `_onFailed` all build a state
  /// directly, so a highlight cannot outlive a show, a new run or a failure.
  ///
  /// A no-op unless the session completed and that register has text: deltas
  /// are "a progressive-rendering optimisation, never the record of truth"
  /// (AD-3), so there is nothing authoritative to select while one is
  /// streaming.
  ///
  /// The same key again clears the highlight. A highlight the user cannot take
  /// back would be a one-way door on the panel's only reversible act — and
  /// since it means nothing but "this is the one I am looking at", there is
  /// nothing to confirm and nothing to lose by dropping it.
  /// The `_disposed` arm here is defence in depth and nothing more: selecting
  /// reaches no port, and [_setState] already refuses to write after shutdown,
  /// so removing it changes no observable behaviour and no test can pin it.
  /// Said out loud because the sibling arm in [copySuggestion] *is*
  /// load-bearing — that one stops a clipboard write — and the two look alike.
  void selectSuggestion(SuggestionRegister register) {
    if (_disposed || _completedTextOf(register) == null) {
      return;
    }
    if (_state.selectedRegister == register) {
      _setSelectionAndNotice(
        selectedRegister: null,
        copyFailure: _state.copyFailure,
      );
      return;
    }
    _setState(_state.copyWith(selectedRegister: register));
  }

  /// Puts exactly [register]'s completed text on the clipboard (CAP-11).
  ///
  /// Never throws, and never hides a failure: a rejected write reaches the
  /// [Logger] type-only and leaves a short sentence in
  /// [CorrectionState.copyFailure], because a copy button that silently does
  /// nothing tells the user their text is on the clipboard when it is not.
  /// The panel stays open and every variant stays copyable either way
  /// (CAP-14) — nothing here disables anything.
  ///
  /// Only completed text is copyable, for the same AD-3 reason selection is:
  /// a partial that `CorrectionCompleted` is about to replace would put a
  /// half-sentence on the clipboard that the panel no longer shows.
  ///
  /// Exactly one copy's verdict is ever on screen, and it is the newest one's:
  /// see [_copyToken] for why a per-session guard was not enough.
  Future<void> copySuggestion(SuggestionRegister register) {
    if (_disposed) {
      return Future<void>.value();
    }
    final token = ++_copyToken;
    final text = _completedTextOf(register);
    if (text == null) {
      _setCopyFeedback(
        register: register,
        failure: 'There is no suggestion text to copy.',
      );
      return Future<void>.value();
    }
    _setCopyFeedback(register: register, pending: true);
    final feedbackDone = Completer<void>();
    var timedOut = false;
    final timer = Timer(_copyWriteLimit, () {
      _copyFeedbackTimers.remove(feedbackDone);
      timedOut = true;
      if (!_disposed && token == _copyToken) {
        _log(() => _logger.error('the clipboard write timed out'));
        _setCopyFeedback(
          register: register,
          failure: "Couldn't copy this suggestion. Try again.",
        );
      }
      feedbackDone.complete();
    });
    _copyFeedbackTimers[feedbackDone] = timer;
    _copyTail = _copyTail
        .then((_) => _writeCopy(register, text, token, () => timedOut))
        .whenComplete(() {
          _copyFeedbackTimers.remove(feedbackDone)?.cancel();
          if (!feedbackDone.isCompleted) {
            feedbackDone.complete();
          }
        });
    return feedbackDone.future;
  }

  Future<void> _writeCopy(
    SuggestionRegister register,
    String text,
    int token,
    bool Function() timedOut,
  ) async {
    // A queued request whose deadline passed must not write after reporting a
    // failure, even when an earlier platform write eventually releases it.
    if (_disposed || token != _copyToken || timedOut()) {
      return;
    }
    try {
      await _clipboard.writeText(text);
    } on Object catch (error) {
      if (_disposed || token != _copyToken || timedOut()) {
        return;
      }
      _log(
        () => _logger.error(
          'the clipboard write failed; the suggestion was not copied',
          context: _errorContext(error),
        ),
      );
      _setCopyFeedback(
        register: register,
        failure:
            'the ${register.name} suggestion could not be copied to the '
            'clipboard. Try again.',
      );
      return;
    }
    if (_disposed || token != _copyToken || timedOut()) {
      return;
    }
    _setCopyFeedback(register: register, succeeded: true);
  }

  /// [register]'s text when it is the authoritative completed text, else null
  /// — the one gate both CAP-4's selection and CAP-11's copy pass through.
  ///
  /// "Has text" is the same `trim()` test [submit] applies to the editor: a
  /// variant that came back as spaces is not something to put over the user's
  /// clipboard, and it is not something to highlight either.
  String? _completedTextOf(SuggestionRegister register) {
    if (_state.status != CorrectionStatus.completed) {
      return null;
    }
    final text = _state.suggestionTexts[register];
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return text;
  }

  void _setCopyFeedback({
    required SuggestionRegister register,
    String? failure,
    bool pending = false,
    bool succeeded = false,
  }) => _setState(
    CorrectionState(
      editorText: _state.editorText,
      status: _state.status,
      suggestionTexts: _state.suggestionTexts,
      submittedText: _state.submittedText,
      failure: _state.failure,
      selectedRegister: _state.selectedRegister,
      copyRegister: register,
      copyPending: pending,
      copySucceeded: succeeded,
      copyFailure: failure,
    ),
  );

  /// Re-emits the current state with the panel's two clearable fields set to
  /// exactly what is passed — the one thing `copyWith` cannot do.
  ///
  /// One enumeration of the carried-over fields, rather than one per clearing
  /// transition: a field forgotten here is a field silently dropped by both a
  /// deselect and a successful copy.
  void _setSelectionAndNotice({
    required SuggestionRegister? selectedRegister,
    required String? copyFailure,
  }) {
    _setState(
      CorrectionState(
        editorText: _state.editorText,
        status: _state.status,
        suggestionTexts: _state.suggestionTexts,
        submittedText: _state.submittedText,
        failure: _state.failure,
        selectedRegister: selectedRegister,
        copyFailure: copyFailure,
        copyRegister: _state.copyRegister,
        copyPending: _state.copyPending,
        copySucceeded: _state.copySucceeded,
      ),
    );
  }

  /// Daemon shutdown — AD-4's third and last cancellation.
  ///
  /// Never rethrows: a rejected cancel or a rejected pending save is logged
  /// and shutdown still completes, because a daemon that cannot exit is a
  /// worse failure than a lost history row.
  Future<void> dispose() async {
    _disposed = true;
    _copyToken++;
    for (final entry in _copyFeedbackTimers.entries) {
      entry.value.cancel();
      if (!entry.key.isCompleted) {
        entry.key.complete();
      }
    }
    _copyFeedbackTimers.clear();
    await _cancel(_visibilityChanges, 'the panel visibility subscription');
    final cancelled = _cancelRun();
    await _changes.close();
    await cancelled;
    // No terminal event can arrive past this line: cancelling a subscription
    // ends delivery even when the cancel itself rejects, so the snapshot
    // below cannot miss a save. A run that terminates while the cancel is
    // still in flight is persisted and waited for, which is what CAP-7
    // promises for a correction that terminates as the daemon exits.
    await Future.wait(_pendingSaves.toList());
  }

  /// AD-18's session rule, and the only place it lives.
  ///
  /// The port says where the window went; what that costs a session is decided
  /// here, so the rule can change without re-teaching an adapter.
  ///
  /// **The rule is three-way, on the human's decision of 2026-08-14 on DW-30.**
  /// A dismissal is the user saying they are done with this window, so the
  /// summon after one opens a fresh session — cleared state, editor re-seeded
  /// from the *current* clipboard. An iconify or a focus loss is not: the same
  /// window comes back with the same work in it, so nothing is emitted at all
  /// and the panel keeps the text, the suggestions and the error it had.
  ///
  /// **That narrows CAP-2, and the narrowing is stated rather than implied.**
  /// CAP-2 says the panel is pre-filled from the clipboard; what it is pre-filled
  /// on is the summon *after a dismissal*, and a return from an iconify or a
  /// focus loss reads no clipboard at all.
  ///
  /// No departure cancels anything. AD-4's three cancellations do not include
  /// one: an in-flight correction runs to its terminal event and is still
  /// persisted (CAP-7), whichever way the panel went away — and it lands into
  /// the session that comes back, when that session survived.
  void _onVisibilityChanged(PanelVisibilityState visibility) {
    if (_disposed) {
      // A rejected cancel leaves this subscription live, and a session begun
      // now would re-seed from the clipboard — display-server IPC issued by a
      // controller that is already torn down.
      return;
    }
    if (visibility == PanelVisibilityState.shown && _dismissalStands) {
      _beginSession();
    }
    _dismissalStands = _dismissalStandsAfter(visibility);
  }

  /// Whether a dismissal still stands once [reported] has been seen.
  ///
  /// A `switch` expression with no grouped arms and no default, so a fifth
  /// member of [PanelVisibilityState] is a compile error here rather than a
  /// silent vote for "the session survives".
  bool _dismissalStandsAfter(
    PanelVisibilityState reported,
  ) => switch (reported) {
    // The user said they are done with this panel. It stands until a summon
    // consumes it.
    PanelVisibilityState.dismissed => true,
    // Survivable. Neither raises a dismissal nor clears one that already
    // stands, so whatever the answer was before this event, it still holds —
    // which is what stops a click-away or a workspace switch from erasing a
    // dismissal the user really made.
    PanelVisibilityState.iconified => _dismissalStands,
    PanelVisibilityState.focusLost => _dismissalStands,
    // The summon consumes it, and that is what makes a *second* `shown` —
    // an adapter breaking the port's transition contract — inert: it finds
    // nothing standing, so the session already on screen is kept.
    PanelVisibilityState.shown => false,
  };

  /// Starts a fresh session: previous suggestions, error, and edits are cleared
  /// and the editor is re-seeded from the *current* clipboard (AD-18, CAP-2).
  ///
  /// Reached from a summon that follows a dismissal, and from nothing else —
  /// see [_onVisibilityChanged] for which departures do not lead here.
  void _beginSession() {
    final token = ++_sessionToken;
    _copyToken++; // a copy in flight belongs to the session that is ending
    _setState(CorrectionState.freshSession);
    unawaited(_seedFromClipboard(token, _editorRevision));
  }

  Future<void> _seedFromClipboard(int token, int editorRevision) async {
    final String? clipboardText;
    try {
      clipboardText = await _clipboard.readText();
    } on Object catch (error) {
      if (token != _sessionToken || _disposed) {
        // The session this read was for is gone, so its failure is nobody's
        // news: warning about it would attribute the failure to whatever
        // session is current now, or log after shutdown.
        return;
      }
      // The clipboard is display-server IPC and can fail. CAP-2's pre-fill
      // is a convenience; the session stays usable with an empty editor,
      // which is what [_beginSession] already put there.
      _log(
        () => _logger.warning(
          'the clipboard read failed; the editor stays empty',
          context: _errorContext(error),
        ),
      );
      return;
    }
    if (token != _sessionToken) {
      return; // a newer show already re-seeded; this read is stale
    }
    if (_editorRevision != editorRevision ||
        _state.editorText.isNotEmpty ||
        _state.status != CorrectionStatus.idle) {
      // The clipboard is IPC and the panel is up in 100 ms (CAP-1), so the
      // user can type before the read lands. Their text wins (CAP-3).
      return;
    }
    final seeded = clipboardText ?? '';
    if (seeded.isEmpty) {
      // Nothing to pre-fill: the editor is already empty (the guard above says
      // so). The emission this skips would carry the same fields — and **not**
      // the same value, which is worth stating precisely because the obvious
      // reason for this guard is now the wrong one. `copyWith` deliberately
      // drops [CorrectionState.isFreshSession], so the state below is `!=` the
      // one it would replace: it would announce the session *ending* one IPC
      // round-trip after it began, to two widgets that read exactly that field.
      //
      // Not the focus defect this guard once carried, either. That one was real
      // while `isFreshSession` was the value comparison `this == empty`: a
      // second emission of that value read as a second session beginning and
      // pulled focus back to the editor out from under a user who had moved it.
      // Stamping the marker answered that direction; this guard is what keeps
      // the other one from opening.
      //
      // The cost, stated rather than left to be found: [state] therefore keeps
      // `isFreshSession` true for the rest of an empty-clipboard session, until
      // something the user does builds a new state. Inert today — the marker is
      // read only by the two stream callbacks, and no emission carries it a
      // second time — but a future consumer that polls [state] instead of
      // watching [changes] would see a session that never stops beginning.
      return;
    }
    _setState(_state.copyWith(editorText: seeded));
  }

  void _startRun(String text) {
    final run = _Run(
      sessionToken: _sessionToken,
      submittedText: text,
      startedAtMillis: _clock.nowMillis(),
      activePair: _activePair,
    );
    _activeRun = run;
    // A copy in flight belongs to the answer this run replaces, so its verdict
    // is no longer about anything on screen. The state built below is what
    // drops the highlight and the notice themselves (AD-18).
    _copyToken++;
    _setState(
      CorrectionState(
        editorText: _state.editorText,
        status: CorrectionStatus.running,
        suggestionTexts: const {},
        submittedText: text,
      ),
    );
    final Stream<CorrectionEvent> events;
    try {
      events = run.activePair.provider.correct(
        text: text,
        preset: run.activePair.preset,
      );
    } on Object catch (error) {
      // AD-3 says no exception escapes correct(). One that does is the same
      // class of breach as a stream error, so it takes the same path: one
      // terminal failure, rendered inline and recorded (CAP-13, CAP-7).
      _log(
        () => _logger.error(
          'the provider threw instead of returning a stream',
          context: {
            'preset_id': run.activePair.preset.id,
            ..._errorContext(error),
          },
        ),
      );
      // The message is CAP-13's inline panel text, so it is a sentence the
      // user can act on. The raw error is not ours to render for the same
      // reason it is not ours to log: a vendor exception's `toString()`
      // routinely carries the payload that caused it — here, the submitted
      // text on a failed sidecar spawn's argument list.
      _onEvent(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerError,
          message:
              'the corrector could not be started. Check the active preset, '
              'then try again.',
        ),
        run,
      );
      return;
    }
    // AD-3 promises no error and exactly one terminal event. Both handlers
    // below exist because a provider that breaks that promise must still not
    // strand the panel on a spinner or take the daemon's zone down with it.
    _events = events.listen(
      (event) => _onEvent(event, run),
      onError: (Object error) => _onEvent(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerError,
          message: 'the corrector stopped unexpectedly. Try again.',
        ),
        run,
      ),
      onDone: () => _onEvent(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerError,
          message: 'the provider closed the stream with no terminal event',
        ),
        run,
      ),
    );
  }

  /// Cancels the in-flight run, if any. A cancelled run never reaches a
  /// terminal event, so nothing is persisted for it.
  Future<void> _cancelRun() {
    final events = _events;
    final run = _activeRun;
    if (run != null) {
      run.terminated = true;
    }
    _events = null;
    _activeRun = null;
    return _cancel(events, 'the in-flight correction');
  }

  /// Cancels [subscription], reducing a rejected cancel to a log line.
  ///
  /// A cancel that fails must not stop what follows it — a Retry still
  /// starts, a new submit still runs, and shutdown still completes.
  Future<void> _cancel(
    StreamSubscription<Object?>? subscription,
    String what,
  ) async {
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } on Object catch (error) {
      // AD-15 backstop: under AD-19 this cancel is the sidecar's
      // process-group kill, so a rejection is worth an operator's attention.
      _log(
        () => _logger.error(
          'cancelling $what failed',
          context: _errorContext(error),
        ),
      );
    }
  }

  void _onEvent(CorrectionEvent event, _Run run) {
    if (run.terminated) {
      // AD-3 promises one terminal event per stream. A provider that breaks
      // that promise must still not double-count the correction (AD-7).
      return;
    }
    switch (event) {
      case SuggestionDelta():
        _onDelta(event, run);
      case CorrectionCompleted():
        _onCompleted(event, run);
      case CorrectionFailed():
        _onFailed(event, run);
    }
  }

  void _onDelta(SuggestionDelta delta, _Run run) {
    if (!_isCurrent(run)) {
      return;
    }
    final texts = Map<SuggestionRegister, String>.of(_state.suggestionTexts);
    // Deltas are incremental fragments, never cumulative (AD-3).
    texts[delta.register] = '${texts[delta.register] ?? ''}${delta.textDelta}';
    _setState(
      _state.copyWith(
        suggestionTexts: Map<SuggestionRegister, String>.unmodifiable(texts),
      ),
    );
  }

  void _onCompleted(CorrectionCompleted event, _Run run) {
    final mismatch = _registerMismatch(event.suggestions);
    if (mismatch != null) {
      // AD-3 guarantees one suggestion per register. The controller is the
      // last point before a `completed` row reaches CAP-7 history, and the
      // shape of the response was wrong — the same thing the adapter's own
      // parser reports as malformedResponse, so history records it the same
      // way whichever layer noticed.
      _log(
        () => _logger.error(
          'the provider completed with a malformed register set',
          context: mismatch,
        ),
      );
      // The message is what CAP-13 renders inline to the user, so it says
      // what happened to their correction; the counts stay in the log
      // context, where an operator diagnosing the provider will look. It
      // covers both shapes [_registerMismatch] fires on — too few distinct
      // registers, and the full set plus a duplicate — because "missing"
      // would be a false statement about the second.
      _onFailed(
        const CorrectionFailed(
          kind: CorrectionFailureKind.malformedResponse,
          message:
              'the corrector sent a malformed answer — the three variants '
              'did not come back as expected. Try again.',
        ),
        run,
      );
      return;
    }
    final current = _isCurrent(run);
    _finish(run);
    _persist(_completedRecord(event, run));
    if (!current) {
      return;
    }
    // The completed suggestions are authoritative and replace whatever the
    // deltas accumulated (AD-3).
    _setState(
      _state.copyWith(
        status: CorrectionStatus.completed,
        suggestionTexts: _textsOf(event.suggestions),
      ),
    );
  }

  void _onFailed(CorrectionFailed event, _Run run) {
    final current = _isCurrent(run);
    _finish(run);
    _persist(_failedRecord(event, run));
    if (!current) {
      return;
    }
    // The error replaces the empty or half-streamed suggestions (CAP-13).
    _setState(
      CorrectionState(
        editorText: _state.editorText,
        status: CorrectionStatus.failed,
        suggestionTexts: const {},
        submittedText: _state.submittedText,
        failure: event,
      ),
    );
  }

  /// This controller is the sole caller of [CorrectionRepository.save], once
  /// per correction, at the terminal event (AD-7). A failed write still
  /// counts as that correction's one attempt: it is never retried and never
  /// re-issued.
  void _persist(CorrectionRecord record) {
    final save = _save(record);
    _pendingSaves.add(save);
    unawaited(save.whenComplete(() => _pendingSaves.remove(save)));
  }

  /// Saves [record], reducing a rejected write to a log line.
  ///
  /// A correction that completed and whose history row was lost did not
  /// fail, so this produces no panel state: [CorrectionState.failure] is
  /// CAP-13's inline error with a Retry, and offering a Retry here would
  /// invite the user to re-run a correction that already succeeded and burn
  /// a second sidecar process. The loss is an operator concern.
  Future<void> _save(CorrectionRecord record) async {
    try {
      await _repository.save(record);
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the history write failed; this correction is not in history',
          context: {
            'preset_id': record.presetId,
            'provider_id': record.providerId,
            'model': record.model,
            'outcome': record.outcome.name,
            'latency_ms': record.latencyMs,
            ..._errorContext(error),
          },
        ),
      );
    }
  }

  CorrectionRecord _completedRecord(CorrectionCompleted event, _Run run) {
    return CorrectionRecord(
      createdAtMillis: run.startedAtMillis,
      inputText: run.submittedText,
      presetId: run.activePair.preset.id,
      providerId: run.activePair.preset.providerId,
      model: run.activePair.preset.model,
      latencyMs: _clock.nowMillis() - run.startedAtMillis,
      outcome: CorrectionOutcome.completed,
      suggestions: event.suggestions,
    );
  }

  CorrectionRecord _failedRecord(CorrectionFailed event, _Run run) {
    return CorrectionRecord(
      createdAtMillis: run.startedAtMillis,
      inputText: run.submittedText,
      presetId: run.activePair.preset.id,
      providerId: run.activePair.preset.providerId,
      model: run.activePair.preset.model,
      latencyMs: _clock.nowMillis() - run.startedAtMillis,
      outcome: CorrectionOutcome.failed,
      failureKind: event.kind,
      suggestions: const [],
    );
  }

  /// True while [run] is both the in-flight run and part of the session the
  /// panel is currently showing.
  bool _isCurrent(_Run run) =>
      identical(_activeRun, run) && run.sessionToken == _sessionToken;

  void _finish(_Run run) {
    run.terminated = true;
    if (!identical(_activeRun, run)) {
      return;
    }
    _activeRun = null;
    final events = _events;
    _events = null;
    // Cancelling is what tears the provider's work down — under AD-19 it is
    // the sidecar's process-group kill. Dropping the subscription would
    // leave that work running in a daemon that never exits.
    unawaited(_cancel(events, 'the terminated correction'));
  }

  void _setState(CorrectionState state) {
    if (_disposed) {
      return; // a clipboard read can resolve after shutdown
    }
    _state = state;
    _changes.add(state);
  }
}

/// Emits a log line without letting the logger's own failure escape.
///
/// This is the canonical site for the rule the other two controllers follow.
/// Every guard in this layer recovers by logging, so the [Logger] is the one
/// port whose failure cannot be reported — and a `StderrLogger` whose sink is
/// gone (a daemon whose parent terminal closed leaves stderr a broken pipe)
/// throws on write. Without this, each guard turns into the unhandled async
/// error it exists to prevent, and `dispose()` breaks its documented promise
/// never to rethrow. It is the sole sanctioned silent swallow in this layer:
/// the reporting channel is precisely what failed.
void _log(void Function() emit) {
  try {
    emit();
  } on Object {
    // Nowhere left to report this: the reporting channel is what broke.
  }
}

/// The only part of a caught error that is safe to put in a log line.
///
/// This is the canonical site for the rule the [Logger] port documents: a
/// vendor exception's `toString()` routinely carries the payload that caused
/// it — `SqliteException` appends the failing statement and its bound
/// parameters, which for the history write are the corrected text and every
/// suggestion body. The type is diagnostic; the message is not ours to trust.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}

/// Describes how [suggestions] fails AD-3's "exactly one entry per
/// [SuggestionRegister] value", or null when it satisfies it.
///
/// Counts only: the registers are structure, the texts are the user's
/// clipboard-derived content and never reach a log line.
Map<String, Object?>? _registerMismatch(List<Suggestion> suggestions) {
  final registers = suggestions.map((suggestion) => suggestion.register);
  final distinct = registers.toSet();
  final expected = SuggestionRegister.values.length;
  if (distinct.length == suggestions.length && distinct.length == expected) {
    return null;
  }
  return {
    'expected_registers': expected,
    'received_suggestions': suggestions.length,
    'distinct_registers': distinct.length,
  };
}

Map<SuggestionRegister, String> _textsOf(List<Suggestion> suggestions) {
  return Map<SuggestionRegister, String>.unmodifiable({
    for (final suggestion in suggestions) suggestion.register: suggestion.text,
  });
}

/// One correction attempt: which session asked for it, what it was asked
/// with, and when — everything the terminal event needs to persist a record
/// that outlives the session (AD-7).
final class _Run {
  _Run({
    required this.sessionToken,
    required this.submittedText,
    required this.startedAtMillis,
    required this.activePair,
  });

  final int sessionToken;
  final String submittedText;
  final int startedAtMillis;
  final ({CorrectionProvider provider, Preset preset}) activePair;

  bool terminated = false;
}
