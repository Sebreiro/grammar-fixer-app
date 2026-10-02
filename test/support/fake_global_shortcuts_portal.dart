import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// A fake `org.freedesktop.portal.GlobalShortcuts` service, on a real D-Bus bus.
///
/// This is not a fake of a port. It is a fake of a *service on a bus*, which is
/// why it lives in `test/support/` rather than `test/fakes/`: `package:dbus`
/// ships its own in-process message bus (`DBusServer.listenAddress`), so the
/// whole AD-11 handshake can be driven over a real wire — real
/// `AddMatch`/`RemoveMatch`, real error replies, real cross-client signal
/// routing — under plain `dart test`, with no `dbus-daemon`, no compositor and
/// no session bus. That is a strictly stronger fake than a fake client: it
/// asserts at the boundary that actually exists, so the call order AD-11 makes
/// an invariant is observable as messages rather than as method calls on an
/// abstraction of our own.
///
/// The bus is a unix socket in a fresh temp directory. Deliberately not the
/// abstract namespace: DW-15's one-bind-per-process hazard is specific to
/// abstract sockets, and several of these are stood up and torn down in a single
/// suite.
///
/// **Teardown is not optional.** `package:dbus` documents that an unclosed
/// client can stop the Dart process terminating, so a suite that forgets
/// [stop] does not fail — it hangs.
final class FakeGlobalShortcutsPortal {
  /// Positional because Dart forbids a *named* parameter from starting with an
  /// underscore, so these four cannot be initializing formals any other way.
  /// [start] is the only caller.
  FakeGlobalShortcutsPortal._(
    this._directory,
    this._server,
    this._address,
    this._service,
  );

