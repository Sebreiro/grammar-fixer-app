import 'app_config.dart';

/// Outcome of loading the config file (AD-13): a malformed file yields
/// defaults plus a surfaced warning — never a failed startup for a resident
/// daemon.
final class ConfigLoadResult {
  const ConfigLoadResult({
    required this.config,
    this.warning,
    this.logWarning,
    this.warningErrorType,
  });

  final AppConfig config;

  /// Human-renderable warning when defaults are needed or saved inline prompts
  /// could not migrate to text files. A migration failure keeps the loaded
  /// config. Null when loading and any required migration succeed.
  final String? warning;

  /// Safe application-authored text for the daemon log when [warning] includes
  /// a user-supplied config value needed to identify the invalid setting.
  final String? logWarning;

  /// Safe diagnostic type for a caught load error; startup logs it separately
  /// from the user-facing warning, without logging the exception's text.
  final String? warningErrorType;
}
