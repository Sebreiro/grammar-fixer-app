import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_status.dart';
import 'package:hotkey_grammar_corrector/src/domain/logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/daemon_lifecycle.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';
import '../../fakes/throwing_logger.dart';

/// The bound for every row where the bound is **not** what is under test.
///
/// Deliberately unreachable rather than merely generous. Two rows here park a
/// step on a completer and settle it several statements later, and a bound they
/// could reach under load would quietly turn them into abandonment rows that
/// still pass — the recorded step sequence ends the same either way, so the row
/// would certify an ordering it never exercised. Nothing here awaits a timer.
const Duration _ampleStepTimeout = Duration(minutes: 5);

/// The bound for the rows where reaching it *is* the behaviour under test.
///
/// Short, because those rows wait it out in real time, twice over in the
/// per-step row — and no shorter, because the machine is shared.
const Duration _stallStepTimeout = Duration(seconds: 1);

/// The resident daemon's runtime lifecycle: what a show request reaches, and
/// the order everything comes down in (CAP-7, CAP-14, AD-14).
///
/// The ordering assertions read the *recorded* sequence rather than checking
/// that each step happened, so swapping any two steps in `shutdown()` fails
/// them — which is the only version of an ordering test worth having. Each was
/// mutation-verified by transposing adjacent steps in the source.
///
/// Pure Dart: this type takes the container-side work as callbacks precisely
/// so it needs no Flutter binding (AGENTS.md §7, AD-1).
void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  group('show requests (AD-14, CAP-1)', () {
    test(
      'AD-14: a show request from a later launch reaches the panel',
      () async {
        harness.lifecycle.start();

        harness.requestShow();
        await pumpEventQueue();

        expect(harness.showPanelCalls, 1);
      },
    );

    test('CAP-1: the request is fired, not awaited — the handler returns '
        'before anything the panel does can resolve', () async {
      harness.onShowRequest = () {
        harness.record('show panel');
        // A real PanelController fires show() and returns; if the lifecycle
        // awaited the handler this would be the wrong place to observe it.
      };
      harness.lifecycle.start();

      harness.requestShow();
      await pumpEventQueue();

      expect(harness.steps, ['show panel']);
    });

    test('AD-15: a show-request stream that errors is logged and the '
        'subscription survives for the next launch', () async {
      harness.lifecycle.start();

      harness.showRequestsController.addError(StateError('the socket failed'));
      await pumpEventQueue();
      harness.requestShow();
      await pumpEventQueue();

      expect(harness.showPanelCalls, 1);
      expect(harness.logger.lines.single.level, 'error');
    });

    test('AD-15: a handler that throws is logged, not left as an uncaught '
        'zone error', () async {
      harness.onShowRequest = () {
        harness.record('show panel');
        // What a graph being torn down does: reading a disposed container
        // throws, and this handler runs from a stream callback with no
        // caller to catch it.
        throw StateError('the provider container is disposed');
      };
      harness.lifecycle.start();

      harness.requestShow();
      await pumpEventQueue();

      expect(harness.steps, ['show panel']);
      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('raising the panel'));
    });

    test('AD-14: a handler that throws does not end the subscription — the '
        'next launch still gets its panel', () async {
      var failNext = true;
      harness.onShowRequest = () {
        harness.showPanelCalls += 1;
        if (failNext) {
          failNext = false;
          throw StateError('transient');
        }
      };
      harness.lifecycle.start();

      harness.requestShow();
      await pumpEventQueue();
      harness.requestShow();
      await pumpEventQueue();

      expect(harness.showPanelCalls, 2);
    });

    test('AD-14: no show request reaches the panel once shutdown has '
        'begun', () async {
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();
      harness.requestShow();
      await pumpEventQueue();

      expect(harness.showPanelCalls, 0);
    });
  });

  group('tray panel requests (AD-12, AD-8)', () {
    test(
      'AD-12: a tray menu pick reaches the same handler a second launch '
      'does — the tray is the way in when no hotkey could be bound',
      () async {
        harness.lifecycle.start();

        harness.requestPanelFromTray();
        await pumpEventQueue();

        expect(harness.showPanelCalls, 1);
      },
    );

    test('CAP-1: the tray request is fired, not awaited', () async {
      harness.onShowRequest = () {
        harness.record('show panel');
        // AD-8: PanelController.showPanel() fires show() and returns. A
        // lifecycle that awaited the handler would put the window-manager
        // round trip on the path CAP-1 budgets.
      };
      harness.lifecycle.start();

      harness.requestPanelFromTray();
      await pumpEventQueue();

      expect(harness.steps, ['show panel']);
    });

    test('AD-15: a tray handler that throws names the tray, not a second '
        'launch', () async {
      // Both sources funnel into one handler, so the distinction the two
      // separate stream parameters exist to preserve has to be threaded
      // through it as well. Without that the more likely of the two failures
      // — the tray pick reaching a graph being torn down — is reported as
      // something a second launch did, and an operator looks in the wrong
      // place.
      harness.onShowRequest = () {
        throw StateError('the provider container is disposed');
      };
      harness.lifecycle.start();

      harness.requestPanelFromTray();
      await pumpEventQueue();

      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('tray menu'));
      expect(errors.single.message, isNot(contains('single-instance')));
    });

    test('AD-15: a show-request handler that throws names the second launch, '
        'not the tray', () async {
      harness.onShowRequest = () {
        throw StateError('the provider container is disposed');
      };
      harness.lifecycle.start();

      harness.requestShow();
      await pumpEventQueue();

      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('single-instance'));
      expect(errors.single.message, isNot(contains('tray')));
    });

    test('AD-15: a tray request stream that errors is logged by name and the '
        'subscription survives the next pick', () async {
      // Deliberately defensive rather than a live path: `TrayManagerTray`
      // absorbs its own seam's errors and only ever calls `add(null)`, so the
      // shipped `panelRequests` cannot error today. This type takes a bare
      // `Stream<void>` from the composition root and cannot see which
      // implementation is behind it, and a subscription that ended on an error
      // would take AD-12's whole fallback down with it — so the branch is kept
      // and this row pins it. It is not evidence that anything errors.
      harness.lifecycle.start();

      harness.trayRequestsController.addError(StateError('the seam broke'));
      await pumpEventQueue();
      harness.requestPanelFromTray();
      await pumpEventQueue();

      expect(harness.showPanelCalls, 1);
      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        contains('tray'),
        reason:
            'the two request streams are separate parameters precisely so an '
            'operator learns which mechanism broke',
      );
    });

    test('AD-12: no tray request reaches the panel once shutdown has '
        'begun', () async {
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();
      harness.requestPanelFromTray();
      await pumpEventQueue();

      expect(harness.showPanelCalls, 0);
    });
  });

  group('shutdown ordering (CAP-7)', () {
    test('CAP-7: both request subscriptions are cancelled, then the '
        'controllers, then the graph, then panel visibility, tray, hotkey, '
        'database, config store and lock', () async {
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      expect(harness.steps, [
        'cancel show requests',
        'cancel tray requests',
        'dispose controllers',
        'dispose graph',
        'close panel visibility',
        'close tray',
        'dispose hotkey',
        'release hotkey grab',
        'close database',
        'close config store',
        'close lock',
      ]);
    });

    test('CAP-14: the panel visibility adapter closes after the graph and '
        'before the hotkey adapter', () async {
      // Its position is pinned by transposition — swap it with either
      // neighbour in `shutdown()` and this fails — so the reason has to be
      // the one that actually holds. It is *not* "a late window event must
      // not reach a disposed controller": `CorrectionController.dispose()`
      // cancels its own visibility subscription two steps earlier, so that
      // hazard cannot occur. What does hold is the other direction. The
      // adapter must outlive every controller that can still call `show()` or
      // `hide()` on it — `PanelController` fires both without awaiting, so a
      // call issued during teardown is still in flight when its owner returns
      // — and it must close before the process exits, because it holds a
      // window listener and a stream of its own.
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      final position = harness.steps.indexOf('close panel visibility');
      expect(position, isNonNegative);
      expect(position, greaterThan(harness.steps.indexOf('dispose graph')));
      expect(position, lessThan(harness.steps.indexOf('dispose hotkey')));
    });

    test('AD-12: the tray closes after the panel visibility adapter and '
        'before the hotkey adapter', () async {
      // Both neighbours are load-bearing, so this reads the recorded sequence
      // and fails in either direction. After the panel adapter: a menu pick
      // already dispatched raises the panel *through* that adapter, so a tray
      // outliving it would be a request with nothing behind it. Before the
      // hotkey: the two are independent, and keeping the tray with the
      // surfaces it drives rather than among the data adapters is what makes
      // the numbered list in `shutdown()`'s doc describe what it does.
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      final position = harness.steps.indexOf('close tray');
      expect(position, isNonNegative);
      expect(
        position,
        greaterThan(harness.steps.indexOf('close panel visibility')),
      );
      expect(position, lessThan(harness.steps.indexOf('dispose hotkey')));
    });

    test('AD-4: the hotkey seam is released right after the adapter that may '
        'own it, on this path and not only on the abort path', () async {
      // `_releaseWithoutLifecycle` in main.dart has closed both since the seam
      // existed; this path was handed only the adapter. On X11 that hid the
      // omission, because `X11GlobalHotkey.dispose()` disposes the seam itself —
      // but on Wayland the adapter never saw it, so the seam main.dart built was
      // closed on the *failure* path and left open on the one that actually runs
      // on SIGTERM. Ordered rather than merely present: releasing the grab
      // before the adapter has let go of its press subscription would tear the
      // seam out from under a live listener.
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      final position = harness.steps.indexOf('release hotkey grab');
      expect(position, isNonNegative);
      expect(position, greaterThan(harness.steps.indexOf('dispose hotkey')));
      expect(position, lessThan(harness.steps.indexOf('close database')));
    });

    test('AD-15: a hotkey seam that refuses to close is logged and every later '
        'step still runs', () async {
      harness.closeHotkeyRegistrar = () async {
        harness.record('release hotkey grab');
        throw StateError('the channel is gone');
      };
      harness.lifecycle.start();

      await expectLater(harness.lifecycle.shutdown(), completes);

      expect(
        harness.steps.sublist(harness.steps.indexOf('release hotkey grab')),
        [
          'release hotkey grab',
          'close database',
          'close config store',
          'close lock',
        ],
        reason: 'the address must go back even when the seam will not close',
      );
      expect(
        harness.logger.lines.where((line) => line.level == 'error'),
        hasLength(1),
      );
    });

    test('AD-12: a tray that refuses to close is logged and every later step '
        'still runs', () async {
      harness.closeTray = () async {
        harness.record('close tray');
        throw StateError('the indicator is gone');
      };
      harness.lifecycle.start();

      await expectLater(harness.lifecycle.shutdown(), completes);

      expect(harness.steps.last, 'close lock');
      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('closing the tray'));
    });

    test('CAP-7: a history write still draining holds the database open — '
        'nothing after the controllers runs until they finish', () async {
      final draining = Completer<void>();
      harness.disposeControllers = () async {
        harness.record('dispose controllers');
        await draining.future;
      };
      harness.lifecycle.start();

      final shutdown = harness.lifecycle.shutdown();
      await pumpEventQueue();

      expect(
        harness.steps,
        ['cancel show requests', 'cancel tray requests', 'dispose controllers'],
        reason:
            'CAP-7 retains a correction that terminates as the daemon '
            'exits, so its write cannot outlive the database',
      );

      draining.complete();
      await shutdown;

      expect(harness.steps, contains('close database'));
      expect(
        harness.steps.indexOf('close database'),
        greaterThan(harness.steps.indexOf('dispose controllers')),
      );
    });

    test('CAP-7: a step that rejects is logged and every later step still '
        'runs — a daemon that cannot exit is the worse failure', () async {
      harness.disposeControllers = () async {
        harness.record('dispose controllers');
        throw StateError('a controller refused to tear down');
      };
      harness.closeDatabase = () async {
        harness.record('close database');
        throw StateError('the database refused to close');
      };
      harness.lifecycle.start();

      await expectLater(harness.lifecycle.shutdown(), completes);

      expect(harness.steps, [
        'cancel show requests',
        'cancel tray requests',
        'dispose controllers',
        'dispose graph',
        'close panel visibility',
        'close tray',
        'dispose hotkey',
        'release hotkey grab',
        'close database',
        'close config store',
        'close lock',
      ]);
      expect(
        harness.logger.lines.where((line) => line.level == 'error'),
        hasLength(2),
      );
    });

    test('AD-15: a rejected step logs the error type only, never the error '
        'itself', () async {
      harness.closeConfigStore = () async {
        harness.record('close config store');
        throw _PayloadCarryingError();
      };
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      final logged = harness.logger.lines.singleWhere(
        (line) => line.level == 'error',
      );
      expect(logged.context, {'error_type': '_PayloadCarryingError'});
    });

    test('CAP-7: start() after shutdown opens no subscription — a stop signal '
        'during startup must not be undone by the rest of startup', () async {
      // `main` installs the signal handlers before the window and the widget
      // tree, but calls `start()` only after `runApp` — deliberately, so an
      // AD-14 show request cannot map a toplevel with no widget tree in it.
      // That leaves a window in which the whole teardown can run first, and
      // `start()` would then subscribe to a lock that has already been
      // released. `shutdown()` is latched against a second signal; this is the
      // same latch seen from the other side.
      await harness.lifecycle.shutdown();

      harness.lifecycle.start();
      harness.showRequestsController.add(null);
      await pumpEventQueue();

      expect(
        harness.steps.where((step) => step == 'show panel'),
        isEmpty,
        reason: 'a request arriving after the teardown reaches nothing',
      );
    });

    test('CAP-7: shutting down twice runs the sequence once', () async {
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();
      await harness.lifecycle.shutdown();

      expect(harness.steps.where((step) => step == 'close lock'), hasLength(1));
      expect(harness.lifecycle.isShuttingDown, isTrue);
    });

    test(
      'CAP-7: a second shutdown awaits the first rather than resolving '
      'early — both signal handlers exit only once the drain is done',
      () async {
        final draining = Completer<void>();
        harness.disposeControllers = () async {
          harness.record('dispose controllers');
          await draining.future;
        };
        harness.lifecycle.start();

        final first = harness.lifecycle.shutdown();
        await pumpEventQueue();
        var secondResolved = false;
        final second = harness.lifecycle.shutdown().then((_) {
          secondResolved = true;
        });
        await pumpEventQueue();

        expect(
          secondResolved,
          isFalse,
          reason:
              'main.dart awaits shutdown() and then exits, so a second signal '
              'resolving early ends the process mid-drain and loses the CAP-7 '
              'write the ordering exists to protect',
        );
        expect(harness.steps, isNot(contains('close database')));

        draining.complete();
        await Future.wait([first, second]);

        expect(secondResolved, isTrue);
        expect(harness.steps, [
          'cancel show requests',
          'cancel tray requests',
          'dispose controllers',
          'dispose graph',
          'close panel visibility',
          'close tray',
          'dispose hotkey',
          'release hotkey grab',
          'close database',
          'close config store',
          'close lock',
        ]);
      },
    );

    test('CAP-7: shutdown completes even when it was never started — a '
        'signal during startup must still bring the daemon down', () async {
      await expectLater(harness.lifecycle.shutdown(), completes);

      expect(harness.steps, [
        // No subscription was ever opened, so there is nothing to cancel; every
        // adapter the daemon did open still closes.
        'dispose controllers',
        'dispose graph',
        'close panel visibility',
        'close tray',
        'dispose hotkey',
        'release hotkey grab',
        'close database',
        'close config store',
        'close lock',
      ]);
    });
  });

  group('bounded teardown (DW-20)', () {
    // The only rows in this file that may reach the bound, so the only ones
    // given a bound they can. `lifecycle` is built lazily, so this lands before
    // the constructor reads it.
    setUp(() => harness.stepTimeout = _stallStepTimeout);

    test('DW-20: a step that never completes is abandoned at the bound, and '
        'every later step still runs', () async {
      // The reason this bound exists at all: `try`/`catch` does nothing for a
      // step that never *completes*, and two shipped steps can genuinely hang —
      // `CorrectionController.dispose()` awaits `Future.wait(_pendingSaves)`
      // and closing the database awaits drift's background isolate. Every
      // `exit(0)`/`exit(1)` in the process sits behind this future.
      final stalled = Completer<void>();
      harness.disposeControllers = () async {
        harness.record('dispose controllers');
        await stalled.future;
      };
      harness.lifecycle.start();

      await expectLater(harness.lifecycle.shutdown(), completes);

      expect(
        harness.steps,
        [
          'cancel show requests',
          'cancel tray requests',
          'dispose controllers',
          'dispose graph',
          'close panel visibility',
          'close tray',
          'dispose hotkey',
          'release hotkey grab',
          'close database',
          'close config store',
          'close lock',
        ],
        reason: 'the address must go back even when a step never answers',
      );
      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        contains('disposing the controllers'),
        reason:
            'the line names the step that stalled, or it names nothing an '
            'operator can act on',
      );
      expect(errors.single.context, {
        'timeout_ms': _stallStepTimeout.inMilliseconds,
      });
    });

    test(
      'DW-20: the bound is per step, not a deadline on the whole teardown '
      '— two stalled steps are both reported and neither stops the rest',
      () async {
        // A total deadline would end the sequence at the first expiry, skipping
        // the release of the single-instance address that is the last step.
        final firstStall = Completer<void>();
        final secondStall = Completer<void>();
        harness.disposeControllers = () async {
          harness.record('dispose controllers');
          await firstStall.future;
        };
        harness.closeDatabase = () async {
          harness.record('close database');
          await secondStall.future;
        };
        harness.lifecycle.start();

        await expectLater(harness.lifecycle.shutdown(), completes);

        expect(harness.steps.last, 'close lock');
        final errors = harness.logger.lines
            .where((line) => line.level == 'error')
            .toList();
        expect(errors, hasLength(2));
        expect(errors.first.message, contains('disposing the controllers'));
        expect(errors.last.message, contains('closing the history database'));
      },
    );

    test('DW-20: a teardown that answers inside the bound reports no '
        'timeout', () async {
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      expect(
        harness.logger.lines.where((line) => line.level == 'error'),
        isEmpty,
        reason:
            'the bound is a backstop; a shutdown where every step answers must '
            'be silent, or the line means nothing when it does appear',
      );
    });

    test('DW-20: a TimeoutException thrown by a step is reported as that step '
        'failing, not as the bound firing', () async {
      // Why `onTimeout` and a flag rather than `on TimeoutException`: steps have
      // deadlines of their own — `SingleInstanceLock.handshakeTimeout` is one —
      // and catching the type would relabel a step's own expiry as this policy
      // firing, sending an operator after a hung teardown that never happened.
      harness.closeLock = () async {
        harness.record('close lock');
        throw TimeoutException('the handshake timed out');
      };
      harness.lifecycle.start();

      await harness.lifecycle.shutdown();

      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        'releasing the single-instance lock failed',
      );
      expect(errors.single.context, {'error_type': 'TimeoutException'});
    });

    test('DW-20: a step that rejects *after* it was abandoned is absorbed — a '
        'late failure is not an unhandled error on the way to exit(0)', () async {
      // Nothing in `_step` states this: it is a property of `Future.timeout`,
      // which keeps its own listener on the source and drops whatever arrives
      // once the bound has already completed the result. The obvious rewrites
      // — `Future.any` with a `Future.delayed`, or a hand-rolled completer —
      // leave the source with no error handler, and a step that fails late
      // then becomes an uncaught zone error between `shutdown()` returning and
      // `exit(0)`. That is the exact class of failure this entry exists to
      // remove, and this is the row that would fail.
      final escaped = <Object>[];

      await runZonedGuarded(() async {
        // Built *inside* the guarded zone, and that placement is load-bearing
        // rather than tidiness: `Future.timeout`'s hold on the source only
        // absorbs an error the two share a zone for, and the daemon's do —
        // `_installErrorHandlers` sets `PlatformDispatcher.onError` and
        // everything then runs in the one root zone beneath it. A completer
        // made outside this one escapes, and the row would be reporting on
        // where the harness put it rather than on what `_step` does.
        final stalled = Completer<void>();
        harness.disposeControllers = () async {
          harness.record('dispose controllers');
          await stalled.future;
        };

        await harness.lifecycle.shutdown();
        stalled.completeError(StateError('the controllers failed, late'));
        await pumpEventQueue();
      }, (Object error, StackTrace stack) => escaped.add(error));

      expect(escaped, isEmpty);
      expect(harness.steps.last, 'close lock');
      final errors = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(
        errors,
        hasLength(1),
        reason:
            'one line, for our own expiry — the rejection arrived after the '
            'step was already abandoned and there is nothing left to report it '
            'as',
      );
      expect(errors.single.context, {
        'timeout_ms': _stallStepTimeout.inMilliseconds,
      });
    });

    test('AD-14: a panel request arriving after step 1 was abandoned raises '
        'nothing — the panel must not be mapped on the way to exit(0)', () async {
      // Newly reachable, and only because of the bound: a `cancel()` that never
      // answered used to hang the whole teardown, so nothing could arrive here
      // afterwards. Abandoning it lets steps 2 to 11 run with the subscription
      // still delivering, and a press landing in that window would otherwise
      // reach the handler, read a graph that is being torn down, and put a
      // window on screen as the process exits.
      harness.showRequests = _UncancellableStream(
        harness.showRequestsController.stream,
      );
      harness.lifecycle.start();

      await expectLater(harness.lifecycle.shutdown(), completes);
      expect(
        harness.steps.last,
        'close lock',
        reason: 'the abandoned cancel did not stop the remaining steps',
      );

      harness.requestShow();
      await pumpEventQueue();

      expect(
        harness.showPanelCalls,
        0,
        reason:
            'the subscription really is still live — that is the point of this '
            'row — so the guard is the only thing standing between a late press '
            'and a mapped window',
      );
    });

    test(
      'AD-15: a logger that throws while reporting an abandoned step does '
      'not let the failure escape — the reporting channel is what broke',
      () async {
        final escaped = <Object>[];
        final throwing = ThrowingLogger();
        final stalled = Completer<void>();
        harness.loggerPort = throwing;
        harness.disposeControllers = () async {
          harness.record('dispose controllers');
          await stalled.future;
        };

        await runZonedGuarded(() async {
          await harness.lifecycle.shutdown();
        }, (Object error, StackTrace stack) => escaped.add(error));

        expect(
          throwing.attempts,
          ['info', 'error'],
          reason:
              'ThrowingLogger records every call attempted, so this proves the '
              'timeout arm fired rather than never running at all',
        );
        expect(
          escaped,
          isEmpty,
          reason:
              'a broken stderr must not be what stops the teardown; both signal '
              'handlers await this and then exit',
        );
        expect(
          harness.steps.last,
          'close lock',
          reason: 'and the address still goes back',
        );
      },
    );
  });
}