  /// Stands up a bus and puts this fake on it.
  ///
  /// [ownsDesktopPortal] false leaves `org.freedesktop.portal.Desktop` unowned,
  /// which is how a session with no `xdg-desktop-portal` running answers.
  /// [ownsHostRegistry] false leaves `org.freedesktop.host.portal` unowned,
  /// which is how xdg-desktop-portal before 1.20 answers AD-11's step 1.
  static Future<FakeGlobalShortcutsPortal> start({
    bool ownsDesktopPortal = true,
    bool ownsHostRegistry = true,
  }) async {
    final directory = Directory.systemTemp.createTempSync('fake-portal-bus-');
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: directory),
    );
    final service = DBusClient(address);
    final portal = FakeGlobalShortcutsPortal._(
      directory,
      server,
      address,
      service,
    );
    if (ownsDesktopPortal) {
      await service.requestName(desktopPortalName);
      await service.registerObject(_DesktopObject(portal));
    }
    if (ownsHostRegistry) {
      await service.requestName(hostRegistryName);
      await service.registerObject(_RegistryObject(portal));
    }
    return portal;
  }

  static const String desktopPortalName = 'org.freedesktop.portal.Desktop';
  static const String hostRegistryName = 'org.freedesktop.host.portal';
  static const String registryInterface =
      'org.freedesktop.host.portal.Registry';
  static const String globalShortcutsInterface =
      'org.freedesktop.portal.GlobalShortcuts';
  static const String requestInterface = 'org.freedesktop.portal.Request';
  static const String sessionInterface = 'org.freedesktop.portal.Session';

  static final DBusObjectPath desktopPath = DBusObjectPath(
    '/org/freedesktop/portal/desktop',
  );
  static final DBusObjectPath registryPath = DBusObjectPath(
    '/org/freedesktop/host/portal/registry',
  );

  final Directory _directory;
  final DBusServer _server;
  final DBusAddress _address;

  /// Not final: [restartPortalService] replaces it, which is the only way to
  /// give the portal a new unique bus name.
  DBusClient _service;
  final List<RecordingBusClient> _clients = [];

  /// A second client on the same bus, owning no name — see
  /// [emitActivatedFromImpostor]. Created on demand so the ordinary rows stand
  /// up one client fewer.
  DBusClient? _impostor;
  final List<_SessionObject> _sessions = [];

  /// Every method call this fake received, in order.
  ///
  /// Order, not a set: A1, A5, A18 and A23 are all claims about sequence — that
  /// `Register` precedes `CreateSession`, that a rebind closes before it creates,
  /// that step 4 comes last, and that two overlapping binds do not interleave.
  final List<PortalCall> calls = [];

  /// The same calls as `Interface.Member` labels, which is what the order rows
  /// read against.
  List<String> get callOrder => [for (final call in calls) call.label];

  /// The session handle of the most recent successful `CreateSession`.
  DBusObjectPath? get currentSession =>
      _sessions.isEmpty ? null : _sessions.last.path;

  /// How many sessions this fake still holds open. A rebind that leaked would
  /// leave two, which is the failure the adapter's serialized queue exists to
  /// prevent.
  int get openSessions => _sessions.length;

  // ---- failure injection -------------------------------------------------
  // Each field is one row of the matrix. They are plain mutable fields rather
  // than constructor arguments because most rows arm one of them *after* a first
  // successful bind.

  /// A D-Bus error name to reject `Registry.Register` with, or null to accept.
  String? registerError;

  /// Answers `Register` successfully but with an out-argument, where the
  /// interface declares none.
  ///
  /// A non-conformant Registry on a perfectly live bus. `package:dbus` raises
  /// `DBusReplySignatureException` for it, which is **not** a
  /// `DBusMethodResponseException`, so it is the one Register answer that can
  /// reach an adapter's catch-all rather than its refusal arm.
  bool answerRegisterWithAnExtraValue = false;

  /// A D-Bus error name to reject `CreateSession` with, or null to accept.
  String? createSessionError;

  /// The response code the `CreateSession` Request answers with. Non-zero is a
  /// dismissed dialog or a refusal.
  int createSessionResponseCode = 0;

  /// Answers the `CreateSession` Response with empty results — a portal reply
  /// carrying no `session_handle`.
  bool omitSessionHandle = false;

  /// Answers the `CreateSession` *method* with a plain string where the portal's
  /// signature says `o`, which is a reply-signature mismatch on the wire.
  bool replyToCreateSessionWithWrongSignature = false;

  /// The response code the `BindShortcuts` Request answers with.
  int bindShortcutsResponseCode = 0;

  /// The shortcut ids the `BindShortcuts` Response carries back, or null for
  /// "exactly what was asked for". The empty list is the documented discard.
  List<String>? boundShortcutIds;

  /// The `trigger_description` the read-back carries.
  String triggerDescription = 'Ctrl+Shift+G';
  bool omitBindTriggerDescription = false;
  String? listShortcutsDescription = 'Ctrl+Shift+G';
  bool refuseListShortcuts = false;

  /// Rejects `Session.Close`, which is the mid-rebind refusal.
  bool refuseSessionClose = false;

  /// The error name [refuseSessionClose] answers with.
  ///
  /// Which one it is decides what the refusal *means*: `Failed` is a live
  /// session the portal would not let go of, and `UnknownObject` is a session
  /// that no longer exists — an `xdg-desktop-portal` restart takes every session
  /// with it. The two need opposite answers, so both are drivable.
  String sessionCloseError = 'org.freedesktop.DBus.Error.Failed';

  /// Emits the Request `Response` **before** answering the method call, which is
  /// the documented portal race a caller that subscribes late loses.
  bool respondBeforeReply = false;

  /// Has a peer that owns **no** portal name emit a correct-looking
  /// `CreateSession` `Response` on the right Request path, just before the
  /// portal emits the real one.
  ///
  /// The only knob that can tell a sender-filtered Request subscription from
  /// one matching on object path alone: everything about the forged signal is
  /// right except who sent it, and the session handle it carries is one the
  /// portal never issued. A subscription that takes the first path match adopts
  /// the impostor's handle and binds against it.
  bool forgeCreateSessionResponseFromImpostor = false;

  /// The session handle [forgeCreateSessionResponseFromImpostor] offers.
  static final DBusObjectPath forgedSessionHandle = DBusObjectPath(
    '/org/freedesktop/portal/desktop/session/forged',
  );

  /// Answers the `CreateSession` Request with a `Response` whose values are not
  /// the documented `(u, a{sv})` at all — a portal this build cannot read.
  bool malformedCreateSessionResponse = false;

  /// Answers the `BindShortcuts` Request with results carrying no `shortcuts`
  /// key at all, rather than an empty list.
  bool omitShortcutsFromResponse = false;

  /// Sends the `shortcuts` list as `a(ss)` — an array of the right *kind* whose
  /// elements are not the documented `(sa{sv})`.
  ///
  /// Distinct from every other malformed knob on purpose: this is the payload
  /// that reaches the adapter's element-signature check rather than its
  /// coarser "is this an array at all" one. Without that check the list reads
  /// as the *empty set*, which is the documented discard — so a reply that said
  /// nothing about the app id would tell the user to install a `.desktop` file.
  bool shortcutListUsesWrongElementSignature = false;

  /// Sends the Request `Response`'s `results` as `a{ss}` — a dict whose values
  /// are strings rather than variants.
  ///
  /// The one payload that makes `mapStringVariant()` throw a cast error rather
  /// than return something wrong, which is why the adapter checks the signature
  /// before calling it.
  bool responseResultsUseWrongDictSignature = false;

  /// Run just before `BindShortcuts` is handled — the seam for asserting what
  /// exists at each point of the sequence rather than only at the end.
  Future<void> Function()? beforeBindShortcuts;

  /// Replies to the method and then **never emits the Request `Response`** —
  /// the portal that never answers (D-17).
  ///
  /// Distinct from every error field above, and the distinction is the whole
  /// point: a refusal is an answer, and the adapter already turns each one into
  /// AD-12's value. This is the state no `catch` can reach, where the call is
  /// out, the reply came back, and the signal the Request convention promises
  /// simply never arrives. It is also what a real backend looks like while a
  /// dialog sits unanswered on the user's screen, which is why the two steps
  /// are armed separately: the adapter bounds them on different budgets and
  /// must never cancel the one with a person behind it.
  bool withholdCreateSessionResponse = false;

  /// The same, for the step that shows the dialog — see
  /// [withholdCreateSessionResponse].
  bool withholdBindShortcutsResponse = false;

  /// Run just before `Session.Close` is handled, so a row can park a Close and
  /// land something else while it is in flight.
  Future<void> Function()? beforeSessionClose;

  /// Restarts the portal *process*: the well-known names come back on a **new
  /// unique name**, and every session goes with the old one.
  ///
  /// This is what `xdg-desktop-portal` does on a session update, and it is the
  /// one thing an injected error name cannot model. The `Session.Close` →
  /// `UnknownObject` row simulates a lost session while the bus identity stays
  /// put — and bus identity is exactly the variable a sender-filtered match rule
  /// is built on, so a rule holding the old unique name silently matches nothing
  /// afterwards. Calls to a session path the new owner does not export answer
  /// `UnknownObject` on their own, with nothing injected.
  Future<void> restartPortalService() async {
    await _service.close();
    _sessions.clear();
    _service = DBusClient(_address);
    await _service.requestName(desktopPortalName);
    await _service.registerObject(_DesktopObject(this));
    await _service.requestName(hostRegistryName);
    await _service.registerObject(_RegistryObject(this));
  }

  /// A client on this fake's bus, for the adapter under test.
  RecordingBusClient newClient() {
    final client = RecordingBusClient(_address);
    _clients.add(client);
    return client;
  }

  /// A client on this fake's bus whose `RemoveMatch` fails — see
  /// [RemoveMatchFailingBusClient].
  RecordingBusClient newClientThatCannotRemoveMatchRules() {
    final client = RemoveMatchFailingBusClient(_address);
    _clients.add(client);
    return client;
  }

  /// A client on this fake's bus whose socket dies at `CreateSession` — see
  /// [SocketDiesAtCreateSessionBusClient].
  RecordingBusClient newClientWhoseSocketDiesAtCreateSession() {
    final client = SocketDiesAtCreateSessionBusClient(_address);
    _clients.add(client);
    return client;
  }

  /// A client on this fake's bus whose transport fails at one named method,
  /// with a chosen error — see [TransportFailingBusClient].
  RecordingBusClient newClientWhoseTransportFailsAt(
    String method,
    Object error,
  ) {
    final client = TransportFailingBusClient(
      _address,
      method: method,
      error: error,
    );
    _clients.add(client);
    return client;
  }

  /// A client pointing at a path where no bus is listening — the state of a
  /// session with neither `DBUS_SESSION_BUS_ADDRESS` nor `/run/user/<uid>/bus`,
  /// which is what `DBusClient.session()` resolves to in this container.
  RecordingBusClient clientForNoBus() {
    final client = RecordingBusClient(
      DBusAddress.unix(path: '${_directory.path}/there-is-no-bus-here'),
    );
    _clients.add(client);
    return client;
  }

  /// Puts a signal on the bus and does not return until every live client on
  /// this bus has taken delivery of it.
  ///
  /// **Ordered, not timed, and it has to be.** A signal from this fake to the
  /// adapter crosses a real unix socket twice, so how long the trip takes is a
  /// function of how busy the machine is — while a barrier expressed as a count
  /// of event-loop turns consumes no wall clock at all. Measured on this host
  /// with an instrumented row: an `Activated` lands **2 turns** after the emit
  /// on an idle machine and **255 turns** after it with every core saturated.
  /// The suite's own barrier gives 50. That gap is the whole of the
  /// nondeterminism 01-VERIFICATION.md measured as 2 PASS / 5 FAIL over seven
  /// full-suite runs, and every failure it recorded has the same shape: a row
  /// emits, waits, and asserts on a list that is still empty.
  ///
  /// Both halves below are D-Bus ordering guarantees rather than waits, so
  /// neither gets slower or less reliable as the machine gets busier:
  ///
  /// * **Before the emit**, every client pings the bus. A `DBusSignalStream`'s
  ///   `AddMatch` goes out on that client's own connection before the ping
  ///   does, and the bus reads one connection in order — so a bus that has
  ///   answered the ping has already applied the match rule, and the signal
  ///   cannot be routed past a subscription that is not yet registered. This is
  ///   the half `_bindAndSettle`'s doc in the suite reasons about.
  /// * **After the emit**, the sender pings every client. The signal and the
  ///   ping travel the same sender → bus → client path in that order, and a
  ///   `DBusClient` dispatches the messages it reads into its signal streams in
  ///   the order it reads them — so a client that has answered the ping has
  ///   already handed the signal to whoever is listening.
  ///
  /// What is left when this returns is in-process only: the listener callback
  /// and whatever the adapter does inside it. That is what the suite's
  /// `_settle()` drains, and no amount of machine load can stretch it.
  ///
  /// [from] is the sender because ordering is per connection —
  /// [emitActivatedFromImpostor] emits from a different one, and pinging from
  /// this fake's own client would order against the wrong stream.
  Future<void> _emitSettled({
    required DBusClient from,
    required DBusObjectPath path,
    required String interface,
    required String name,
    required List<DBusValue> values,
  }) async {
    for (final client in _synchronisableClients) {
      await client.ping();
    }
    await from.emitSignal(
      path: path,
      interface: interface,
      name: name,
      values: values,
    );
    for (final client in _synchronisableClients) {
      await from.ping(client.uniqueName);
    }
  }

  /// The clients a delivery barrier can round-trip against.
  ///
  /// A client that never connected has no bus name, no match rules and no way
  /// to receive anything — [clientForNoBus] points at a path where nothing is
  /// listening, so waiting on it would wait forever rather than fail. A closed
  /// one is in the same position from the other end. Neither can take delivery
  /// of a signal, so neither is waited for.
  Iterable<RecordingBusClient> get _synchronisableClients => _clients.where(
    (client) => !client.closed && client.uniqueName.isNotEmpty,
  );

  /// Emits `Activated`, as the compositor does on a real key press.
  ///
  /// [session] defaults to the live one; passing another is how "a press that is
  /// not ours" is driven.
  Future<void> emitActivated({
    DBusObjectPath? session,
    String shortcutId = 'toggle-panel',
    int timestamp = 1234,
    Map<String, DBusValue> options = const {},
  }) async {
    await _emitSettled(
      from: _service,
      path: desktopPath,
      interface: globalShortcutsInterface,
      name: 'Activated',
      values: [
        session ?? currentSession ?? DBusObjectPath('/no/session'),
        DBusString(shortcutId),
        DBusUint64(timestamp),
        DBusDict.stringVariant(options),
      ],
    );
  }

  /// Emits `Activated` from a client on this bus that owns **no** portal name —
  /// any other process on a real session bus.
  ///
  /// The arguments are deliberately the right ones: the live session handle and
  /// the real shortcut id. Only the sender differs, so this is the one emitter
  /// that can tell a sender-filtered subscription from an unfiltered one.
  Future<void> emitActivatedFromImpostor({
    DBusObjectPath? session,
    String shortcutId = 'toggle-panel',
  }) async {
    final impostor = _impostor ??= DBusClient(_address);
    await _emitSettled(
      from: impostor,
      path: desktopPath,
      interface: globalShortcutsInterface,
      name: 'Activated',
      values: [
        session ?? currentSession ?? DBusObjectPath('/no/session'),
        DBusString(shortcutId),
        DBusUint64(4321),
        DBusDict.stringVariant(const {}),
      ],
    );
  }

  /// Emits a `ShortcutsChanged` whose second value is not the documented
  /// `a(sa{sv})` at all — a payload this build cannot read, as distinct from one
  /// that says the shortcut is gone.
  Future<void> emitMalformedShortcutsChanged({DBusObjectPath? session}) async {
    await _emitSettled(
      from: _service,
      path: desktopPath,
      interface: globalShortcutsInterface,
      name: 'ShortcutsChanged',
      values: [
        session ?? currentSession ?? DBusObjectPath('/no/session'),
        DBusString('not a shortcut list'),
      ],
    );
  }

  /// Emits an `Activated` or a `ShortcutsChanged` carrying **one** value where
  /// the portal documents four and two.
  ///
  /// A different axis from every other malformed knob, which all send the right
  /// number of values with a wrong type inside one of them. Both handlers index
  /// `values[1]` after checking the arity, and a truncated signal is the only
  /// payload that reaches that check — with it gone, the index throws
  /// `RangeError` inside a stream callback, which no `try` in the adapter
  /// covers and which lands as an unhandled zone error in a daemon whose whole
  /// premise is that nothing escapes.
  Future<void> emitTruncatedSignal({
    required String name,
    DBusObjectPath? session,
  }) async {
    await _emitSettled(
      from: _service,
      path: desktopPath,
      interface: globalShortcutsInterface,
      name: name,
      values: [session ?? currentSession ?? DBusObjectPath('/no/session')],
    );
  }

  /// Emits `ShortcutsChanged`, as a compositor does after the user rebinds the
  /// shortcut in its own settings.
  Future<void> emitShortcutsChanged({
    DBusObjectPath? session,
    List<String> shortcutIds = const ['toggle-panel'],
    String triggerDescription = 'Super+Space',
  }) async {
    await _emitSettled(
      from: _service,
      path: desktopPath,
      interface: globalShortcutsInterface,
      name: 'ShortcutsChanged',
      values: [
        session ?? currentSession ?? DBusObjectPath('/no/session'),
        _shortcutList(shortcutIds, triggerDescription),
      ],
    );
  }

  /// Closes both ends and the bus, in the order that leaves nothing behind.
  ///
  /// Every step is independent, for the reason this class's own doc gives: a
  /// missed teardown does not fail the suite, it hangs the process. One client
  /// whose `close()` throws — [RemoveMatchFailingBusClient] is exactly that
  /// shape — must not skip the server, the remaining clients or the temp
  /// directory. A step that could not be completed is reported at the end,
  /// because a silently swallowed teardown failure is how a leak hides.
  Future<void> stop() async {
    final failures = <Object>[];
    Future<void> attempt(Future<void> Function() step) async {
      try {
        await step();
      } on Object catch (error) {
        failures.add(error);
      }
    }

    for (final client in _clients) {
      await attempt(client.close);
    }
    final impostor = _impostor;
    if (impostor != null) {
      await attempt(impostor.close);
    }
    await attempt(_service.close);
    await attempt(_server.close);
    await attempt(() async {
      if (_directory.existsSync()) {
        _directory.deleteSync(recursive: true);
      }
    });
    if (failures.isNotEmpty) {
      throw StateError('the fake portal could not be torn down: $failures');
    }
  }

  // ---- the service side --------------------------------------------------

  Future<DBusMethodResponse> _handleRegister(DBusMethodCall call) async {
    calls.add(
      PortalCall._(registryPath, registryInterface, call.name, call.values),
    );
    final error = registerError;
    if (error != null) {
      return DBusMethodErrorResponse(error);
    }
    if (answerRegisterWithAnExtraValue) {
      return DBusMethodSuccessResponse([const DBusString('registered')]);
    }
    return DBusMethodSuccessResponse();
  }

  Future<DBusMethodResponse> _handleCreateSession(DBusMethodCall call) async {
    calls.add(
      PortalCall._(
        desktopPath,
        globalShortcutsInterface,
        call.name,
        call.values,
      ),
    );
    final error = createSessionError;
    if (error != null) {
      return DBusMethodErrorResponse(error);
    }
    final options = _optionsOf(call.values, 0);
    final requestPath = _requestPathFor(options['handle_token']);
    final sessionPath = DBusObjectPath(
      '/org/freedesktop/portal/desktop/session/fake/'
      '${_tokenOf(options['session_handle_token'])}',
    );

    Future<void> respond() async {
      if (forgeCreateSessionResponseFromImpostor) {
        final impostor = _impostor ??= DBusClient(_address);
        await impostor.emitSignal(
          path: requestPath,
          interface: requestInterface,
          name: 'Response',
          values: [
            const DBusUint32(0),
            DBusDict.stringVariant({
              'session_handle': DBusString(forgedSessionHandle.value),
            }),
          ],
        );
      }
      await _service.emitSignal(
        path: requestPath,
        interface: requestInterface,
        name: 'Response',
        values: malformedCreateSessionResponse
            ? [DBusString('not a response at all')]
            : [
                DBusUint32(createSessionResponseCode),
                DBusDict.stringVariant(
                  omitSessionHandle
                      ? const {}
                      // The portal documents this as `s`, not `o`, and that is
                      // what real backends send.
                      : {'session_handle': DBusString(sessionPath.value)},
                ),
              ],
      );
    }

    if (createSessionResponseCode == 0 && !omitSessionHandle) {
      final session = _SessionObject(this, sessionPath);
      _sessions.add(session);
      await _service.registerObject(session);
    }
    if (withholdCreateSessionResponse) {
      // Nothing scheduled at all: the reply below still goes out, so the
      // adapter is left waiting on a signal that will never come.
    } else if (respondBeforeReply) {
      await respond();
    } else {
      _respondAfterReply(respond);
    }
    if (replyToCreateSessionWithWrongSignature) {
      return DBusMethodSuccessResponse([DBusString(requestPath.value)]);
    }
    return DBusMethodSuccessResponse([requestPath]);
  }

  Future<DBusMethodResponse> _handleBindShortcuts(DBusMethodCall call) async {
    await beforeBindShortcuts?.call();
    calls.add(
      PortalCall._(
        desktopPath,
        globalShortcutsInterface,
        call.name,
        call.values,
      ),
    );
    final options = _optionsOf(call.values, 3);
    final requestPath = _requestPathFor(options['handle_token']);
    final requested = [
      for (final shortcut in _requestedShortcuts(call.values))
        shortcut.children[0].asString(),
    ];

    if (withholdBindShortcutsResponse) {
      // The dialog case: the request exists on the portal, the user has not
      // answered it, and this fake never will. The reply still goes out.
      return DBusMethodSuccessResponse([requestPath]);
    }
    _respondAfterReply(
      () => _service.emitSignal(
        path: requestPath,
        interface: requestInterface,
        name: 'Response',
        values: [
          DBusUint32(bindShortcutsResponseCode),
          if (responseResultsUseWrongDictSignature)
            DBusDict(DBusSignature('s'), DBusSignature('s'), {
              const DBusString('shortcuts'): const DBusString('not a variant'),
            })
          else
            DBusDict.stringVariant(
              omitShortcutsFromResponse
                  ? const {}
                  : {
                      'shortcuts': _shortcutList(
                        boundShortcutIds ?? requested,
                        omitBindTriggerDescription ? null : triggerDescription,
                      ),
                    },
            ),
        ],
      ),
    );
    return DBusMethodSuccessResponse([requestPath]);
  }

  Future<DBusMethodResponse> _handleListShortcuts(DBusMethodCall call) async {
    calls.add(
      PortalCall._(
        desktopPath,
        globalShortcutsInterface,
        call.name,
        call.values,
      ),
    );
    if (refuseListShortcuts) {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed');
    }
    final options = _optionsOf(call.values, 1);
    final requestPath = _requestPathFor(options['handle_token']);
    _respondAfterReply(
      () => _service.emitSignal(
        path: requestPath,
        interface: requestInterface,
        name: 'Response',
        values: [
          const DBusUint32(0),
          DBusDict.stringVariant({
            'shortcuts': _shortcutList([
              'toggle-panel',
            ], listShortcutsDescription),
          }),
        ],
      ),
    );
    return DBusMethodSuccessResponse([requestPath]);
  }

  /// Emits a Request `Response` strictly *after* the method reply has gone out —
  /// the ordinary portal ordering, and the control that [respondBeforeReply]'s
  /// row is measured against.
  ///
  /// A timer rather than a microtask, because that is what makes it ordinary
  /// rather than accidental: `package:dbus` writes the reply from a microtask
  /// once `handleMethodCall` resolves, so a microtask here could land on either
  /// side of it and both modes would then be the same mode. This is sequencing a
  /// fake service on purpose, not a delay papering over a race.
  void _respondAfterReply(Future<void> Function() respond) {
    unawaited(Future<void>.delayed(Duration.zero, respond));
  }

  Future<DBusMethodResponse> _handleSessionClose(
    _SessionObject session,
    DBusMethodCall call,
  ) async {
    await beforeSessionClose?.call();
    calls.add(
      PortalCall._(session.path, sessionInterface, call.name, call.values),
    );
    if (refuseSessionClose) {
      return DBusMethodErrorResponse(sessionCloseError);
    }
    _sessions.remove(session);
    await _service.unregisterObject(session);
    return DBusMethodSuccessResponse();
  }

  List<DBusStruct> _requestedShortcuts(List<DBusValue> values) {
    if (values.length < 2) {
      return const [];
    }
    final shortcuts = values[1];
    if (shortcuts is! DBusArray) {
      return const [];
    }
    return shortcuts.children.whereType<DBusStruct>().toList();
  }

  DBusValue _shortcutList(List<String> ids, String? triggerDescription) {
    if (shortcutListUsesWrongElementSignature) {
      return DBusArray(DBusSignature('(ss)'), [
        for (final id in ids)
          DBusStruct([DBusString(id), DBusString(triggerDescription ?? '')]),
      ]);
    }
    return DBusArray(DBusSignature('(sa{sv})'), [
      for (final id in ids)
        DBusStruct([
          DBusString(id),
          DBusDict.stringVariant({
            'description': DBusString('Show the grammar correction panel'),
            if (triggerDescription != null)
              'trigger_description': DBusString(triggerDescription),
          }),
        ]),
    ]);
  }

  Map<String, DBusValue> _optionsOf(List<DBusValue> values, int index) {
    if (values.length <= index) {
      return const {};
    }
    final options = values[index];
    if (options is! DBusDict || options.signature.value != 'a{sv}') {
      return const {};
    }
    return options.mapStringVariant();
  }

  /// The path shape a real portal derives from the caller's `handle_token`,
  /// which is what makes a reused token collide with a live Request.
  DBusObjectPath _requestPathFor(DBusValue? token) => DBusObjectPath(
    '/org/freedesktop/portal/desktop/request/fake/${_tokenOf(token)}',
  );

  String _tokenOf(DBusValue? token) =>
      token is DBusString ? token.value : 'no_token';
}

