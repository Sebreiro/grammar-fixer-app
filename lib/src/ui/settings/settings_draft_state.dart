import '../../application/settings_state.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/correction/preset.dart';
import 'settings_category.dart';

/// Non-secret presentation drafts and the snapshots against which they began.
final class SettingsDraftState {
  const SettingsDraftState({
    required this.urlBaseline,
    required this.modelPreset,
    required this.activePreset,
    required this.url,
    required this.model,
    required this.prompt,
    required this.promptSnapshot,
    this.category = SettingsCategory.general,
    this.setupProviderId,
    this.urlConflict = false,
    this.modelConflict = false,
    this.promptConflict = false,
  });

  factory SettingsDraftState.initial(SettingsState value) => SettingsDraftState(
    urlBaseline: value.compatibleBaseUrl,
    modelPreset: _compatiblePreset(value),
    activePreset: value.activePreset,
    url: value.compatibleBaseUrl,
    model:
        value.presetForProvider(ProviderConfig.compatibleProviderId)?.model ??
        '',
    prompt: value.activePreset?.systemPrompt ?? '',
    promptSnapshot: value.activePreset,
  );

  final String urlBaseline;
  final Preset? modelPreset;
  final Preset? activePreset;
  final SettingsCategory category;
  final String? setupProviderId;
  final String url;
  final String model;
  final String prompt;
  final Preset? promptSnapshot;
  final bool urlConflict;
  final bool modelConflict;
  final bool promptConflict;

  SettingsDraftState copyWith({
    SettingsCategory? category,
    ({String? value})? setupProvider,
    String? url,
    String? model,
    String? prompt,
  }) => SettingsDraftState(
    urlBaseline: urlBaseline,
    modelPreset: modelPreset,
    activePreset: activePreset,
    category: category ?? this.category,
    setupProviderId: setupProvider == null
        ? setupProviderId
        : setupProvider.value,
    url: url ?? this.url,
    model: model ?? this.model,
    prompt: prompt ?? this.prompt,
    promptSnapshot: promptSnapshot,
    urlConflict: urlConflict && (url ?? this.url) != urlBaseline,
    modelConflict:
        modelConflict && (model ?? this.model) != (modelPreset?.model ?? ''),
    promptConflict:
        promptConflict && (prompt ?? this.prompt) != activePreset?.systemPrompt,
  );

  SettingsDraftState reconcile(SettingsState next) {
    final nextPrompt = next.activePreset?.systemPrompt ?? '';
    final oldPrompt = activePreset?.systemPrompt ?? '';
    final presetChanged = activePreset?.id != next.activePreset?.id;
    final modelChanged = modelPreset?.id != _compatiblePreset(next)?.id;
    final reconciledPrompt = presetChanged
        ? nextPrompt
        : _follow(prompt, oldPrompt, nextPrompt);
    return SettingsDraftState(
      urlBaseline: next.compatibleBaseUrl,
      modelPreset: _compatiblePreset(next),
      activePreset: next.activePreset,
      category: category,
      setupProviderId: presetChanged ? null : setupProviderId,
      url: _follow(url, urlBaseline, next.compatibleBaseUrl),
      model: modelChanged
          ? _model(next)
          : _follow(model, (modelPreset?.model ?? ''), _model(next)),
      prompt: reconciledPrompt,
      promptSnapshot: presetChanged || reconciledPrompt == nextPrompt
          ? next.activePreset
          : promptSnapshot,
      urlConflict: _conflict(
        url,
        urlBaseline,
        next.compatibleBaseUrl,
        urlConflict,
      ),
      modelConflict:
          !modelChanged &&
          _conflict(
            model,
            (modelPreset?.model ?? ''),
            _model(next),
            modelConflict,
          ),
      promptConflict:
          !presetChanged &&
          _conflict(prompt, oldPrompt, nextPrompt, promptConflict),
    );
  }

  static String _follow(String draft, String before, String after) =>
      draft == before ? after : draft;
  static bool _conflict(
    String draft,
    String before,
    String after,
    bool previous,
  ) => draft != after && draft != before && (previous || before != after);
  static Preset? _compatiblePreset(SettingsState value) =>
      value.presetForProvider(ProviderConfig.compatibleProviderId);
  static String _model(SettingsState value) =>
      _compatiblePreset(value)?.model ?? '';
}
