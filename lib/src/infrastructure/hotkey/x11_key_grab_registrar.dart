import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../domain/hotkey/hotkey_binding.dart';
import 'hotkey_grab.dart';
import 'hotkey_key_catalogue.dart';
import 'hotkey_registrar.dart';
import 'xdg_shortcut_trigger.dart';

/// [HotkeyRegistrar] over a private X11 connection — the one file in `lib/` that
/// names `dart:ffi`, and the one that opens an X `Display` (AD-1, AD-17).
///
/// **No Flutter import of any kind, and this is load-bearing rather than
/// stylistic.** `test/infrastructure/system/daemon_startup_test.dart` imports
/// `x11_global_hotkey.dart` and runs under `dart test`, which cannot resolve
/// `dart:ui`. A Flutter import reaching this directory does not fail a test, it
/// stops the whole binding-free suite resolving. `dart:ffi`, `dart:isolate` and
/// `package:ffi` are all binding-free — `package:ffi` is pure Dart — so the
/// suite still loads. `test/architecture/hotkey_confinement_test.dart` is what
/// keeps that from regressing quietly.
///
/// **Why a private `Display` rather than the one GTK already has.** Xlib on a
/// connection this app opened itself shares no state with GDK's, so nothing here
/// touches the GTK main loop, and the question of which thread Dart runs on
/// stops being load-bearing. Passive grabs are per-connection and X delivers the
/// resulting `KeyPress` to the grabbing connection, which is how `xbindkeys`,
/// `sxhkd` and `i3` work. It also adds no runtime dependency: `libX11.so.6` is
/// already an unconditional `DT_NEEDED` of `libgdk-3.so.0`, so on any host where
/// this Flutter app starts at all, it is already loaded.
///
/// **Nothing here opens a library, spawns an isolate or connects to X before a
/// grab is asked for.** `main.dart` builds this object before it knows which
/// display server it is on, so a Wayland session that constructs it and never
/// binds must pay nothing for the arm it did not take. That promise is one level
/// stronger than the `hotkey_manager` seam this replaces, whose cost was reading
/// a lazy singleton; here it is a `dlopen`, an `Isolate.spawn` and a socket.
/// [dispose] holds to the same rule: with no worker there is nothing to tear
/// down. The row at `test/architecture/composition_wiring_test.dart` that reads
/// this as "stays inert" is what keeps it honest.
///
/// **Two measured facts carried over from the deleted `hotkey_manager` seam,**
/// because a deleted doc comment is not surfaced to the next reader by git:
///
/// 1. *Never more than one combination held, and the release comes after the
///    acquisition.* [grab] takes the new combination, confirms it against the
///    server, and only *then* lets the previous one go. The ordering was the
///    other way round while the vendor plugin was in the tree, which prevented
///    a double registration at the cost of dropping a working shortcut on the
///    way to failing — the plugin's native side keyed its keystring table with
///    `std::map::insert`, which does not overwrite
///    (`hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:91-92`),
///    so one press ran two handlers and AD-8's toggle showed and immediately
///    hid. Acquiring first avoids both, and three facts measured against a live
///    `Xvfb` (2026-09-01) are why it is safe:
///    * `BadAccess` for a combination another client owns is **synchronous**, so
///      the acquisition can be confirmed before anything is released;
///    * a client may hold *different* combinations at once, which is the state
///      the release below exists to prevent — a rebind that never released would
///      leave the old shortcut still opening the panel;
///    * re-issuing `XGrabKey` for a combination this same connection already
///      holds is **not** an error and does **not** produce a second grab — and a
///      single `XUngrabKey` then removes it. That is why an identical rebind is
///      short-circuited in [_X11Worker._grab] rather than swapped: acquiring and
///      then releasing "the previous" combination would ungrab the very grab
///      just taken and leave the user with nothing.
/// 2. *The backend this replaces could not report a refused grab at all.* The
///    plugin discarded `keybinder_bind`'s `gboolean` and answered `true`
///    regardless (`hotkey_manager_linux_plugin.cc:96,99`), so the commonest real
///    failure — another client already owning the combination — arrived as
///    success. That is what made AD-10's "a failed grab must not report success"
///    unsatisfiable through it, and it is the defect this file exists to close.
///
/// **The grab is exactly as wide as the combination the user bound.** One
/// keycode, and exactly the four modifier states of [_ignoredModifierStates].
/// No `AnyKey`, no `AnyModifier`, no `XGrabKeyboard`: a global grab observes
/// keystrokes system-wide, and widening it to simplify the implementation would
/// turn a shortcut daemon into a key logger.
final class X11KeyGrabRegistrar implements HotkeyRegistrar {
  X11KeyGrabRegistrar();

  /// Broadcast so the seam does not impose a one-listener rule of its own.
  final StreamController<void> _presses = StreamController<void>.broadcast();

  bool _disposed = false;

  /// The worker isolate and the port that reaches it, or null before the first
  /// [grab] and after [dispose].
  ///
  /// Nullable and threaded rather than null-asserted, exactly as the Wayland
  /// adapter holds its `DBusClient?`: absence here is a real state — the inert
  /// one this class promises — and not an oversight to silence. `analysis_
  /// options.yaml` and AGENTS.md §6 both forbid reaching a handle through `!`.
  Isolate? _worker;
  SendPort? _commands;
  ReceivePort? _fromWorker;

  /// What is held right now, and the handle [release] needs. Assigned only after
  /// the worker confirms the grab, so a refusal leaves both sides consistently
  /// empty.
  HotkeyGrab? _held;

  /// In-flight worker calls, keyed by request id. A `Completer` per call rather
  /// than one at a time, because [dispose] can arrive while a [grab] is still
  /// waiting and both need an answer.
  final Map<int, Completer<_WorkerReply>> _pending =
      <int, Completer<_WorkerReply>>{};

  int _nextRequestId = 0;