/// One method call the fake portal received.
final class PortalCall {
  PortalCall._(this.path, this.interface, this.member, this.values);

  /// The object path the call was made on. AD-11 names one for each step, and
  /// `Registry.Register` on the wrong path is a call a real portal ignores.
  final DBusObjectPath path;

  final String interface;
  final String member;
  final List<DBusValue> values;

  /// `GlobalShortcuts.BindShortcuts` and the like — the interface's last segment
  /// plus the member, which is how the order rows read.
  String get label => '${interface.split('.').last}.$member';

  /// The `a{sv}` at [index], as a plain map, or empty when there is none.
  Map<String, DBusValue> optionsAt(int index) {
    if (values.length <= index) {
      return const {};
    }
    final options = values[index];
    if (options is! DBusDict || options.signature.value != 'a{sv}') {
      return const {};
    }
    return options.mapStringVariant();
  }

  /// The `a(sa{sv})` shortcut list at [index], as id to its own vardict.
  Map<String, Map<String, DBusValue>> shortcutsAt(int index) {
    if (values.length <= index) {
      return const {};
    }
    final shortcuts = values[index];
    if (shortcuts is! DBusArray) {
      return const {};
    }
    return {
      for (final entry in shortcuts.children.whereType<DBusStruct>())
        if (entry.children.length >= 2)
          entry.children[0].asString(): (entry.children[1] as DBusDict)
              .mapStringVariant(),
    };
  }

