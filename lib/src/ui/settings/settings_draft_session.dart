import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/composition/controller_providers.dart';
import '../../application/composition/port_providers.dart';
import 'settings_category.dart';
import 'settings_draft_state.dart';

final settingsDraftSessionProvider =
    NotifierProvider<SettingsDraftSession, SettingsDraftState>(
      SettingsDraftSession.new,
    );

/// Retained by the root scope, including while Settings is absent.
class SettingsDraftSession extends Notifier<SettingsDraftState> {
  @override
  SettingsDraftState build() {
    final controller = ref.read(settingsControllerProvider);
    final logger = ref.read(loggerProvider);
    final subscription = controller.changes.listen(
      (next) => state = state.reconcile(next),
      onError: (Object error) => logger.error(
        'the settings draft stream errored',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    return SettingsDraftState.initial(controller.state);
  }

  void selectCategory(SettingsCategory value) =>
      state = state.copyWith(category: value);
  void selectSetupProvider(String? value) =>
      state = state.copyWith(setupProvider: (value: value));
  void editUrl(String value) => state = state.copyWith(url: value);
  void editModel(String value) => state = state.copyWith(model: value);
  void editPrompt(String value) => state = state.copyWith(prompt: value);
}
