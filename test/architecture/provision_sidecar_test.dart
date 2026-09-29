import 'dart:io';

import 'package:test/test.dart';

/// `tool/provision_sidecar.sh`, driven end to end against a temporary root.
///
/// Its sibling installer is exercised by `desktop_entries_test.dart`; this one
/// was executed by nothing, which mattered because it carries a *third* reader
/// of the `claude_agent_sdk` pin — after `requirements.txt` and the spine's
/// Stack table — and a third reader that disagrees with the other two turns a
/// correct install into a failure the script blames on the environment.
///
/// Nothing here installs anything, reaches the network, or touches the real
/// `.venv-sidecar`. The script is copied into a temp root beside a fixture
/// `requirements.txt` and a stub interpreter, which is enough to reach
/// `read_pin`, the resolved-version probe and the comparison between them.
void main() {
  group('the pin reader', () {
    test('a trailing comment is not part of the version', () {
      // The bug this pins: `${line#*==}` keeps the comment, so the script
      // installs the right version and then fails its own verification.
      final root = _root(
        requirements:
            'claude-agent-sdk==0.2.132  # keep in sync with the spine\n',
        reportedVersion: '0.2.132',
      );

      final result = _run(root);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('claude_agent_sdk 0.2.132'));
    });

    test('a second pinning line is refused rather than silently resolved to '
        'the first', () {
      final root = _root(
        requirements:
            'claude-agent-sdk==0.2.132\n'
            'claude-agent-sdk==0.2.131\n',
        reportedVersion: '0.2.132',
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('2 lines'));
    });

    test('a pinning line with no version after == fails as a parse problem, '
        'not as a version mismatch', () {
      // `sed` without -n prints a non-matching line unchanged, so this used to
      // make the pin the whole requirement line and the script then blamed the
      // environment: "pins claude-agent-sdk==claude-agent-sdk== but the
      // environment resolved 0.2.132". The exit code was non-zero either way,
      // so the message is what this row is about.
      final root = _root(
        requirements: 'claude-agent-sdk==\n',
        reportedVersion: '0.2.132',
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('no version after it'));
    });

    test('a requirements file pinning nothing fails naming the '
        'distribution', () {
      final root = _root(
        requirements: '# nothing here\nsomething-else==1.0.0\n',
        reportedVersion: '0.2.132',
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('claude-agent-sdk'));
    });
  });

  group('the provisioning decision', () {
    test('an environment that already resolves the pin is reported and left '
        'alone, so a rerun is offline and idempotent', () {
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.132',
      );

      final first = _run(root);
      final second = _run(root);

      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');
      expect(second.exitCode, 0);
      expect(first.stdout, contains('already provisioned'));
      expect(second.stdout, first.stdout);
      expect(
        first.stdout,
        contains('.venv-sidecar/bin/python3'),
        reason: 'the interpreter path is the one thing a caller needs next',
      );
    });

    test('an environment resolving a different version aborts naming both, '
        'rather than reporting a provisioned host', () {
      // The failure the verification step exists for: pip resolving something
      // other than the pin — an index override, a cached wheel, a manual
      // install — must not pass as success.
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.131',
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('0.2.132'));
      expect(result.stderr, contains('0.2.131'));
    });

    test('an environment with no pip prints the bootstrap rather than failing '
        'somewhere inside venv', () {
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.131',
        hasPip: false,
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('get-pip.py'));
      expect(
        result.stdout,
        contains('rerun this script'),
        reason: 'a bootstrap the user cannot act on is a mystery failure',
      );
    });

    test('a metadata directory left behind by a broken install is not reported '
        'as a provisioned host', () {
      // `importlib.metadata.version()` reads dist-info, which outlives the code
      // it describes — a partially removed package, a wheel for another ABI, a
      // broken native dependency. Reporting the pin from metadata alone made the
      // script declare success on a host where `import claude_agent_sdk` fails,
      // and every fake-CLI row then skipped on its own import probe: a green
      // `dart test` that ran none of the sidecar.
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.132',
        canImportModule: false,
      );

      final result = _run(root);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('cannot import claude_agent_sdk'));
      expect(
        result.stdout,
        isNot(contains('already provisioned')),
        reason: 'the metadata alone must not stand in for a working import',
      );
    });
  });

  group('the fresh-machine path', () {
    // Every row above pre-creates an executable stub at .venv-sidecar/bin/python3,
    // so `[ ! -x "$venv_python" ]` was never true and create_venv — the whole
    // reason the script exists, and the branch a clean checkout and a CI runner
    // both take — was executed by nothing. These two rows omit the stub venv and
    // put a stub `python3` first on PATH instead.

    test('with no environment yet it creates one with the host python3', () {
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.132',
        withStubVenv: false,
      );

      final result = _run(root, hostPythonIn: root);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        File('$root/.venv-sidecar/bin/python3').existsSync(),
        isTrue,
        reason: 'the venv the whole script exists to build',
      );
      expect(result.stdout, contains('claude_agent_sdk 0.2.132'));
    });

    test('a host python3 with no ensurepip says so and prints the pip '
        'bootstrap, rather than failing inside venv', () {
      // The branch this devcontainer itself takes: /usr/bin/python3 here has no
      // ensurepip, so the one host the script is most often run on was the one
      // host whose path no row covered.
      final root = _root(
        requirements: 'claude-agent-sdk==0.2.132\n',
        reportedVersion: '0.2.132',
        withStubVenv: false,
        hostHasEnsurepip: false,
      );

      final result = _run(root, hostPythonIn: root);

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('no ensurepip'));
      expect(result.stdout, contains('get-pip.py'));
    });
  });
}