  /// The spawn currently in flight, so two callers cannot start two isolates.
  Future<SendPort>? _starting;

  @override
  Stream<void> get presses => _presses.stream;

  /// Asks X to hold [grab], letting go of whatever was held only once the new
  /// combination is confirmed — so a rejection has released nothing.
  ///
  /// Rejects — the seam's declared contract — rather than returning a value:
  /// `X11GlobalHotkey` is what turns a rejection into a `HotkeyBindOutcome`, and
  /// AD-12's "unavailability is a value" is honoured there, not here. Every
  /// refusal this method can produce is a rejection with a sentence naming the
  /// cause, and none of them carries a vendor error's string form.
  @override
  Future<void> grab(HotkeyGrab grab) async {
    _refuseIfDisposed('grab');
    // Resolved first, so an unrepresentable request rejects before anything is
    // opened, spawned or grabbed. Nothing held is disturbed by a refusal here
    // or by any refusal the worker produces: the whole swap happens inside the
    // worker's own grab, which acquires before it releases.
    final request = _requestFor(grab);
    final commands = await _ensureWorker();
    if (_disposed) {
      throw StateError('the hotkey registrar was disposed during this grab');
    }
    final reply = await _ask(commands, _grabCommand, <Object?>[
      request.keysymName,
      request.modifierMask,
    ]);
    if (reply.code != _ok) {
      // [_held] is deliberately left as it was: the worker refused without
      // releasing, so the previous combination is still registered and still
      // the one [release] must let go of.
      throw _refusalFor(reply);
    }
    if (_disposed) {
      // [dispose] ran while the grab was in flight, so it found nothing to
      // release and this grab would outlive the seam that owns it. Undone here
      // rather than left to the caller: by the time the caller could ask,
      // [release] would itself be refused. What this is *not* is a leak that
      // outlives the daemon — every path that disposes this seam exits the
      // process, and the X server drops a disconnecting client's passive grabs.
      // It is undone because the server holding a grab this object no longer
      // knows about is the state that makes a later rebind double-fire.
      try {
        await _ask(commands, _releaseCommand, const <Object?>[]);
      } on Object {
        // Best-effort, and deliberately swallowed so the `StateError` below is
        // what every disposed-mid-grab call rejects with. The caller needs to
        // know the seam was torn down under it; a failure while undoing is the
        // less useful of the two facts, and `_held` is left unset either way
        // because there is no longer anything that could act on it.
      }
      throw StateError('the hotkey registrar was disposed during this grab');
    }
    _held = grab;
  }

  /// Releases the held combination. A no-op when nothing is held.
  ///
  /// Rejects once disposed, for the reason [grab] gives: a caller that cannot
  /// tell "released" from "there is no seam left" will grab over a live binding.
  @override
  Future<void> release() async {
    _refuseIfDisposed('release');
    await _releaseHeld();
  }

