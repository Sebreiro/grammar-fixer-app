import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_paths.dart';

/// How a [SingleInstanceLock.acquire] attempt resolved (AD-14).
enum SingleInstanceStatus {
  /// This process is the daemon. Its [SingleInstanceLock.showRequests] is
  /// live and will emit whenever a later launch asks for the panel.
  acquired,

  /// Another instance already holds the address and has been asked to show
  /// its panel. This process should exit 0.
  alreadyRunning,

  /// The address is unusable, so singleton-ness cannot be enforced here.
  /// Start anyway: refusing to start a desktop daemon is worse than the
  /// double-launch race it would prevent.
  unavailable,
}

/// The outcome of one [SingleInstanceLock.acquire] call: the decision, plus
/// the reason when it is [SingleInstanceStatus.unavailable].
final class SingleInstanceAcquisition {
  const SingleInstanceAcquisition({required this.status, this.warning});

  final SingleInstanceStatus status;

  /// Human-renderable explanation of a degraded outcome. Null unless
  /// [status] is [SingleInstanceStatus.unavailable].
  final String? warning;
}

/// AD-14's singleton, over an abstract-namespace unix socket scoped to
/// `$XDG_RUNTIME_DIR`.
///
/// The abstract namespace (a socket name whose first byte is NUL) is used
/// rather than a socket file because the kernel reclaims it when the holder
/// dies: a filesystem socket left behind by a crashed daemon makes every
/// later launch fail to bind, the classic stale-socket trap. The namespace is
/// flat and per-network-namespace, so the name embeds the resolved runtime
/// directory — that is what keeps two users on one machine apart.
///
/// **The tradeoff that buys:** an abstract name carries no filesystem
/// permissions. Any local process that can compute the name can bind it
/// first — making every real launch see [SingleInstanceStatus.alreadyRunning]
/// and exit — or, once the daemon holds it, connect and pop the panel of
/// whoever is logged in. A socket file under `$XDG_RUNTIME_DIR` (mode 0700)
/// would not allow either, at the cost of the stale-socket trap above. This
/// is a denial-of-service and nuisance surface only: no correction, config,
/// or history data crosses this socket, whose entire vocabulary is
/// [showRequestLine].
final class SingleInstanceLock {
  SingleInstanceLock({required AppPaths paths})
    : _name = '${paths.runtimeDirectory}/$socketBasename';

  /// The address's last segment. Only ever part of an abstract name — no
  /// file of this name is created.
  static const String socketBasename = 'daemon.sock';

  /// The one line a second launch writes to the holder before exiting.
  static const String showRequestLine = 'show-panel';

  /// Linux caps `sockaddr_un.sun_path` at 108 bytes, the leading NUL of an
  /// abstract name included. Dart binds an over-long name anyway and the
  /// kernel truncates it, which would let two different runtime directories
  /// collide into one instance — so the limit is checked, never risked.
  static const int maxSocketNameBytes = 108;

  /// Bound on both halves of the handshake. A holder that bound the address
  /// and then stopped accepting would otherwise leave a second launch
  /// waiting forever with no status at all — worse than the exception the
  /// status type exists to avoid — and a peer that connects and says nothing
  /// would hold one of the daemon's descriptors for the rest of the day.
  static const Duration handshakeTimeout = Duration(seconds: 2);

  final String _name;

  /// `late` because the initializer names an instance method: `onListen` is
  /// what drains [_pendingShowRequest], and a plain field initializer cannot
  /// see `this`.
  late final StreamController<void> _showRequests =
      StreamController<void>.broadcast(onListen: _scheduleDrain);

  /// Whether a show request arrived while nothing was listening.
  ///
  /// A flag, not a queue, and deliberately: the daemon subscribes only after
  /// `runApp`, so every launch during startup would otherwise be dropped —
  /// but three impatient double-clicks mean "raise the panel", once, not
  /// three panels' worth of work handed to the first subscriber.
  bool _pendingShowRequest = false;

  ServerSocket? _server;

