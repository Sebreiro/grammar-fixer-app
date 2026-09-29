import '../collection_equality.dart';
import '../correction/preset.dart';
import '../hotkey/hotkey_binding.dart';
import 'provider_config.dart';

/// The whole configuration as one immutable value.
///
/// Loaded, validated, and written in exactly one place — the ConfigStore
/// (AD-13); everything else receives this value and never touches the file.
/// The store is also the single validation point for cross-field references:
/// [activePresetId] must name a preset in [presets], and every
/// `preset.providerId` must name an entry in [providers].
///
/// There is deliberately no first-class home here for a provider's interpreter
/// or sidecar path. AD-15 keeps transport detail inside the adapter that owns
/// it, so those live in [ProviderConfig.settings] and are read only by the
/// registry that builds the adapter — one provider's process layout has no
/// business in a type every other provider inherits.
///
/// Collection ownership: the const constructor cannot defensively copy, so
/// callers hand over unowned (ideally const) collections and never mutate
/// them after construction.
final class AppConfig {
  const AppConfig({
    required this.providers,
    required this.presets,
    required this.activePresetId,
    required this.hotkeyBinding,
  });

  /// Described providers by provider id. Many may be described; exactly one
  /// is active per correction, resolved via the active preset (AD-5).
  final Map<String, ProviderConfig> providers;

  final List<Preset> presets;
  final String activePresetId;
  final HotkeyBinding hotkeyBinding;

  AppConfig copyWith({
    Map<String, ProviderConfig>? providers,
    List<Preset>? presets,
    String? activePresetId,
    HotkeyBinding? hotkeyBinding,
  }) {
    return AppConfig(
      providers: providers ?? this.providers,
      presets: presets ?? this.presets,
      activePresetId: activePresetId ?? this.activePresetId,
      hotkeyBinding: hotkeyBinding ?? this.hotkeyBinding,
    );
  }

  /// Deep value equality: maps as maps, lists in order, and every nested type
  /// by value too. `ConfigStore.changes` promises no instance identity, so a
  /// consumer that compared configs by identity — `SettingsController`'s echo
  /// suppression did — silently stops working the moment an adapter rebuilds
  /// the value rather than handing back the instance it was given.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppConfig &&
        activePresetId == other.activePresetId &&
        hotkeyBinding == other.hotkeyBinding &&
        listEquals(presets, other.presets) &&
        mapEquals(providers, other.providers);
  }

  @override
  int get hashCode => Object.hash(
    activePresetId,
    hotkeyBinding,
    listHash(presets),
    mapHash(providers),
  );
}
