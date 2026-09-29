import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'package:test/test.dart';

/// ARCH-02's consequence, exercised as the pure function it is: the answer
/// decides whether AD-11's step 1 runs at all, it is asked once at startup, and
/// a wrong answer is silent — a Register skipped on a host that needed it
/// orphans the app-id association and the compositor discards the bind.
///
/// Pure Dart over an injected map and an injected probe: no sandbox, no
/// filesystem, no binding (AGENTS.md §7). Both branches are reachable here,
/// which is the whole reason the probe is a parameter.
void main() {
  /// A probe that answers for a named set and false for everything else, so a
  /// row asserting the sandboxed branch cannot pass by answering true to any
  /// path at all.
  bool Function(String) probeFinding(Set<String> present) =>
      (path) => present.contains(path);

  final nothingExists = probeFinding(const {});

  group('the sandbox supplies the app id', () {
    test('/.flatpak-info existing is enough on its own', () {
      expect(
        PortalAppIdRegime.fromEnvironment(
          const {},
          fileExists: probeFinding({PortalAppIdRegime.sandboxInfoFile}),
        ),
        PortalAppIdRegime.sandboxSupplied,
      );
    });

    test('FLATPAK_ID is enough on its own, with no readable filesystem', () {
      // The second signal is not redundant: the environment survives a
      // filesystem view this process may not be able to read.
      expect(
        PortalAppIdRegime.fromEnvironment(const {
          'FLATPAK_ID': 'com.divertedriver.HotkeyGrammarCorrector',
        }, fileExists: nothingExists),
        PortalAppIdRegime.sandboxSupplied,
      );
    });

    test('FLATPAK_ID is trimmed, like every other environment read here', () {
      expect(
        PortalAppIdRegime.fromEnvironment(const {
          'FLATPAK_ID': '  com.divertedriver.HotkeyGrammarCorrector  ',
        }, fileExists: nothingExists),
        PortalAppIdRegime.sandboxSupplied,
      );
    });
  });

  group('the host registry owns the app id', () {
    test('an empty environment and an empty filesystem answer hostRegistry', () {
      // The fallback, and the direction the argument runs: a Register on a host
      // with no such interface is already tolerated, while skipping it on a
      // host that needed it fails silently.
      expect(
        PortalAppIdRegime.fromEnvironment(const {}, fileExists: nothingExists),
        PortalAppIdRegime.hostRegistry,
      );
    });

    test('an empty FLATPAK_ID is absence, not a sandbox', () {
      expect(
        PortalAppIdRegime.fromEnvironment(const {
          'FLATPAK_ID': '   ',
        }, fileExists: nothingExists),
        PortalAppIdRegime.hostRegistry,
      );
    });

    test('the rejected container markers do not move the answer', () {
      // The objection this predicate exists to answer, stated as a row.
      // `/.dockerenv` is true in this project's own development container, and
      // a detector keyed on it would take the sandboxed branch in every test
      // run — leaving AD-11's first invariant executed by nothing.
      expect(
        PortalAppIdRegime.fromEnvironment(
          const {'container': 'docker'},
          fileExists: probeFinding(const {
            '/.dockerenv',
            '/run/.containerenv',
            '/proc/self/cgroup',
          }),
        ),
        PortalAppIdRegime.hostRegistry,
      );
    });
  });

  test('measured: this project\'s own container answers hostRegistry', () {
    // The row that makes the recorded measurement a gate rather than a comment
    // in the predicate's doc. It reads the real environment and the real
    // filesystem on purpose — this is the one claim that cannot be made with
    // injected inputs, and it is the claim the adapter's old objection asked
    // for. On a genuinely sandboxed host it answers `sandboxSupplied`, which is
    // also correct, so the assertion is conditional on what is actually there
    // rather than on where it happens to run.
    final flatpakInfoExists = File(
      PortalAppIdRegime.sandboxInfoFile,
    ).existsSync();
    final flatpakId = Platform.environment['FLATPAK_ID']?.trim() ?? '';
    final sandboxed = flatpakInfoExists || flatpakId.isNotEmpty;

    expect(
      PortalAppIdRegime.fromEnvironment(
        Platform.environment,
        fileExists: (path) => File(path).existsSync(),
      ),
      sandboxed
          ? PortalAppIdRegime.sandboxSupplied
          : PortalAppIdRegime.hostRegistry,
      reason:
          'the predicate must agree with the two signals it is allowed to '
          'read, and with nothing else this host happens to carry',
    );
  });
}