  /// The string at [index], or null when it is not one.
  String? stringAt(int index) {
    if (values.length <= index) {
      return null;
    }
    final value = values[index];
    return value is DBusString ? value.value : null;
  }

  @override
  String toString() => '$label($values)';
}

/// A [DBusClient] that records whether it was closed.
///
/// AD-4 makes closing the client load-bearing rather than tidy — `package:dbus`
/// documents that an unclosed one can stop the Dart process terminating, which
/// on the Wayland branch is a daemon that never exits — so "dispose closed the
/// client" has to be observable. It cannot be observed by calling through the
/// client afterwards: a call issued on a closed client never completes at all
/// (measured), so a test written that way would hang rather than fail.
final class RecordingBusClient extends DBusClient {
  RecordingBusClient(super.address);

  /// True once [close] has been called, by anyone.
  bool closed = false;

  /// Every `AddMatch` and `RemoveMatch` this client put on the bus, in order.
  ///
  /// The adapter opens one Request `Response` subscription per portal call and
  /// cancels it in a `finally`. A cancel that stopped happening is invisible in
  /// every other way — the outcome of the bind is identical — while it leaks a
  /// bus-level match rule and a live `DBusSignalStream` per call, for the life
  /// of the daemon, each leaked stream still being handed every `Response` on
  /// the session bus. Counting the rules is the only place that shows.
  final List<String> matchRuleCalls = [];

