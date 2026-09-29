import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'keyboard_focus_witness.dart';

/// The X11 [KeyboardFocusWitness]: one `XGetInputFocus` round trip, compared
/// against the focus window recorded when the panel last said it took the
/// keyboard.
///
/// **Why the read path is a single Xlib call, and must stay one.**
/// `XSetErrorHandler` writes a *process-global* handler shared by every
/// `Display` the process holds, and `x11_key_grab_registrar.dart:604-634`
/// records what that costs here: the key-grab worker arms its own trap for the
/// span of a grab batch, and that trap is a `Pointer.fromFunction` belonging to
/// the *worker's* isolate. An X error raised from the main isolate while the
/// trap is armed would invoke it cross-isolate, which the VM treats as fatal
/// rather than as a stray log line. `XGetInputFocus` takes **no window
/// argument**, so it cannot raise `BadWindow` on a window destroyed between two
/// calls — the one X error this read could plausibly produce. A one-call read
/// path closes that hazard by construction, which is why the answer is not
/// built from a tree walk plus a property read even though those would name the
/// toplevel more directly. Do not add a second, window-taking call here.
///
/// **Why a focus belonging to no window is stored as nothing rather than as an
/// id.** X reports the focus as `None` when no window has it and as
/// `PointerRoot` under a focus-follows-mouse server. Both are answers about the
/// *absence* of a focus owner, not window ids, and storing either would make
/// the later comparison succeed on every blur — the stored value and the
/// re-read value would both be `PointerRoot`, [focusUnmoved] would answer
/// `true`, and CAP-14's focus-loss dismissal would be suppressed entirely.
/// Neither is stored, and neither satisfies a comparison, so such a host
/// behaves exactly as it did before this seam existed.
///
/// **The call is a synchronous round trip on the platform thread, and is
/// deliberately not bounded by a timeout.** An X server that stops answering
/// blocks it. The reason that adds no new class of hang is reasoning rather
/// than a measurement, and is stated in that register: GDK already makes
/// synchronous round trips to the same server on the same thread for its own
/// per-frame work, so a server that has stopped answering has stopped the
/// daemon before this call is reached. Bounding it would need a timer, and the
/// whole point of this seam is to answer G-01-13 with a fact instead of with
/// timing.
///
/// `libX11.so.6` is already an unconditional `DT_NEEDED` of `libgdk-3.so.0`, so
/// no new runtime dependency appears with this file.
final class X11KeyboardFocusWitness implements KeyboardFocusWitness {
  /// `None` — the server reporting that no window holds the keyboard.
  static const int _none = 0;

  /// `PointerRoot` — the server reporting focus-follows-mouse rather than a
  /// window.
  static const int _pointerRoot = 1;

  /// Opened lazily, at the first read rather than in the constructor: a witness
  /// that is never asked holds no connection, and a startup that aborts before
  /// the panel exists leaks nothing.
  _X11FocusBindings? _bindings;
  Pointer<Void> _display = nullptr;

  /// The out-parameters, allocated once beside the display and reused, because
  /// this runs in a resident daemon on every blur at a focused panel all day.
  /// Freed by [dispose], the same discipline `x11_key_grab_registrar.dart`
  /// applies to its own event buffer.
  Pointer<UnsignedLong> _focusOut = nullptr;
  Pointer<Int32> _revertToOut = nullptr;

  /// Set once the connection could not be established, and never retried.
  ///
  /// A host with no reachable X server would otherwise pay a failed
  /// `XOpenDisplay` on every blur for the life of the daemon, and the answer
  /// would be the same `false` every time.
  bool _unavailable = false;

  bool _disposed = false;

  /// The focus window as it stood when the panel last reported taking the
  /// keyboard. Null whenever nothing comparable was witnessed.
  ///
  /// Note that this is not the daemon's toplevel: the window X names as the
  /// focus owner is a *child* of it (measured `4194308` under a toplevel
  /// `4194307`). So the question this type answers is not "is the focus window
  /// ours?" — which would need the tree walk the class doc rules out — but "is
  /// it the same one it was?".
  int? _witnessed;

  @override
  void recordFocusGained() {
    _witnessed = _readFocus();
  }

  @override
  bool get focusUnmoved {
    final witnessed = _witnessed;
    if (witnessed == null) {
      return false;
    }
    final current = _readFocus();
    if (current == null) {
      return false;
    }
    return current == witnessed;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _witnessed = null;
    final bindings = _bindings;
    // Guarded, and only when a display was actually opened: `XCloseDisplay`
    // against `nullptr` faults inside Xlib rather than throwing, so there is
    // nothing for `on Object catch` to see. That is the failure `a419249`
    // closed on the key-grab seam, and it is the same shape here — the
    // bindings can exist with no display behind them.
    if (bindings != null && _display != nullptr) {
      try {
        bindings.closeDisplay(_display);
      } on Object {
        // Teardown only: a daemon that cannot exit is the worse failure, and
        // the reporting channel is not reachable from this seam by design.
      }
    }
    _display = nullptr;
    _bindings = null;
    _free();
  }

