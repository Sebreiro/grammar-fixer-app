import 'hotkey_grab.dart';

/// The X11 key grab, as the hotkey adapter needs it: hold one combination,
/// let it go, and report presses.
///
/// An infrastructure-private seam, and the third abstraction in this project
/// with a single implementation — which AGENTS.md §4.2 warns against unless
/// there is a real test need. There is one, and it is the same one `PanelWindow`
/// and `TrayIcon` carry, in its sharpest form yet: the implementation opens a
/// real X11 connection over `dart:ffi` and pumps it from a worker isolate, so
/// exercising it at all needs a live X server — there is no display in CI and
/// none in this project's devcontainer by default. Everything worth testing
/// above it is pure decision-making — what `bind()` reports, what a rebind
/// reports when it is refused, what a press becomes, what a refusal degrades
/// to — and AGENTS.md §7 wants that in the binding-free `dart test` set.
///
/// The confinement is load-bearing beyond tidiness:
/// `test/infrastructure/system/daemon_startup_test.dart` imports
/// `x11_global_hotkey.dart` and runs under `dart test`, which cannot resolve
/// `dart:ui`. A Flutter import reaching that file — directly or transitively —
/// does not fail a test, it stops the whole binding-free suite resolving.
/// `test/architecture/hotkey_confinement_test.dart` is what keeps that from
/// happening quietly.
///
/// **Two properties of the backend that callers must not re-derive.** Both of
/// these previously said the opposite, and both inverted when the
/// `hotkey_manager` plugin was removed in favour of a private X11 connection.
/// The old wording is preserved in that plan's summary and in the ledger closure
/// for DW-39, because "a refusal is readable" is only meaningful next to the
/// version of this seam where it was not.
///
/// 1. *The key name is computed in Dart.* The implementation resolves the label
///    to a keysym name with `XdgShortcutTrigger.keysymNameFor` and hands that to
///    `XStringToKeysym`, so the serialization genuinely happens in this project
///    — which is what AD-9 always described. It is still true that no vendor
///    vocabulary crosses this seam: what crosses is a [HotkeyGrab], a USB HID
///    usage and a set of domain modifiers, and nothing else. No keysym, keycode,
///    modifier mask, `Pointer` or `SendPort` rises above the implementation.
/// 2. *A refused grab is readable, and named.* `XSetErrorHandler` plus
///    `XSync` makes the server's answer synchronous: a combination another
///    client already owns produces `BadAccess` (error code 10) against
///    `X_GrabKey` (request 33) before `XSync` returns. So a [grab] that resolves
///    means "the combination is now held", and a rejection distinguishes *why* —
///    no backend, an unknown key, a key absent from the layout, or another
///    client owning it. AD-10's "a failed grab must not report success" is
///    satisfiable here, which it was not through the plugin this replaced.
///
///    **The distinction crosses the seam as [HotkeyRegistrarRefusal], and that
///    is what makes this property true above it.** It read as true for a phase
///    while being false: the implementation diagnosed four codes and threw
///    `StateError(sentence)`, so the only carrier left was English and the
///    adapter above hard-coded one cause for all four. A consumer that has to
///    parse a sentence to tell "no backend" from "this key refused" is exactly
///    what HOTKEY-08 exists to remove, so a rejection that distinguishes *why*
///    has to do it with a value.
/// Which of the seam's refusals a [HotkeyRegistrarRefusal] is, as a value.
///
/// Deliberately the backend's vocabulary rather than the user's:
/// `HotkeyUnavailableCause` is named for what it means to the person whose
/// hotkey stopped working and has three values, this one is named for what the
/// backend answered and has four. Collapsing them into one enum here would
/// force the mapping decision into the implementation, and it belongs in the
/// adapter — which is the only thing that knows AD-12's rule about when a user
/// should be told to try another key.
enum HotkeyRefusalCode {
  /// There is no X11 mechanism to talk to at all: no client library, or no
  /// display this process can open. Nothing the user tries reaches a backend.
  noBackend,

  /// A backend answered and did not grant this request — another client owns
  /// the combination, the server does not know the key, or the current layout
  /// has no key for it. Another combination may well work.
  keyRefused,

