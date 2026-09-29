import 'dart:io';

import 'package:test/test.dart';

/// AD-19's interpreter and sidecar paths have exactly one home:
/// `ProviderConfig.settings`, read only by the adapter that owns the keys.
///
/// This is a "no second home exists" pin rather than a "the two agree" one.
/// `AppConfig` used to carry both paths as first-class fields that nothing
/// read, so the codec persisted one set of values while the registry built the
/// adapter from another — the two could not drift because only one was ever
/// live, and reintroducing the dead one is what this test fails on.
void main() {
  test('AD-19: AppConfig declares no interpreter or sidecar path member', () {
    final source = File(
      'lib/src/domain/config/app_config.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains('sidecarPath')),
      reason:
          'AD-15 keeps transport detail inside the adapter that owns it; '
          'one provider process layout has no home in a domain type every '
          'other provider inherits',
    );
    expect(source, isNot(contains('interpreterPath')));
  });

  test('AD-19: only the adapter that owns the settings keys, the registry '
      'that reads them, and the default config that seeds them name '
      'them', () {
    const allowed = {
      'lib/src/infrastructure/correction/claude_agent_sdk/'
          'claude_agent_sdk_correction_provider.dart',
      'lib/src/infrastructure/correction/provider_registry.dart',
      'lib/src/infrastructure/config/default_app_config.dart',
    };

    final naming = <String>{};
    for (final file in _dartFilesUnder('lib')) {
      if (_namesAnAd19PathKey(file.readAsStringSync())) {
        naming.add(file.path);
      }
    }

    expect(
      naming,
      allowed,
      reason:
          'a second home for the AD-19 paths was introduced (or one of '
          'the three moved); the settings map is the only home',
    );
  });

  test('AD-19: the settings keys the registry reads are the ones the adapter '
      'declares, by symbol and not by a copied string', () {
    final registry = File(
      'lib/src/infrastructure/correction/provider_registry.dart',
    ).readAsStringSync();

    expect(
      registry,
      contains('ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey'),
    );
    expect(
      registry,
      contains('ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey'),
    );
    expect(
      registry,
      isNot(contains("'interpreter'")),
      reason: 'a copied literal is a second home for the key itself',
    );
    expect(registry, isNot(contains("'sidecar'")));
  });
}

/// True when [source] names either AD-19 path setting — by the constant the
/// adapter declares, or by the literal key that constant holds.
bool _namesAnAd19PathKey(String source) {
  const markers = [
    'interpreterSettingsKey',
    'sidecarSettingsKey',
    "'interpreter'",
    "'sidecar'",
  ];
  return markers.any(source.contains);
}

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