  /// Emits once per show request from a later launch. Broadcast, like every
  /// other notification stream in the daemon.
  ///
  /// Requests landing during **startup** — the address is taken well before
  /// the daemon subscribes — are held rather than dropped: the first
  /// subscriber is handed one event for however many arrived until then.
  /// Teardown is the other side of that window and is not covered:
  /// `DaemonLifecycle.shutdown()` cancels its subscription at step 1 and
  /// disposes this lock ten steps later, so a line arriving in between sets a
  /// flag no one is left to drain. Nothing here recovers that request, and it
  /// is worth being exact about what the user sees rather than calling it
  /// self-correcting: the address stays bound until step 11, so that launch
  /// was already told `alreadyRunning` and has exited 0. Its click raises
  /// nothing and starts nothing; the *next* launch is the one that finds the
  /// address free and becomes the daemon. Closing that window means reordering
  /// `DaemonLifecycle._run()` — releasing the address before the subscription,
  /// or refusing requests between the two — which is a contract other entries
  /// rest on and not this class's to change.
  Stream<void> get showRequests => _showRequests.stream;

  /// Binds the address, or — when someone else holds it — asks that instance
  /// to show its panel. Never throws: every failure is a status.
  Future<SingleInstanceAcquisition> acquire() async {
    // Measured, not bound: the +1 is the leading NUL of the abstract name.
    final nameBytes = utf8.encode(_name).length + 1;
    if (nameBytes > maxSocketNameBytes) {
      return SingleInstanceAcquisition(
        status: SingleInstanceStatus.unavailable,
        warning:
            'the single-instance socket name "$_name" is $nameBytes bytes, '
            'over the $maxSocketNameBytes-byte sun_path limit; '
            'single-instance enforcement is off',
      );
    }
    try {
      final server = await ServerSocket.bind(_address, 0);
      _server = server;
      server.listen(_onConnection);
      return const SingleInstanceAcquisition(
        status: SingleInstanceStatus.acquired,
      );
    } on SocketException catch (bindError) {
      // Deliberately not branching on the errno: a rebind from within this
      // process and one from a second process fail with different Dart-level
      // messages, and the recovery is the same either way.
      return _signalHolder(bindError);
    }
  }

  /// Stops holding the address, leaving [showRequests] usable. The kernel
  /// frees an abstract name as soon as its listener closes, so the same lock
  /// — or any other — can [acquire] the name again afterwards.
  Future<void> release() async {
    await _server?.close();
    _server = null;
    // The address going back is the moment a request stops being this holder's
    // to serve: whoever sent it will find the name free and become the daemon.
    // Keeping the flag would replay it to the first subscriber of the *next*
    // holding period — `acquire()` after `release()` is a shipped path.
    _pendingShowRequest = false;
  }

  /// Releases the address and closes [showRequests]. Terminal: the lock must
  /// not be acquired again after this, because a re-acquired lock with a
  /// closed notification channel would report [SingleInstanceStatus.acquired]
  /// while silently dropping every show request — a second launch would exit
  /// 0 and no panel would ever appear. Shutdown only.
  Future<void> dispose() async {
    await release();
    if (!_showRequests.isClosed) {
      await _showRequests.close();
    }
  }

  /// The leading NUL is what places the name in the abstract namespace; it
  /// is not a path and nothing is created on disk.
  InternetAddress get _address =>
      InternetAddress('\u0000$_name', type: InternetAddressType.unix);

  Future<SingleInstanceAcquisition> _signalHolder(
    SocketException bindError,
  ) async {
    try {
      await _sendShowRequest();
      return const SingleInstanceAcquisition(
        status: SingleInstanceStatus.alreadyRunning,
      );
    } on SocketException catch (reachError) {
      // Near-unreachable — a bind refusal implies a live listener — but a
      // daemon that throws here would be unlaunchable, so it reports instead.
      return _unreachable(bindError, reachError);
    } on TimeoutException catch (reachError) {
      // A holder that bound the address and then wedged: the launch must
      // still resolve to a status rather than hanging on the handshake.
      return _unreachable(bindError, reachError);
    }
  }