  /// The two halves of the implementation disagreed about the shape of a
  /// message. A defect, not a condition of the host, and reported rather than
  /// swallowed so it cannot present as a mysterious refusal.
  badRequest,

  /// The worker that owns the connection stopped answering, so there is
  /// nothing left to ask.
  workerGone,
}

/// A [HotkeyRegistrar] refusing a request, with the reason as a value.
///
/// An exception rather than a returned value because that is the seam's
/// declared contract — [HotkeyRegistrar.grab] rejects, and `X11GlobalHotkey` is
/// what turns a rejection into a `HotkeyBindOutcome`, so AD-12's "unavailability
/// is a value" is honoured one level up rather than twice.
///
/// [message] is **project-authored** on every path: the implementation writes
/// each sentence itself and never lets a vendor error's string form into one,
/// so an adapter can carry it straight through to
/// `HotkeyUnavailable.message`. Each ends by naming the tray menu, which is
/// AD-12's rule for a sentence a surface renders verbatim.
final class HotkeyRegistrarRefusal implements Exception {
  const HotkeyRegistrarRefusal({required this.code, required this.message});

  /// Readable without parsing [message] — the whole point of the type
  /// (HOTKEY-08, D-06).
  final HotkeyRefusalCode code;

  /// The diagnosis in terms a user can act on, ending with the tray route.
  final String message;

  /// The code and nothing else, on purpose.
  ///
  /// Nobody should be logging an error's string form (see the `Logger` port),
  /// and an uncaught one prints this at top level. [message] is safe — it is
  /// authored here, not taken from user text — but leaving it out means no
  /// future path can start relying on the prose when [code] is what it should
  /// read.
  @override
  String toString() => 'HotkeyRegistrarRefusal(${code.name})';
}

abstract interface class HotkeyRegistrar {
  /// Asks the backend to hold [grab], letting go of whatever was held only once
  /// the new combination is confirmed, so at most one is ever registered.
  ///
  /// **A rejected [grab] has released nothing.** Whatever was held before the
  /// call is still held and still delivering presses. That is the whole of what
  /// makes a refusal non-destructive: the adapter above can answer with the
  /// combination genuinely still in effect (AD-10) instead of telling the user
  /// the hotkey is inactive, and a user who asks for a combination another
  /// application already owns never loses the shortcut they had.
  ///
  /// The ordering is load-bearing in both directions. Two grabs on one
  /// combination make a single press fire twice — AD-8's toggle shows and
  /// immediately hides, so the panel appears never to open — which is why the
  /// swap belongs here rather than as a release the caller issues first: only
  /// the implementation can acquire, confirm, and then release without ever
  /// being in either bad state.
  ///
  /// Rejects when the backend refuses the request, when the grab cannot be
  /// represented at all, or when this registrar has already been [dispose]d.
  /// The adapter above turns any of them into `HotkeyUnavailable` (AD-12) *or*
  /// into the binding that is still in effect; see the class doc for what a
  /// *resolved* future does and does not promise.
  ///
  /// The first two reject with [HotkeyRegistrarRefusal], so the adapter reads
  /// which of them it was from [HotkeyRegistrarRefusal.code] rather than from
  /// the sentence. The disposed case is a lifecycle error and rejects with a
  /// `StateError`, because there is no backend condition to report.
  ///
  /// The disposed case rejects rather than resolving quietly on purpose. A
  /// resolved future here becomes a `HotkeyBound` naming the requested
  /// combination, so a silent no-op would put a shortcut on the tray and the
  /// settings screen that was never registered.
  Future<void> grab(HotkeyGrab grab);

  /// Releases the held combination. A no-op when nothing is held; rejects once
  /// [dispose]d, for the reason [grab] gives — a caller that cannot tell
  /// "released" from "there is no seam left" will grab over a live binding.
  Future<void> release();

  /// One event per press of whatever is currently held. Broadcast, so the seam
  /// imposes no one-listener rule of its own.
  Stream<void> get presses;

  /// Releases the grab and closes [presses]. Idempotent.
  Future<void> dispose();
}
