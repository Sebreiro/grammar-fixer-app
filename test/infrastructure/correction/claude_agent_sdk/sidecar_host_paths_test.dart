import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart';
import 'package:test/test.dart';

import '../../../support/declared_flutter_assets.dart';

/// The two things the shipped defaults have to get right about the host they
/// find themselves on: where the Python asset is, and which interpreter can
/// actually run it.
///
/// An installed daemon and a run from the checkout disagree about both, and
/// only one of the two answers can be a compile-time constant. The rows drive
/// the real derivations with scripted probes, and two of them build the layout
/// on disk and use the real `File.existsSync`, so the installed-bundle branch —
/// the one no test host has natively — is exercised here rather than deferred
/// to a machine nobody runs the suite on.
void main() {
  group('AD-19: where the sidecar script is', () {
    test('an AppImage stores its launcher argument across mount changes', () {
      for (final mount in ['/tmp/.mount_first', '/tmp/.mount_second']) {
        final resolved = SidecarHostPaths.resolveScript(
          executablePath: '$mount/usr/bin/hotkey_grammar_corrector',
          workingDirectory: '/home/user',
          appImagePath: '/home/user/Grammar.AppImage',
          exists: (_) => true,
        );

        expect(resolved, '--sidecar');
      }
    });

    test('an installed build resolves to the bundle copy beside the '
        'executable', () {
      const executable = '/opt/hgc/hotkey_grammar_corrector';
      const bundled =
          '/opt/hgc/data/flutter_assets/'
          'assets/sidecar/claude_agent_sdk_sidecar.py';
      final probed = <String>[];

      final resolved = SidecarHostPaths.resolveScript(
        executablePath: executable,
        workingDirectory: '/home/dev/checkout',
        exists: (candidate) {
          probed.add(candidate);
          return candidate == bundled;
        },
      );

      expect(resolved, bundled);
      expect(probed, [
        bundled,
      ], reason: 'a bundle that has the asset ends the search');
    });

    test('a run from a checkout resolves to the asset under the working '
        'directory, spelled absolutely', () {
      const workingDirectory = '/home/dev/checkout';
      const expected =
          '$workingDirectory/assets/sidecar/claude_agent_sdk_sidecar.py';

      final resolved = SidecarHostPaths.resolveScript(
        executablePath: '$workingDirectory/build/linux/x64/debug/runner/app',
        workingDirectory: workingDirectory,
        exists: (candidate) => candidate == expected,
      );

      expect(resolved, expected);
    });

    test('with the asset in neither place, the answer is the absolute bundle '
        'candidate — so the adapter names a real location', () {
      // A relative path in the failure message resolves against whatever
      // directory the session launched the daemon from, which makes the
      // adapter's "not found at ..." tell the user to look somewhere that
      // depends on their shell.
      final resolved = SidecarHostPaths.resolveScript(
        executablePath: '/opt/hgc/hotkey_grammar_corrector',
        workingDirectory: '/home/dev/checkout',
        exists: (_) => false,
      );

      expect(
        resolved,
        '/opt/hgc/data/flutter_assets/'
        'assets/sidecar/claude_agent_sdk_sidecar.py',
      );
    });

    test('an executable at the filesystem root still builds a rooted bundle '
        'candidate rather than a relative one', () {
      // The layout is spelled out rather than built from the constants under
      // test: comparing a derivation against its own inputs would pass just as
      // happily on a wrong `data/flutter_assets`.
      final probed = <String>[];

      SidecarHostPaths.resolveScript(
        executablePath: '/app',
        workingDirectory: '/home/dev/checkout',
        exists: (candidate) {
          probed.add(candidate);
          return false;
        },
      );

      expect(
        probed.first,
        '/data/flutter_assets/assets/sidecar/claude_agent_sdk_sidecar.py',
      );
    });
  });

  group('AD-19: which interpreter runs it', () {
    test('an AppImage stores its host path across mount changes', () {
      for (final mount in ['/tmp/.mount_first', '/tmp/.mount_second']) {
        final resolved = SidecarHostPaths.resolveInterpreter(
          executablePath: '$mount/usr/bin/hotkey_grammar_corrector',
          workingDirectory: '/home/user',
          appImagePath: '/home/user/Grammar.AppImage',
          exists: (_) => true,
        );

        expect(resolved, '/home/user/Grammar.AppImage');
      }
    });

    test(
      'an installed package chooses its wrapper before a checkout environment',
      () {
        final resolved = SidecarHostPaths.resolveInterpreter(
          executablePath: '/opt/hgc/hotkey_grammar_corrector',
          workingDirectory: '/home/dev/checkout',
          exists: (candidate) =>
              candidate == '/opt/hgc/sidecar-python' ||
              candidate == '/home/dev/checkout/.venv-sidecar/bin/python3',
        );

        expect(resolved, '/opt/hgc/sidecar-python');
      },
    );

    test(
      'an installed package preserves spaces in its absolute wrapper path',
      () {
        final resolved = SidecarHostPaths.resolveInterpreter(
          executablePath: '/opt/Grammar Corrector/hotkey_grammar_corrector',
          workingDirectory: '/home/dev/checkout',
          exists: (candidate) =>
              candidate == '/opt/Grammar Corrector/sidecar-python',
        );

        expect(resolved, '/opt/Grammar Corrector/sidecar-python');
      },
    );

    test('an installed build resolves to the provisioned environment beside '
        'the executable', () {
      final resolved = SidecarHostPaths.resolveInterpreter(
        executablePath: '/opt/hgc/hotkey_grammar_corrector',
        workingDirectory: '/home/dev/checkout',
        exists: (candidate) =>
            candidate == '/opt/hgc/.venv-sidecar/bin/python3',
      );

      expect(resolved, '/opt/hgc/.venv-sidecar/bin/python3');
    });

    test('a run from a checkout resolves to the environment '
        'tool/provision_sidecar.sh built there, spelled absolutely', () {
      const workingDirectory = '/home/dev/checkout';
      const expected = '$workingDirectory/.venv-sidecar/bin/python3';

      final resolved = SidecarHostPaths.resolveInterpreter(
        executablePath: '/usr/lib/dart/bin/dart',
        workingDirectory: workingDirectory,
        exists: (candidate) => candidate == expected,
      );

      expect(resolved, expected);
    });

    test('an unprovisioned host falls back to the bare command name, so the '
        'failure is the sidecar own actionable import message', () {
      // A bare name has no separator, which is exactly what the adapter's
      // preflight leaves to PATH. The correction still fails on such a host —
      // but it fails naming claude_agent_sdk, not naming a venv the user has
      // never heard of.
      final resolved = SidecarHostPaths.resolveInterpreter(
        executablePath: '/opt/hgc/hotkey_grammar_corrector',
        workingDirectory: '/home/dev/checkout',
        exists: (_) => false,
      );

      expect(resolved, 'python3');
      expect(resolved, isNot(contains('/')));
    });
  });

  group('AD-19: what gets persisted', () {
    test('the same checkout, entered from two different working directories, '
        'derives the same absolute paths', () {
      // This is the defect the working-directory parameter exists for, and this
      // story is what made it routine rather than theoretical: it ships an
      // autostart entry, so the process that reads the seeded value back has a
      // different working directory than the one that wrote it. A relative
      // answer persisted from a checkout resolves against $HOME at login, and
      // AD-13 gives ConfigStore no rule for repairing a value that was valid
      // when written — so every correction fails until the file is hand-edited.
      const first = '/home/dev/checkout';
      const second = '/srv/build/checkout';

      String resolvedFrom(String workingDirectory) =>
          SidecarHostPaths.resolveScript(
            executablePath: '/usr/lib/dart/bin/dart',
            workingDirectory: workingDirectory,
            exists: (candidate) => candidate.startsWith(workingDirectory),
          );

      expect(
        resolvedFrom(first),
        '$first/assets/sidecar/claude_agent_sdk_sidecar.py',
      );
      expect(
        resolvedFrom(second),
        '$second/assets/sidecar/claude_agent_sdk_sidecar.py',
      );
      expect(
        resolvedFrom(first),
        isNot(resolvedFrom(second)),
        reason:
            'a derivation that answered the bare repo-relative constant would '
            'return the same string for both, which is the whole defect: the '
            'string is persisted and read back by a process that is somewhere '
            'else',
      );
    });

    test('a working directory that is the filesystem root does not produce a '
        'doubled separator', () {
      final resolved = SidecarHostPaths.resolveScript(
        executablePath: '/opt/hgc/hotkey_grammar_corrector',
        workingDirectory: '/',
        exists: (candidate) =>
            candidate == '/assets/sidecar/claude_agent_sdk_sidecar.py',
      );

      expect(resolved, '/assets/sidecar/claude_agent_sdk_sidecar.py');
    });

    test('an executable path with no separator is refused rather than silently '
        'resolved against the working directory', () {
      // Answering `.` for the directory part — which it used to — reintroduced
      // exactly the CWD dependency every arm above is absolute in order to
      // avoid, on the one input where nothing would notice.
      expect(
        () => SidecarHostPaths.resolveScript(
          executablePath: 'hotkey_grammar_corrector',
          workingDirectory: '/home/dev/checkout',
          exists: (_) => false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the shipped defaults against a real bundle layout', () {
    test('AD-19: with a bundle on disk beside the executable, the real '
        'existence probe selects the bundled script and interpreter', () {
      // The seams exist for exactly this: nothing about the installed-bundle
      // branch is reachable while Platform.resolvedExecutable is hard-wired,
      // and it is the branch every user of a packaged build takes.
      final tempDir = Directory.systemTemp.createTempSync('bundle_layout_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final executable = '${tempDir.path}/hotkey_grammar_corrector';
      File(executable).writeAsStringSync('not a real binary');
      final bundledScript = File(
        '${tempDir.path}/data/flutter_assets/'
        '${SidecarHostPaths.repoRelativeScriptPath}',
      );
      bundledScript.parent.createSync(recursive: true);
      bundledScript.writeAsStringSync('# a stand-in for the shipped asset');
      final bundledInterpreter = File(
        '${tempDir.path}/${SidecarHostPaths.packagedInterpreterPath}',
      );
      bundledInterpreter.parent.createSync(recursive: true);
      bundledInterpreter.writeAsStringSync('#!/bin/sh\n');

      expect(
        DefaultAppConfig.sidecarPath(executablePath: executable),
        bundledScript.path,
      );
      expect(
        DefaultAppConfig.interpreterPath(executablePath: executable),
        bundledInterpreter.path,
      );
    });

    test('AD-19: pubspec.yaml declares the sidecar directory under '
        'flutter: assets:', () {
      // Without the declaration the bundle branch above resolves to a path
      // that will never exist, silently reinstating the defect the derivation
      // was written to fix — and every other row here would stay green,
      // because they all script their own probe.
      final directory =
          '${SidecarHostPaths.repoRelativeScriptPath.split('/').take(2).join('/')}/';

      expect(
        declaredFlutterAssets(),
        contains(directory),
        reason:
            'an undeclared asset never reaches flutter_assets, so an '
            'installed daemon would resolve the sidecar to nothing',
      );
    });
  });
}
