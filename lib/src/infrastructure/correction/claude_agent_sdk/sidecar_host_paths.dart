/// The two host-dependent paths AD-19 needs, derived rather than compiled in.
///
/// A checkout and an installed bundle disagree about both of them, and the
/// daemon has no say in which one it is. `flutter build linux` copies `assets/`
/// into `data/flutter_assets/` beside the executable, while a run from the repo
/// has no such directory and reads the asset out of the working tree; and the
/// pinned interpreter `tool/provision_sidecar.sh` builds lives beside whichever
/// of the two roots the daemon was started from. A compiled-in constant is
/// therefore correct for exactly one case and wrong for the other — and the
/// interpreter constant was wrong for *both*, because a bare `python3` is
/// whatever the session's `PATH` resolves, which is precisely the interpreter
/// that cannot import the SDK.
///
/// All three inputs are injected — the executable's own path, the working
/// directory, and a probe for whether a candidate exists — so each decision is a
/// pure function of its arguments and the installed-bundle case is reachable
/// from a headless test without an installed bundle. Deciding here and acting in
/// the caller is AGENTS.md §2's split between decision and I/O.
///
/// The working directory is a parameter rather than something read here for the
/// same reason: what these methods return is written into the config file once
/// and read back for the lifetime of the install, so "resolve it later, against
/// wherever the process happens to be" is not an option the answers can carry.
/// Every file path returned is absolute. AppImages instead persist the stable
/// image path and a launcher argument because their mount path changes on each
/// start.
///
/// These are only *defaults*. AD-19 keeps both effective paths config values,
/// so what this returns seeds a fresh install and is overridable afterwards.
final class SidecarHostPaths {
  const SidecarHostPaths._();

  /// The asset as it is addressed from the repository root — also what a bundle
  /// path is built out of, because `flutter build` preserves the declared asset
  /// layout underneath [bundleAssetRoot].
  static const String repoRelativeScriptPath =
      'assets/sidecar/claude_agent_sdk_sidecar.py';

  /// Where a Linux bundle puts its assets, relative to the executable.
  static const String bundleAssetRoot = 'data/flutter_assets';

  /// The interpreter `tool/provision_sidecar.sh` builds, addressed from the
  /// root it was built under. Untracked and per-machine, so it is found by
  /// probing rather than assumed.
  static const String repoRelativeInterpreterPath = '.venv-sidecar/bin/python3';

  /// The portable wrapper installed beside every packaged Linux executable.
  static const String packagedInterpreterPath = 'sidecar-python';

  /// The AppImage launcher's sidecar entry point. The AppImage mount path is
  /// temporary, so a config value must not persist any path inside that mount.
  static const String appImageSidecarArgument = '--sidecar';

  /// The last resort when no provisioned environment is found: a bare command
  /// name, which the adapter's preflight deliberately leaves to `PATH`.
  static const String interpreterCommand = 'python3';

  /// Where the sidecar script is: an AppImage launcher argument when the host
  /// image path is known, otherwise a bundled or checkout file path.
  ///
  /// File paths are **absolute**. That is not tidiness: what this returns is
  /// persisted by the config store at seed time and never re-derived,
  /// so a relative answer is not a path but a path *plus* an unrecorded
  /// dependency on the shell that produced it. This story ships an autostart
  /// entry, which makes the divergence a routine event rather than a corner
  /// case — a developer provisions and seeds from a checkout, logs in, and the
  /// autostarted daemon resolves the same stored string against `$HOME`.
  ///
  /// The last arm is the interesting one. When neither location holds the file
  /// the run is going to fail either way, and what decides how *legibly* it
  /// fails is which path the adapter names in its message: the absolute bundle
  /// candidate names a real, checkable place.
  static String resolveScript({
    required String executablePath,
    required bool Function(String candidate) exists,
    required String workingDirectory,
    String? appImagePath,
  }) {
    if (appImagePath != null && appImagePath.startsWith('/')) {
      return appImageSidecarArgument;
    }
    final bundled = _besideExecutable(
      executablePath,
      '$bundleAssetRoot/$repoRelativeScriptPath',
    );
    if (exists(bundled)) {
      return bundled;
    }
    final inWorkingTree = _under(workingDirectory, repoRelativeScriptPath);
    if (exists(inWorkingTree)) {
      return inWorkingTree;
    }
    return bundled;
  }

  /// Which interpreter to run the sidecar with: the stable AppImage path when
  /// available, else the provisioned environment, else the bare command name.
  ///
  /// The first two arms are absolute, for the reason [resolveScript] gives; the
  /// last is deliberately bare.
  ///
  /// The bare name is a genuine fallback rather than a preference. An
  /// unprovisioned host has no better answer, and `python3` at least produces
  /// the sidecar's own "cannot import claude_agent_sdk" message — which names
  /// the package and is actionable — instead of a missing-file error about a
  /// venv the user has never heard of.
  static String resolveInterpreter({
    required String executablePath,
    required bool Function(String candidate) exists,
    required String workingDirectory,
    String? appImagePath,
  }) {
    if (appImagePath != null && appImagePath.startsWith('/')) {
      return appImagePath;
    }
    final packaged = _besideExecutable(executablePath, packagedInterpreterPath);
    if (exists(packaged)) {
      return packaged;
    }
    final beside = _besideExecutable(
      executablePath,
      repoRelativeInterpreterPath,
    );
    if (exists(beside)) {
      return beside;
    }
    final inWorkingTree = _under(workingDirectory, repoRelativeInterpreterPath);
    if (exists(inWorkingTree)) {
      return inWorkingTree;
    }
    return interpreterCommand;
  }

  static String _besideExecutable(String executablePath, String relative) =>
      _under(_directoryOf(executablePath), relative);

  /// [relative] under [directory], with the filesystem root spelled once.
  static String _under(String directory, String relative) =>
      directory == '/' ? '/$relative' : '$directory/$relative';

  /// The directory part of a Linux path. Deliberately not `dart:io`'s: this
  /// file stays import-free so it is testable as plain string logic, and the
  /// target is Linux only (AGENTS.md).
  ///
  /// A path with no separator has no directory part to speak of, and answering
  /// `.` would silently reintroduce the CWD dependency every arm above is
  /// absolute in order to avoid. The only caller passes an executable path, so
  /// a separator-less value is a programming error rather than a host state.
  static String _directoryOf(String path) {
    final lastSeparator = path.lastIndexOf('/');
    if (lastSeparator < 0) {
      throw ArgumentError.value(
        path,
        'executablePath',
        'expected an absolute Linux path',
      );
    }
    if (lastSeparator == 0) {
      return '/';
    }
    return path.substring(0, lastSeparator);
  }
}
