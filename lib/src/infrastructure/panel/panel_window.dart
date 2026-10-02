import 'panel_activation.dart';

/// The daemon's one toplevel window, as the visibility adapter needs it:
/// three requests and the raw stream of events the window reports back.
///
/// An infrastructure-private seam, and the only abstraction in this slice with
/// a single implementation — which AGENTS.md §4.2 warns against unless there is
/// a real test need. There is one, and it is specific: the defect this adapter
/// exists to close lives in the *gap* between a request and its echo, so a test
/// has to be able to lengthen that gap and hold two requests open at once.
/// `windowManager` is a singleton behind a private method channel, reachable
/// only through a mocked channel and therefore only with a Flutter binding,
/// which cannot easily park two calls in a chosen order. This seam keeps the
/// mirror logic in `dart test`'s binding-free set (AGENTS.md §7) and confines
/// `window_manager` to one file (AD-1).
///
/// [events] carries **raw window event names** — `show`, `hide`, `focus`,
/// `blur`, `minimize`, `restore`, `close`, `self-focus` — rather than a typed vocabulary,
/// because the one route `window_manager 0.5.2` offers to the two that matter
/// most is untyped (see `WindowManagerPanelWindow`). Translating them is the
/// visibility adapter's job.
///
/// `focus` is in that list because `WindowManagerPanelVisibility` cannot answer
/// a `blur` without it (DW-33). A focus-out that follows a real focus-in is the
/// user turning away, which CAP-14 answers with a hide; a focus-out at a window
/// that never took the keyboard is a window manager with focus-stealing
/// prevention declining to give it, and hiding there takes the panel down at
/// the moment it was summoned. Only the pair distinguishes them, so a forwarder
/// that dropped `focus` would leave every `blur` looking like the second case —
/// a window that never took the keyboard — and **CAP-14's focus-loss dismissal
/// would never fire again**. The panel would still be dismissable by the hotkey
/// and by its close control (DW-12); it would simply stop putting itself away
/// when the user clicked elsewhere, which is the one dismissal nobody asks for
/// explicitly and so the one nobody would report as missing.
///
/// `close` is in that list and is **load-bearing**, which is easy to miss
/// because it is the one name that does not describe a state the window has
/// already reached. `main.dart` sets `setPreventClose(true)` at startup, and the
/// plugin emits `close` *before* it reads that flag — so the event arrives with
/// the toplevel **still mapped**, and `WindowManagerPanelVisibility` answers it
/// by reporting close intent to the application (DW-12). A forwarder narrowed to the other six names
/// would therefore leave a dismissed panel on screen, and every binding-free
/// suite above this seam would stay green throughout — the only implementation
/// of this interface needs a Flutter binding. What catches that narrowing is
/// the one row that reaches the real channel:
/// `test/platform/window_manager_panel_window_test.dart`'s
/// `AD-8: show, focus, blur, hide and close all reach events through
/// onWindowEvent`.
abstract interface class PanelWindow {
  /// Maps the window. On Linux this is `gtk_widget_show`, which neither raises
  /// it nor gives it the keyboard — hence [focus] as a separate step.
  Future<void> show();

  Future<void> hide();

  /// Raises the window and gives it focus. On Linux this is
  /// `gtk_window_present`, which **also maps a hidden toplevel** — so calling
  /// it after a superseded [show] would put the panel back on screen.
  Future<void> focus({PanelActivation? activation});

  /// Every event the window reports, by name. `self-focus` marks a focus-in
  /// expected from this seam's own show/present; `focus` is a user focus-in.
  /// Broadcast, so the adapter's subscription is not the only one possible.
  Stream<String> get events;

  /// Deregisters from the window and closes [events]. Idempotent.
  Future<void> dispose();
}
