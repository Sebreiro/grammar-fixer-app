import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

import '../../domain/config/provider_key_writer.dart';
import '../../domain/config/secret_store.dart';
import '../../domain/config/secret_write_result.dart';

/// Secret Service credential storage shared by gnome-keyring and KWallet.
///
/// Items are identified by the public attributes `application` and
/// `provider`. Reads never prompt; explicit writes may ask to unlock the keyring.
final class SecretServiceSecretStore implements SecretStore, ProviderKeyWriter {
  const SecretServiceSecretStore({
    this.lookupTimeout = const Duration(seconds: 3),
    this.closeTimeout = const Duration(seconds: 1),
    this.promptTimeout = const Duration(minutes: 2),
    this.connect,
  });

  static const _destination = 'org.freedesktop.secrets';
  static const _service = 'org.freedesktop.Secret.Service';
  static const _session = 'org.freedesktop.Secret.Session';
  static final _servicePath = DBusObjectPath('/org/freedesktop/secrets');

  final Duration lookupTimeout;
  final Duration closeTimeout;
  final Duration promptTimeout;
  final DBusClient Function()? connect;

  @override
  Future<SecretWriteResult> writeProviderKey(
    String providerId,
    String apiKey,
  ) async {
    if (apiKey.trim().isEmpty) return SecretWriteResult.unavailable;
    DBusClient? client;
    DBusObjectPath? session;
    try {
      client = connect?.call() ?? DBusClient.session();
      final items = await _matchingItems(client, providerId);
      final targets = items.isEmpty
          ? [await _defaultCollection(client)]
          : items;
      if (targets.any((path) => path.value == '/') ||
          !await _unlock(client, targets)) {
        return SecretWriteResult.unavailable;
      }
      session = await _openSession(client).timeout(lookupTimeout);
      final entry = (
        session: session,
        providerId: providerId,
        apiKey: apiKey.trim(),
      );
      if (items.isNotEmpty) {
        await _replaceSecrets(client, items, entry);
        return SecretWriteResult.saved;
      }
      final item = await _createItem(client, targets.single, entry);
      return item.value == '/'
          ? SecretWriteResult.unavailable
          : SecretWriteResult.saved;
    } on Object {
      // Vendor errors may include the secret; expose only a modeled failure.
      return SecretWriteResult.unavailable;
    } finally {
      if (client != null) await _close(client, session);
    }
  }

  Future<List<DBusObjectPath>> _matchingItems(
    DBusClient client,
    String providerId,
  ) async {
    final response = await client
        .callMethod(
          destination: _destination,
          path: _servicePath,
          interface: _service,
          name: 'SearchItems',
          values: [_attributes(providerId)],
          replySignature: DBusSignature('aoao'),
        )
        .timeout(lookupTimeout);
    return {
      ...response.values[0].asObjectPathArray(),
      ...response.values[1].asObjectPathArray(),
    }.toList();
  }

  static DBusDict _attributes(String providerId) =>
      DBusDict(DBusSignature('s'), DBusSignature('s'), {
        const DBusString('application'): const DBusString(
          'hotkey-grammar-corrector',
        ),
        const DBusString('provider'): DBusString(providerId),
      });

  static DBusStruct _secret(
    ({DBusObjectPath session, String providerId, String apiKey}) entry,
  ) => DBusStruct([
    entry.session,
    DBusArray.byte(const []),
    DBusArray.byte(utf8.encode(entry.apiKey)),
    const DBusString('text/plain; charset=utf-8'),
  ]);

  Future<void> _replaceSecrets(
    DBusClient client,
    List<DBusObjectPath> items,
    ({DBusObjectPath session, String providerId, String apiKey}) entry,
  ) async {
    // Lookup searches every collection. Update all matching entries so it cannot
    // later choose an older credential from a different collection.
    for (final item in items) {
      await client
          .callMethod(
            destination: _destination,
            path: item,
            interface: 'org.freedesktop.Secret.Item',
            name: 'SetSecret',
            values: [_secret(entry)],
            replySignature: DBusSignature(''),
          )
          .timeout(lookupTimeout);
    }
  }

