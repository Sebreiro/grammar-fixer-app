/// Whether the daemon's toplevel still holds the keyboard, asked of the display
/// server directly rather than inferred from the events the window reports.
///
/// This exists because the window events cannot answer it. A passive key grab
/// activating makes X send the focused window a `FocusOut` whose *mode* says
/// `NotifyGrab` — no keyboard moved, the grab merely intercepted it — and
/// `window_manager 0.5.2` forwards that as a bare `blur` with the mode
/// discarded. CAP-14's focus-loss hide reads that bare `blur` as the user
/// turning away and dismisses the panel, so the daemon dismisses its own panel
/// on its own shortcut (G-01-13). Recovering the mode would mean forking the
/// plugin or adding a second channel that races the first; the mode is only a
/// proxy anyway. CAP-14's real question is *has this window lost the
/// keyboard?*, and the display server answers that one synchronously and
/// without being disturbed by a grab — a keyboard grab does not move the input
/// focus, which is precisely why X labels the focus-out `NotifyGrab` rather
/// than sending a real focus transfer.
///
/// So the discriminator is not "was this a grab?" but "is the keyboard still
/// where it was when we last held it?", and that is race-free in both
/// directions: under a grab the focus never moves at all, and under a genuine
/// focus loss it has already moved before the focus-out is sent. No timer, no
/// delay and no deadline appears anywhere on this path, and none may be added:
/// the defect is a race with a measured 4 ms margin, and widening a race is not
/// closing it (AGENTS.md §6).
///
/// An infrastructure-private seam, beside the `PanelWindow` seam in this
/// directory and justified the same way AGENTS.md §4.2 allows a
/// single-implementation abstraction: there is a real test need. The visibility
/// adapter's rows are binding-free `package:test` rows and cannot reach a real
/// X server, so the question has to be fakeable. Kept out of `lib/src/domain/`
/// deliberately — nothing above infrastructure reads it, and keeping it here is
/// what leaves AD-8's `PanelVisibility` and AD-9's `GlobalHotkey` declarations
/// untouched by this fix.
abstract interface class KeyboardFocusWitness {
  /// Records who the display server gives the keyboard to right now, so a
  /// later [focusUnmoved] has something to compare against.
  ///
  /// Called when the window reports that it took the keyboard, and nowhere
  /// else — the comparison is against what the window last *said* it held, not
  /// against a window id this seam picked for itself.
  ///
  /// **This may throw, and the caller backstops it.** Unlike [dispose] it
  /// carries no never-throws promise: the X11 implementation reaches
  /// `DynamicLibrary.open`, `calloc` and an FFI call behind this call. The
  /// caller runs it inside a window-event listener, where a throw would reach
  /// the root zone rather than any `onError`, so it wraps this in the same
  /// AD-15 backstop it wraps [focusUnmoved] in. A recording that failed leaves
  /// nothing witnessed, which [focusUnmoved] answers `false` — so the failure
  /// costs the caller nothing beyond the dismissal it would have performed
  /// anyway. Stating the asymmetry here keeps it a contract rather than an
  /// accident of which member happened to get a guard.
  void recordFocusGained();

  /// Whether the display server still gives the keyboard to the same window
  /// [recordFocusGained] last recorded.
  ///
  /// **This may only be `true` where the absence of a focus transfer is
  /// positively established.** Every other outcome is `false` — nothing
  /// witnessed yet, no display, a server that will not answer, a focus the
  /// server reports as belonging to no window, or a throw — so a caller that
  /// dismisses on `false` behaves exactly as it did before this seam existed.
  /// The asymmetry is the whole contract: a `true` suppresses CAP-14's
  /// dismissal, and suppressing a dismissal that should have fired costs the
  /// user a panel that will not go away, while a needless `false` costs
  /// nothing beyond the dismissal CAP-14 already performed.
  bool get focusUnmoved;

  /// Releases whatever the answer was built from. Idempotent, and never
  /// throws: it runs on the shutdown path.
  Future<void> dispose();
}