  /// The focus window the server names right now, or null when the question
  /// could not be answered.
  int? _readFocus() {
    if (_disposed) {
      return null;
    }
    final bindings = _open();
    if (bindings == null) {
      return null;
    }
    // A belt, and named as one: on today's paths [_open] cannot return
    // non-null with either pointer still `nullptr`, so this branch is not
    // reachable. It is here for the `dispose`-then-read ordering the class
    // currently guards by the `_disposed` flag alone — [dispose] calls [_free],
    // which returns both pointers to `nullptr` — so that a future edit moving
    // that flag check does not reintroduce a null-pointer write. Same register
    // as [dispose]'s own `nullptr` guard and the `a419249` failure it cites.
    // Null is this method's existing vocabulary for "the question could not be
    // answered", which `focusUnmoved` turns into `false`.
    if (_focusOut == nullptr || _revertToOut == nullptr) {
      return null;
    }
    // Cleared before the call so that a call which writes nothing leaves
    // `None` behind rather than the previous read's answer. `XGetInputFocus`
    // returns 1 unconditionally in libX11 — it does not report a failed reply
    // — so the out-parameter, not the return value, is what is checked.
    _focusOut.value = _none;
    bindings.getInputFocus(_display, _focusOut, _revertToOut);
    final focus = _focusOut.value;
    if (focus == _none || focus == _pointerRoot) {
      return null;
    }
    return focus;
  }

  /// Opens the library, the display and the out-parameters, once.
  _X11FocusBindings? _open() {
    if (_unavailable) {
      return null;
    }
    final existing = _bindings;
    if (existing != null) {
      return _display == nullptr ? null : existing;
    }
    final _X11FocusBindings bindings;
    try {
      // `DynamicLibrary.open` throws `ArgumentError` when the soname cannot be
      // resolved. Structurally unreachable under GTK — `libX11.so.6` is an
      // unconditional `DT_NEEDED` of `libgdk-3.so.0` — but it is still a value
      // here rather than a throw crossing the seam.
      bindings = _X11FocusBindings(DynamicLibrary.open('libX11.so.6'));
    } on Object {
      _unavailable = true;
      return null;
    }
    // `XOpenDisplay(NULL)` reads `DISPLAY` itself and answers `nullptr` when
    // there is no server to talk to, which is a value rather than a throw.
    final display = bindings.openDisplay(nullptr);
    if (display == nullptr) {
      _unavailable = true;
      return null;
    }
    // Allocate first, publish last. Every later call's health check is
    // `_bindings != null && _display != nullptr`, so a display published
    // without its buffers reads as healthy and the next [_readFocus] writes
    // `_focusOut.value` through `nullptr` — a fault no `on Object catch` can
    // reduce, unlike every other failure in this file. In this order a `calloc`
    // that throws leaves `_bindings` null and `_display` `nullptr`, so the next
    // call takes the not-yet-opened path instead of the healthy one.
    //
    // Deliberately NOT covered by either `_unavailable` latch above:
    // `_unavailable` means the connection could not be established and will not
    // be retried, and an allocation failure is not that. Latching it would turn
    // one failed `calloc` into a witness that never answers again for the life
    // of the daemon.
    final focusOut = calloc<UnsignedLong>();
    final revertToOut = calloc<Int32>();
    _focusOut = focusOut;
    _revertToOut = revertToOut;
    _bindings = bindings;
    _display = display;
    return bindings;
  }

  void _free() {
    if (_focusOut != nullptr) {
      calloc.free(_focusOut);
      _focusOut = nullptr;
    }
    if (_revertToOut != nullptr) {
      calloc.free(_revertToOut);
      _revertToOut = nullptr;
    }
  }
}

/// The `libX11.so.6` entry points this file uses, and no others.
///
/// Three, and the read path is one of them. Notably absent, and deliberately:
/// `XQueryTree`, `XGetWindowProperty` and anything else taking a `Window`
/// argument — see the class doc for why a window-taking call on this path is a
/// fatal-crash hazard rather than a style preference.
final class _X11FocusBindings {
  _X11FocusBindings(DynamicLibrary library)
    : openDisplay = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Utf8>)
          >('XOpenDisplay'),
      closeDisplay = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('XCloseDisplay'),
      getInputFocus = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<UnsignedLong>,
              Pointer<Int32>,
            ),
            int Function(Pointer<Void>, Pointer<UnsignedLong>, Pointer<Int32>)
          >('XGetInputFocus');

  final Pointer<Void> Function(Pointer<Utf8>) openDisplay;
  final int Function(Pointer<Void>) closeDisplay;
  final int Function(Pointer<Void>, Pointer<UnsignedLong>, Pointer<Int32>)
  getInputFocus;
}
