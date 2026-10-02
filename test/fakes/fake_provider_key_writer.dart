import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/config/provider_key_writer.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_write_result.dart';

final class FakeProviderKeyWriter implements ProviderKeyWriter {
  SecretWriteResult result = SecretWriteResult.saved;
  Object? error;
  Completer<void>? gate;
  final List<({String providerId, String apiKey})> writes = [];

  @override
  Future<SecretWriteResult> writeProviderKey(
    String providerId,
    String apiKey,
  ) async {
    writes.add((providerId: providerId, apiKey: apiKey));
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}