  /// Releases the grab, tears the worker down and closes [presses]. Idempotent,
  /// and never throws.
  ///
  /// It runs on the shutdown path (AD-4), and every step is independently
  /// guarded because the point is to leave nothing behind: a release X refuses
  /// must not stop the `Display` being closed, and neither must stop the isolate
  /// being killed. A worker isolate holding an open `Display` blocks process
  /// exit, and this tree already carries a recorded instance of that bug class
  /// on the D-Bus side — an unclosed client "can stop the Dart process
  /// terminating" (`wayland_portal_global_hotkey.dart:1009-1011`).
  ///
  /// Deliberately different from the seam it replaces on one point: that one let
  /// a refused release propagate and relied on `X11GlobalHotkey` to reduce it to
  /// a log line. This one cannot, because the steps after it are what stop the
  /// process lingering. The adapter above still logs the outcome of this call
  /// through its own `_guard`.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _shutdownWorker();
    } finally {
      await _presses.close();
    }
  }

  void _refuseIfDisposed(String what) {
    if (_disposed) {
      throw StateError('the hotkey registrar was disposed before this $what');
    }
  }

  Future<void> _releaseHeld() async {
    if (_held == null) {
      return;
    }
    final commands = _commands;
    if (commands == null) {
      // Nothing was ever opened, so there is nothing the server is holding.
      _held = null;
      return;
    }
    final reply = await _ask(commands, _releaseCommand, const <Object?>[]);
    if (reply.code != _ok) {
      // Cleared regardless of the answer only on the success path: a refused
      // release leaves the combination held, and forgetting the handle would
      // strand it registered with nothing able to release it. The process keeps
      // running after an explicit [release], so a later one can retry.
      throw _refusalFor(reply);
    }
    _held = null;
  }

  /// Spawns the worker on first use and returns the port that reaches it.
  ///
  /// Coalesced through [_starting], because `X11GlobalHotkey.dispose()` is
  /// deliberately not queued behind its `bind()` — a daemon that must exit
  /// cannot wait on a socket — so a stop signal during a first bind really can
  /// arrive here while the spawn is still in flight.
  Future<SendPort> _ensureWorker() {
    final existing = _commands;
    if (existing != null) {
      return Future<SendPort>.value(existing);
    }
    return _starting ??= _spawnWorker().whenComplete(() {
      _starting = null;
    });
  }

  Future<SendPort> _spawnWorker() async {
    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();
    // `onError` and `onExit` land on the same port so a worker that dies cannot
    // leave a caller waiting forever on a reply that will never come.
    fromWorker.listen((message) => _onWorkerMessage(message, ready));
    final worker = await Isolate.spawn(
      _workerMain,
      fromWorker.sendPort,
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
      debugName: 'x11-key-grab',
    );
    _worker = worker;
    _fromWorker = fromWorker;
    final commands = await ready.future;
    _commands = commands;
    return commands;
  }

  void _onWorkerMessage(Object? message, Completer<SendPort> ready) {
    if (message is! List<Object?> || message.isEmpty) {
      // `onExit` sends null, and an uncaught error in the worker sends a
      // two-element list of strings. Either way the worker is gone and every
      // waiting caller needs an answer. The error's own text is deliberately
      // not read: a vendor error carries the payload that caused it, and this
      // daemon reads the clipboard.
      _failPending(
        'the X11 hotkey worker stopped before answering, so no global '
        'shortcut is registered — the tray menu still opens the panel',
      );
      return;
    }
    switch (message.first) {
      case _readyTag:
        final port = message.length > 1 ? message[1] : null;
        if (port is SendPort && !ready.isCompleted) {
          ready.complete(port);
        }
      case _pressTag:
        if (!_disposed && !_presses.isClosed) {
          _presses.add(null);
        }
      case _replyTag:
        _completeReply(message);
      default:
        _failPending(
          'the X11 hotkey worker stopped before answering, so no global '
          'shortcut is registered — the tray menu still opens the panel',
        );
    }
  }

  void _completeReply(List<Object?> message) {
    if (message.length < 4) {
      return;
    }
    final id = message[1];
    final code = message[2];
    final detail = message[3];
    if (id is! int || code is! String || detail is! String) {
      return;
    }
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) {
      pending.complete(_WorkerReply(code, detail));
    }
  }

  void _failPending(String reason) {
    final waiting = List<Completer<_WorkerReply>>.of(_pending.values);
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) {
        completer.complete(_WorkerReply(_workerGone, reason));
      }
    }
  }

  /// The worker's answer as the seam's declared refusal, so the code it already
  /// computed is what crosses rather than being re-derived from the sentence.
  ///
  /// This is the whole of WR-03: four named codes and five authored sentences
  /// used to collapse into `StateError(detail)`, and the adapter above then
  /// hard-coded `keyRefused` for all of them — so a host where no display can
  /// be opened told the user to pick a different combination. The mapping from
  /// a code to what the *user* is told stays in `X11GlobalHotkey`; all this
  /// does is stop the code being thrown away.
  static HotkeyRegistrarRefusal _refusalFor(_WorkerReply reply) {
    return HotkeyRegistrarRefusal(
      code: switch (reply.code) {
        _noBackend => HotkeyRefusalCode.noBackend,
        _keyRefused => HotkeyRefusalCode.keyRefused,
        _badRequest => HotkeyRefusalCode.badRequest,
        _workerGone => HotkeyRefusalCode.workerGone,
        // A code neither half of this file recognises is the two isolates
        // disagreeing about their own protocol, which is what `badRequest`
        // means. It also maps to the non-defeatist reading above — another
        // combination may work — and telling a user to give up on the strength
        // of a string this file failed to recognise would be the worse guess.
        _ => HotkeyRefusalCode.badRequest,
      },
      message: reply.detail,
    );
  }

  Future<_WorkerReply> _ask(
    SendPort commands,
    String command,
    List<Object?> arguments,
  ) {
    final id = _nextRequestId++;
    final completer = Completer<_WorkerReply>();
    _pending[id] = completer;
    commands.send(<Object?>[command, id, ...arguments]);
    return completer.future;
  }

  Future<void> _shutdownWorker() async {
    final commands = _commands;
    final worker = _worker;
    final fromWorker = _fromWorker;
    _commands = null;
    _worker = null;
    _fromWorker = null;
    _held = null;
    if (commands != null) {
      // Asks the worker to ungrab every state it holds and close its own
      // `Display` before it is killed: a grab the server still holds for a
      // connection that is going away is tidied by the server, but a `Display`
      // closed by the worker is one fewer reason for the process to linger.
      try {
        await _ask(commands, _closeCommand, const <Object?>[]);
      } on Object {
        // Guarded independently: a worker that cannot answer must not stop it
        // being killed below.
      }
    }
    worker?.kill(priority: Isolate.immediate);
    fromWorker?.close();
    _failPending(
      'the X11 hotkey backend has been shut down, so no global shortcut is '
      'registered — the tray menu still opens the panel',
    );
  }

  /// Resolves [grab] into the two values the worker needs, refusing anything
  /// this build cannot express before any native call is made.
  ///
  /// The keysym **name** is produced by [XdgShortcutTrigger.keysymNameFor] —
  /// the vocabulary this project already measured against xkbcommon 1.6.0 — and
  /// not by a second name table in this file. That is the whole DW-41/DW-43
  /// lesson: the seven labels the old backend bound to a keypad, ISO or 3270
  /// variant were wrong precisely because the name was resolved through a table
  /// this project could not see. Here the name is chosen in Dart and handed to
  /// `XStringToKeysym`, which is what AD-9 always described.
  ///
  /// Two refusals, both before the worker is asked anything:
  ///
  /// * a usage outside [HotkeyKeyCatalogue], so there is no label to serialize;
  /// * a label with no keysym name, so there is nothing `XStringToKeysym` could
  ///   resolve.
  ///
  /// A rejection rather than a modelled value, for the reason [grab] gives —
  /// and a [HotkeyRegistrarRefusal] rather than a bare `StateError`, so the
  /// adapter reads `keyRefused` from a field instead of inferring it from the
  /// sentence. Both of these are one bad key on a backend that may be working
  /// perfectly, which is what makes them `keyRefused` and not `noBackend`:
  /// another combination really may bind.
  _GrabRequest _requestFor(HotkeyGrab grab) {
    final label = HotkeyKeyCatalogue.labelForUsage(grab.usbHidUsage);
    if (label == null) {
      throw HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.keyRefused,
        message:
            'USB HID usage 0x${grab.usbHidUsage.toRadixString(16)} is outside '
            'the catalogue, so this build offers no key to grab for it — pick '
            'a different combination, or use the tray menu',
      );
    }
    final keysymName = XdgShortcutTrigger.keysymNameFor(label);
    if (keysymName == null) {
      throw HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.keyRefused,
        message:
            'the key "$label" has no X keysym name in this build, so no grab '
            'can be requested for it — pick a different combination, or use '
            'the tray menu',
      );
    }
    return _GrabRequest(keysymName, _maskFor(grab.modifiers));
  }

  // The usage-to-label map this file used to derive for itself now lives on
  // `HotkeyKeyCatalogue` as `labelForUsage`, because the capture control needs
  // the same direction and two derivations of one table are two things to
  // drift.

  /// The X core-protocol modifier mask for [modifiers].
  ///
  /// This is the translation `gtk_accelerator_parse` used to do, and it moves
  /// here with the route. An exhaustive `switch` with no default, so a fifth
  /// [HotkeyModifier] fails to compile rather than silently grabbing a
  /// combination missing a modifier.
  ///
  /// `alt` maps to `Mod1Mask` and `meta` to `Mod4Mask`. Both are conventions of
  /// every mainstream X keymap rather than guarantees of the protocol, which
  /// gives `Mod1`..`Mod5` no meaning at all — the authoritative mapping is
  /// whatever `XGetModifierMapping` reports for the running server. Recorded as
  /// a documented assumption for the same reason [_mod2Mask] is: if it is wrong,
  /// the symptom is a shortcut that binds and never fires.
  static int _maskFor(Set<HotkeyModifier> modifiers) {
    var mask = 0;
    for (final modifier in modifiers) {
      mask |= switch (modifier) {
        HotkeyModifier.control => _controlMask,
        HotkeyModifier.alt => _mod1Mask,
        HotkeyModifier.shift => _shiftMask,
        HotkeyModifier.meta => _mod4Mask,
      };
    }
    return mask;
  }
}