  /// Every method this client put on the bus, in order — portal calls and the
  /// bus daemon's own `AddMatch`/`RemoveMatch` together.
  ///
  /// The fake's own `calls` list cannot see match rules: they go to
  /// `org.freedesktop.DBus`, not to an object the fake exports. So AD-11's "step
  /// 4 comes **last**" — the one step that is a subscription rather than a call
  /// — is invisible there, and this is where it shows.
  final List<String> methodCalls = [];

  /// How many match rules this client has added and not removed.
  int get liveMatchRules =>
      matchRuleCalls.where((name) => name == 'AddMatch').length -
      matchRuleCalls.where((name) => name == 'RemoveMatch').length;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) {
    if (name == 'Ping') {
      // The delivery barrier in [FakeGlobalShortcutsPortal._emitSettled] makes
      // a round trip on this connection, and that trip is the harness
      // synchronising rather than the adapter calling anything. Recording it
      // would put a call the adapter never made into the list AD-11's
      // step-4-comes-last row reads. Safe to exclude because the adapter issues
      // no `Ping` of any kind: `grep -in ping
      // lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` hits
      // only "mapping" and "stopping".
      return super.callMethod(
        destination: destination,
        path: path,
        interface: interface,
        name: name,
        values: values,
        replySignature: replySignature,
        noReplyExpected: noReplyExpected,
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization,
      );
    }
    if (name == 'AddMatch' || name == 'RemoveMatch') {
      matchRuleCalls.add(name);
    }
    methodCalls.add(name);
    return super.callMethod(
      destination: destination,
      path: path,
      interface: interface,
      name: name,
      values: values,
      replySignature: replySignature,
      noReplyExpected: noReplyExpected,
      noAutoStart: noAutoStart,
      allowInteractiveAuthorization: allowInteractiveAuthorization,
    );
  }

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}

