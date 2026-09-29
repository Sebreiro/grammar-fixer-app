import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_store.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/secret_service_secret_store.dart';
import 'package:test/test.dart';

void main() {
  late _SecretBus bus;

  setUp(() async => bus = await _SecretBus.start());
  tearDown(() async => bus.stop());

  SecretServiceSecretStore store() => SecretServiceSecretStore(
    connect: bus.client,
    lookupTimeout: const Duration(seconds: 2),
  );

  test('CAP-8: an unlocked matching key is read through a fresh session '
      'and the session is closed', () async {
    bus.unlocked = [_SecretBus.item];
    bus.secret = 'private-key';

    final result = await store().readProviderKey('openai-compatible');

    expect(
      result,
      isA<SecretFound>().having((value) => value.value, 'key', 'private-key'),
    );
    expect(bus.calls, ['SearchItems', 'OpenSession', 'GetSecrets', 'Close']);
    expect(bus.attributes, {
      'application': 'hotkey-grammar-corrector',
      'provider': 'openai-compatible',
    });
  });

  test('CAP-8: absent and locked entries do not open a session', () async {
    expect(
      await store().readProviderKey('openai-compatible'),
      isA<SecretAbsent>(),
    );
    expect(bus.calls, ['SearchItems']);

    bus.calls.clear();
    bus.locked = [_SecretBus.item];
    expect(
      await store().readProviderKey('openai-compatible'),
      isA<SecretUnavailable>(),
    );
    expect(bus.calls, ['SearchItems']);
  });

  test('CAP-13: missing, empty, wrong-session, and unreadable secrets are '
      'unavailable and always close the session', () async {
    bus.unlocked = [_SecretBus.item];
    for (final caseName in ['missing', 'empty', 'wrong-session', 'bad-utf8']) {
      bus.calls.clear();
      bus.caseName = caseName;

      expect(
        await store().readProviderKey('openai-compatible'),
        isA<SecretUnavailable>(),
        reason: caseName,
      );
      expect(bus.calls, ['SearchItems', 'OpenSession', 'GetSecrets', 'Close']);
    }
  });

  test('CAP-13: service failures stay unavailable and a close refusal '
      'does not discard a found key', () async {
    bus.unlocked = [_SecretBus.item];
    for (final failure in ['search', 'open', 'get']) {
      bus.calls.clear();
      bus.caseName = failure;
      expect(
        await store().readProviderKey('openai-compatible'),
        isA<SecretUnavailable>(),
        reason: failure,
      );
    }

    bus.calls.clear();
    bus.caseName = 'close';
    bus.secret = 'still-valid';
    final result = await store().readProviderKey('openai-compatible');
    expect(
      result,
      isA<SecretFound>().having((value) => value.value, 'key', 'still-valid'),
    );
    expect(bus.calls.last, 'Close');
  });
}

final class _SecretBus {
  _SecretBus(this.directory, this.server, this.address, this.service);

  static final item = DBusObjectPath('/org/freedesktop/secrets/item/1');
  static final session = DBusObjectPath('/org/freedesktop/secrets/session/1');
  static final wrongSession = DBusObjectPath(
    '/org/freedesktop/secrets/session/other',
  );

  final Directory directory;
  final DBusServer server;
  final DBusAddress address;
  final DBusClient service;

  List<DBusObjectPath> unlocked = [];
  List<DBusObjectPath> locked = [];
  String secret = '';
  String caseName = '';
  final List<String> calls = [];
  Map<String, String> attributes = {};

  static Future<_SecretBus> start() async {
    final directory = Directory.systemTemp.createTempSync(
      'secret-service-bus-',
    );
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: directory),
    );
    final service = DBusClient(address);
    final bus = _SecretBus(directory, server, address, service);
    await service.requestName('org.freedesktop.secrets');
    await service.registerObject(_ServiceObject(bus));
    await service.registerObject(_SessionObject(bus));
    return bus;
  }

  DBusClient client() => DBusClient(address);

  Future<void> stop() async {
    await service.close();
    await server.close();
    directory.deleteSync(recursive: true);
  }

  DBusMethodResponse search(DBusMethodCall call) {
    calls.add('SearchItems');
    final values = call.values.single.asDict();
    attributes = {
      for (final entry in values.entries)
        entry.key.asString(): entry.value.asString(),
    };
    if (caseName == 'search') {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed');
    }
    return DBusMethodSuccessResponse([
      DBusArray.objectPath(unlocked),
      DBusArray.objectPath(locked),
    ]);
  }

  DBusMethodResponse open() {
    calls.add('OpenSession');
    if (caseName == 'open') {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed');
    }
    return DBusMethodSuccessResponse([
      DBusVariant(const DBusString('')),
      session,
    ]);
  }

  DBusMethodResponse get() {
    calls.add('GetSecrets');
    if (caseName == 'get') {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed');
    }
    final contents = caseName == 'bad-utf8' ? [0xff] : utf8.encode(secret);
    final held = switch (caseName) {
      'missing' => <DBusValue, DBusValue>{},
      _ => <DBusValue, DBusValue>{
        item: DBusStruct([
          caseName == 'wrong-session' ? wrongSession : session,
          DBusArray.byte(const []),
          DBusArray.byte(contents),
          const DBusString('text/plain'),
        ]),
      },
    };
    return DBusMethodSuccessResponse([
      DBusDict(DBusSignature('o'), DBusSignature('(oayays)'), held),
    ]);
  }

  DBusMethodResponse close() {
    calls.add('Close');
    if (caseName == 'close') {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed');
    }
    return DBusMethodSuccessResponse();
  }
}

final class _ServiceObject extends DBusObject {
  _ServiceObject(this.bus) : super(DBusObjectPath('/org/freedesktop/secrets'));

  final _SecretBus bus;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async =>
      switch (call.name) {
        'SearchItems' => bus.search(call),
        'OpenSession' => bus.open(),
        'GetSecrets' => bus.get(),
        _ => DBusMethodErrorResponse.unknownMethod(),
      };
}

final class _SessionObject extends DBusObject {
  _SessionObject(this.bus) : super(_SecretBus.session);

  final _SecretBus bus;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async =>
      call.name == 'Close'
      ? bus.close()
      : DBusMethodErrorResponse.unknownMethod();
}
