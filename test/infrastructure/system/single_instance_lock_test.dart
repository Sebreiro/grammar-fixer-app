import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/single_instance_lock.dart';
import 'package:test/test.dart';

import '../../support/child_process.dart';

/// Behaviour tests for `SingleInstanceLock` (AD-14). Every case derives its
/// own abstract socket name from a unique fake runtime directory, so the
/// suites stay independent even though the abstract namespace is flat and
/// shared by the whole machine. Nothing is created on disk.
void main() {
  var uniqueRun = 0;

  /// A runtime directory nothing else in this namespace can collide with.
  AppPaths pathsFor(String label) {
    uniqueRun += 1;
    return AppPaths.fromEnvironment({
      'HOME': '/home/test',
      'XDG_RUNTIME_DIR': '/run/hgc-test-$pid-$label-$uniqueRun',
    });
  }

  SingleInstanceLock lockOn(AppPaths paths) {
    final lock = SingleInstanceLock(paths: paths);
    addTearDown(lock.dispose);
    return lock;
  }

  test('AD-14: a free address is acquired, with no warning', () async {
    final lock = lockOn(pathsFor('free'));

    final acquisition = await lock.acquire();

    expect(acquisition.status, SingleInstanceStatus.acquired);
    expect(acquisition.warning, isNull);
  });

  test('AD-14: a second lock on the same address reports alreadyRunning and '
      'the holder receives exactly one show request', () async {
    final paths = pathsFor('held');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final requests = <void>[];
    holder.showRequests.listen(requests.add);

    final second = lockOn(paths);
    final acquisition = await second.acquire();
    await pumpEventQueue();

    expect(acquisition.status, SingleInstanceStatus.alreadyRunning);
    expect(
      requests,
      hasLength(1),
      reason: 'a second launch asks the daemon to show its panel, once',
    );
  });

  test('AD-14: release frees the address for the very lock that held it, and '
      'its show requests still work afterwards', () async {
    // The same instance, not a fresh one: a lock that came back up with a
    // dead notification channel would report acquired while every later
    // launch exited 0 to a panel that never appears.
    final paths = pathsFor('released');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    await holder.release();

    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final requests = <void>[];
    holder.showRequests.listen(requests.add);
    final second = lockOn(paths);
    expect(
      (await second.acquire()).status,
      SingleInstanceStatus.alreadyRunning,
    );
    await pumpEventQueue();

    expect(requests, hasLength(1));
  });

  test('AD-14: a peer whose line lands after dispose is dropped, not turned '
      'into an unhandled add-after-close', () async {
    // Exactly the shutdown race: the connection is accepted while the daemon
    // is up, and the line arrives after the notification channel is gone.
    final paths = pathsFor('shutdownrace');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final peer = await Socket.connect(
      InternetAddress(
        '\u0000${paths.runtimeDirectory}/${SingleInstanceLock.socketBasename}',
        type: InternetAddressType.unix,
      ),
      0,
    );
    addTearDown(peer.destroy);
    await pumpEventQueue();

    await holder.dispose();
    peer.writeln(SingleInstanceLock.showRequestLine);
    await peer.flush();
    await pumpEventQueue();

    // No expectation to state beyond "the test did not fail": an unhandled
    // async error from the holder's listener fails this test on its own.
    expect(holder.showRequests.isBroadcast, isTrue);
  });

  test('AD-14: one connection yields at most one show request, however many '
      'lines the peer sends', () async {
    final paths = pathsFor('flood');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final requests = <void>[];
    holder.showRequests.listen(requests.add);

    final peer = await Socket.connect(
      InternetAddress(
        '\u0000${paths.runtimeDirectory}/${SingleInstanceLock.socketBasename}',
        type: InternetAddressType.unix,
      ),
      0,
    );
    addTearDown(peer.destroy);
    for (var line = 0; line < 20; line += 1) {
      peer.writeln(SingleInstanceLock.showRequestLine);
    }
    await peer.flush();
    await pumpEventQueue();

    expect(
      requests,
      hasLength(1),
      reason:
          'the protocol is one line per connection, so one peer cannot '
          'flood the panel',
    );
  });

  /// A peer on the holder's address, connected but silent, so the test decides
  /// when the line lands.
  Future<Socket> peerOn(AppPaths paths) async {
    final peer = await Socket.connect(
      InternetAddress(
        '\u0000${paths.runtimeDirectory}/${SingleInstanceLock.socketBasename}',
        type: InternetAddressType.unix,
      ),
      0,
    );
    addTearDown(peer.destroy);
    return peer;
  }

  /// Sends one show request over the wire and waits for the holder to have
  /// handled it.
  ///
  /// The same two writes `_sendShowRequest` makes — connect, write the one
  /// line, flush — because that is the whole protocol; the `alreadyRunning`
  /// half of a real second launch is pinned by the rows above. What a raw peer
  /// buys is the barrier: the holder destroys a connection the moment its line
  /// is handled, so the peer seeing the socket end is the one deterministic
  /// signal that the request has been through the holder's handler. The rows
  /// below need it, because a request landing while nothing is subscribed is by
  /// definition unobservable until something subscribes — and a fixed number of
  /// event-loop pumps in its place is a row that goes green on a loaded machine
  /// for the wrong reason.
  Future<void> sendShowRequest(AppPaths paths) async {
    final peer = await peerOn(paths);
    peer.writeln(SingleInstanceLock.showRequestLine);
    await peer.flush();
    await peer.drain<void>();
  }

  test('DW-19: a request that lands while nothing is listening still raises '
      'the panel — the first subscriber drains it', () async {
    // The window this closes is the whole of startup: `main.dart` subscribes
    // only after `_createHiddenWindow`, `runApp` and the first frame, and a
    // launcher double-click during those raised nothing at all.
    final paths = pathsFor('buffered');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);

    await sendShowRequest(paths);

    final requests = <void>[];
    holder.showRequests.listen(requests.add);
    await pumpEventQueue();

    expect(
      requests,
      hasLength(1),
      reason: 'the request is held for the first subscriber, not dropped',
    );
  });

  test('DW-19: several requests during startup collapse into exactly one show '
      'request', () async {
    // A flag, not a queue: three impatient double-clicks mean "raise the
    // panel", once — not three panels' worth of work handed to the daemon the
    // moment it finishes starting.
    final paths = pathsFor('buffercollapse');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);

    for (var launch = 0; launch < 3; launch += 1) {
      await sendShowRequest(paths);
    }

    final requests = <void>[];
    holder.showRequests.listen(requests.add);
    await pumpEventQueue();

    expect(requests, hasLength(1));
  });

  test('DW-19: a request arriving while a subscriber is live is delivered and '
      'not also buffered', () async {
    // The other half of the flag's contract. A request that was delivered and
    // *also* buffered would raise the panel a second time the next time
    // anything subscribed — and `DaemonLifecycle.start()` after a `shutdown()`
    // is exactly such a subscriber.
    //
    // The cancel is what makes that observable, and it is the real sequence
    // rather than a contrivance: a broadcast controller runs `onListen` on the
    // transition from no listeners to one, so only a subscription that replaces
    // a cancelled one can see a stale flag drain.
    final paths = pathsFor('livesubscriber');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final requests = <void>[];
    final subscription = holder.showRequests.listen(requests.add);

    await sendShowRequest(paths);
    await pumpEventQueue();

    expect(requests, hasLength(1));

    await subscription.cancel();
    final later = <void>[];
    holder.showRequests.listen(later.add);
    await pumpEventQueue();

    expect(
      later,
      isEmpty,
      reason: 'a delivered request must not be replayed to a later subscriber',
    );
  });

  test('DW-19: a line that lands after dispose is dropped, and the closed '
      'channel stays closed', () async {
    // The shutdown race, re-pinned now that the delivery path has a branch in
    // it: the `isClosed` guard moved into `_recordShowRequest`, so this row
    // exists to keep the swallow from being lost in that move.
    //
    // What it does *not* pin, deliberately, so the name does not overclaim: a
    // closed controller can never drain, so an implementation that set the
    // flag and only then noticed the close would pass this identically. The
    // stale flag is unobservable — the lock is terminal after dispose.
    final paths = pathsFor('bufferafterdispose');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final peer = await peerOn(paths);
    await pumpEventQueue();

    await holder.dispose();
    peer.writeln(SingleInstanceLock.showRequestLine);
    await peer.flush();
    await pumpEventQueue();

    final requests = <void>[];
    var closed = false;
    holder.showRequests.listen(requests.add, onDone: () => closed = true);
    await pumpEventQueue();

    // No expectation to state beyond "the test did not fail": an unhandled
    // add-after-close from the holder's listener fails this test on its own.
    expect(requests, isEmpty, reason: 'a disposed lock has no panel to raise');
    expect(
      closed,
      isTrue,
      reason: 'the channel stays closed — the drain must not reopen anything',
    );
  });

  test('DW-19: a request buffered in one holding period is not replayed to the '
      'next', () async {
    // `release()` hands the address back and the same lock may `acquire()` it
    // again — the contract this class states and the row above pins for the
    // stream. The flag is the half of that contract the buffer added, and it
    // has to be reset with the rest: a request that arrived while the previous
    // holder was starting is not a request the next one was asked to serve,
    // and draining it would raise the panel for a launch that has long since
    // exited.
    final paths = pathsFor('bufferacrossrelease');
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);

    await sendShowRequest(paths);
    await holder.release();

    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final requests = <void>[];
    holder.showRequests.listen(requests.add);
    await pumpEventQueue();

    expect(
      requests,
      isEmpty,
      reason: 'the flag belongs to the holding period that buffered it',
    );
  });

  test(
    'DW-19: a peer accepted before release cannot arm the flag after it',
    () async {
      // The narrow half of the same contract, and the one clearing the flag in
      // `release()` does not close on its own. `ServerSocket.close()` stops
      // accepting; it does not close connections already accepted. So a peer
      // that connected while this holder still held the address — and is still
      // inside its handshake deadline — can deliver its line *after* the flag
      // was cleared, re-arming it for a holding period that has not begun.
      final paths = pathsFor('bufferinflight');
      final holder = lockOn(paths);
      expect((await holder.acquire()).status, SingleInstanceStatus.acquired);

      // Connected, deliberately silent: the line is held back until the address
      // has already been handed off.
      final peer = await peerOn(paths);
      await pumpEventQueue();

      await holder.release();
      peer.writeln(SingleInstanceLock.showRequestLine);
      await peer.flush();
      await pumpEventQueue();

      expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
      final requests = <void>[];
      holder.showRequests.listen(requests.add);
      await pumpEventQueue();

      expect(
        requests,
        isEmpty,
        reason:
            'the address is the authority on whose request this is; once it is '
            'handed back the line is not this holder to serve',
      );
    },
  );

  test('AD-14: a runtime directory that overflows the sun_path limit is '
      'reported as unavailable, without attempting a bind', () async {
    // The kernel silently truncates an over-long abstract name, which would
    // make two unrelated runtime directories look like one instance — so the
    // limit is a reported configuration problem, not a caught exception.
    final paths = AppPaths.fromEnvironment({
      'HOME': '/home/test',
      'XDG_RUNTIME_DIR': '/run/${'d' * 200}',
    });
    final lock = lockOn(paths);

    final acquisition = await lock.acquire();

    expect(acquisition.status, SingleInstanceStatus.unavailable);
    expect(
      acquisition.warning,
      contains('${SingleInstanceLock.maxSocketNameBytes}'),
    );
  });

  test('AD-14: an address that can be neither bound nor reached reports '
      'unavailable, names both failures, and still lets the daemon '
      'start', () async {
    // Staged by exhausting the child's file descriptors under a lowered
    // ulimit: bind fails for want of a descriptor and so does the fallback
    // connect. It is the only way found to reach this branch — a bind
    // refusal on an abstract name normally implies a live listener that then
    // accepts the connect, and even a datagram holder does not collide with
    // a stream bind (verified 2026-08-07).
    final child = await runGuardedChild(
      'bash',
      [
        '-c',
        'ulimit -n 256; exec "\$0" run test/support/single_instance_child.dart '
            'exhaust-descriptors',
        dartExecutable,
      ],
      environment: {
        'HOME': '/home/test',
        'XDG_RUNTIME_DIR': '/run/hgc-test-$pid-exhausted',
      },
    );

    expect(child.exitCode, 0, reason: 'the branch must not throw');
    expect(
      '${child.stdout}'.trim(),
      SingleInstanceStatus.unavailable.name,
      reason: 'child stderr: ${child.stderr}',
    );
    expect(
      '${child.stderr}',
      allOf(contains('could not bind'), contains('could not reach')),
      reason: 'the warning has to name both failures to be actionable',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'AD-14: a holder that binds the address and then stops accepting is '
    'bounded by the handshake timeout',
    () {
      // Deliberately unexecuted. Dart offers no way to bind an abstract name
      // and then refuse to accept on it — ServerSocket.bind() already calls
      // listen(2), and the kernel completes the handshake from the backlog
      // without the application. The timeout exists so that a peer which is
      // wedged at a lower level resolves to a status instead of hanging a
      // launch forever; the descriptor-exhaustion case above covers the same
      // unavailable branch it feeds into.
    },
    skip:
        'no way to bind an abstract unix socket without accepting on it '
        'from Dart',
  );

  test('AD-14: an unavailable lock still lets the daemon start — nothing '
      'throws and disposal is safe', () async {
    final paths = AppPaths.fromEnvironment({
      'HOME': '/home/test',
      'XDG_RUNTIME_DIR': '/run/${'e' * 200}',
    });
    final lock = SingleInstanceLock(paths: paths);

    await lock.acquire();

    await expectLater(lock.dispose(), completes);
  });

  test('AD-14: a second process on the same address reports alreadyRunning '
      'while the in-process holder gets the show request', () async {
    final runtimeRoot = '/run/hgc-test-$pid-crossprocess';
    final paths = AppPaths.fromEnvironment({
      'HOME': '/home/test',
      'XDG_RUNTIME_DIR': runtimeRoot,
    });
    final holder = lockOn(paths);
    expect((await holder.acquire()).status, SingleInstanceStatus.acquired);
    final firstRequest = holder.showRequests.first;

    final child = await runGuardedChild(
      dartExecutable,
      ['run', 'test/support/single_instance_child.dart'],
      environment: {'HOME': '/home/test', 'XDG_RUNTIME_DIR': runtimeRoot},
    );

    expect(child.exitCode, 0, reason: 'child stderr: ${child.stderr}');
    expect(
      '${child.stdout}'.trim(),
      SingleInstanceStatus.alreadyRunning.name,
      reason: 'child stderr: ${child.stderr}',
    );
    await expectLater(firstRequest, completes);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