/// The two values a grab is reduced to before it crosses into the worker.
///
/// A keysym *name* and an `int` mask, never a `Pointer`, a `KeySym`, a keycode
/// or a `SendPort`: nothing that names the vendor's vocabulary leaves this file,
/// and nothing that names Dart's isolate machinery enters the seam.
final class _GrabRequest {
  const _GrabRequest(this.keysymName, this.modifierMask);

  final String keysymName;
  final int modifierMask;
}

/// One answer from the worker, already reduced to a code and a sentence.
final class _WorkerReply {
  const _WorkerReply(this.code, this.detail);

  final String code;

  /// Already in terms a caller can act on, and never a vendor error's string
  /// form — see [_errorContext].
  final String detail;
}

// Message tags. Deliberately namespaced: an uncaught error in the worker arrives
// as a two-element list whose first element is a string, and a bare tag like
// 'press' could in principle collide with it.
const String _readyTag = '_x11:ready';
const String _pressTag = '_x11:press';
const String _replyTag = '_x11:reply';

const String _grabCommand = '_x11:grab';
const String _releaseCommand = '_x11:release';
const String _closeCommand = '_x11:close';

/// The reply vocabulary, shared by the worker that writes it and the owner that
/// maps it to a [HotkeyRefusalCode].
///
/// Constants rather than the literals that used to sit at each `_reply` call:
/// the two halves live in one file but run in two isolates and only ever agree
/// by matching strings, so a typo on either side became a refusal nobody could
/// classify. Spelled as the enum's own names so [_refusalFor] reads as the
/// identity it is.
const String _ok = 'ok';
const String _noBackend = 'noBackend';
const String _keyRefused = 'keyRefused';
const String _badRequest = 'badRequest';
const String _workerGone = 'workerGone';

/// The only part of a caught error that is safe to put in a diagnostic — see the
/// [Logger] port's doc, and the canonical note in `correction_controller.dart`.
/// A vendor exception carries the payload that caused it, and this daemon reads
/// the clipboard.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}

/// The four modifier states X must be told about separately.
///
/// X matches modifier state **exactly**, so a bare `Ctrl+Shift+G` grab silently
/// stops working the moment CapsLock or NumLock is latched. Measured against a
/// live `Xvfb`: the four are independent grabs and do not conflict with each
/// other, so all four are issued and the two bits are masked out of an incoming
/// event's `state` before it is matched.
const List<int> _ignoredModifierStates = <int>[
  0,
  _lockMask,
  _mod2Mask,
  _lockMask | _mod2Mask,
];

// X.h. Named here rather than looked up, because they are protocol constants.
const int _shiftMask = 1 << 0;
const int _lockMask = 1 << 1;
const int _controlMask = 1 << 2;
const int _mod1Mask = 1 << 3;

/// NumLock, by the near-universal convention rather than by the protocol.
///
/// **Documented assumption.** X.h defines `Mod2Mask` as a bit position with no
/// meaning attached; which physical modifier occupies it is a property of the
/// running server's modifier map. Every mainstream keymap puts NumLock here. The
/// robust form discovers it with `XGetModifierMapping` and
/// `XKeysymToKeycode(XK_Num_Lock)`; if this assumption is ever wrong the symptom
/// is narrow and specific — the shortcut works until NumLock is pressed.
const int _mod2Mask = 1 << 4;

const int _mod4Mask = 1 << 6;

const int _grabModeAsync = 1;

/// `BadAccess`, and the major opcode of the request that produces it here.
/// Together they are what makes a refusal *named* rather than one bit: a
/// `BadAccess` against request 33 is another client already owning the
/// combination, and nothing else.
const int _badAccess = 10;
const int _xGrabKeyRequest = 33;

const int _keyPress = 2;
const int _mappingNotify = 34;

/// `XEvent` is a union whose largest member is `long pad[24]`
/// (`/usr/include/X11/Xlib.h:1008`), so 24 machine words is the whole of it.
const int _xEventSize = 24 * 8;

/// How often the worker looks for events.
///
/// A poll rather than a blocking `XNextEvent`, deliberately: a blocked
/// `XNextEvent` cannot also notice a teardown message, and T-01-09's whole
/// concern is a worker that stops the process exiting. `XPending` is a cheap
/// check of the already-buffered queue plus a non-blocking read, and 8 ms is far
/// below the threshold at which a person notices a shortcut responding. AD-8's
/// allocation-free press path is on the *main* isolate and is untouched by this.
const Duration _pollInterval = Duration(milliseconds: 8);