/// A [DBusClient] that answers AD-11's step 1 and then loses its socket.
///
/// The dead-connection latch exists because `package:dbus` never completes a
/// call issued on a client whose connect failed, so a second `bind()` would wait
/// on nobody. Driving that through a client with *no bus at all* only ever
/// reaches the latch on the Register path, because Register is the first call
/// out — this reaches it on the Request path instead, which is a different arm
/// of the adapter and was pinned by nothing.
final class SocketDiesAtCreateSessionBusClient extends RecordingBusClient {
  SocketDiesAtCreateSessionBusClient(super.address);

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) {
    if (name == 'CreateSession') {
      throw const SocketException('the session bus socket went away');
    }
    return super.callMethod(
      destination: destination,
      path: path,
      interface: interface,
      name: name,
      values: values,
      replySignature: replySignature,
      noReplyExpected: noReplyExpected,
      noAutoStart: noAutoStart,
      allowInteractiveAuthorization: allowInteractiveAuthorization,
    );
  }
}

/// A [DBusClient] whose transport fails at one named method, with a chosen
/// error.
///
/// The adapter's `_isConnectionFailure` names three types — `SocketException`,
/// `OSError` and `DBusClosedException` — and which one arrives decides whether a
/// failure costs one bind or every later one, and which sentence the user then
/// reads for the life of the daemon. Only the first had a fixture. The method
/// name is a parameter for the same reason: the rebind's `Session.Close` is the
/// one bus-touching path whose failure was read as a *refusal* regardless of
/// what actually failed.
final class TransportFailingBusClient extends RecordingBusClient {
  TransportFailingBusClient(
    super.address, {
    required this.method,
    required this.error,
  });