/// Records every lifecycle step in the order it ran, so the assertions above
/// are about sequence rather than mere occurrence.
final class _Harness {
  _Harness() {
    showRequestsController = StreamController<void>.broadcast(
      onCancel: () => record('cancel show requests'),
    );
    trayRequestsController = StreamController<void>.broadcast(
      onCancel: () => record('cancel tray requests'),
    );
    disposeControllers = () async => record('dispose controllers');
    closePanelVisibility = () async => record('close panel visibility');
    closeTray = () async => record('close tray');
    closeHotkeyRegistrar = () async => record('release hotkey grab');
    closeDatabase = () async => record('close database');
    closeConfigStore = () async => record('close config store');
    closeLock = () async => record('close lock');
    onShowRequest = () {
      showPanelCalls += 1;
      record('show panel');
    };
  }

  final List<String> steps = [];
  final FakeLogger logger = FakeLogger();

  /// The logger the lifecycle is actually given. Replaced before the lifecycle
  /// is built by the rows that need one which throws.
  late Logger loggerPort = logger;

  /// Replaced before the lifecycle is built by the rows that are *about* the
  /// bound. Everything else runs under one it cannot reach.
  Duration stepTimeout = _ampleStepTimeout;

  late final StreamController<void> showRequestsController;
  late final StreamController<void> trayRequestsController;
  late Future<void> Function() disposeControllers;
  late Future<void> Function() closePanelVisibility;
  late Future<void> Function() closeTray;
  late Future<void> Function() closeHotkeyRegistrar;
  late Future<void> Function() closeDatabase;
  late Future<void> Function() closeConfigStore;
  late Future<void> Function() closeLock;
  late void Function() onShowRequest;