/// The worker isolate's entry point.
///
/// Everything that touches the `Display` runs here and only here, so the
/// blocking half of X stays off the isolate that renders the panel.
void _workerMain(SendPort toOwner) {
  final commands = ReceivePort();
  final worker = _X11Worker(toOwner);
  commands.listen(worker.handle);
  toOwner.send(<Object?>[_readyTag, commands.sendPort]);
}

/// Where the trap records what Xlib reported, read straight after `XSync`.
///
/// Top-level rather than a field because `Pointer.fromFunction` needs a static
/// target. *This list* is per-isolate Dart state, so no other isolate can see or
/// write it.
///
/// **The registration is not per-isolate, which is why [_X11Worker._acquire]
/// puts the previous handler back.** `XSetErrorHandler` writes a single
/// process-global (`_XErrorFunction`) shared by every `Display` the process
/// holds, not a per-connection hook — and this worker's `libX11.so.6` is the
/// same mapping `libgdk-3.so.0` already loaded, which is exactly what the class
/// doc's dependency argument relies on. Left installed, this trap would displace
/// `gdk_x_error` for GTK's own connection for the rest of the process's life:
/// the routine X errors GDK traps and swallows (a `BadWindow` on a torn-down
/// window) would be collected here instead of handled, and — the severe half —
/// [_trapHandler] is a `Pointer.fromFunction` belonging to *this* isolate, so
/// GDK raising one on the platform thread would invoke it cross-isolate, which
/// the VM treats as fatal rather than as a stray log line.
///
/// So the trap is armed for the span of one grab batch and handed straight back,
/// and within that span the Xlib call being made on purpose is this isolate's
/// own. A GDK error landing inside that window is a residual race — narrowed to
/// the length of the batch rather than closed, because Xlib offers no
/// per-`Display` handler to close it with — and it is stated here rather than
/// claimed away.
///
/// `Pointer.fromFunction` rather than a `NativeCallable`: a `NativeCallable`
/// keeps its isolate alive by default, which is exactly the shape Pitfall 7
/// warns about, and there is nothing here that needs one — Xlib calls the
/// handler on the same thread, inside the same call, and wants an `int` back.
final List<_TrappedError> _trappedErrors = <_TrappedError>[];

final class _TrappedError {
  const _TrappedError(this.errorCode, this.requestCode);

  final int errorCode;
  final int requestCode;
}

int _trapXError(Pointer<Void> display, Pointer<_XErrorEvent> event) {
  _trappedErrors.add(_TrappedError(event.ref.errorCode, event.ref.requestCode));
  // Xlib ignores the return value of an error handler; 0 is the conventional
  // answer and the one every in-tree example of this pattern uses.
  return 0;
}

/// Owns the private X connection, the grab, and the event pump.
final class _X11Worker {
  _X11Worker(this._toOwner);

  final SendPort _toOwner;

  /// Opened at first grab, never at construction — the inert-construction
  /// promise reaches in here too, because the isolate itself is not spawned
  /// until then and nothing in this constructor touches X.
  _X11Bindings? _bindings;
  Pointer<Void> _display = nullptr;
  Pointer<Uint8> _eventBuffer = nullptr;
  int _root = 0;

  /// The keysym rather than the keycode, because a keycode is not stable across
  /// a layout change and `MappingNotify` is the signal to resolve it again.
  int _keysym = 0;
  int _modifierMask = 0;
  int _keycode = 0;

  /// Exactly the modifier states currently held, so a refusal can put back
  /// precisely what it took and nothing is left half-held.
  final List<int> _heldStates = <int>[];

  Timer? _poller;

  void handle(Object? message) {
    if (message is! List<Object?> || message.length < 2) {
      return;
    }
    final command = message.first;
    final id = message[1];
    if (command is! String || id is! int) {
      return;
    }
    switch (command) {
      case _grabCommand:
        final keysymName = message.length > 2 ? message[2] : null;
        final modifierMask = message.length > 3 ? message[3] : null;
        if (keysymName is! String || modifierMask is! int) {
          _reply(
            id,
            _badRequest,
            'the grab request was malformed, so the shortcut could not be '
            'registered — the tray menu still opens the panel',
          );
          return;
        }
        _grab(id, keysymName, modifierMask);
      case _releaseCommand:
        _release(id);
      case _closeCommand:
        _close(id);
    }
  }

