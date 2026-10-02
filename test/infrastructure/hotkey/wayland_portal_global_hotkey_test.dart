import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';
import '../../fakes/throwing_logger.dart';
import '../../support/fake_global_shortcuts_portal.dart';
import '../../support/value_equality.dart';

/// The Wayland adapter's whole contract, over a **real D-Bus wire**.
///
/// These rows replaced `stub_hotkey_adapters_test.dart`'s. That file's own doc
/// promised that "the day either grows a real backend, its half of this suite is
/// what says the degradation was replaced rather than merely renamed"; story 7
/// took the X11 half and this takes the last one, so the file is gone. A stub row
/// still passing here would mean the backend was never wired.
///
/// Nothing is mocked at the Dart level: [FakeGlobalShortcutsPortal] is a real
/// service on a real in-process message bus, so AD-11's call order is asserted as
/// *messages the portal received*, in the order it received them — not as calls
/// on an abstraction of our own. That is why this story has no `HotkeyRegistrar`
/// -shaped seam: `package:dbus` is pure `dart:io` and ships its own bus, so the
/// test need that justifies a one-implementation abstraction is absent.
///
/// What this suite deliberately cannot say: that a real portal, a real
/// compositor or a real key press was ever involved. See
/// `test/platform/wayland_hotkey_live_test.dart`, which records that as owed.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  late FakeLogger logger;

  setUp(() => logger = FakeLogger());

  Future<FakeGlobalShortcutsPortal> startPortal({
    bool ownsDesktopPortal = true,
    bool ownsHostRegistry = true,
  }) async {
    final portal = await FakeGlobalShortcutsPortal.start(
      ownsDesktopPortal: ownsDesktopPortal,
      ownsHostRegistry: ownsHostRegistry,
    );
    // Registered first, so it runs last: an unclosed client or server does not
    // fail this suite, it hangs the process.
    addTearDown(portal.stop);
    return portal;
  }

  WaylandPortalGlobalHotkey buildOn(
    FakeGlobalShortcutsPortal portal, {
    Logger? withLogger,
    DBusClient? client,
    PortalAppIdRegime appIdRegime = PortalAppIdRegime.hostRegistry,
    Duration requestTimeout = _shippedCallBudget,
    void Function(String?)? onActivationToken,
  }) {
    final hotkey = WaylandPortalGlobalHotkey(
      client: client ?? portal.newClient(),
      appIdRegime: appIdRegime,
      requestTimeout: requestTimeout,
      logger: withLogger ?? logger,
      onActivationToken: onActivationToken,
    );
    addTearDown(hotkey.dispose);
    return hotkey;
  }

  List<({String level, String message, Map<String, Object?>? context})> linesAt(
    String level,
  ) => logger.lines.where((line) => line.level == level).toList();

  List<({String level, String message, Map<String, Object?>? context})>
  errors() => linesAt('error');

  group('the handshake (CAP-1, AD-10, AD-11)', () {
    test('AD-10: a grant without wording is re-read from the compositor '
        'before the bind is shown as active', () async {
      final portal = await startPortal();
      portal.omitBindTriggerDescription = true;
      portal.listShortcutsDescription = 'Super+Space';
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyBound>());
      expect(hotkey.current?.backendDescription, 'Super+Space');
      expect(portal.callOrder.last, 'GlobalShortcuts.ListShortcuts');
    });

    test('AD-10: a compositor that still offers no wording leaves the '
        'shortcut active without inventing a description', () async {
      final portal = await startPortal();
      portal.omitBindTriggerDescription = true;
      portal.listShortcutsDescription = null;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyBound>());
      expect(hotkey.current?.backendDescription, isNull);
      expect(linesAt('info').last.message, contains('without describing'));
    });

    test('CAP-13: a refused description re-read does not undo a granted '
        'shortcut', () async {
      final portal = await startPortal();
      portal.omitBindTriggerDescription = true;
      portal.refuseListShortcuts = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyBound>());
      expect(hotkey.current?.backendDescription, isNull);
      expect(errors().last.message, contains('re-read'));
    });

    test('AD-11: the application id is the reverse-DNS spelling, literally', () {
      // Every other assertion in this suite compares the value that reached the
      // wire against this same constant, so all of them stay green through a
      // rename, a typo or a case shift — of the one string that decides whether
      // Wayland hotkeys work at all. AD-11 requires reverse-DNS *and* an
      // installed `.desktop` file of the same basename, so the literal is what
      // the packaging story has to match.
      expect(
        WaylandPortalGlobalHotkey.applicationId,
        'com.divertedriver.HotkeyGrammarCorrector',
      );
      expect(WaylandPortalGlobalHotkey.shortcutId, 'toggle-panel');
    });

    test('A1 CAP-1, AD-10, AD-11: a first bind performs exactly Register, '
        'CreateSession, BindShortcuts, in that order and nothing else', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);

      final register = portal.calls[0];
      expect(register.stringAt(0), WaylandPortalGlobalHotkey.applicationId);
      expect(
        register.path,
        FakeGlobalShortcutsPortal.registryPath,
        reason: 'AD-11 names the path as well as the method',
      );
      expect(
        register.values,
        hasLength(2),
        reason:
            'Registry.Register is `(s app_id, a{sv} options)`. A real '
            'xdg-desktop-portal answers a wrong-arity call with InvalidArgs, '
            'which this adapter tolerates as the advisory failure AD-11 makes '
            'it — so the app id would silently never be associated, GNOME would '
            'return an empty subset, and the user would be told to install a '
            '.desktop file they already have',
      );
      expect(register.optionsAt(1), isEmpty);

      final createSession = portal.calls[1];
      expect(
        createSession.optionsAt(0).keys,
        containsAll(const ['handle_token', 'session_handle_token']),
        reason: 'AD-11 requires both, and they are different things',
      );

      final bindShortcuts = portal.calls[2];
      expect(
        bindShortcuts.values[0],
        portal.currentSession,
        reason:
            'the session handle is read out of the CreateSession Response, not '
            'guessed from the token this side chose',
      );
      expect(bindShortcuts.shortcutsAt(1).keys, ['toggle-panel']);
      expect(
        bindShortcuts.shortcutsAt(1)['toggle-panel']!.keys,
        containsAll(const ['description', 'preferred_trigger']),
      );
      expect(
        bindShortcuts.shortcutsAt(1)['toggle-panel']!['description'],
        const DBusString('Show the grammar correction panel'),
        reason:
            'the value, not just the key: this string is the only human-readable '
            'label this app ever gives the shortcut, and it is what the portal '
            'permission dialog and the compositor shortcut list show the user',
      );
      expect(_triggerOf(bindShortcuts), 'CTRL+SHIFT+g');
      expect(
        bindShortcuts.stringAt(2),
        '',
        reason: 'no window of ours is involved; the portal parents its dialog',
      );

      expectSameValue(
        outcome,
        HotkeyBound(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );
      expect(
        (outcome as HotkeyBound).registration.effective,
        isNull,
        reason:
            'the portal reports the bound shortcut only as a localized '
            'trigger_description — there is no machine-readable combination in '
            'the reply, which is exactly AD-10 null case',
      );
      expect(errors(), isEmpty);
      expect(
        linesAt('info'),
        hasLength(1),
        reason:
            'while `effective` is always null, this line is the only record '
            'anywhere of the combination the compositor actually put in force',
      );
      expect(linesAt('info').single.message, _boundLine);
      expect(linesAt('info').single.context, {
        'trigger_description': 'Ctrl+Shift+G',
      });
    });

    test('A2 AD-11: a Registry that answers any of the four "there is no such '
        'thing" names is tolerated — the sequence continues and nothing is '
        'logged as an error', () async {
      // All four, not just UnknownMethod. Which one a portal without the
      // Registry answers with is not something this project can settle, and
      // `_messageFor` already treats UnknownMethod and UnknownInterface as one
      // class on exactly that ground. Settling it the other way here would put
      // an error line on the happy path of every launch — on the one signal this
      // code itself calls the likeliest cause of a later discard — and would
      // trip `daemon_startup_test.dart`'s no-warning row.
      for (final errorName in const [
        'org.freedesktop.DBus.Error.UnknownMethod',
        'org.freedesktop.DBus.Error.UnknownInterface',
        'org.freedesktop.DBus.Error.UnknownObject',
        'org.freedesktop.DBus.Error.ServiceUnknown',
      ]) {
        logger.lines.clear();
        final portal = await startPortal();
        portal.registerError = errorName;
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect(portal.callOrder, [
          'Registry.Register',
          'GlobalShortcuts.CreateSession',
          'GlobalShortcuts.BindShortcuts',
        ], reason: errorName);
        expect(outcome, isA<HotkeyBound>(), reason: errorName);
        expect(
          errors(),
          isEmpty,
          reason:
              'xdg-desktop-portal before 1.20 has no Registry at all, so '
              '$errorName is the tolerated case rather than a recovery',
        );
      }
    });

    test('A3 AD-11: a session where nobody owns the host portal name is the '
        'same tolerated case', () async {
      final portal = await startPortal(ownsHostRegistry: false);
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(portal.callOrder, [
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(outcome, isA<HotkeyBound>());
      expect(errors(), isEmpty);
    });

    test('A4 AD-11: a Registry that refuses some other way logs the error type '
        'and the sequence still continues', () async {
      final portal = await startPortal();
      portal.registerError = 'org.freedesktop.DBus.Error.AccessDenied';
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(
        outcome,
        isA<HotkeyBound>(),
        reason:
            'AD-12 names only CreateSession and BindShortcuts as the steps '
            'whose failure means no hotkey; Register is advisory app-id '
            'association',
      );
      expect(errors(), hasLength(1));
      expect(
        errors().single.context,
        {'error_type': 'DBusAccessDeniedException'},
        reason: 'the type only — a vendor error toString carries its payload',
      );
    });

    test('AD-11: a Registry that answers Register in a shape this build cannot '
        'read is logged, and the handshake still completes — twice', () async {
      // The one Register answer that is neither a refusal nor a dead socket:
      // `package:dbus` raises `DBusReplySignatureException` for an
      // out-argument, and that type implements `Exception` directly rather than
      // extending `DBusMethodResponseException`, so it lands in the adapter's
      // catch-all rather than its refusal arm. When that arm latched the
      // connection dead, one non-conformant reply from an *advisory* step
      // answered every later bind() for the life of the process without
      // touching the bus — the opposite of AD-11, which makes only CreateSession
      // and BindShortcuts fatal.
      final portal = await startPortal();
      portal.answerRegisterWithAnExtraValue = true;
      final hotkey = buildOn(portal);

      final first = await hotkey.bind(_ctrlShiftG);

      expect(
        portal.callOrder,
        [
          'Registry.Register',
          'GlobalShortcuts.CreateSession',
          'GlobalShortcuts.BindShortcuts',
        ],
        reason: 'step 1 is advisory: its answer must not stop steps 2 and 3',
      );
      expect(first, isA<HotkeyBound>());
      expect(errors(), hasLength(1));
      expect(errors().single.context, {
        'error_type': 'DBusReplySignatureException',
      });

      // And the second bind, which is where a latched connection showed: it
      // would have answered before reaching the bus at all.
      portal.calls.clear();
      final second = await hotkey.bind(_altSpace);

      expect(second, isA<HotkeyBound>());
      expect(portal.callOrder, [
        'Session.Close',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
    });

    test('ARCH-02: a sandboxed build performs no Register at all, and binds '
        'without it', () async {
      // The specification is blunter than AD-11 is: the host registry "will
      // not work with applications xdg-desktop-portal identifies as
      // sandboxed", because inside the sandbox the portal derives the app id
      // from the sandbox metadata. So this is not an optimisation that saves a
      // round trip — a Register from inside a sandbox is a claim this process
      // is not entitled to make, and on a real portal it is an error line on
      // every launch.
      final portal = await startPortal();
      final hotkey = buildOn(
        portal,
        appIdRegime: PortalAppIdRegime.sandboxSupplied,
      );

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(portal.callOrder, [
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(
        portal.callOrder,
        isNot(contains('Registry.Register')),
        reason:
            'the skipped step is what this row exists for; the two that remain '
            'are here so a branch that skipped the whole handshake could not '
            'pass it',
      );
      expect(outcome, isA<HotkeyBound>());
      expect(
        logger.lines.where((line) => line.message.contains('registry')),
        isEmpty,
        reason:
            'nothing happened, so nothing may be reported as having happened '
            '— a log line about an association that was never attempted sends '
            'the next reader after a call that is not on the wire',
      );
    });

    test('ARCH-02: a sandboxed rebind is as silent as the first bind, so the '
        'latch is not what is doing the work', () async {
      // The regime check sits ahead of the once-per-connection latch rather
      // than in place of it. If it sat behind, the first bind would still
      // Register and only the second would be silent, which is the opposite of
      // what the specification asks for.
      final portal = await startPortal();
      final hotkey = buildOn(
        portal,
        appIdRegime: PortalAppIdRegime.sandboxSupplied,
      );
      await hotkey.bind(_ctrlShiftG);
      portal.calls.clear();

      final outcome = await hotkey.bind(_altSpace);

      expect(portal.callOrder, [
        'Session.Close',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(outcome, isA<HotkeyBound>());
    });

    test('A5 CAP-12: a rebind closes the old session, creates a new one, and '
        'issues no second Register — no restart involved', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      await hotkey.bind(_ctrlShiftG);
      final firstSession = portal.currentSession;
      portal.calls.clear();

      final outcome = await hotkey.bind(_altSpace);

      expect(portal.callOrder, [
        'Session.Close',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(
        portal.callOrder,
        isNot(contains('Registry.Register')),
        reason: 'AD-11 says once, and the association is per connection',
      );
      expect(_triggerOf(portal.calls[2]), 'ALT+space');
      expect(portal.currentSession, isNot(firstSession));
      expect(
        portal.calls[2].values[0],
        portal.currentSession,
        reason: 'the new bind goes to the new session, not the closed one',
      );
      expect(
        portal.openSessions,
        1,
        reason:
            'the portal only lets a session be bound once, so a rebind that '
            'kept the old one would leave the compositor holding two shortcuts',
      );
      expect(outcome, isA<HotkeyBound>());

      // The half a rebind row is not obviously about, and the one that decides
      // whether CAP-12 is worth anything: step 4 is subscribed once and never
      // rebuilt, so the *only* thing that lets a press through after a rebind is
      // the filter reading the current session handle at delivery time. Pinned
      // by nothing before: A16 presses after a first bind, and A6 presses after
      // an *abandoned* rebind, where the surviving session is the original one —
      // so a filter frozen at subscribe time passed both while dropping every
      // press the user's new hotkey produces, for the life of the daemon.
      await _settle();
      await portal.emitActivated();
      await _settle();

      expect(
        activations,
        hasLength(1),
        reason: 'the new session is the one that now reaches the panel',
      );
      logger.lines.clear();
      await portal.emitShortcutsChanged();
      await _settle();

      expect(
        linesAt('info'),
        hasLength(1),
        reason:
            'and the ShortcutsChanged half of step 4 follows the session too',
      );
    });

    test('A6 AD-10: a Session.Close refused mid-rebind abandons the rebind, '
        'and the session that is still live keeps delivering', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await hotkey.bind(_ctrlShiftG);
      final previousDescription = hotkey.current?.backendDescription;
      final liveSession = portal.currentSession;
      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      portal.calls.clear();
      portal.refuseSessionClose = true;

      final outcome = await hotkey.bind(_altSpace);

      expect(
        portal.callOrder,
        ['Session.Close'],
        reason:
            'no CreateSession is issued: two live sessions is the worse '
            'failure, and one press would then toggle the panel twice',
      );
      expectSameValue(
        outcome,
        HotkeyRetained(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );
      expect(hotkey.current?.outcome, outcome);
      expect(hotkey.current?.backendDescription, previousDescription);
      expect(errors(), hasLength(1));
      expect(errors().single.context, {'error_type': 'DBusFailedException'});
      expect(
        portal.openSessions,
        1,
        reason:
            'the abandoned rebind created nothing, so exactly the session that '
            'was already live is what remains',
      );

      await portal.emitActivated(session: liveSession);
      await _settle();

      expect(
        activations,
        hasLength(1),
        reason:
            'the abandoned rebind left the previous session in effect, so it is '
            'still the one that reaches the panel',
      );
      await portal.emitShortcutsChanged(shortcutIds: const []);
      await _settle();
      expect(
        hotkey.current?.outcome,
        isA<HotkeyUnavailable>().having(
          (value) => value.cause,
          'cause',
          HotkeyUnavailableCause.revoked,
        ),
      );
      expect(hotkey.current?.backendDescription, isNull);
    });

    test('AD-10: a Close the portal answers with UnknownObject means the '
        'session is gone, so the rebind goes ahead rather than reporting a '
        'shortcut that is not bound', () async {
      // The opposite of A6 despite sharing its shape, and the distinction is
      // the whole point: `Failed` is a live session the portal would not let go
      // of, and `UnknownObject` is a session that no longer exists — an
      // `xdg-desktop-portal` restart, routine on a session update, takes every
      // session with it. Reading the second as "the previous shortcut is still
      // in effect" restores a dead handle and answers HotkeyBound for a
      // shortcut bound to nothing, on every later rebind too, because the arm
      // is reached identically each time.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await hotkey.bind(_ctrlShiftG);
      final deadSession = portal.currentSession;
      portal.calls.clear();
      portal.refuseSessionClose = true;
      portal.sessionCloseError = 'org.freedesktop.DBus.Error.UnknownObject';

      final outcome = await hotkey.bind(_altSpace);

      expect(
        portal.callOrder,
        [
          'Session.Close',
          'GlobalShortcuts.CreateSession',
          'GlobalShortcuts.BindShortcuts',
        ],
        reason: 'there was nothing left to close, so nothing was abandoned',
      );
      expect(outcome, isA<HotkeyBound>());
      expect(
        portal.currentSession,
        isNot(deadSession),
        reason: 'the reported bind is against the session that exists',
      );
      expect(_triggerOf(portal.calls[2]), 'ALT+space');
      expect(
        errors(),
        isEmpty,
        reason:
            'a portal reporting a session it no longer holds is a fact about '
            'the portal, not a failure of ours',
      );
      expect(
        linesAt('info').where(
          (line) => line.message.contains(
            'no longer '
            'exists',
          ),
        ),
        hasLength(1),
      );
    });

    test('AD-12: an xdg-desktop-portal restart between binds does not park the '
        'rebind — the Response from the new portal still arrives', () async {
      // The row above models a lost session by injecting `UnknownObject` from
      // the *same* portal instance, so the bus identity never changes — and bus
      // identity is precisely what a sender-filtered match rule is built on. A
      // real restart brings the well-known name back on a **new unique name**,
      // and a rule still naming the old one matches nothing that will ever be
      // remapped, because `package:dbus` keys its name-owner cache by
      // well-known names. Measured before the sender was resolved per call: the
      // second `CreateSession` reached the new portal, its `Response` was
      // dropped on the floor, and `bind()` never resolved — and since binds are
      // chained on one queue, every later bind was parked behind it too.
      // `SettingsController.changeHotkey` awaits `bind()` with no timeout, so
      // that is a settings screen that never comes back.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await hotkey.bind(_ctrlShiftG);
      await portal.restartPortalService();
      portal.calls.clear();

      final outcome = await hotkey.bind(_altSpace).timeout(_answerBudget);

      expect(outcome, isA<HotkeyBound>());
      expect(portal.callOrder, contains('GlobalShortcuts.BindShortcuts'));
      expect(_triggerOf(portal.calls.last), 'ALT+space');
      expect(
        await hotkey.bind(_ctrlShiftG).timeout(_answerBudget),
        isA<HotkeyBound>(),
        reason: 'and the queue behind it was never poisoned',
      );
    });

    test('AD-12: a rebind whose Session.Close fails on the transport reports '
        'unavailable, not "the previous shortcut is still in effect"', () async {
      // The one bus-touching path that read every failure as a portal refusal.
      // "The previous shortcut is still in effect" is a claim about a live
      // session behind a live connection, and a dead socket is neither:
      // measured, this arm answered `HotkeyBound` with **zero** calls on the
      // wire, and because it is reached identically each time it would answer
      // that forever, while `SettingsController` persisted a binding nothing
      // holds and the tray went on reporting hotkeys available.
      final portal = await startPortal();
      final hotkey = buildOn(
        portal,
        client: portal.newClientWhoseTransportFailsAt(
          'Close',
          const SocketException('the session bus went away'),
        ),
      );
      await hotkey.bind(_ctrlShiftG);
      portal.calls.clear();

      final outcome = await hotkey.bind(_altSpace);

      expect(outcome, isA<HotkeyUnavailable>());
      expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      expect(
        portal.calls,
        isEmpty,
        reason: 'no new session was created against a connection that is gone',
      );
      expect(
        await hotkey.bind(_ctrlShiftG),
        isA<HotkeyUnavailable>(),
        reason: 'and it stays a value rather than reverting to a false success',
      );
    });
  });

  group('every way the portal can refuse (AD-12)', () {
    test('A7 AD-12: no session bus is a value, and no portal call is made at '
        'all', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal, client: portal.clientForNoBus());

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('session bus'));
      expect(
        outcome.message,
        contains('tray menu'),
        reason: 'AD-12 keeps the app usable and the message says how',
      );
      expect(portal.calls, isEmpty);
      expect(
        errors(),
        isEmpty,
        reason:
            'one missing bus is one diagnosis: the Register step must not also '
            'report that the registry refused the application id',
      );
    });

    test('AD-12: a second bind after an unreachable bus resolves too, rather '
        'than waiting on a connection that will never come back', () async {
      // Not hypothetical and not cosmetic. `package:dbus` `_connect()` assigns
      // its completer before awaiting the socket and never completes it when
      // that throws, so on the unpatched code every later call on that client
      // waits on a completer nobody will complete.
      // `SettingsController._bind` has no timeout, so a user who opens the
      // settings screen on a session with no bus and changes the hotkey would
      // get a screen that never resolves.
      final portal = await startPortal();
      final hotkey = buildOn(portal, client: portal.clientForNoBus());

      final first = await hotkey.bind(_ctrlShiftG);
      final second = await hotkey.bind(_altSpace);

      expect((first as HotkeyUnavailable).message, contains('session bus'));
      expect(
        second,
        first,
        reason:
            'the same cause, so the same sentence — and answered rather than '
            'left pending',
      );
      expect(portal.calls, isEmpty);
    });

    test(
      'AD-12: a socket that dies after Register is latched, so the bind '
      'after it answers instead of waiting on a connection that is gone',
      () async {
        // A socket that dies *after* step 1 — a bus restart, a dropped socket
        // between binds — where every other refusal row loses the bus before the
        // first call goes out. What this pins is the answer: both binds resolve
        // with one sentence, and the second reaches the portal zero times.
        //
        // What it deliberately does **not** claim to pin is the dead-connection
        // latch on this path, and that was measured rather than assumed: removing
        // the latch here fails nothing, and so does widening it back. The latch
        // exists for a `package:dbus` state — a `_connectCompleter` left
        // uncompleted by a failed *initial* connect — that no injected client can
        // reproduce, because a client that never connected always fails at
        // `Register` first, where the latch already has a row. So the latch on
        // this arm is defensive, its mutation gate fails zero, and that is
        // recorded here rather than left to look pinned.
        final portal = await startPortal();
        final hotkey = buildOn(
          portal,
          client: portal.newClientWhoseSocketDiesAtCreateSession(),
        );

        final first = await hotkey.bind(_ctrlShiftG);
        expect(portal.callOrder, ['Registry.Register']);
        expect((first as HotkeyUnavailable).message, contains('session bus'));

        portal.calls.clear();
        final second = await hotkey
            .bind(_altSpace)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => fail('the second bind never resolved'),
            );

        expect(second, first, reason: 'the same cause, so the same sentence');
        expect(
          portal.calls,
          isEmpty,
          reason: 'and answered without asking a connection that cannot answer',
        );
      },
    );

    test('A8 AD-12: no desktop portal on the session names the missing '
        'portal', () async {
      final portal = await startPortal(ownsDesktopPortal: false);
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(
        (outcome as HotkeyUnavailable).message,
        contains('desktop portal'),
      );
      expect(outcome.message, contains('tray menu'));
      expect(
        portal.callOrder,
        ['Registry.Register'],
        reason: 'step 1 still reached the host registry, which is owned',
      );
    });

    test('A9 AD-12: a compositor whose portal provides no GlobalShortcuts '
        'backend degrades visibly — the wlroots case', () async {
      // Both error names, because which one a backend-less portal answers with
      // is not something this container can settle: an
      // xdg-desktop-portal with no GlobalShortcuts implementation may answer
      // either, and only GNOME and KDE ship one at all.
      for (final errorName in const [
        'org.freedesktop.DBus.Error.UnknownMethod',
        'org.freedesktop.DBus.Error.UnknownInterface',
      ]) {
        final portal = await startPortal();
        portal.createSessionError = errorName;
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect(
          (outcome as HotkeyUnavailable).message,
          contains('no global shortcuts portal'),
          reason: '$errorName must reach the same sentence',
        );
        expect(outcome.message, contains('tray menu'));
        expect(
          portal.callOrder,
          isNot(contains('GlobalShortcuts.BindShortcuts')),
        );
      }
    });

    test('A10 AD-12: a dismissed portal dialog is a non-zero Response, not an '
        'exception, and no BindShortcuts follows it', () async {
      final portal = await startPortal();
      portal.createSessionResponseCode = 1;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyUnavailable>());
      expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      expect(
        outcome.message,
        isNot(contains('dialog')),
        reason:
            'the GlobalShortcuts portal shows its dialog on BindShortcuts, not '
            'on CreateSession, so a message naming one here would send the user '
            'hunting for something they were never shown',
      );
      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
      ]);
    });

    test('A11 AD-12: a Response carrying no session_handle is a value, and no '
        'BindShortcuts is issued', () async {
      final portal = await startPortal();
      portal.omitSessionHandle = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      expect(
        portal.callOrder,
        isNot(contains('GlobalShortcuts.BindShortcuts')),
      );
    });

    test(
      'A12 AD-11, AD-12: a bind the compositor discards comes back as an '
      'empty shortcut set, and names the app id and its .desktop entry',
      () async {
        final portal = await startPortal();
        portal.boundShortcutIds = const [];
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect(
          outcome,
          isA<HotkeyUnavailable>(),
          reason:
              'the portal documents the returned shortcuts as a subset of what '
              'was passed in, explicitly including the empty set — so a '
              'successful reply without our id is not a bind',
        );
        expect(
          (outcome as HotkeyUnavailable).message,
          contains(WaylandPortalGlobalHotkey.applicationId),
        );
        expect(
          outcome.message,
          contains('.desktop'),
          reason:
              'this is how GNOME reports a bind it dropped for an app id with no '
              'installed desktop entry, and the message has to say so',
        );
        expect(outcome.message, contains('tray menu'));
        expect(
          portal.callOrder.last,
          'Session.Close',
          reason:
              'the session was created before the bind was discarded, so the '
              'refusal has to hand it back',
        );
        expect(
          portal.openSessions,
          0,
          reason:
              'this is the path a real GNOME session takes on every bind until '
              'the packaging story ships the .desktop file, so a settings '
              'screen retried a few times would otherwise leave the compositor '
              'holding a handful of live sessions',
        );
      },
    );

    test('AD-11: four discarded binds in a row leave nothing open, and dispose '
        'has nothing left to close', () async {
      // The counting version of the row above, because one leak and four leaks
      // fail the same single-session assertion for different reasons.
      final portal = await startPortal();
      portal.boundShortcutIds = const [];
      final hotkey = buildOn(portal);

      for (var attempt = 0; attempt < 4; attempt += 1) {
        expect(await hotkey.bind(_ctrlShiftG), isA<HotkeyUnavailable>());
        expect(portal.openSessions, 0, reason: 'after attempt $attempt');
      }

      expect(
        portal.callOrder.where((label) => label == 'Session.Close'),
        hasLength(4),
        reason: 'one Close per session created',
      );
      await hotkey.dispose();
      expect(portal.openSessions, 0);
    });

    test('A13 AD-11: a read-back carrying only somebody else\'s id is the same '
        'answer', () async {
      final portal = await startPortal();
      portal.boundShortcutIds = const ['some-other-id'];
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(
        (outcome as HotkeyUnavailable).message,
        contains(WaylandPortalGlobalHotkey.applicationId),
      );
      expect(portal.openSessions, 0);
    });

    test('A13b AD-12: a read-back with no shortcuts list at all is a malformed '
        'reply, and still not a bind', () async {
      // Distinct from A12/A13 on purpose: an empty list is the portal telling us
      // which shortcuts it holds, and a missing one is it telling us nothing
      // this build can read. Both refuse, and neither leaves a session behind.
      final portal = await startPortal();
      portal.omitShortcutsFromResponse = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('cannot read'));
      expect(portal.openSessions, 0);
    });

    test('AD-12: a shortcuts list whose elements are not (sa{sv}) is reported '
        'as unreadable, not as the .desktop discard', () async {
      // The element-signature check, which no fixture reached before: A12/A13
      // send a well-formed list, A13b sends none at all. Without it an `a(ss)`
      // list reads as the *empty* set — the documented discard — so the user
      // would be told to install `com.divertedriver.HotkeyGrammarCorrector
      // .desktop` on the strength of a reply that said nothing about the app id.
      final portal = await startPortal();
      portal.shortcutListUsesWrongElementSignature = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('cannot read'));
      expect(
        outcome.message,
        isNot(contains('.desktop')),
        reason: 'nothing was learned about the application id',
      );
      expect(outcome.message, contains('tray menu'));
      expect(portal.openSessions, 0);
    });

    test('AD-12: a Response whose results dict is a{ss} is a value, and does '
        'not poison the connection', () async {
      // The one payload that makes `mapStringVariant()` throw a cast error
      // rather than return something merely wrong. Unchecked it escapes into
      // the request path catch-all, where it used to latch the client dead —
      // so one malformed reply would have answered every later bind without
      // touching the bus. Both halves are asserted.
      final portal = await startPortal();
      portal.responseResultsUseWrongDictSignature = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('cannot read'));
      expect(portal.openSessions, 0);

      portal.responseResultsUseWrongDictSignature = false;
      portal.calls.clear();

      expect(
        await hotkey.bind(_altSpace),
        isA<HotkeyBound>(),
        reason:
            'the connection was never the problem, so the next attempt must '
            'reach the bus',
      );
      expect(portal.callOrder, contains('GlobalShortcuts.BindShortcuts'));
    });

    test('A14 AD-12: a non-zero BindShortcuts Response is a value', () async {
      for (final code in const [1, 2]) {
        final portal = await startPortal();
        portal.bindShortcutsResponseCode = code;
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect(
          outcome,
          isA<HotkeyUnavailable>(),
          reason: 'response code $code',
        );
        expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
        expect(
          outcome.message,
          contains('dialog'),
          reason:
              'this is the step with a dialog behind it, so this is the message '
              'that may name one — the other half of the A10 assertion',
        );
        expect(
          portal.openSessions,
          0,
          reason: 'the session opened for this attempt is handed back',
        );
      }
    });

    test(
      'AD-12: a reply whose signature is not the one the portal documents is '
      'a value, not a cast error crossing the port',
      () async {
        final portal = await startPortal();
        portal.replyToCreateSessionWithWrongSignature = true;
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect(outcome, isA<HotkeyUnavailable>());
        expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      },
    );

    test('AD-12: a Response signal that is not the documented (u, a{sv}) is a '
        'value too', () async {
      final portal = await startPortal();
      portal.malformedCreateSessionResponse = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('cannot read'));
      expect(outcome.message, contains('tray menu'));
    });

    test(
      'AD-12: an unclassified portal failure is still a value, and it is the '
      'one case where the error type is the only clue there is',
      () async {
        final portal = await startPortal();
        portal.createSessionError = 'org.freedesktop.DBus.Error.Failed';
        final hotkey = buildOn(portal);

        final outcome = await hotkey.bind(_ctrlShiftG);

        expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
        expect(errors(), hasLength(1));
        expect(errors().single.context, {'error_type': 'DBusFailedException'});
      },
    );

    test('AD-12: a match-rule teardown that fails does not change the answer, '
        'and reaches the zone rather than the caller', () async {
      // Both halves are measurements rather than design. The `finally` that
      // cancels the Request subscription sits outside every catch in
      // `_callThroughRequest`, which looks like a hole in `bind()`'s
      // unconditional "never throws" — and is not one: `DBusSignalStream` is a
      // broadcast `StreamController`, and a broadcast controller **discards the
      // future its `onCancel` returns**, so a `RemoveMatch` that fails is
      // reported to the enclosing zone and no `try` at the call site can ever
      // see it. That is why the guard around the cancel cannot be pinned by an
      // outcome, and why what this row pins instead is the part this adapter does
      // control: the answer is unchanged. The stray zone error is a property of
      // the pinned package, recorded here rather than claimed as handled.
      final portal = await startPortal();
      final zoneErrors = <Object>[];
      HotkeyBindOutcome? outcome;

      await runZonedGuarded(() async {
        final hotkey = WaylandPortalGlobalHotkey(
          client: portal.newClientThatCannotRemoveMatchRules(),
          appIdRegime: PortalAppIdRegime.hostRegistry,
          requestTimeout: _shippedCallBudget,
          logger: logger,
        );
        outcome = await hotkey.bind(_ctrlShiftG);
        await hotkey.dispose();
      }, (error, stack) => zoneErrors.add(error));
      await _settle();

      expect(
        outcome,
        isA<HotkeyBound>(),
        reason:
            'the handshake itself succeeded; only the teardown of a match rule '
            'did not, and that must not undo the answer or reject out of bind()',
      );
      expect(
        zoneErrors,
        everyElement(isA<StateError>()),
        reason:
            'the injected RemoveMatch failure and nothing else — anything of '
            'another type would be this adapter losing an error of its own',
      );
      expect(
        zoneErrors,
        isNotEmpty,
        reason:
            'the row would be vacuous if the injection never fired; this is also '
            'the measurement itself, that the failure lands in the zone',
      );
    });

    test('A22 AD-12: bind after dispose is a value and reaches the portal zero '
        'times', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await hotkey.dispose();
      portal.calls.clear();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect((outcome as HotkeyUnavailable).message, contains('shut down'));
      expect(portal.calls, isEmpty);
    });

    test('A22 AD-12: and it still holds while a portal call is parked, which '
        'is the state A22 exists to cover', () async {
      // Binds are chained on one queue, so a call that never resolves — the
      // filed never-answering portal — parked every later answer behind it,
      // including the two that need no portal at all and that A22 says must
      // come back. Measured on the unpatched code: with `BindShortcuts` held,
      // a bind issued after `dispose()` never resolved.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final parked = Completer<void>();
      addTearDown(() {
        if (!parked.isCompleted) {
          parked.complete();
        }
      });
      portal.beforeBindShortcuts = () => parked.future;

      // Left in flight on purpose: closing the client under it means
      // `package:dbus` never completes it, which is the whole premise.
      hotkey.bind(_ctrlShiftG).ignore();
      await _settle();
      await hotkey.dispose();
      portal.calls.clear();

      final outcome = await hotkey.bind(_altSpace).timeout(_answerBudget);

      expect((outcome as HotkeyUnavailable).message, contains('shut down'));
      expect(portal.calls, isEmpty);
    });

    for (final (label, error) in <(String, Object)>[
      ('an OSError', const OSError('the socket is gone')),
      ('a DBusClosedException', DBusClosedException()),
    ]) {
      test('AD-12: $label from the transport is answered as a lost connection, '
          'not as a portal refusal', () async {
        // `_isConnectionFailure` names three types and decides whether a
        // failure costs one bind or every later one; only `SocketException`
        // had a fixture. The two consequences are separate and both bite: an
        // unrecognised transport failure is not latched, so the next bind waits
        // on a `package:dbus` completer nobody completes — and its sentence
        // falls through to "the desktop portal refused the global shortcut
        // request", which is then latched and shown for the life of the daemon,
        // sending the user after a permission they were never asked for.
        final portal = await startPortal();
        final hotkey = buildOn(
          portal,
          client: portal.newClientWhoseTransportFailsAt('CreateSession', error),
        );

        final first = await hotkey.bind(_ctrlShiftG).timeout(_answerBudget);
        portal.calls.clear();
        final second = await hotkey.bind(_altSpace).timeout(_answerBudget);

        expect((first as HotkeyUnavailable).message, contains('session bus'));
        expect(first.message, contains('tray menu'));
        expect(
          first.message,
          isNot(contains('portal refused')),
          reason: 'the portal refused nothing; the connection went away',
        );
        expect(second, first, reason: 'latched, so the same answer, at once');
        expect(
          portal.calls,
          isEmpty,
          reason: 'and reached without touching a connection that is gone',
        );
      });
    }

    test('AD-11: the Request Response subscription is cancelled after every '
        'portal call, so match rules do not accumulate per bind', () async {
      // Invisible in every other way — the bind answers identically whether or
      // not the `finally` cancels — while each skipped cancel leaks a live
      // `DBusSignalStream` and its bus match rule, for the life of the daemon,
      // with every leaked stream still handed every `Response` on the session
      // bus. Counting the rules is the only place it shows.
      final portal = await startPortal();
      final client = portal.newClient();
      final hotkey = buildOn(portal, client: client);

      await _bindAndSettle(hotkey, _ctrlShiftG);
      final liveAfterFirst = client.liveMatchRules;
      final callsAfterFirst = client.matchRuleCalls.length;
      await _bindAndSettle(hotkey, _altSpace);

      // The absolute count is not 2: `package:dbus` installs rules of its own on
      // connect, and how many is its business. What this adapter owns is the
      // delta, and the delta is the leak.
      expect(
        client.matchRuleCalls.length - callsAfterFirst,
        4,
        reason:
            'the rebind opens a Request subscription for CreateSession and one '
            'for BindShortcuts and closes both — two AddMatch and two '
            'RemoveMatch. The row is vacuous unless it really did',
      );
      expect(
        client.liveMatchRules,
        liveAfterFirst,
        reason:
            'step 4 subscribes once and is reused, so a rebind that left its '
            'Request rules behind would leak two per bind for the life of the '
            'daemon, each leaked stream still handed every Response on the bus',
      );
    });

    test('A26 CAP-12: a key that cannot be expressed as a trigger omits the '
        'preference instead of costing the user a shortcut', () async {
      // Deliberately the opposite of the X11 adapter, which refuses. There the
      // app owns the grab, so a key it cannot express is a shortcut that cannot
      // exist. Here the app owns nothing: preferred_trigger is a documented
      // hint, and the compositor and the user choose the combination.
      final portal = await startPortal();
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(
        HotkeyBinding(modifiers: {HotkeyModifier.control}, key: 'Compose'),
      );

      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      final shortcut = portal.calls[2].shortcutsAt(1)['toggle-panel']!;
      expect(shortcut.keys, ['description']);
      expect(shortcut.containsKey('preferred_trigger'), isFalse);
      expect(outcome, isA<HotkeyBound>());
      expect(
        linesAt('info').where((line) => line.context?['key'] == 'Compose'),
        hasLength(1),
        reason: 'not an error, but the user asked for something we dropped',
      );
      expect(errors(), isEmpty);
    });
  });

  group('the Request race and the token discipline (CAP-1, AD-11)', () {
    test('A15 CAP-1: a Response emitted before the method reply is still '
        'received — the subscription precedes the call', () async {
      // The portal's Request convention exists because of this documented race.
      // Subscribing after the reply loses a signal that was already emitted, and
      // bind() would then never resolve at all.
      final portal = await startPortal();
      portal.respondBeforeReply = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyBound>());
      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
    });

    test('CAP-1: a Response forged by another peer on the same bus is ignored, '
        'and the session the bind uses is the one the portal issued', () async {
      // The Request stream's counterpart to the forged-Activated row. It
      // matched on object path alone, and the stated substitute for a sender
      // rule — that the path carries a random token — is a guessing budget, not
      // an authenticator; measured, a client owning no name forged a Response
      // and the adapter reported HotkeyBound. Here the impostor emits first,
      // with a correct response code on the right path, offering a session
      // handle the portal never issued. Everything about it is right except who
      // sent it.
      final portal = await startPortal();
      portal.forgeCreateSessionResponseFromImpostor = true;
      final hotkey = buildOn(portal);

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyBound>());
      expect(
        portal.calls
            .firstWhere((call) => call.member == 'BindShortcuts')
            .values[0],
        portal.currentSession,
        reason:
            'the handle came from the portal, not from the first peer to shout '
            'a Response at the right object path',
      );
      expect(
        portal.calls
            .firstWhere((call) => call.member == 'BindShortcuts')
            .values[0],
        isNot(FakeGlobalShortcutsPortal.forgedSessionHandle),
      );
    });

    test('A25 AD-11: every handle token the portal received is distinct and is '
        'a valid object path segment', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await hotkey.bind(_ctrlShiftG);
      await hotkey.bind(_altSpace);

      final tokens = <String>[];
      for (final call in portal.calls) {
        switch (call.member) {
          case 'CreateSession':
            final options = call.optionsAt(0);
            tokens.add((options['handle_token']! as DBusString).value);
            tokens.add((options['session_handle_token']! as DBusString).value);
          case 'BindShortcuts':
            final options = call.optionsAt(3);
            tokens.add((options['handle_token']! as DBusString).value);
        }
      }

      expect(tokens, hasLength(6));
      expect(
        tokens.toSet(),
        hasLength(6),
        reason:
            'a reused handle_token collides with a live Request object path, '
            'and a reused session_handle_token with a live session',
      );
      expect(
        tokens,
        everyElement(matches(RegExp(r'^[A-Za-z0-9_]+$'))),
        reason: 'the portal builds an object path segment out of the token',
      );
    });

    test('A23 CAP-12: two overlapping binds are serialized, and exactly one '
        'session survives', () async {
      // Unserialized these interleave, and the portal's "a session can only be
      // bound once" rule means the two cannot share a session: the compositor
      // would end up holding two, with only one of them filtered in.
      // `SettingsController.changeHotkey` has no in-flight guard of its own, and
      // a portal dialog makes the window seconds wide by design.
      final portal = await startPortal();
      final hotkey = buildOn(portal);

      final outcomes = await Future.wait([
        hotkey.bind(_ctrlShiftG),
        hotkey.bind(_altSpace),
      ]);

      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
        'Session.Close',
        'GlobalShortcuts.CreateSession',
        'GlobalShortcuts.BindShortcuts',
      ]);
      expect(outcomes, everyElement(isA<HotkeyBound>()));
      expect(portal.openSessions, 1);
      expect(
        _triggerOf(portal.calls.last),
        'ALT+space',
        reason: 'the last request issued is the one that ends up in effect',
      );
    });
  });

  group('activations (CAP-1, AD-8, AD-11)', () {
    test(
      'CAP-1: fresh portal tokens are prepared before activation listeners',
      () async {
        final portal = await startPortal();
        final prepared = <String?>[];
        final observed = <String?>[];
        final hotkey = buildOn(portal, onActivationToken: prepared.add);
        hotkey.activations.listen((_) => observed.add(prepared.last));
        await _bindAndSettle(hotkey, _ctrlShiftG);

        await portal.emitActivated(
          options: {'activation_token': const DBusString('fresh')},
        );
        await portal.emitActivated();
        await portal.emitActivated(
          options: {'activation_token': const DBusUint32(12)},
        );
        await portal.emitActivated(
          options: {'activation_token': const DBusString('')},
        );
        await _settle();

        expect(prepared, ['fresh', null, null, null]);
        expect(observed, prepared);
      },
    );

    test(
      'CAP-1: another shortcut, session, or sender cannot prepare a token',
      () async {
        final portal = await startPortal();
        final prepared = <String?>[];
        final hotkey = buildOn(portal, onActivationToken: prepared.add);
        await _bindAndSettle(hotkey, _ctrlShiftG);
        final options = {'activation_token': const DBusString('foreign')};

        await portal.emitActivated(
          session: DBusObjectPath('/other/session'),
          options: options,
        );
        await portal.emitActivated(
          shortcutId: 'other-shortcut',
          options: options,
        );
        await portal.emitActivatedFromImpostor();
        await _settle();

        expect(prepared, isEmpty);
        await portal.emitActivated(options: options);
        await _settle();
        expect(prepared, ['foreign']);
      },
    );

    test('A16 CAP-1: a press reaches every listener exactly once', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final first = <void>[];
      final second = <void>[];
      // Two listeners: a single-subscription stream would throw on the second,
      // and PanelController is not promised to be the only consumer.
      hotkey.activations.listen(first.add);
      hotkey.activations.listen(second.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitActivated();
      await _settle();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('A17 CAP-1: a press for another session, or another shortcut id, '
        'reaches nobody', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitActivated(
        session: DBusObjectPath(
          '/org/freedesktop/portal/desktop/session/other',
        ),
      );
      await portal.emitActivated(shortcutId: 'some-other-id');
      await _settle();

      expect(
        fired,
        isEmpty,
        reason:
            'AD-11 requires the filter on both the session handle and the '
            'shortcut id, and this process may hold neither',
      );
    });

    test('CAP-1: an Activated forged by another peer on the same bus reaches '
        'nobody, however right its arguments are', () async {
      // The only row that can tell a sender-filtered subscription from an
      // unfiltered one: the session handle and the shortcut id are both correct,
      // and only the sender is wrong. Without the filter any process on the
      // session bus could raise a panel that reads the clipboard, and every other
      // activation row would stay green — the fake emits from the portal's own
      // name.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitActivatedFromImpostor();
      await _settle();

      expect(fired, isEmpty);

      // And the control, so the row cannot pass because the bus dropped every
      // signal: the same arguments from the portal itself do fire.
      await portal.emitActivated();
      await _settle();

      expect(fired, hasLength(1));
    });

    test('A18 AD-11: a press delivered before BindShortcuts reaches nobody — '
        'step 4 does not exist yet', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      // After the CreateSession Response, so the session exists and the signal
      // carries the handle the adapter is about to hold — and still before the
      // subscription that would deliver it.
      portal.beforeBindShortcuts = () async {
        await portal.emitActivated();
        await _settle();
      };

      await _bindAndSettle(hotkey, _ctrlShiftG);
      await _settle();

      expect(
        fired,
        isEmpty,
        reason:
            'AD-11 subscribes last, so nothing is bound yet and there is '
            'nothing for a press to toggle',
      );
    });

    test('A18 AD-11: and step 4 really is last — the subscriptions reach the '
        'bus after BindShortcuts, not merely before a session exists', () async {
      // The row above cannot say this on its own, and measuring showed it:
      // subscribing at step 4 *early* fails it zero times, because the press it
      // emits arrives while `_session` is still null and the delivery-time
      // session filter rejects it whether or not the subscription exists. Two
      // reasons, one assertion, and no way to tell them apart.
      //
      // AD-11's ordering claim is about the wire, so it is asserted there. The
      // fake's own `calls` list cannot see it: `AddMatch` goes to the bus
      // daemon rather than to an object the fake exports, which is why the
      // client records every method instead.
      final portal = await startPortal();
      final client = portal.newClient();
      final hotkey = buildOn(portal, client: client);

      await _bindAndSettle(hotkey, _ctrlShiftG);

      final calls = client.methodCalls;
      final afterBind = calls.sublist(calls.lastIndexOf('BindShortcuts') + 1);
      expect(
        afterBind.where((name) => name == 'AddMatch'),
        hasLength(2),
        reason:
            'Activated and ShortcutsChanged are subscribed after step 3 '
            'answered — subscribing either earlier would deliver a press for a '
            'shortcut that is not bound yet',
      );
    });

    test('A19 AD-11: ShortcutsChanged is recorded and does not fire the '
        'panel', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      logger.lines.clear();

      await portal.emitShortcutsChanged(triggerDescription: 'Super+Space');
      await _settle();

      expect(
        fired,
        isEmpty,
        reason: 'a rebind in the compositor is not a press',
      );
      final changed = linesAt('info');
      expect(changed, hasLength(1));
      expect(
        changed.single.message,
        contains('changed'),
        reason:
            'this line is the *entire* consumer of AD-11 ShortcutsChanged '
            'subscription — the port has nowhere to push a rebind upward — so a '
            'message indistinguishable from the first-bind one would leave the '
            'only record of a compositor-side rebind reading as startup noise',
      );
      expect(
        changed.single.message,
        isNot(equals(_boundLine)),
        reason: 'and specifically not the sentence a first bind emits',
      );
      expect(
        changed.single.context,
        {'trigger_description': 'Super+Space'},
        reason:
            'this log line is the whole of the record: the GlobalHotkey port '
            'has no way to push a changed registration upward, which is filed',
      );
      expect(
        changed.single.context!['trigger_description'],
        isA<String>(),
        reason:
            'and it is never parsed back into a HotkeyBinding — it is '
            'localized, backend-specific, user-readable text',
      );
    });

    test(
      'A19c AD-11: a ShortcutsChanged whose list no longer holds our id says '
      'exactly that, and nothing more',
      () async {
        final portal = await startPortal();
        final hotkey = buildOn(portal);
        final fired = <void>[];
        hotkey.activations.listen(fired.add);
        await _bindAndSettle(hotkey, _ctrlShiftG);
        logger.lines.clear();

        await portal.emitShortcutsChanged(shortcutIds: const []);
        await _settle();

        expect(fired, isEmpty);
        expect(linesAt('info'), hasLength(1));
        expect(linesAt('info').single.message, contains('no longer holds'));
        expect(errors(), isEmpty);
      },
    );

    test('A19d AD-11: a ShortcutsChanged this build cannot read is reported as '
        'unreadable, not as a shortcut that was dropped', () async {
      // The two must not collapse. An empty list is the compositor telling us
      // which shortcuts it holds; an unparseable payload is it telling us nothing
      // this build can read. Saying "this session no longer holds the global
      // shortcut" for the second would state a fact about compositor state that
      // was never established, which is the misreporting AGENTS.md §1 rules out
      // and which this file quotes three times.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      logger.lines.clear();

      await portal.emitMalformedShortcutsChanged();
      await _settle();

      expect(linesAt('info'), isEmpty);
      expect(errors(), hasLength(1));
      expect(errors().single.message, contains('cannot read'));
      expect(
        errors().single.message,
        isNot(contains('no longer holds')),
        reason: 'nothing was learned about what the compositor holds',
      );
    });

    test('A19d AD-11: the same holds for a list whose elements are the wrong '
        'shape, not only for one that is no list at all', () async {
      // A19d drives `is! DBusArray`; this drives the element-signature check
      // beside it, which no fixture reached. Unchecked, an `a(ss)` list reads as
      // the empty set and this signal would be logged as "the compositor
      // reports this session no longer holds the global shortcut" — a claim
      // about compositor state that was never established.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      logger.lines.clear();
      portal.shortcutListUsesWrongElementSignature = true;

      await portal.emitShortcutsChanged();
      await _settle();

      expect(linesAt('info'), isEmpty);
      expect(errors(), hasLength(1));
      expect(errors().single.message, contains('cannot read'));
      expect(errors().single.message, isNot(contains('no longer holds')));
    });

    test(
      'A19b AD-11: a ShortcutsChanged for another session is ignored',
      () async {
        final portal = await startPortal();
        final hotkey = buildOn(portal);
        await _bindAndSettle(hotkey, _ctrlShiftG);
        logger.lines.clear();

        await portal.emitShortcutsChanged(
          session: DBusObjectPath(
            '/org/freedesktop/portal/desktop/session/other',
          ),
        );
        await _settle();

        expect(logger.lines, isEmpty);
      },
    );

    test('C1 AD-10, AD-11: a compositor rebind is pushed up the port as a '
        'HotkeyBound the settings surface can render', () async {
      // The sentence this file used to carry — "this log line is the *entire*
      // consumer of AD-11's ShortcutsChanged subscription" — is what the port's
      // new member retires. The log line is unchanged; what is new is that the
      // change now has somewhere to go.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final changes = <HotkeyBindOutcome>[];
      hotkey.bindingChanges.listen(changes.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      logger.lines.clear();

      await portal.emitShortcutsChanged(triggerDescription: 'Super+Space');
      await _settle();

      expect(changes, [
        const HotkeyBound(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      ]);
      expect(
        changes.single,
        isA<HotkeyBound>().having(
          (bound) => bound.registration.effective,
          'effective',
          isNull,
        ),
        reason:
            'the portal sends only a localized trigger_description, and nothing '
            'parses that string back into a combination — so what goes up is '
            'AD-10\'s own "null when the backend cannot report it"',
      );
      expect(
        linesAt('info').single.message,
        contains('changed'),
        reason: 'and the existing record of the rebind is untouched',
      );
    });

    test('C1 AD-11: a rebind for another session pushes nothing', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final changes = <HotkeyBindOutcome>[];
      hotkey.bindingChanges.listen(changes.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitShortcutsChanged(
        session: DBusObjectPath(
          '/org/freedesktop/portal/desktop/session/other',
        ),
      );
      await _settle();

      expect(changes, isEmpty);
    });

    test('C2 AD-11, AD-12: a shortcut the desktop no longer holds is pushed up '
        'as HotkeyUnavailable naming the removal', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final changes = <HotkeyBindOutcome>[];
      hotkey.bindingChanges.listen(changes.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitShortcutsChanged(shortcutIds: const []);
      await _settle();

      expect(changes, hasLength(1));
      final unavailable = changes.single;
      expect(unavailable, isA<HotkeyUnavailable>());
      expect(
        (unavailable as HotkeyUnavailable).message,
        allOf(
          contains('desktop no longer holds'),
          contains('tray menu still opens the panel'),
        ),
        reason:
            'AD-12: the degradation is a sentence a user can act on, naming the '
            'way in that still works',
      );
    });

    test('C2 AD-11: a ShortcutsChanged this build cannot read pushes nothing at '
        'all', () async {
      // The sharp half. An empty list is the compositor saying which shortcuts
      // it holds; an unreadable payload is it saying nothing this build can
      // read. Emitting *either* value here would state a fact about compositor
      // state that was never established — the same misreport A19d forbids the
      // log line from making, now reachable by a surface.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final changes = <HotkeyBindOutcome>[];
      hotkey.bindingChanges.listen(changes.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await portal.emitMalformedShortcutsChanged();
      portal.shortcutListUsesWrongElementSignature = true;
      await portal.emitShortcutsChanged();
      await _settle();

      expect(changes, isEmpty);
    });

    test('C3 AD-4: dispose closes the binding-change stream, a later signal '
        'pushes nothing, and disposing twice never throws', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final changes = <HotkeyBindOutcome>[];
      var done = false;
      hotkey.bindingChanges.listen(changes.add, onDone: () => done = true);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await hotkey.dispose();
      await portal.emitShortcutsChanged(shortcutIds: const []);
      await _settle();

      expect(done, isTrue);
      expect(changes, isEmpty);
      await expectLater(hotkey.dispose(), completes);
    });

    test('A20 AD-4: a press after dispose reaches nobody and the stream is '
        'closed', () async {
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      var done = false;
      hotkey.activations.listen(fired.add, onDone: () => done = true);
      await _bindAndSettle(hotkey, _ctrlShiftG);

      await hotkey.dispose();
      await portal.emitActivated();
      await _settle();

      expect(fired, isEmpty);
      expect(done, isTrue, reason: 'shutdown must not leave a live stream');
    });

    test('A20 AD-4: a press landing *inside* the teardown window reaches nobody '
        'either, which is the window the guard exists for', () async {
      // A20 above emits after `dispose()` has returned, so the client is already
      // closed and the signal never reaches the adapter at all — it passes with
      // or without the post-dispose guard. The reachable window is inside
      // `dispose()`: `_disposed` is set, then the session Close is awaited with
      // the bus client still open and `activations` still open.
      //
      // What this row pins is the property, not one particular guard: nothing
      // reaches a listener from inside teardown, and nothing lands in the zone.
      // Measured, the adapter's `_disposed` check on this path fails zero tests
      // in both directions and cannot be made to fail one — `dispose()` clears
      // `_session` in the same synchronous run as it sets `_disposed`, so the
      // session filter beside it already rejects the press. That is recorded on
      // the guard itself rather than dressed up as a gate here.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      final zoneErrors = <Object>[];

      portal.beforeSessionClose = () async {
        await portal.emitActivated();
        await _settle();
      };
      await runZonedGuarded(
        () async => hotkey.dispose(),
        (error, stack) => zoneErrors.add(error),
      );
      await _settle();

      expect(fired, isEmpty);
      expect(zoneErrors, isEmpty);
    });

    for (final name in const ['Activated', 'ShortcutsChanged']) {
      test('AD-12: a truncated $name is ignored rather than throwing '
          'RangeError into the zone', () async {
        // A different axis from every other malformed row, which all send the
        // documented number of values with a wrong type inside one of them.
        // Both handlers index `values[1]` behind an arity check, and a
        // truncated signal is the only payload that reaches it — without the
        // check the index throws inside a stream callback, which no `try` in
        // the adapter covers, in a daemon whose whole premise is that nothing
        // escapes.
        final portal = await startPortal();
        final hotkey = buildOn(portal);
        final fired = <void>[];
        hotkey.activations.listen(fired.add);
        await _bindAndSettle(hotkey, _ctrlShiftG);
        logger.lines.clear();
        final zoneErrors = <Object>[];

        await runZonedGuarded(() async {
          await portal.emitTruncatedSignal(name: name);
          await _settle();
        }, (error, stack) => zoneErrors.add(error));
        await _settle();

        expect(zoneErrors, isEmpty);
        expect(fired, isEmpty);
        expect(
          logger.lines,
          isEmpty,
          reason:
              'nothing was learned about the compositor, so nothing is claimed '
              'about it',
        );
      });
    }
  });

  group('a portal that never answers (D-17)', () {
    test('D-17: a CreateSession the portal never answers is abandoned at the '
        'bound, and the settings screen gets a value', () async {
      // The hang this bound exists for. Before it, `SettingsController._bind`
      // awaited a future nothing would ever complete: the method reply came
      // back, the `Response` never did, and the screen sat on a busy state
      // with no way out. Note what is *not* asserted — that the call was
      // cancelled — because it was not; see the row below.
      final portal = await startPortal();
      final hotkey = buildOn(portal, requestTimeout: _impatient);
      portal.withholdCreateSessionResponse = true;

      final outcome = await hotkey
          .bind(_ctrlShiftG)
          .timeout(
            _answerBudget,
            onTimeout: () =>
                fail('the bind was not bounded; it is still waiting'),
          );

      expect(outcome, isA<HotkeyUnavailable>());
      expect(
        (outcome as HotkeyUnavailable).cause,
        HotkeyUnavailableCause.keyRefused,
        reason:
            'a portal answered the method call, so this desktop demonstrably '
            'has the mechanism — telling the user it has none would talk them '
            'out of a retry that may well work',
      );
      expect(outcome.message, contains('tray menu still opens the panel'));
      expect(
        errors().single.context,
        {'call': 'CreateSession', 'timeout_ms': _impatient.inMilliseconds},
        reason:
            'the log line carries the call and the bound and nothing else — no '
            'vendor error, and nothing of the user\'s',
      );
    });

    test('D-17: nothing is sent on the timeout path — no Close, and no second '
        'call of any kind', () async {
      // The prohibition, as a row. Abandoning a wait is permitted; withdrawing
      // a request the user may be looking at is not, and a `Session.Close`
      // here is exactly that withdrawal.
      final portal = await startPortal();
      final hotkey = buildOn(portal, requestTimeout: _impatient);
      portal.withholdCreateSessionResponse = true;

      await hotkey.bind(_ctrlShiftG);

      expect(portal.callOrder, [
        'Registry.Register',
        'GlobalShortcuts.CreateSession',
      ]);
      expect(
        portal.callOrder,
        isNot(contains('Session.Close')),
        reason:
            'the session handle was never learned, so there is nothing this '
            'adapter could honestly close — and on the BindShortcuts path, '
            'where it does have one, closing it would cancel a live dialog',
      );
    });

    test('D-17: the dialog step waits materially longer than the dialogless '
        'ones, and is not abandoned at the short bound', () async {
      // The other half of the prohibition. `BindShortcuts` is the one step
      // with a person behind it, so a few seconds — long enough for a portal
      // to be called unresponsive — is nowhere near long enough to call a
      // human unresponsive. This row proves the two bounds are different by
      // waiting past the short one and finding the bind still in flight.
      final portal = await startPortal();
      final hotkey = buildOn(portal, requestTimeout: _impatient);
      portal.withholdBindShortcutsResponse = true;
      HotkeyBindOutcome? settled;

      final bind = hotkey.bind(_ctrlShiftG).then((outcome) {
        settled = outcome;
      });
      await Future<void>.delayed(_impatient * 3);

      expect(
        settled,
        isNull,
        reason:
            'three times the dialogless bound has passed and the dialog step '
            'is still waiting, which is the difference this row exists to pin',
      );

      await bind.timeout(
        _impatientDialog,
        onTimeout: () => fail('the dialog step was not bounded at all'),
      );

      expect(settled, isA<HotkeyUnavailable>());
    });

    test('D-17: an abandoned dialog leaves its session tracked rather than '
        'closed, so a late Allow still reaches the panel', () async {
      // Neither of the two obvious answers is right. Closing the session
      // cancels the dialog the user is reading; forgetting it leaves the
      // compositor holding a session this process no longer tracks, and a
      // rebind would then create a second one. Tracking it does both jobs: the
      // rebind closes it first, and the `Activated` filter reads the tracked
      // handle at delivery time, so a grant a minute late still toggles the
      // panel.
      final portal = await startPortal();
      final hotkey = buildOn(portal, requestTimeout: _impatient);
      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      portal.withholdBindShortcutsResponse = true;

      final outcome = await hotkey.bind(_ctrlShiftG).timeout(_answerBudget);

      expect(
        outcome,
        isA<HotkeyUnavailable>(),
        reason:
            'nothing has been granted yet, so nothing may be reported as '
            'bound — the answer is corrected by the compositor, never '
            'predicted here',
      );
      expect(portal.callOrder, isNot(contains('Session.Close')));

      // Settled first, for the reason every other activation row settles: the
      // signal subscriptions match on the portal's *well-known* name, which
      // `package:dbus` resolves through an asynchronous name-owner lookup, so a
      // press emitted before that resolves is dropped by the bus rather than by
      // the adapter.
      await _settle();
      // The late grant, arriving after this app stopped waiting for it.
      await portal.emitActivated();
      await _settle();

      expect(
        activations,
        hasLength(1),
        reason:
            'the session was tracked, so the filter recognised the press — an '
            'untracked session would have dropped it',
      );

      portal.calls.clear();
      portal.withholdBindShortcutsResponse = false;
      await hotkey.bind(_altSpace).timeout(_answerBudget);

      expect(
        portal.callOrder.first,
        'Session.Close',
        reason:
            'and the rebind closes it, so two attempts cannot leave the '
            'compositor holding two live sessions',
      );
      expect(portal.openSessions, 1);
    });
  });

  group('teardown (AD-4)', () {
    test('A21 AD-4: dispose closes the session, cancels the subscriptions, '
        'closes the bus client and the stream, and is safe twice', () async {
      final portal = await startPortal();
      final client = portal.newClient();
      final hotkey = buildOn(portal, client: client);
      var done = false;
      hotkey.activations.listen(null, onDone: () => done = true);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      portal.calls.clear();

      await hotkey.dispose();
      await _settle();

      expect(portal.callOrder, ['Session.Close']);
      expect(portal.openSessions, 0);
      expect(
        client.closed,
        isTrue,
        reason:
            'package:dbus documents that an unclosed client can stop the Dart '
            'process terminating, which on this branch is a daemon that never '
            'exits — so this is load-bearing, not hygiene',
      );
      expect(done, isTrue);
      await expectLater(hotkey.dispose(), completes);
      expect(errors(), isEmpty);
    });

    test(
      'A21b AD-4: a refused Session.Close is logged and every remaining step '
      'still runs',
      () async {
        final portal = await startPortal();
        final client = portal.newClient();
        final hotkey = buildOn(portal, client: client);
        var done = false;
        hotkey.activations.listen(null, onDone: () => done = true);
        await _bindAndSettle(hotkey, _ctrlShiftG);
        portal.refuseSessionClose = true;

        await expectLater(hotkey.dispose(), completes);
        await _settle();

        expect(
          client.closed,
          isTrue,
          reason: 'a Close the portal refuses must not strand the client',
        );
        expect(done, isTrue);
        expect(errors(), hasLength(1));
        expect(errors().single.context, {'error_type': 'DBusFailedException'});
      },
    );

    test('AD-4: a dispose landing while a rebind Close is in flight sends one '
        'Close, not two', () async {
      // Without clearing `_session` before the await, teardown reads a handle
      // whose Close is already outstanding and sends a second one. The portal
      // answers `UnknownObject`, and `_guard` logs it as a teardown failure that
      // did not happen — the exact mistake the bind path's own comment says it
      // avoids, and the one story 7 spent a review pass correcting on X11.
      final portal = await startPortal();
      final hotkey = buildOn(portal);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      final closeReached = Completer<void>();
      final letCloseFinish = Completer<void>();
      // One-shot: a second Close must go straight through and be recorded, which
      // is what makes this row fail rather than deadlock when the bug is present.
      portal.beforeSessionClose = () async {
        portal.beforeSessionClose = null;
        closeReached.complete();
        await letCloseFinish.future;
      };

      // Deliberately not awaited: `dispose()` closes the bus client, and
      // `package:dbus` never completes a call that was in flight when its socket
      // closed, so this future stays pending for the rest of the test. It cannot
      // reject — `bind()` never does — so nothing reaches the zone.
      unawaited(hotkey.bind(_altSpace));
      await closeReached.future;
      await hotkey.dispose();
      letCloseFinish.complete();
      await _settle();

      expect(
        portal.callOrder.where((label) => label == 'Session.Close'),
        hasLength(1),
        reason: 'one session, so at most one Close for it, ever',
      );
      expect(
        errors(),
        isEmpty,
        reason: 'and therefore no teardown failure to report',
      );
    });

    test('AD-4: a teardown landing between a refused Close and its report is '
        'answered as the shutdown it is, not as a live shortcut', () async {
      // The refused-Close arm is the one await in the bind path whose post-await
      // `_disposed` re-check can actually be driven, and this is how: the arm
      // logs before it decides, so a logger that tears the adapter down while
      // reporting puts the teardown exactly in the gap. That is the same
      // technique story 7 used on X11 — `registrar.onRelease = () =>
      // registrar.emitPress()` — arming a collaborator to make a real race
      // deterministic rather than hoping for it. Without the re-check this
      // answers `HotkeyBound`, "the previous shortcut is still in effect", about
      // a session whose bus client teardown has already closed.
      final portal = await startPortal();
      late WaylandPortalGlobalHotkey hotkey;
      final teardowns = <Future<void>>[];
      final tearDownWhileReporting = _DisposeWhileReportingLogger(
        () => teardowns.add(hotkey.dispose()),
      );
      hotkey = WaylandPortalGlobalHotkey(
        client: portal.newClient(),
        appIdRegime: PortalAppIdRegime.hostRegistry,
        requestTimeout: _shippedCallBudget,
        logger: tearDownWhileReporting,
      );
      addTearDown(hotkey.dispose);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      portal.refuseSessionClose = true;

      final outcome = await hotkey.bind(_altSpace);
      await Future.wait(teardowns);

      expect(
        (outcome as HotkeyUnavailable).message,
        contains('shut down'),
        reason: 'nothing above this adapter could act on a bound hotkey now',
      );
      expect(
        tearDownWhileReporting.reported,
        anyElement(contains('could not be closed')),
        reason: 'the row is vacuous unless the refusal really was reported',
      );
    });

    test('AD-4: a Session.Close the portal never answers does not stop the '
        'daemon exiting', () async {
      // `_guard` reduces a teardown *throw* to a log line and can do nothing
      // about a teardown that never returns — and `package:dbus` never
      // completes a call whose socket died under it, so a portal that stops
      // answering mid-Close parks `dispose()` forever. `DaemonLifecycle` awaits
      // this step in sequence, so the history database, the config store and
      // the AD-14 lock would never be released and the process would never
      // reach `exit`: every later launch would then find a stale address. A
      // daemon that cannot exit is the worse failure, so teardown stops waiting.
      final portal = await startPortal();
      final client = portal.newClient();
      final hotkey = buildOn(portal, client: client);
      await _bindAndSettle(hotkey, _ctrlShiftG);
      final neverAnswers = Completer<void>();
      portal.beforeSessionClose = () => neverAnswers.future;

      await expectLater(
        hotkey.dispose().timeout(
          const Duration(seconds: 15),
          onTimeout: () => fail('dispose() never returned'),
        ),
        completes,
      );

      expect(
        client.closed,
        isTrue,
        reason: 'the step that actually ends the session still ran',
      );
      expect(errors(), hasLength(1));
      expect(errors().single.context, {'error_type': 'TimeoutException'});
      neverAnswers.complete();
      await _settle();
    });

    test('AD-4: disposing an adapter that never bound closes nothing it never '
        'opened, and never connects', () async {
      final portal = await startPortal();
      final client = portal.clientForNoBus();
      final hotkey = WaylandPortalGlobalHotkey(
        client: client,
        appIdRegime: PortalAppIdRegime.hostRegistry,
        requestTimeout: _shippedCallBudget,
        logger: logger,
      );

      await expectLater(hotkey.dispose(), completes);

      expect(portal.calls, isEmpty);
      expect(client.closed, isTrue);
      expect(logger.lines, isEmpty);
    });
  });

  group('the logger is the thing that broke (A24)', () {
    test('A24: every failing path completes and emits no unhandled zone error '
        'when the logger itself throws', () async {
      final broken = ThrowingLogger();
      final errorsInZone = <Object>[];
      final portal = await startPortal();

      await runZonedGuarded(() async {
        // The Register refusal, the unclassified failure, the omitted trigger,
        // the successful read-back log, the abandoned rebind and the refused
        // teardown Close — every site that reports through the logger.
        portal.registerError = 'org.freedesktop.DBus.Error.AccessDenied';
        portal.createSessionError = 'org.freedesktop.DBus.Error.Failed';
        final hotkey = WaylandPortalGlobalHotkey(
          client: portal.newClient(),
          appIdRegime: PortalAppIdRegime.hostRegistry,
          requestTimeout: _shippedCallBudget,
          logger: broken,
        );
        expect(await hotkey.bind(_ctrlShiftG), isA<HotkeyUnavailable>());

        portal.createSessionError = null;
        expect(
          await hotkey.bind(
            HotkeyBinding(modifiers: {HotkeyModifier.control}, key: 'Compose'),
          ),
          isA<HotkeyBound>(),
        );

        portal.refuseSessionClose = true;
        expect(await hotkey.bind(_altSpace), isA<HotkeyRetained>());

        await expectLater(hotkey.dispose(), completes);
      }, (error, stack) => errorsInZone.add(error));
      await _settle();

      expect(errorsInZone, isEmpty);
      expect(
        broken.attempts,
        isNotEmpty,
        reason: 'the guards must still have tried to report',
      );
    });
  });
}