  Future<void> _sendShowRequest() async {
    final socket = await Socket.connect(_address, 0, timeout: handshakeTimeout);
    try {
      socket.writeln(showRequestLine);
      // Not close(): that waits on the peer, which is exactly the party
      // suspected of being wedged. flush() puts the line in the kernel's
      // hands, which is all the protocol promises.
      await socket.flush().timeout(handshakeTimeout);
    } finally {
      socket.destroy();
    }
  }

  SingleInstanceAcquisition _unreachable(
    SocketException bindError,
    Object reachError,
  ) => SingleInstanceAcquisition(
    status: SingleInstanceStatus.unavailable,
    warning:
        'could not bind the single-instance socket "$_name" ($bindError) '
        'and could not reach a running instance either ($reachError); '
        'starting without single-instance enforcement',
  );

  /// Delivers a show request, or holds it for the first subscriber.
  ///
  /// The daemon takes this address before it has a widget tree and subscribes
  /// only after `runApp`, so a launcher double-click landing in that window
  /// would otherwise raise nothing at all — the second launch exits 0 and no
  /// panel appears. Buffering here rather than in `main.dart` is what closes
  /// that window without moving the subscription ahead of the widget tree.
  void _recordShowRequest() {
    // A peer whose line lands between release() and dispose() must not become
    // an unhandled "add after close" in an all-day daemon — and must not set
    // a flag no one will ever drain either.
    if (_showRequests.isClosed) {
      return;
    }
    // Nor may a line accepted *before* release() set the flag after it.
    // `ServerSocket.close()` stops accepting but leaves already-accepted
    // sockets live, so a peer still inside its handshake deadline can deliver
    // here after release() cleared the flag — re-arming it for a holding
    // period that has not begun. The address is the authority on whose request
    // this is: once it is handed back, it is not this holder's to serve.
    if (_server == null) {
      return;
    }
    if (_showRequests.hasListener) {
      _showRequests.add(null);
      return;
    }
    _pendingShowRequest = true;
  }

  /// Hands a buffered request to a subscriber that has just attached.
  ///
  /// A microtask, not an inline `add`, for the re-check it makes room for
  /// rather than for any re-entrancy it avoids: `onListen` runs synchronously
  /// inside `listen()`, and between it and this microtask the subscription can
  /// be cancelled and the lock disposed, so the drain has to re-read the state
  /// it acts on. (An inline `add` would *not* have re-entered the subscriber:
  /// `_showRequests` is a default `sync: false` controller, which never
  /// delivers from within `add`. Deferring is a clearer place to put the
  /// re-check, not a fix for a hazard this controller has.) Microtasks drain
  /// before the event loop returns to socket I/O, so the buffered request still
  /// arrives ahead of any later one.
  void _scheduleDrain() {
    scheduleMicrotask(() {
      // Re-checked rather than trusted: the subscription can be cancelled and
      // the lock disposed between the listen and this microtask.
      if (!_pendingShowRequest ||
          _showRequests.isClosed ||
          !_showRequests.hasListener) {
        return;
      }
      _pendingShowRequest = false;
      _showRequests.add(null);
    });
  }

  void _onConnection(Socket socket) {
    // The protocol is one line per connection. Accepting more would let a
    // single peer flood showRequests, and accepting none forever would let a
    // silent peer pin a descriptor in a daemon that never exits.
    var handled = false;
    final deadline = Timer(handshakeTimeout, socket.destroy);
    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (handled) {
              return;
            }
            handled = true;
            deadline.cancel();
            if (line.trim() == showRequestLine) {
              _recordShowRequest();
            }
            socket.destroy();
          },
          // A peer that dies mid-line must not become an unhandled async
          // error in a daemon that runs all day.
          onError: (Object _) {
            deadline.cancel();
            socket.destroy();
          },
          onDone: () {
            deadline.cancel();
            socket.destroy();
          },
          cancelOnError: true,
        );
  }
}