  void _grab(int id, String keysymName, int modifierMask) {
    final bindings = _openBindings();
    if (bindings == null) {
      _reply(
        id,
        _noBackend,
        'this system has no X11 client library, so the shortcut cannot be '
        'registered — the tray menu still opens the panel',
      );
      return;
    }
    if (!_openDisplay(bindings)) {
      _reply(
        id,
        _noBackend,
        'no X display could be opened, so the shortcut cannot be registered — '
        'the tray menu still opens the panel',
      );
      return;
    }
    final keysym = _withNativeString(
      keysymName,
      (name) => bindings.stringToKeysym(name),
    );
    if (keysym == 0) {
      _reply(
        id,
        _keyRefused,
        'this X server does not know the key "$keysymName", so the shortcut '
        'cannot be registered — pick a different combination, or use the '
        'tray menu',
      );
      return;
    }
    final keycode = bindings.keysymToKeycode(_display, keysym);
    if (keycode == 0) {
      _reply(
        id,
        _keyRefused,
        'the current keyboard layout has no key for "$keysymName", so the '
        'shortcut cannot be registered — pick a different combination, or '
        'use the tray menu',
      );
      return;
    }
    // Already satisfied, and compared against what is **held** rather than
    // against what was **requested**. Two reasons, and the second is why the
    // comparison is not the obvious one:
    //
    // * Re-grabbing a combination this connection already holds is not an error
    //   and does not produce a second grab, while one `XUngrabKey` removes it
    //   (both measured). So swapping instead of short-circuiting would acquire
    //   nothing new, then ungrab the grab it just re-took, leaving the user with
    //   no shortcut at all — a silent loss on the most ordinary rebind there is.
    // * [_heldStates] is only ever populated after a confirmed acquisition, so
    //   a combination that was *refused* was never recorded here and can always
    //   be asked for again. Short-circuiting on the request instead would close
    //   every recovery path — a binding that was refused, or lost, could never
    //   be re-requested.
    if (_heldStates.isNotEmpty &&
        keycode == _keycode &&
        modifierMask == _modifierMask) {
      _reply(id, _ok, 'the shortcut is already registered');
      return;
    }
    // Acquire, confirm, and only then release — the ordering the whole
    // non-destructive refusal rests on (fact 1 on the class doc). The release
    // below is what keeps a rebind from leaving the old combination still
    // opening the panel; doing it *after* the acquisition is what keeps a
    // refusal from costing the user a shortcut that was working. Both hold at
    // once because the two grab sets cannot collide: a bindable modifier set
    // never contains the two lock bits, so `mask | state` identifies the pair,
    // and the only combination that could conflict with what is held is the
    // identical one — handled above, and for the reason given there.
    final acquisition = _acquire(bindings, keycode, modifierMask);
    final refusal = acquisition.refusal;
    if (refusal != null) {
      // Nothing was released and nothing is left half-held: [_acquire] put back
      // exactly what it took, and the previous combination was never touched.
      _reply(id, _keyRefused, refusal);
      return;
    }
    _ungrabHeld(bindings);
    _keysym = keysym;
    _modifierMask = modifierMask;
    _keycode = keycode;
    _heldStates
      ..clear()
      ..addAll(acquisition.states);
    _startPolling(bindings);
    _reply(id, _ok, 'the shortcut is registered');
  }

  /// Issues the four grabs for [keycode] and [modifierMask] and reads the result
  /// synchronously, **without touching whatever is already held.**
  ///
  /// Returns the modifier states now taken and a null `refusal` when the
  /// combination is held, or the sentence to refuse with and no states. Nothing
  /// here writes [_heldStates], [_keycode] or [_modifierMask]: the caller owns
  /// the swap, and until it says otherwise the previously held combination is
  /// still the one this worker is registered for and still the one [_ungrabHeld]
  /// would let go of.
  ///
  /// The order is what makes the failure readable: the trap is cleared and
  /// armed first, every state is requested, and one `XSync` then guarantees the
  /// server has answered all of them — Xlib runs the handler *before* `XSync`
  /// returns, and that synchrony is the whole of HOTKEY-01. The handler that was
  /// there before goes back on the way out, and [_trappedErrors] is read after
  /// that, because by then `XSync` has already put everything in it.
  ({String? refusal, List<int> states}) _acquire(
    _X11Bindings bindings,
    int keycode,
    int modifierMask,
  ) {
    _trappedErrors.clear();
    // Installed for the span of this batch and no longer, because
    // `XSetErrorHandler` writes one process-global that GDK's `Display` shares
    // — see [_trappedErrors] for why leaving it in place is a crash rather than
    // a stray log line. The previous handler is whatever `XSetErrorHandler`
    // hands back, `nullptr` included: Xlib spells "the built-in default" that
    // way and takes it back on the same terms, so no null case is needed.
    final previous = bindings.setErrorHandler(_trapHandler);
    final requested = <int>[];
    try {
      for (final state in _ignoredModifierStates) {
        bindings.grabKey(
          _display,
          keycode,
          modifierMask | state,
          _root,
          1, // ownerEvents: the grab is ours, events come to this connection.
          _grabModeAsync,
          _grabModeAsync,
        );
        requested.add(state);
      }
      // Inside the trap's span, not after it. X reports errors asynchronously,
      // and this `XSync` is what makes the server's answer to all four grabs —
      // including the `BadAccess` a refusal is read from — land in the handler
      // before the call returns. Restoring first would hand those errors to
      // GDK's handler instead and lose HOTKEY-01's synchronous refusal.
      bindings.sync(_display, 0);
    } finally {
      bindings.setErrorHandler(previous);
    }
    final refused = _trappedErrors.any(
      (error) =>
          error.errorCode == _badAccess &&
          error.requestCode == _xGrabKeyRequest,
    );
    if (!refused) {
      return (refusal: null, states: requested);
    }
    // X reports the failing *request*, not which of the four it was, so a
    // BadAccess anywhere in the batch is read as the base state being taken.
    // That is the conservative reading and the right one: reporting a shortcut
    // as bound when another client owns it is the exact defect this file exists
    // to close, and the four requests are issued together precisely because the
    // combination is unusable unless all four land. It also costs the user
    // nothing now — a refusal leaves the combination they already had working.
    _ungrabStates(bindings, keycode, modifierMask, requested);
    return (
      refusal:
          'another application already owns that shortcut, so it could not '
          'be registered — pick a different combination, or use the tray menu',
      states: const <int>[],
    );
  }

  void _release(int id) {
    final bindings = _bindings;
    if (bindings == null || _heldStates.isEmpty) {
      _reply(id, _ok, 'nothing was held');
      return;
    }
    _ungrabHeld(bindings);
    _reply(id, _ok, 'the shortcut was released');
  }

  void _ungrabHeld(_X11Bindings bindings) {
    if (_heldStates.isEmpty) {
      return;
    }
    _ungrabStates(bindings, _keycode, _modifierMask, _heldStates);
    _heldStates.clear();
    _stopPolling();
  }