  Future<DBusObjectPath> _defaultCollection(DBusClient client) async {
    final response = await client
        .callMethod(
          destination: _destination,
          path: _servicePath,
          interface: _service,
          name: 'ReadAlias',
          values: [const DBusString('default')],
          replySignature: DBusSignature('o'),
        )
        .timeout(lookupTimeout);
    return response.values.single.asObjectPath();
  }

  Future<bool> _unlock(DBusClient client, List<DBusObjectPath> targets) async {
    final response = await client
        .callMethod(
          destination: _destination,
          path: _servicePath,
          interface: _service,
          name: 'Unlock',
          values: [DBusArray.objectPath(targets)],
          replySignature: DBusSignature('aoo'),
        )
        .timeout(lookupTimeout);
    final prompt = response.values[1].asObjectPath();
    final unlocked = response.values[0].asObjectPathArray().toSet();
    if (prompt.value != '/') {
      final result = await _performPrompt(client, prompt);
      if (result == null) return false;
      unlocked.addAll(result.asObjectPathArray());
    }
    return targets.every(unlocked.contains);
  }

  Future<DBusObjectPath> _createItem(
    DBusClient client,
    DBusObjectPath collection,
    ({DBusObjectPath session, String providerId, String apiKey}) entry,
  ) async {
    final response = await client
        .callMethod(
          destination: _destination,
          path: collection,
          interface: 'org.freedesktop.Secret.Collection',
          name: 'CreateItem',
          values: [
            DBusDict.stringVariant({
              'org.freedesktop.Secret.Item.Label': const DBusString(
                'Grammar Corrector API key',
              ),
              'org.freedesktop.Secret.Item.Attributes': _attributes(
                entry.providerId,
              ),
            }),
            _secret(entry),
            const DBusBoolean(true),
          ],
          replySignature: DBusSignature('oo'),
        )
        .timeout(lookupTimeout);
    final prompt = response.values[1].asObjectPath();
    if (prompt.value == '/') return response.values[0].asObjectPath();
    final result = await _performPrompt(client, prompt);
    return result?.asObjectPath() ?? DBusObjectPath('/');
  }

  Future<DBusValue?> _performPrompt(
    DBusClient client,
    DBusObjectPath prompt,
  ) async {
    const interface = 'org.freedesktop.Secret.Prompt';
    final completion = Completer<DBusValue?>();
    var completedByService = false;
    final subscription =
        DBusSignalStream(
          client,
          sender: _destination,
          path: prompt,
          interface: interface,
          name: 'Completed',
          signature: DBusSignature('bv'),
        ).listen(
          (signal) {
            if (completion.isCompleted) return;
            completedByService = true;
            completion.complete(
              signal.values[0].asBoolean()
                  ? null
                  : signal.values[1].asVariant(),
            );
          },
          onError: (Object error) {
            if (!completion.isCompleted) completion.complete(null);
          },
        );
    try {
      await client
          .callMethod(
            destination: _destination,
            path: prompt,
            interface: interface,
            name: 'Prompt',
            values: [const DBusString('')],
            replySignature: DBusSignature(''),
          )
          .timeout(lookupTimeout);
      return await completion.future.timeout(promptTimeout);
    } finally {
      if (!completedByService) {
        try {
          await client
              .callMethod(
                destination: _destination,
                path: prompt,
                interface: interface,
                name: 'Dismiss',
                replySignature: DBusSignature(''),
              )
              .timeout(closeTimeout);
        } on Object {
          // Closing the client releases a prompt whose service stopped replying.
        }
      }
      try {
        await subscription.cancel().timeout(closeTimeout);
      } on Object {
        // The owning operation closes the client even if RemoveMatch fails.
      }
    }
  }

  Future<void> _close(DBusClient client, DBusObjectPath? session) async {
    try {
      if (session != null) {
        await client
            .callMethod(
              destination: _destination,
              path: session,
              interface: _session,
              name: 'Close',
              replySignature: DBusSignature(''),
            )
            .timeout(closeTimeout);
      }
    } on Object {
      // Closing the connection also releases its session.
    } finally {
      try {
        await client.close().timeout(closeTimeout);
      } on Object {
        // Cleanup cannot turn a modeled result into a vendor exception.
      }
    }
  }

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
      if (client != null) await _close(client, session);
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
