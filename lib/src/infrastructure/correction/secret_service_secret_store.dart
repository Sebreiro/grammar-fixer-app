import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

import '../../domain/config/secret_store.dart';

/// Read-only Secret Service lookup shared by gnome-keyring and KWallet.
///
/// Items are identified by the public attributes `application` and
/// `provider`. Only an unlocked matching item is read. The service is never
/// asked to unlock, create, or update an item.
final class SecretServiceSecretStore implements SecretStore {
  const SecretServiceSecretStore({
    this.lookupTimeout = const Duration(seconds: 3),
    this.closeTimeout = const Duration(seconds: 1),
    this.connect,
  });

  static const _destination = 'org.freedesktop.secrets';
  static const _service = 'org.freedesktop.Secret.Service';
  static const _session = 'org.freedesktop.Secret.Session';
  static final _servicePath = DBusObjectPath('/org/freedesktop/secrets');

  final Duration lookupTimeout;
  final Duration closeTimeout;
  final DBusClient Function()? connect;

  @override
  Future<SecretLookup> readProviderKey(String providerId) async {
    DBusClient? client;
    DBusObjectPath? session;
    try {
      client = connect?.call() ?? DBusClient.session();
      final search = await client
          .callMethod(
            destination: _destination,
            path: _servicePath,
            interface: _service,
            name: 'SearchItems',
            values: [
              DBusDict(DBusSignature('s'), DBusSignature('s'), {
                const DBusString('application'): const DBusString(
                  'hotkey-grammar-corrector',
                ),
                const DBusString('provider'): DBusString(providerId),
              }),
            ],
            replySignature: DBusSignature('aoao'),
          )
          .timeout(lookupTimeout);
      final unlocked = search.values[0].asObjectPathArray().toList();
      final locked = search.values[1].asObjectPathArray().toList();
      if (unlocked.isEmpty) {
        return locked.isEmpty
            ? const SecretAbsent()
            : const SecretUnavailable();
      }

      session = await _openSession(client).timeout(lookupTimeout);
      return await _readSecret(
        client,
        session,
        unlocked,
      ).timeout(lookupTimeout);
    } on Object {
      // D-Bus error payloads can contain user data; no exception is logged.
      return const SecretUnavailable();
    } finally {
      if (client != null) {
        if (session != null) {
          try {
            await client
                .callMethod(
                  destination: _destination,
                  path: session,
                  interface: _session,
                  name: 'Close',
                  replySignature: DBusSignature(''),
                )
                .timeout(closeTimeout);
          } on Object {
            // Closing the bus connection also releases the session.
          }
        }
        await client.close();
      }
    }
  }

  Future<DBusObjectPath> _openSession(DBusClient client) async {
    final reply = await client.callMethod(
      destination: _destination,
      path: _servicePath,
      interface: _service,
      name: 'OpenSession',
      values: [const DBusString('plain'), DBusVariant(const DBusString(''))],
      replySignature: DBusSignature('vo'),
    );
    return reply.values[1].asObjectPath();
  }

  Future<SecretLookup> _readSecret(
    DBusClient client,
    DBusObjectPath session,
    List<DBusObjectPath> items,
  ) async {
    final reply = await client.callMethod(
      destination: _destination,
      path: _servicePath,
      interface: _service,
      name: 'GetSecrets',
      values: [DBusArray.objectPath(items), session],
      replySignature: DBusSignature('a{o(oayays)}'),
    );
    final secrets = reply.values.single.asDict();
    for (final item in items) {
      final secret = secrets[item];
      if (secret == null) continue;
      final fields = secret.asStruct();
      if (fields[0].asObjectPath() != session) continue;
      final value = utf8.decode(fields[2].asByteArray().toList());
      if (value.isNotEmpty) return SecretFound(value);
    }
    return const SecretUnavailable();
  }
}
