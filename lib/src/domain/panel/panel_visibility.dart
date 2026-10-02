/// Where the panel window is, and — for the three ways it goes away — which
/// gesture put it there.
///
/// Declared beside [PanelVisibility] rather than in a file of its own, the way
/// `CorrectionFailureKind` sits beside the `CorrectionEvent` family: it is the
/// vocabulary of one member of one port and has no life apart from it.
///
/// **Descriptive only.** Each member says where the window went, never what
/// that costs a session. AD-18's rule — which returns clear the panel and
/// re-seed from the clipboard — is `CorrectionController`'s, so that the rule
/// can change without re-teaching an adapter.
enum PanelVisibilityState {
  /// The panel is up: the hotkey summoning it, a de-iconify, or the window
  /// manager mapping it on its own.
  ///
  /// The only member for which [isVisible] is true, and therefore the only one
  /// at which a session can begin.
  shown,

  /// The panel was put away *as a `hide()` request would put it away*: the
  /// hotkey toggle pressed at a visible panel, or the window's own close
  /// control, which an implementation answers with a real hide.
  ///
  /// The departure that **ends** a session. The next [shown] after it clears
  /// the panel and re-seeds the editor from the current clipboard (AD-18,
  /// CAP-2).
  ///
  /// The tray menu is deliberately not in that list: it offers "open the
  /// panel" and Quit, and neither of those hides anything.
  dismissed,

  /// The panel was iconified — today a workspace switch or a show-desktop
  /// gesture, and a task-bar minimise once the panel window has a task-bar
  /// entry to be minimised to.
  ///
  /// The user did not ask to be done with the window, so the session
  /// **survives**: the next [shown] emits nothing and the panel comes back with
  /// the text, the suggestions and the error it had.
  ///
  /// **Owed to the panel-window-geometry bundle (DW-50, DW-53, DW-61, DW-72).**
  /// The human's rule of 2026-08-14 is three-way because a minimise *to the
  /// tray icon* ends a session while a minimise *to the task bar* does not.
  /// Only the second of those is this member: an adapter reaches it from a GTK
  /// `minimize` event, and nothing today can raise one by way of the tray, so
  /// the distinction is currently unreachable rather than implemented.
  /// `setSkipTaskbar(true)` is what keeps it that way. When that bundle makes
  /// the task-bar entry conditional, a minimise-to-tray must be told apart from
  /// a minimise-to-task-bar *before* it reaches this member — attributed
  /// [dismissed] instead — or the human's rule inverts on the one gesture they
  /// named for it, with every row in the suite still green.
  iconified,

  /// The panel took itself down because the window lost the keyboard (CAP-14).
  ///
  /// A dismissal of the *window*, not of the work in it, so the session
  /// **survives** exactly as it does across an [iconified] departure.
  focusLost;

  /// Whether the panel is on screen in this state.
  ///
  /// The mirror [PanelVisibility.isVisible] carries, written from the same
  /// value the matching [PanelVisibility.changes] event reports.
  bool get isVisible => this == shown;
}

/// AD-8 pairs a synchronous visibility mirror with attributed transitions.
/// AD-18 uses the departure reason to decide whether the session survives.
abstract interface class PanelVisibility {
  /// Synchronous in-process mirror. Never an IPC query.
  bool get isVisible;

  /// Emits on every change of [PanelVisibilityState], including focus-loss
  /// hides (CAP-14), and says which of the three departures took the window
  /// away.
  ///
  /// Broadcast: a state-change notification stream, in the same terms
  /// `ConfigStore.changes` uses. `CorrectionController` owns the panel session;
  /// `PanelController` observes focus-loss departures so Settings can discard
  /// its capture draft. The panel widget watches `CorrectionController.changes`
  /// instead of reaching for this port. The stream is broadcast so these
  /// independent listeners can observe the same transition.
  ///
  /// Emits **exactly on a transition of the state**, whatever caused it. There
  /// is one way to be up and three ways to be away, so the rule is not
  /// symmetric and stating it precisely matters:
  ///
  /// - A [PanelVisibilityState.shown] over a panel that is already up reports
  ///   nothing. A [show] at a visible panel is the whole of that case.
  /// - A departure that **repeats the one already standing** reports nothing.
  ///   A [hide] at a panel that was already dismissed is the whole of that
  ///   case, and it is the only sense in which "a hide at a hidden panel emits
  ///   nothing" is true.
  /// - A **different** departure arriving over a panel that is already away
  ///   *is* a transition — the reason it is away has been replaced — and is
  ///   reported. The window's close control activated on an iconified panel is
  ///   the case that matters, because under AD-18 the last reason is the one
  ///   the next [PanelVisibilityState.shown] is judged against.
  Stream<PanelVisibilityState> get changes;

  /// Native Close intent, before the application chooses hide or quit.
  /// Broadcast; it never destroys the warm window on its own.
  Stream<void> get closeRequests;

  /// Asks for the already-constructed window to be shown **and focused**.
  ///
  /// A resolved future means the request was accepted and has left the
  /// implementation's queue. It does **not** mean the window moved: the request
  /// may have been superseded by a later one, abandoned at disposal, or
  /// abandoned because the window did not answer within the implementation's
  /// bound. All three resolve rather than throw, because none of them is the
  /// caller's error to handle.
  ///
  /// A rejection therefore means one thing: the window *refused* a call, and
  /// did so **while the request was still being awaited**. A refusal that
  /// arrives after the implementation stopped waiting cannot be reported — the
  /// request has already resolved as abandoned by then — so the absence of an
  /// error is not evidence that nothing was refused.
  ///
  /// [isVisible] and [changes] are where the intent is observable; awaiting
  /// this is not a way to read it.
  Future<void> show();

  /// Asks for the window to be hidden. Its future carries the same meaning as
  /// [show]'s: accepted and out of the queue, not "the window moved".
  ///
  /// A request to hide is the user saying they are done with this window, so
  /// what [changes] reports for it is [PanelVisibilityState.dismissed] — the
  /// departure that ends a session.
  Future<void> hide();
}