/// A [Logger] that tears the adapter down from inside its own `error` call.
///
/// One-shot, so the teardown it triggers cannot recurse through the log lines
/// teardown itself emits. `dispose()` sets `_disposed` synchronously before its
/// first await, so by the time `error` returns the adapter is torn down — which
/// is precisely the interleaving a real stop signal produces and which no amount
/// of pumping can schedule reliably.
final class _DisposeWhileReportingLogger implements Logger {
  _DisposeWhileReportingLogger(this._tearDown);

  final void Function() _tearDown;

  /// Every message this logger was given, so a row can prove it was reached.
  final List<String> reported = [];

  bool _fired = false;

  @override
  void info(String message, {Map<String, Object?>? context}) {
    reported.add(message);
  }

  @override
  void warning(String message, {Map<String, Object?>? context}) {
    reported.add(message);
  }

  @override
  void error(String message, {Map<String, Object?>? context}) {
    reported.add(message);
    if (_fired) {
      return;
    }
    _fired = true;
    _tearDown();
  }
}

/// Drains what is left once the bus has already delivered.
///
/// It no longer waits for the wire, and it must not be asked to: the trip a
/// signal makes from the fake to the adapter crosses a real unix socket, so how
/// long it takes is a function of how busy the machine is, while a count of
/// event-loop turns consumes no wall clock at all. Measured on this host, an
/// `Activated` landed 2 turns after the emit on an idle machine and 255 turns
/// after it with every core saturated — against the 50 this gives. That is the
/// nondeterminism 01-VERIFICATION.md recorded as 2 PASS / 5 FAIL over seven
/// full-suite runs, and it is fixed where it happens:
/// [FakeGlobalShortcutsPortal]'s emit path now returns only once every client
/// has taken delivery, by an ordered D-Bus round trip rather than by waiting.
///
/// What is left for this to drain is in-process and load-independent — the
/// listener callback and whatever the adapter does inside it. Raising the count
/// would not make this suite more reliable, and lowering it is not worth the
/// churn.
Future<void> _settle() => pumpEventQueue(times: 50);