  int showPanelCalls = 0;

  void record(String step) => steps.add(step);

  void requestShow() => showRequestsController.add(null);

  /// AD-12: the user picking the tray menu's open-panel entry.
  void requestPanelFromTray() => trayRequestsController.add(null);

  /// Replaced before the lifecycle is built by the one row that needs step 1's
  /// cancel to be *abandonable*. A broadcast controller cannot express that —
  /// its `onCancel` returns `void`, so there is nothing for step 1 to hang on.
  late Stream<void> showRequests = showRequestsController.stream;

  /// Built lazily so a test can replace a callback before the lifecycle
  /// captures it — and, since the bound was added, [stepTimeout], [loggerPort]
  /// and [showRequests] too. Every row that assigns one of those relies on
  /// nothing having touched this field yet.
  late final DaemonLifecycle lifecycle = DaemonLifecycle(
    showRequests: showRequests,
    trayRequests: trayRequestsController.stream,
    onShowRequest: () => onShowRequest(),
    disposeControllers: () => disposeControllers(),
    disposeGraph: () => record('dispose graph'),
    closePanelVisibility: () => closePanelVisibility(),
    closeTray: () => closeTray(),
    hotkey: _RecordingHotkey(() => record('dispose hotkey')),
    closeHotkeyRegistrar: () => closeHotkeyRegistrar(),
    closeDatabase: () => closeDatabase(),
    closeConfigStore: () => closeConfigStore(),
    closeLock: () => closeLock(),
    stepTimeout: stepTimeout,
    logger: loggerPort,
  );