/// A temp tree holding the real script, a fixture `requirements.txt`, and the
/// stub interpreters that answer the probes the script makes.
///
/// The stubs are what keep this offline. The venv interpreter reports
/// [reportedVersion] for the metadata query, refuses the import probe when
/// [canImportModule] is false, and refuses the pip probe when [hasPip] is false —
/// so every branch is reached without anything ever being installed.
///
/// [withStubVenv] is the switch between the two halves of the script. With it
/// true the environment already exists and the rows exercise the reader, the
/// comparison and the install decision; with it false there is no environment at
/// all, which is the only way to reach `create_venv` — and `create_venv` needs a
/// host `python3`, supplied by `_run`'s [_run.hostPythonIn].
String _root({
  required String requirements,
  required String reportedVersion,
  bool hasPip = true,
  bool canImportModule = true,
  bool withStubVenv = true,
  bool hostHasEnsurepip = true,
}) {
  final tempDir = Directory.systemTemp.createTempSync('provision_sidecar_');
  addTearDown(() => tempDir.deleteSync(recursive: true));
  final root = tempDir.path;

  final script = File('$root/tool/provision_sidecar.sh');
  script.parent.createSync(recursive: true);
  File('tool/provision_sidecar.sh').copySync(script.path);

  final fixture = File('$root/assets/sidecar/requirements.txt');
  fixture.parent.createSync(recursive: true);
  fixture.writeAsStringSync(requirements);

  // Three arms, in this order on purpose. The first is the combined probe the
  // script actually makes (import *and* metadata); the second is a
  // metadata-only query, which always succeeds because dist-info outlives the
  // code it describes — that asymmetry is what makes [canImportModule] a
  // mutation gate rather than a restatement of the script. Collapsing the first
  // two into one arm keyed on the flag would let a script that dropped the
  // import back to metadata-only keep passing.
  const failure =
      'echo "ModuleNotFoundError: No module named '
      "'claude_agent_sdk'\" >&2; exit 1";
  final venvStub =
      '#!/bin/sh\n'
      '# Stub interpreter written by test/architecture/provision_sidecar_test.dart.\n'
      'case "\$*" in\n'
      '  *"import claude_agent_sdk; import importlib.metadata"*)\n'
      '    ${canImportModule ? 'echo "$reportedVersion"; exit 0' : failure} ;;\n'
      '  *importlib.metadata*)\n'
      '    echo "$reportedVersion"; exit 0 ;;\n'
      '  *"import claude_agent_sdk"*)\n'
      '    ${canImportModule ? 'exit 0' : failure} ;;\n'
      '  *pip*)\n'
      '    if [ -f "\$(dirname "\$0")/../.no_pip" ]; then exit 1; fi\n'
      '    ${hasPip ? 'echo "pip 24.0"; exit 0' : 'exit 1'} ;;\n'
      'esac\n'
      'exit 0\n';

  // Kept beside the tree rather than inside .venv-sidecar, because the
  // create_venv rows need it *after* the script has decided the directory does
  // not exist: the host stub copies it into place as `python3 -m venv` would.
  final template = File('$root/venv_python_template')
    ..writeAsStringSync(venvStub);

  if (withStubVenv) {
    final interpreter = File('$root/.venv-sidecar/bin/python3');
    interpreter.parent.createSync(recursive: true);
    interpreter.writeAsStringSync(venvStub);
    Process.runSync('chmod', ['+x', interpreter.path]);
  }

  // The host interpreter `create_venv` finds via `command -v python3`. It
  // answers the ensurepip probe and, for `-m venv <dir>`, materialises the venv
  // stub — marking it pip-less when it was asked for `--without-pip`, which is
  // what makes the bootstrap branch observable.
  final hostBin = File('$root/hostbin/python3');
  hostBin.parent.createSync(recursive: true);
  hostBin.writeAsStringSync(
    '#!/bin/sh\n'
    '# Stub host interpreter written by test/architecture/provision_sidecar_test.dart.\n'
    'case "\$*" in\n'
    '  *"import ensurepip"*) ${hostHasEnsurepip ? 'exit 0' : 'exit 1'} ;;\n'
    '  *"-m venv"*)\n'
    '    target=""\n'
    '    for a in "\$@"; do target="\$a"; done\n'
    '    mkdir -p "\$target/bin"\n'
    '    cp "${template.path}" "\$target/bin/python3"\n'
    '    chmod +x "\$target/bin/python3"\n'
    '    case "\$*" in *--without-pip*) : > "\$target/.no_pip" ;; esac\n'
    '    exit 0 ;;\n'
    'esac\n'
    'exit 0\n',
  );
  Process.runSync('chmod', ['+x', script.path, hostBin.path]);
  return root;
}

/// Runs the copied script. [hostPythonIn] puts that root's stub `python3` first
/// on `PATH`, which is how a `create_venv` row keeps the real interpreter — and
/// the real `python3 -m venv` — out of it.
ProcessResult _run(String root, {String? hostPythonIn}) => Process.runSync(
  '$root/tool/provision_sidecar.sh',
  const [],
  environment: hostPythonIn == null
      ? const {}
      : {
          'PATH':
              '$hostPythonIn/hostbin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        },
);