  /// Lets go of exactly [states] for [keycode] and [modifierMask], and nothing
  /// else — so a partial acquisition can put back precisely what it took.
  ///
  /// `XUngrabKey` on a grab that was never held is idempotent (measured), so
  /// this needs no trap and no read-back.
  void _ungrabStates(
    _X11Bindings bindings,
    int keycode,
    int modifierMask,
    List<int> states,
  ) {
    if (states.isEmpty) {
      return;
    }
    for (final state in states) {
      bindings.ungrabKey(_display, keycode, modifierMask | state, _root);
    }
    bindings.sync(_display, 0);
  }

  /// Tears the connection down.
  ///
  /// Every step that can *throw* is wrapped in [_guard], because a worker that
  /// cannot exit is the worse failure. What [_guard] cannot do — and what this
  /// doc used to claim it did — is make a native call safe: a null-pointer
  /// dereference inside Xlib raises `SIGSEGV`, which the Dart VM never
  /// delivers as an exception, so there is nothing for `on Object catch` to
  /// see and the process dies on the shutdown path. The guarding that actually
  /// covers the native half is therefore the null-display check each of these
  /// calls makes for itself.
  ///
  /// `closeDisplay` is the one that used to make none. [_openBindings] assigns
  /// [_bindings] before [_openDisplay] runs, so a host with no reachable X
  /// server left [_bindings] set and [_display] `nullptr` — and the first
  /// teardown called `XCloseDisplay(nullptr)` and exited 134. Both of
  /// `main.dart`'s teardown paths reach here, the lifecycle one and the
  /// pre-lifecycle abort, so on such a host every exit was a crash. AD-12's
  /// rule is that a backend which cannot bind is a visible `HotkeyUnavailable`
  /// rather than a crash; the check below is what makes that true of this
  /// route.
  void _close(int id) {
    final bindings = _bindings;
    if (bindings != null) {
      _guard(() => _ungrabHeld(bindings));
      if (_display != nullptr) {
        _guard(() => bindings.closeDisplay(_display));
      }
    }
    _guard(_stopPolling);
    _guard(_freeEventBuffer);
    _display = nullptr;
    _bindings = null;
    _reply(id, _ok, 'the X11 connection was closed');
  }

  _X11Bindings? _openBindings() {
    final existing = _bindings;
    if (existing != null) {
      return existing;
    }
    try {
      // `DynamicLibrary.open` throws `ArgumentError` when the soname cannot be
      // resolved, and that is caught *here* rather than at construction: this
      // is the first grab, and a Wayland session that never grabs never opens
      // anything. Under this route the branch is structurally unreachable
      // rather than merely handled — `libX11.so.6` is already an unconditional
      // `DT_NEEDED` of `libgdk-3.so.0` — but it is still a value, not a throw.
      final bindings = _X11Bindings(DynamicLibrary.open('libX11.so.6'));
      _bindings = bindings;
      return bindings;
    } on Object catch (error) {
      // Reduced through `_errorContext`, so nothing but the type is retained.
      // The sentence the caller sees is authored here, not taken from the error.
      _errorContext(error);
      return null;
    }
  }

  bool _openDisplay(_X11Bindings bindings) {
    if (_display != nullptr) {
      return true;
    }
    // `XOpenDisplay(NULL)` reads `DISPLAY` itself and answers `nullptr` when
    // there is no server to talk to, which is a value rather than a throw.
    final display = bindings.openDisplay(nullptr);
    if (display == nullptr) {
      return false;
    }
    _display = display;
    _root = bindings.defaultRootWindow(display);
    _eventBuffer = calloc<Uint8>(_xEventSize);
    return true;
  }