  void dispose() {
    unawaited(showRequestsController.close());
    unawaited(trayRequestsController.close());
  }
}

/// A stream whose subscription's `cancel()` never completes, and which keeps
/// delivering afterwards.
///
/// Step 1 of the teardown awaits that cancel. Before the steps were bounded a
/// cancel like this hung the whole shutdown, so nothing could reach the panel
/// handler afterwards; abandoning it is exactly what lets steps 2 to 11 run
/// with a live subscription behind them, which is the state the guard in
/// `_raisePanel` exists for.
final class _UncancellableStream extends Stream<void> {
  _UncancellableStream(this._source);

  final Stream<void> _source;

  @override
  StreamSubscription<void> listen(
    void Function(void event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _UncancellableSubscription(
    _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

final class _UncancellableSubscription implements StreamSubscription<void> {
  _UncancellableSubscription(this._inner);

  final StreamSubscription<void> _inner;

  /// Never completes, and deliberately does not cancel [_inner]: a source that
  /// stopped delivering the moment cancellation was *requested* would model
  /// the opposite of the case here.
  @override
  Future<void> cancel() => Completer<void>().future;

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(void data)? handleData) =>
      _inner.onData(handleData);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

/// A `GlobalHotkey` whose only job is to say when it was disposed relative to
/// everything else. The shared fake records disposal as a flag, which cannot
/// express order.
final class _RecordingHotkey implements GlobalHotkey {
  _RecordingHotkey(this._onDispose);

  final void Function() _onDispose;

  @override
  Stream<void> get activations => const Stream<void>.empty();

  @override
  Stream<HotkeyBindOutcome> get bindingChanges =>
      const Stream<HotkeyBindOutcome>.empty();

  /// Nothing in this suite reads it: the rows here are about disposal order.
  @override
  HotkeyStatus? get current => null;

  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) async =>
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'not part of this suite',
      );

  @override
  Future<void> dispose() async => _onDispose();
}

/// Stands in for a vendor exception whose `toString()` carries the payload
/// that caused it — the reason the [Logger] port bans logging one.
final class _PayloadCarryingError implements Exception {
  @override
  String toString() => 'failed while writing: the user private clipboard text';
}
