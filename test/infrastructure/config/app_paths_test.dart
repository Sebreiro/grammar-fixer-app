import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:test/test.dart';

/// Behaviour tests for `AppPaths`, the one type that resolves the XDG layout
/// (Consistency Conventions). Every row runs against an injected environment
/// map — no real session, no Flutter binding, no filesystem.
void main() {
  group('XDG overrides', () {
    test('CAP-8: an environment with all three XDG homes set resolves both '
        'files and the runtime directory under them, warning about '
        'nothing', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_CONFIG_HOME': '/x',
        'XDG_DATA_HOME': '/y',
        'XDG_RUNTIME_DIR': '/z',
      });

      expect(paths.configFile, '/x/hotkey-grammar-corrector/config.json');
      expect(
        paths.logFile,
        '/x/hotkey-grammar-corrector/logs/grammmar-corrector.log',
      );
      expect(paths.databaseFile, '/y/hotkey-grammar-corrector/history.sqlite');
      expect(paths.runtimeDirectory, '/z/hotkey-grammar-corrector');
      expect(paths.warning, isNull);
    });

    test('CAP-8: with no XDG overrides the paths fall back to the '
        'HOME-relative defaults', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_RUNTIME_DIR': '/run/user/1000',
      });

      expect(
        paths.configFile,
        '/home/u/.config/hotkey-grammar-corrector/config.json',
      );
      expect(
        paths.databaseFile,
        '/home/u/.local/share/hotkey-grammar-corrector/history.sqlite',
      );
      expect(
        paths.logFile,
        '/home/u/.config/hotkey-grammar-corrector/logs/grammmar-corrector.log',
      );
      expect(paths.warning, isNull);
    });

    test('CAP-8: a relative XDG value is invalid per the spec, is ignored in '
        'favour of the HOME default, and says so', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_CONFIG_HOME': 'relative/path',
        'XDG_DATA_HOME': 'also/relative',
        'XDG_RUNTIME_DIR': '/run/user/1000',
      });

      expect(
        paths.configFile,
        '/home/u/.config/hotkey-grammar-corrector/config.json',
      );
      expect(
        paths.databaseFile,
        '/home/u/.local/share/hotkey-grammar-corrector/history.sqlite',
      );
      expect(
        paths.warning,
        allOf(
          contains('XDG_CONFIG_HOME'),
          contains('relative/path'),
          contains('XDG_DATA_HOME'),
        ),
        reason:
            'a user who set the variable would otherwise edit a file the '
            'daemon never reads',
      );
    });

    test('CAP-8: several degraded resolutions are reported together, not one '
        'at the expense of the rest', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_CONFIG_HOME': 'relative/path',
        'USER': 'ada',
      });

      expect(
        paths.warning,
        allOf(contains('XDG_CONFIG_HOME'), contains('XDG_RUNTIME_DIR')),
      );
    });

    test('CAP-8: a trailing slash on an XDG home does not double up in the '
        'resolved path', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_CONFIG_HOME': '/x/',
        'XDG_DATA_HOME': '/y/',
        'XDG_RUNTIME_DIR': '/z/',
      });

      expect(paths.configFile, '/x/hotkey-grammar-corrector/config.json');
      expect(
        paths.logFile,
        '/x/hotkey-grammar-corrector/logs/grammmar-corrector.log',
      );
      expect(paths.databaseFile, '/y/hotkey-grammar-corrector/history.sqlite');
      expect(paths.runtimeDirectory, '/z/hotkey-grammar-corrector');
    });
  });

  group('runtime directory fallback (AD-14)', () {
    test('AD-14: no XDG_RUNTIME_DIR falls back under TMPDIR with the user '
        'name, and says so in the warning', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'TMPDIR': '/scratch',
        'USER': 'ada',
      });

      expect(paths.runtimeDirectory, '/scratch/hotkey-grammar-corrector-ada');
      expect(paths.warning, contains('/scratch/hotkey-grammar-corrector-ada'));
      expect(paths.warning, contains('XDG_RUNTIME_DIR'));
    });

    test('AD-14: an empty XDG_RUNTIME_DIR is treated as unset and /tmp is the '
        'default base', () {
      final paths = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'XDG_RUNTIME_DIR': '',
        'USER': 'ada',
      });

      expect(paths.runtimeDirectory, '/tmp/hotkey-grammar-corrector-ada');
      expect(paths.warning, isNotNull);
    });

    test('AD-14: the user segment falls back USER, then LOGNAME, then '
        'unknown', () {
      final logname = AppPaths.fromEnvironment(const {
        'HOME': '/home/u',
        'LOGNAME': 'grace',
      });
      final neither = AppPaths.fromEnvironment(const {'HOME': '/home/u'});

      expect(logname.runtimeDirectory, '/tmp/hotkey-grammar-corrector-grace');
      expect(neither.runtimeDirectory, '/tmp/hotkey-grammar-corrector-unknown');
    });
  });

  group('a home that cannot be resolved', () {
    test('CAP-8: neither HOME nor an absolute XDG override throws a '
        'StateError naming the missing variable', () {
      expect(
        () => AppPaths.fromEnvironment(const {}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('HOME'), contains('XDG_CONFIG_HOME')),
          ),
        ),
      );
    });

    test('CAP-8: a missing HOME is survivable when every XDG home is set '
        'absolutely', () {
      final paths = AppPaths.fromEnvironment(const {
        'XDG_CONFIG_HOME': '/x',
        'XDG_DATA_HOME': '/y',
        'XDG_RUNTIME_DIR': '/z',
      });

      expect(paths.configFile, '/x/hotkey-grammar-corrector/config.json');
      expect(
        paths.logFile,
        '/x/hotkey-grammar-corrector/logs/grammmar-corrector.log',
      );
    });

    test(
      'CAP-8: a missing HOME still throws when only one XDG home is set',
      () {
        expect(
          () => AppPaths.fromEnvironment(const {'XDG_CONFIG_HOME': '/x'}),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('XDG_DATA_HOME'),
            ),
          ),
        );
      },
    );
  });
}