/// Binds and then lets the bus settle.
///
/// AD-11's step 4 subscribes as `bind()` returns, and a `DBusSignalStream`'s
/// `AddMatch` reaches the bus a microtask later — so a signal emitted in the
/// same turn as the bind resolving could beat the rule that forwards it. That is
/// a property of the test's own timing, not of the adapter: the adapter's own
/// ordering claim is A15, where the *portal* is the one racing.
Future<HotkeyBindOutcome> _bindAndSettle(
  WaylandPortalGlobalHotkey hotkey,
  HotkeyBinding binding,
) async {
  final outcome = await hotkey.bind(binding);
  await _settle();
  return outcome;
}

/// The `preferred_trigger` a recorded `BindShortcuts` asked for, or null when it
/// omitted one.
String? _triggerOf(PortalCall call) {
  final trigger = call.shortcutsAt(1)['toggle-panel']?['preferred_trigger'];
  return trigger is DBusString ? trigger.value : null;
}

/// The info line a *first* bind emits, so the compositor-rebind line can be
/// pinned as a different sentence rather than merely as a line that exists.
const String _boundLine = 'the compositor bound the global shortcut';

/// How long a row waits for an answer the adapter promises unconditionally.
///
/// Every use is a place where the regression is a *hang* rather than a wrong
/// value — a `Response` filtered out by a stale match rule, a queue parked
/// behind a call that never resolves. Without a budget those rows would hang the
/// suite instead of failing it, which is the one failure mode this file's own
/// teardown doc says does not report itself.
const Duration _answerBudget = Duration(seconds: 10);