  final String method;
  final Object error;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) {
    if (name == method) {
      throw error;
    }
    return super.callMethod(
      destination: destination,
      path: path,
      interface: interface,
      name: name,
      values: values,
      replySignature: replySignature,
      noReplyExpected: noReplyExpected,
      noAutoStart: noAutoStart,
      allowInteractiveAuthorization: allowInteractiveAuthorization,
    );
  }
}

/// A [DBusClient] whose `RemoveMatch` fails, and nothing else.
///
/// Cancelling a `DBusSignalStream` sends `RemoveMatch`, and the adapter does that
/// from a `finally` that sits outside every `catch` in the same method — so a
/// socket dying underneath the cancel is the one way a failure can leave that
/// method without being translated. On a real session that is an ordinary
/// shutdown race; here it has to be injected, because the in-process bus does not
/// die halfway through a test.
final class RemoveMatchFailingBusClient extends RecordingBusClient {
  RemoveMatchFailingBusClient(super.address);

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) {
    if (name == 'RemoveMatch') {
      throw StateError('the socket died under the match rule');
    }
    return super.callMethod(
      destination: destination,
      path: path,
      interface: interface,
      name: name,
      values: values,
      replySignature: replySignature,
      noReplyExpected: noReplyExpected,
      noAutoStart: noAutoStart,
      allowInteractiveAuthorization: allowInteractiveAuthorization,
    );
  }
}

