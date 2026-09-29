import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart';

/// The test harness that makes the AD-19 sidecar's failure branches reachable
/// without a network, a model, or a nested real `claude` process.
///
/// Three facts about `claude_agent_sdk 0.2.132` decide its shape, and each one
/// is a thing the harness has to work around rather than a preference:
///
/// 1. **The linux wheel bundles its own `claude`.** `_find_bundled_cli()` is
///    consulted *before* `shutil.which("claude")`, so a stub on `PATH` alone
///    is never spawned. [_buildPackageView] therefore builds a directory of
///    symlinks to every entry of the installed package **except `_bundled`**
///    and puts it first on `PYTHONPATH`; discovery then falls through to
///    `PATH`. Nothing inside `.venv-sidecar` is touched — the venv is shared,
///    per-machine, and provisioned by `tool/provision_sidecar.sh`.
/// 2. **The SDK opens with a control handshake.** It writes an `initialize`
///    control request and blocks on the matching `control_response` before it
///    sends the prompt, so a stub that only replayed a fixture would hang for
///    60 s and then fail as a timeout. `fake_claude_cli/claude.py` answers it.
/// 3. **The subject is the sidecar script, not the Dart adapter.** The adapter
///    exposes no environment seam — it spawns `setsid <interpreter> <script>`
///    with the ambient environment — so a row that needs a doctored `PATH` and
///    `PYTHONPATH` runs the script directly and asserts its NDJSON.
///
/// Construct one per row with [FakeClaudeCli.create] and release it with
/// [dispose]; [unavailableReason] is what a row skips on, and it is written to
/// be read out of a test run by a human who has to fix it.
final class FakeClaudeCli {
  FakeClaudeCli._({
    required this.interpreterPath,
    required this.logPath,
    required this._root,
    required this._binDirectory,
    required this._packageViewDirectory,
  });

  /// The provisioned interpreter, relative to the repository root.
  ///
  /// Taken from the shipped constant rather than respelled. There were six
  /// independent copies of these two strings across the tool, the harness and
  /// the live rows, and the failure mode of a rename is invisible: every row
  /// that depends on the venv skips when it cannot find it, so renaming
  /// `.venv-sidecar` on one side of the pair turns the whole sidecar suite green
  /// and silent. `SidecarHostPaths` is the declared home of both facts;
  /// `sidecar_pin_drift_test.dart` covers the one consumer that cannot import
  /// Dart, `tool/provision_sidecar.sh`.
  static const String venvInterpreterPath =
      SidecarHostPaths.repoRelativeInterpreterPath;

  /// The script under test. Spawned directly, because the environment is what
  /// the harness has to control and the adapter does not expose it.
  static const String sidecarScriptPath =
      SidecarHostPaths.repoRelativeScriptPath;

  static const String _stubSourcePath =
      'test/support/fake_claude_cli/claude.py';
  static const String _fixtureDirectory =
      'test/support/fake_claude_cli/fixtures';

  /// The command that turns every row this harness owns from a skip into a
  /// run. Quoted verbatim in [unavailableReason] so nobody has to find it.
  static const String provisionCommand = 'tool/provision_sidecar.sh';

  final String interpreterPath;

  /// Where the stub records what it was asked and what it replayed. A row
  /// asserts this file is non-empty, which is the only direct evidence that
  /// the SDK spawned the stub rather than reaching a real CLI.
  final String logPath;

  final Directory _root;
  final String _binDirectory;
  final String _packageViewDirectory;

  /// Why the harness cannot run here, or null when it can.
  ///
  /// Never a bare `false`: the string names the rows, the cause, and the one
  /// command that fixes it, because a skip whose reason is not in the run
  /// output is indistinguishable from a row that does not exist.
  static String? unavailableReason() {
    if (!File(venvInterpreterPath).existsSync()) {
      return 'the fake-claude-CLI rows (sidecar error branch, assistant '
          'fallback, streaming control) need the pinned sidecar environment, '
          'and $venvInterpreterPath does not exist. Create it with: '
          '$provisionCommand';
    }
    final probe = Process.runSync(venvInterpreterPath, [
      '-c',
      'import claude_agent_sdk',
    ]);
    if (probe.exitCode != 0) {
      return 'the fake-claude-CLI rows (sidecar error branch, assistant '
          'fallback, streaming control) need claude_agent_sdk importable by '
          '$venvInterpreterPath, and it is not: ${probe.stderr}. Fix it with: '
          '$provisionCommand';
    }
    return null;
  }

