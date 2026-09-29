/// The one type that resolves the XDG layout (Consistency Conventions):
/// where the config file, the history database, and the runtime directory
/// live for this user.
///
/// The environment arrives as an injected map rather than being read from
/// `Platform.environment`, which is what lets every path row be exercised
/// headlessly, over a temp directory, with no real desktop session.
final class AppPaths {
  const AppPaths._({
    required this.configFile,
    required this.databaseFile,
    required this.runtimeDirectory,
    required this.warning,
  });

  /// Resolves the layout from [environment], honouring the XDG Base
  /// Directory spec: an override that is not an absolute path is invalid and
  /// is ignored in favour of the `$HOME` default — with a [warning], because
  /// a user who set the variable will otherwise edit a config file the
  /// daemon never reads.
  ///
  /// Throws [StateError] when neither an absolute XDG override nor `HOME` is
  /// available. AD-13's "never fail startup" rule is about a malformed
  /// *file*; an environment with no home would silently scatter the user's
  /// settings somewhere they would never find them, so that case is loud.
  factory AppPaths.fromEnvironment(Map<String, String> environment) {
    final warnings = <String>[];
    final configHome = _xdgHome(
      environment,
      variable: 'XDG_CONFIG_HOME',
      homeRelativeDefault: '.config',
      warnings: warnings,
    );
    final dataHome = _xdgHome(
      environment,
      variable: 'XDG_DATA_HOME',
      homeRelativeDefault: '.local/share',
      warnings: warnings,
    );
    final runtimeDirectory = _runtimeDirectory(environment, warnings);
    return AppPaths._(
      configFile: '$configHome/$applicationDirectoryName/$configFileName',
      databaseFile: '$dataHome/$applicationDirectoryName/$databaseFileName',
      runtimeDirectory: runtimeDirectory,
      warning: warnings.isEmpty ? null : warnings.join('; '),
    );
  }

  /// The directory every one of this app's XDG homes is namespaced under.
  static const String applicationDirectoryName = 'hotkey-grammar-corrector';

  /// The config file's name. It lives here, with the rest of the layout,
  /// because path resolution is this type's job — AD-13's rule is that
  /// exactly one type *opens* the file, and that is `JsonConfigStore`.
  static const String configFileName = 'config.json';

  /// The CAP-7 history store's filename (AD-7's schema lives in it).
  static const String databaseFileName = 'history.sqlite';

  /// `${XDG_CONFIG_HOME:-$HOME/.config}/…/`[configFileName].
  final String configFile;

  /// `${XDG_DATA_HOME:-$HOME/.local/share}/…/`[databaseFileName].
  final String databaseFile;

  /// Where AD-14's single-instance address is scoped, per user and session.
  final String runtimeDirectory;

  /// Human-renderable note about every degraded resolution, joined into one
  /// line. Null when each path came from the environment the XDG spec
  /// prescribes.
  final String? warning;

  static String _xdgHome(
    Map<String, String> environment, {
    required String variable,
    required String homeRelativeDefault,
    required List<String> warnings,
  }) {
    final raw = environment[variable];
    final override = _absolute(raw);
    if (override != null) {
      return override;
    }
    if (raw != null && raw.isNotEmpty) {
      warnings.add(
        '$variable is set to "$raw", which is not an absolute path; the XDG '
        'spec says to ignore it, so the HOME-relative default is used',
      );
    }
    final home = _absolute(environment['HOME']);
    if (home == null) {
      throw StateError(
        'cannot resolve $variable: it is unset or relative and HOME is not '
        'set to an absolute path either',
      );
    }
    return '$home/$homeRelativeDefault';
  }

  static String _runtimeDirectory(
    Map<String, String> environment,
    List<String> warnings,
  ) {
    final override = _absolute(environment['XDG_RUNTIME_DIR']);
    if (override != null) {
      return '$override/$applicationDirectoryName';
    }
    // The XDG spec prescribes a warned fallback for this one directory, so a
    // session without it degrades rather than refusing to start.
    final base = _absolute(environment['TMPDIR']) ?? '/tmp';
    final user =
        _nonEmpty(environment['USER']) ??
        _nonEmpty(environment['LOGNAME']) ??
        'unknown';
    final directory = '$base/$applicationDirectoryName-$user';
    warnings.add(
      'XDG_RUNTIME_DIR is unset or relative; using "$directory" as the '
      'runtime directory instead',
    );
    return directory;
  }

  /// The value without its trailing slash, or null when it is absent, empty,
  /// or relative — the XDG spec says a relative value must be ignored.
  static String? _absolute(String? value) {
    if (value == null || !value.startsWith('/')) {
      return null;
    }
    var end = value.length;
    while (end > 1 && value[end - 1] == '/') {
      end -= 1;
    }
    return value.substring(0, end);
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