  void _startPolling(_X11Bindings bindings) {
    if (_poller != null) {
      return;
    }
    _poller = Timer.periodic(_pollInterval, (_) => _drain(bindings));
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  void _drain(_X11Bindings bindings) {
    if (_display == nullptr || _eventBuffer == nullptr) {
      return;
    }
    // `XPending` first, so `XNextEvent` never blocks: it is only called when the
    // queue already holds an event.
    while (bindings.pending(_display) > 0) {
      bindings.nextEvent(_display, _eventBuffer);
      final type = _eventBuffer.cast<Int32>().value;
      if (type == _keyPress) {
        _onKeyPress();
      } else if (type == _mappingNotify) {
        _onMappingChanged(bindings);
      }
    }
  }

  void _onKeyPress() {
    final event = _eventBuffer.cast<_XKeyEvent>().ref;
    if (event.keycode != _keycode) {
      return;
    }
    // The two lock bits are masked out because they are grabbed separately and
    // are not part of what the user bound.
    final state = event.state & ~(_lockMask | _mod2Mask);
    if (state != _modifierMask) {
      return;
    }
    _toOwner.send(const <Object?>[_pressTag]);
  }

  /// Keycodes are not stable across a layout change, so the grab is retaken
  /// against the same keysym. Measured: `MappingNotify` (type 34) really does
  /// arrive on the grabbing connection when the mapping changes.
  ///
  /// Same acquire-then-release order as [_grab], for a sharper version of the
  /// same reason: nobody asked for this rebind, so a refusal here must be even
  /// less able to cost the user their shortcut. If the new keycode cannot be
  /// taken, what is held stays held — stale, but no worse than before.
  void _onMappingChanged(_X11Bindings bindings) {
    bindings.refreshKeyboardMapping(_eventBuffer);
    if (_keysym == 0) {
      return;
    }
    final keycode = bindings.keysymToKeycode(_display, _keysym);
    if (keycode == 0 || keycode == _keycode) {
      return;
    }
    final acquisition = _acquire(bindings, keycode, _modifierMask);
    if (acquisition.refusal != null) {
      return;
    }
    _ungrabHeld(bindings);
    _keycode = keycode;
    _heldStates
      ..clear()
      ..addAll(acquisition.states);
    _startPolling(bindings);
  }

  void _freeEventBuffer() {
    if (_eventBuffer == nullptr) {
      return;
    }
    calloc.free(_eventBuffer);
    _eventBuffer = nullptr;
  }

  void _guard(void Function() run) {
    try {
      run();
    } on Object catch (error) {
      // Nowhere to report this from inside the worker, and a teardown step's
      // failure must not stop the steps after it. Reduced so nothing but the
      // type could ever be retained.
      _errorContext(error);
    }
  }

  void _reply(int id, String code, String detail) {
    _toOwner.send(<Object?>[_replyTag, id, code, detail]);
  }

  /// Runs [use] with [value] as a NUL-terminated native string, freeing it
  /// afterwards on every path.
  T _withNativeString<T>(String value, T Function(Pointer<Utf8>) use) {
    final native = value.toNativeUtf8();
    try {
      return use(native);
    } finally {
      calloc.free(native);
    }
  }
}

/// Built once per worker and held for its life, so the handler pointer is stable
/// across every `XSetErrorHandler` call.
final Pointer<NativeFunction<_XErrorHandlerNative>> _trapHandler =
    Pointer.fromFunction<_XErrorHandlerNative>(_trapXError, 0);

typedef _XErrorHandlerNative =
    Int32 Function(Pointer<Void>, Pointer<_XErrorEvent>);

/// The `libX11.so.6` entry points this file uses, and no others.
///
/// Looked up once at first grab. Notably absent, and deliberately: `XGrabKeyboard`
/// and anything taking `AnyKey` or `AnyModifier`. A grab wider than the bound
/// combination would deliver keystrokes this daemon has no business seeing.
final class _X11Bindings {
  _X11Bindings(DynamicLibrary library)
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
      defaultRootWindow = library
          .lookupFunction<
            UnsignedLong Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('XDefaultRootWindow'),
      stringToKeysym = library
          .lookupFunction<
            UnsignedLong Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)
          >('XStringToKeysym'),
      keysymToKeycode = library
          .lookupFunction<
            UnsignedChar Function(Pointer<Void>, UnsignedLong),
            int Function(Pointer<Void>, int)
          >('XKeysymToKeycode'),
      grabKey = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              UnsignedInt,
              UnsignedLong,
              Int32,
              Int32,
              Int32,
            ),
            int Function(Pointer<Void>, int, int, int, int, int, int)
          >('XGrabKey'),
      ungrabKey = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, UnsignedInt, UnsignedLong),
            int Function(Pointer<Void>, int, int, int)
          >('XUngrabKey'),
      sync = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('XSync'),
      // Typed as returning a handler rather than an opaque `Pointer<Void>`,
      // because the return value is load-bearing: `XSetErrorHandler` answers
      // with the process-global handler it just displaced, and [_acquire] hands
      // that same pointer back to this function to restore it. The C signature
      // is `XErrorHandler XSetErrorHandler(XErrorHandler)`, so one lookup does
      // both jobs.
      setErrorHandler = library
          .lookupFunction<
            Pointer<NativeFunction<_XErrorHandlerNative>> Function(
              Pointer<NativeFunction<_XErrorHandlerNative>>,
            ),
            Pointer<NativeFunction<_XErrorHandlerNative>> Function(
              Pointer<NativeFunction<_XErrorHandlerNative>>,
            )
          >('XSetErrorHandler'),
      pending = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('XPending'),
      nextEvent = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>),
            int Function(Pointer<Void>, Pointer<Uint8>)
          >('XNextEvent'),
      refreshKeyboardMapping = library
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('XRefreshKeyboardMapping');

  final Pointer<Void> Function(Pointer<Utf8>) openDisplay;
  final int Function(Pointer<Void>) closeDisplay;
  final int Function(Pointer<Void>) defaultRootWindow;
  final int Function(Pointer<Utf8>) stringToKeysym;
  final int Function(Pointer<Void>, int) keysymToKeycode;
  final int Function(Pointer<Void>, int, int, int, int, int, int) grabKey;
  final int Function(Pointer<Void>, int, int, int) ungrabKey;
  final int Function(Pointer<Void>, int) sync;
  final Pointer<NativeFunction<_XErrorHandlerNative>> Function(
    Pointer<NativeFunction<_XErrorHandlerNative>>,
  )
  setErrorHandler;
  final int Function(Pointer<Void>) pending;
  final int Function(Pointer<Void>, Pointer<Uint8>) nextEvent;
  final int Function(Pointer<Uint8>) refreshKeyboardMapping;
}

/// `XKeyEvent`, laid out as `/usr/include/X11/Xlib.h` declares it. Field order
/// is the ABI: Dart computes the offsets, so the order and the widths are what
/// must match, and both were read from the installed header rather than recalled.
final class _XKeyEvent extends Struct {
  @Int32()
  external int type;

  @UnsignedLong()
  external int serial;

  @Int32()
  external int sendEvent;

  external Pointer<Void> display;

  @UnsignedLong()
  external int window;

  @UnsignedLong()
  external int root;

  @UnsignedLong()
  external int subwindow;

  @UnsignedLong()
  external int time;

  @Int32()
  external int x;

  @Int32()
  external int y;

  @Int32()
  external int xRoot;

  @Int32()
  external int yRoot;

  @Uint32()
  external int state;

  @Uint32()
  external int keycode;

  @Int32()
  external int sameScreen;
}

/// `XErrorEvent`, same source. Note the order: `resourceid` comes **before**
/// `serial`, which is the opposite of `XKeyEvent`'s and easy to get wrong from
/// memory — only `errorCode` and `requestCode` are read, and both sit after
/// those two, so an order slip here would silently read the wrong bytes.
final class _XErrorEvent extends Struct {
  @Int32()
  external int type;

  external Pointer<Void> display;

  @UnsignedLong()
  external int resourceId;

  @UnsignedLong()
  external int serial;

  @UnsignedChar()
  external int errorCode;

  @UnsignedChar()
  external int requestCode;

  @UnsignedChar()
  external int minorCode;
}