  /// Absolute path of the fixture the stub replays, by bare name.
  ///
  /// Existence is asserted here rather than left to the stub: a mistyped name
  /// would otherwise surface as the stub dying mid-replay, which the SDK
  /// reports as a transport error and the row reports as wrong NDJSON — three
  /// layers away from the typo.
  static String fixture(String name) {
    final path = '${Directory.current.path}/$_fixtureDirectory/$name.ndjson';
    if (!File(path).existsSync()) {
      throw ArgumentError.value(name, 'name', 'no such fixture at $path');
    }
    return path;
  }

  /// Builds a throwaway `PATH` entry holding the stub and a `claude_agent_sdk`
  /// view with no bundled CLI in it.
  static FakeClaudeCli create() {
    final root = Directory.systemTemp.createTempSync('fake_claude_cli_');
    final binDirectory = '${root.path}/bin';
    Directory(binDirectory).createSync();
    final logPath = '${root.path}/stub.log';

    _writeStubLauncher(
      launcherPath: '$binDirectory/claude',
      interpreterPath: venvInterpreterPath,
    );
    final packageViewDirectory = _buildPackageView(root);
    _assertNoBundledCliIsVisible(packageViewDirectory);

    return FakeClaudeCli._(
      interpreterPath: venvInterpreterPath,
      logPath: logPath,
      root: root,
      binDirectory: binDirectory,
      packageViewDirectory: packageViewDirectory,
    );
  }

  /// The environment the sidecar must run under for the stub to be the CLI the
  /// SDK finds.
  Map<String, String> environmentFor(String fixturePath) => {
    // First on PATH, so shutil.which("claude") resolves to the stub.
    'PATH': _prepended(_binDirectory, Platform.environment['PATH']),
    // First on PYTHONPATH, so the bundled-CLI-free view of the package wins
    // over the installed one. Prepended rather than replacing: a developer
    // with their own PYTHONPATH should get the same result as one without,
    // and the view only has to win — it does not have to be alone.
    'PYTHONPATH': _prepended(
      _packageViewDirectory,
      Platform.environment['PYTHONPATH'],
    ),
    // Without this the SDK runs `claude -v` first; the stub answers it anyway,
    // but skipping the probe keeps the row's failure surface to one spawn.
    'CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK': '1',
    'FAKE_CLAUDE_FIXTURE': fixturePath,
    'FAKE_CLAUDE_LOG': logPath,
  };