/// The bound the shipped composition root hands this adapter (`main.dart`'s
/// `_unresponsiveCallBudget`).
///
/// Restated rather than imported because `main.dart` needs a binding and this
/// suite runs under `dart test`; `composition_wiring_test.dart` is what holds
/// the two together. Every row that is not *about* the bound takes this one, so
/// no row is quietly exercising a different policy from the daemon's — the fake
/// portal answers in microseconds, so it never fires.
const Duration _shippedCallBudget = Duration(seconds: 5);

/// Short enough that a row can watch the bound fire inside a test.
///
/// The dialog step is deliberately not measured against this — it takes twelve
/// times as long by design — so a row wanting to observe an abandoned
/// `BindShortcuts` has to wait `_impatient * 12`, which is what
/// `_impatientDialog` is for.
const Duration _impatient = Duration(milliseconds: 30);

/// What the adapter's dialog bound works out to at [_impatient], plus room for
/// the timer to actually fire.
const Duration _impatientDialog = Duration(milliseconds: 30 * 12 + 500);

final HotkeyBinding _ctrlShiftG = HotkeyBinding(
  modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
  key: 'G',
);

/// The matrix's second combination. Alt+Space is deliberately usable here, where
/// the X11 adapter refuses it: `Space` reaches keybinder as `KP_Space` through a
/// vendor key table, while the XDG trigger is `ALT+space` and correct.
final HotkeyBinding _altSpace = HotkeyBinding(
  modifiers: {HotkeyModifier.alt},
  key: 'Space',
);
