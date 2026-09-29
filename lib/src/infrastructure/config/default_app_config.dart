import 'dart:io';

import '../../domain/config/app_config.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/correction/preset.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import '../correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import '../correction/claude_agent_sdk/register_tagged_stream_parser.dart';
import '../correction/claude_agent_sdk/sidecar_host_paths.dart';

/// The configuration a fresh install starts from: one described provider,
/// one preset, one hotkey.
///
/// It is a *default*, not a constant the code depends on — CAP-8 lets the
/// user replace any of it by editing the config file, and AD-5 keeps the
/// prompt bound to its model inside the preset (CAP-9's tuning seam).
final class DefaultAppConfig {
  const DefaultAppConfig._();

  /// The shipped preset's id (kebab-case, per the Consistency Conventions).
  static const String shippedPresetId = 'default-formal-casual-shorter';

  /// The shipped preset's system prompt. It fixes AD-16's wire format and
  /// nothing else: output-quality wording is a SPEC non-goal.
  ///
  /// The closing sentinel is interpolated from
  /// [RegisterTaggedStreamParser.endSentinel] rather than spelled out, so
  /// the prompt and the parser that enforces it cannot drift apart.
  static const String shippedSystemPrompt =
      'You correct English grammar. Reply with exactly four lines and '
      'nothing else:\n'
      'FORMAL: <the corrected text in a formal register>\n'
      'CASUAL: <the corrected text in a casual register>\n'
      'SHORTER: <the shortest correct rewrite>\n'
      '${RegisterTaggedStreamParser.endSentinel}\n'
      'Each tag appears exactly once, in that order, and the final line is '
      'exactly ${RegisterTaggedStreamParser.endSentinel}.\n'
      'Do not add other text, blank lines, quotes, or markdown.';

  /// The default model the shipped preset is bound to.
  static const String shippedModel = 'claude-sonnet-5';

  /// Which interpreter the sidecar runs under: the environment
  /// `tool/provision_sidecar.sh` builds when one is found, and the bare
  /// command name otherwise.
  ///
  /// The bare name alone was the shipped default and was wrong for everybody:
  /// `python3` resolves to the session's system interpreter, which is exactly
  /// the one that cannot import `claude_agent_sdk`, so a user who followed the
  /// provisioning instructions to the letter still got `providerUnavailable`
  /// on every correction. The provisioned environment is untracked and
  /// per-machine, so it is found by probing rather than assumed.
  static String interpreterPath({
    String? executablePath,
    bool Function(String candidate)? exists,
    String? workingDirectory,
    String? appImagePath,
  }) => SidecarHostPaths.resolveInterpreter(
    executablePath: executablePath ?? Platform.resolvedExecutable,
    exists: exists ?? _fileExists,
    workingDirectory: workingDirectory ?? Directory.current.path,
    appImagePath: appImagePath ?? Platform.environment['APPIMAGE'],
  );

  /// Where the shipped Python asset is for *this* build — the copy inside the
  /// installed bundle when the running executable has one beside it, and the
  /// repo-relative asset otherwise.
  ///
  /// A method rather than a constant because the answer is a property of the
  /// host, not of the source: an installed daemon's working directory is
  /// wherever the session launched it from, so a repo-relative default would
  /// resolve to nothing for every user who did not start it from a checkout.
  /// [SidecarHostPaths] holds the decision; this supplies the two facts about
  /// the host.
  ///
  /// It runs **once**, at seed time. The store writes what it returns into the
  /// config file on first run and nothing re-derives it afterwards, so a
  /// daemon that is later moved or installed keeps the path its first run
  /// chose until the setting is edited. That is also why the working directory
  /// is resolved here and baked into the answer rather than left in it: this
  /// story ships an autostart entry, so the process that reads the stored value
  /// back routinely has a different working directory than the one that wrote
  /// it, and a stored relative path would resolve against `$HOME` at login.
  ///
  /// All three seams take a host default. They exist because the
  /// installed-bundle arm is otherwise unreachable from any test: a test runner
  /// has no bundle beside it, so a hard-wired `Platform.resolvedExecutable`
  /// would leave the branch that matters to users exercised by nothing.
  static String sidecarPath({
    String? executablePath,
    bool Function(String candidate)? exists,
    String? workingDirectory,
    String? appImagePath,
  }) => SidecarHostPaths.resolveScript(
    executablePath: executablePath ?? Platform.resolvedExecutable,
    exists: exists ?? _fileExists,
    workingDirectory: workingDirectory ?? Directory.current.path,
    appImagePath: appImagePath ?? Platform.environment['APPIMAGE'],
  );

  static bool _fileExists(String candidate) => File(candidate).existsSync();

  /// The AD-19 wall-clock bound on one correction, in milliseconds.
  static const int timeoutMillis = 60000;

  /// The shipped preset, and the backstop the composition root falls back to
  /// when `activePresetId` names no preset — a `ConfigStore` contract breach
  /// that must still leave the daemon with a preset to correct with (AD-5).
  static const Preset shippedPreset = Preset(
    id: shippedPresetId,
    providerId: ClaudeAgentSdkCorrectionProvider.providerId,
    model: shippedModel,
    systemPrompt: shippedSystemPrompt,
  );

  /// The shipped configuration.
  ///
  /// Built per call rather than returned from a const field, because two
  /// settings are derived from the running host ([interpreterPath] and
  /// [sidecarPath]) and no longer have compile-time values.
  ///
  /// The maps are wrapped rather than merely freshly allocated. As a
  /// `static const AppConfig` field every collection in it was a const literal,
  /// so `AppConfig`'s "immutable value" contract was enforced by the language —
  /// a write threw `UnsupportedError`. Neither `AppConfig` nor `ProviderConfig`
  /// copies or wraps what it is handed, so dropping the const would have
  /// downgraded that guarantee to a convention on exactly the instance that
  /// needs it most: the composition root hands one `build()` result to
  /// `JsonConfigStore` as its defaults, and that same instance is what every
  /// fallback path returns for the daemon's whole lifetime.
  static AppConfig build() => AppConfig(
    providers: Map.unmodifiable({
      ClaudeAgentSdkCorrectionProvider.providerId: ProviderConfig(
        settings: Map.unmodifiable({
          ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey:
              interpreterPath(),
          ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey: sidecarPath(),
          ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: '$timeoutMillis',
        }),
      ),
    }),
    presets: const [shippedPreset],
    activePresetId: shippedPresetId,
    // Startup preference only; CAP-12 lets Settings replace and persist it.
    hotkeyBinding: HotkeyBinding(
      modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
      key: 'G',
    ),
  );
}