final class _RegistryObject extends DBusObject {
  _RegistryObject(this._portal) : super(FakeGlobalShortcutsPortal.registryPath);

  final FakeGlobalShortcutsPortal _portal;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) {
    if (call.interface != FakeGlobalShortcutsPortal.registryInterface ||
        call.name != 'Register') {
      return Future.value(DBusMethodErrorResponse.unknownMethod());
    }
    return _portal._handleRegister(call);
  }
}

final class _DesktopObject extends DBusObject {
  _DesktopObject(this._portal) : super(FakeGlobalShortcutsPortal.desktopPath);

  final FakeGlobalShortcutsPortal _portal;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) {
    if (call.interface != FakeGlobalShortcutsPortal.globalShortcutsInterface) {
      return Future.value(DBusMethodErrorResponse.unknownInterface());
    }
    return switch (call.name) {
      'CreateSession' => _portal._handleCreateSession(call),
      'BindShortcuts' => _portal._handleBindShortcuts(call),
      'ListShortcuts' => _portal._handleListShortcuts(call),
      _ => Future.value(DBusMethodErrorResponse.unknownMethod()),
    };
  }
}

final class _SessionObject extends DBusObject {
  _SessionObject(this._portal, DBusObjectPath path) : super(path);

  final FakeGlobalShortcutsPortal _portal;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) {
    if (call.interface != FakeGlobalShortcutsPortal.sessionInterface ||
        call.name != 'Close') {
      return Future.value(DBusMethodErrorResponse.unknownMethod());
    }
    return _portal._handleSessionClose(this, call);
  }
}