  /// Runs the sidecar under this harness with [fixtureName] replayed, feeding
  /// it one AD-19 request line and closing stdin, exactly as the adapter does.
  Future<ProcessResult> runSidecar({
    required String fixtureName,
    String text = 'i has went to the store yesterday',
    String model = 'claude-sonnet-5',
    String systemPrompt = 'reply with the four shipped lines',
  }) async {
    final process = await Process.start(interpreterPath, [
      sidecarScriptPath,
    ], environment: environmentFor(fixture(fixtureName)));
    // Encoded, never interpolated: a row whose text carries a quote, a
    // backslash or a newline would otherwise reach the sidecar as a broken
    // line and fail as a decode error rather than as whatever it was testing.
    process.stdin.writeln(
      jsonEncode({'text': text, 'model': model, 'system_prompt': systemPrompt}),
    );
    await process.stdin.close();
    // Both pipes are drained concurrently: a row whose stderr filled its pipe
    // buffer while only stdout was being read would deadlock rather than fail.
    final streams = await Future.wait([
      process.stdout.transform(_decoder).join(),
      process.stderr.transform(_decoder).join(),
    ]);
    // Bounded, and killed on the bound. DW-92 records that an SDK upgrade
    // breaking the control handshake surfaces "like a hang", and an unbounded
    // wait spends that hang as the framework's own 30 s timeout — a row that
    // reports nothing about why. Worse, the timeout tears the row down while the
    // process is still alive, so [dispose] deletes the stub launcher and the
    // package view out from under it and leaves it orphaned.
    final exitCode = await process.exitCode.timeout(
      _sidecarDeadline,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException(
          'the sidecar did not exit within $_sidecarDeadline under the fake '
          'CLI. The stub replays a fixture and exits, so a hang means the SDK '
          'never reached it — most likely the control handshake or the bundled-'
          'CLI discovery changed (deferred-work DW-92). Stub log: $logPath',
        );
      },
    );
    return ProcessResult(process.pid, exitCode, streams[0], streams[1]);
  }

  /// Long enough that a cold interpreter start is never mistaken for a hang,
  /// short enough to beat the test framework's own timeout so the failure is
  /// this class's explanation rather than an anonymous one.
  static const Duration _sidecarDeadline = Duration(seconds: 20);

  void dispose() {
    if (_root.existsSync()) {
      _root.deleteSync(recursive: true);
    }
  }

  /// Malformed bytes are replaced rather than thrown on: a row asserting that
  /// stderr is *empty* must fail on the traceback it found, not on a decode
  /// error while reading it.
  static const _decoder = Utf8Decoder(allowMalformed: true);

  /// [head] first, then whatever the developer already had. An empty tail is
  /// dropped rather than joined, because a trailing separator means "the
  /// current directory" to both PATH and PYTHONPATH.
  static String _prepended(String head, String? existing) =>
      (existing == null || existing.isEmpty) ? head : '$head:$existing';

  /// A shell launcher rather than a copy of the stub, because the SDK spawns
  /// whatever `PATH` names and the stub is Python: the launcher is what makes
  /// the file on `PATH` directly executable under any host interpreter.
  static void _writeStubLauncher({
    required String launcherPath,
    required String interpreterPath,
  }) {
    final stubPath = '${Directory.current.path}/$_stubSourcePath';
    final absoluteInterpreter = '${Directory.current.path}/$interpreterPath';
    File(launcherPath).writeAsStringSync(
      '#!/bin/sh\n'
      '# Generated by test/support/fake_claude_cli.dart.\n'
      'FAKE_CLAUDE_INVOKED_AS="\$0"\n'
      'export FAKE_CLAUDE_INVOKED_AS\n'
      'exec "$absoluteInterpreter" "$stubPath" "\$@"\n',
    );
    Process.runSync('chmod', ['+x', launcherPath]);
  }

  /// A `claude_agent_sdk` package that is the installed one minus `_bundled`.
  ///
  /// Symlinks per entry, never a copy: the package carries a ~282 MB bundled
  /// CLI and copying it per row would be the slowest thing in the suite. The
  /// omission is the entire point — with `_bundled/claude` absent,
  /// `_find_bundled_cli()` returns None and discovery reaches `PATH`.
  static String _buildPackageView(Directory root) {
    final installed = Directory(_installedPackageDirectory());
    final view = Directory('${root.path}/sdk_view/claude_agent_sdk')
      ..createSync(recursive: true);
    for (final entry in installed.listSync()) {
      final name = entry.path.split('/').last;
      if (name == '_bundled') {
        continue;
      }
      Link('${view.path}/$name').createSync(entry.path);
    }
    return '${root.path}/sdk_view';
  }

  /// Refuses to run a row whose environment could still reach a real `claude`.
  ///
  /// The `_bundled` omission is the only thing standing between this harness and
  /// spawning the wheel's own ~282 MB CLI, and that is the process the intent
  /// forbids outright — it has been observed terminating the surrounding
  /// session. The existing evidence for the omission working is the stub's log
  /// file, which is read *after* the spawn: by the time it says the wrong binary
  /// ran, the wrong binary has run.
  ///
  /// So the view is interrogated through the SDK's own discovery function before
  /// anything is started. A future SDK that finds a bundled CLI some other way
  /// fails here, with the reason named, instead of reaching for the network.
  static void _assertNoBundledCliIsVisible(String packageViewDirectory) {
    final probe = Process.runSync(
      venvInterpreterPath,
      const [
        '-c',
        // The finder is an instance method that never touches `self`, so it is
        // called unbound: constructing a transport would open a connection,
        // which is the thing being guarded against.
        'from claude_agent_sdk._internal.transport.subprocess_cli import '
            'SubprocessCLITransport as t; '
            'print(t._find_bundled_cli(None) or "")',
      ],
      environment: {
        'PATH': '/nonexistent',
        'PYTHONPATH': _prepended(
          packageViewDirectory,
          Platform.environment['PYTHONPATH'],
        ),
      },
    );
    if (probe.exitCode != 0) {
      throw StateError(
        'the fake-CLI harness could not ask claude_agent_sdk whether it still '
        'sees a bundled CLI, so it cannot promise no real `claude` will be '
        'spawned. This is the SDK-internals dependency recorded as DW-92; the '
        'pin moved or the private API did. Interpreter said: ${probe.stderr}',
      );
    }
    final found = (probe.stdout as String).trim();
    if (found.isNotEmpty) {
      throw StateError(
        'the package view still exposes a bundled `claude` at $found, so the '
        'SDK would spawn a real CLI rather than the stub. Refusing to run: a '
        'nested real `claude` has been observed terminating the session.',
      );
    }
  }

  static String _installedPackageDirectory() {
    final located = Process.runSync(venvInterpreterPath, [
      '-c',
      'import claude_agent_sdk, os; '
          'print(os.path.dirname(claude_agent_sdk.__file__))',
    ]);
    if (located.exitCode != 0) {
      throw StateError(
        'could not locate the installed package: ${located.stderr}',
      );
    }
    return (located.stdout as String).trim();
  }
}
