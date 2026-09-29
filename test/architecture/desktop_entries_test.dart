import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart';
import 'package:test/test.dart';

/// AD-11's app-id desktop entry and AD-14's autostart entry, and the one string
/// they both have to agree with.
///
/// AD-11 makes the app-id entry a precondition of the Wayland hotkey working at
/// all: GNOME discards the bind when the registered app id has no installed
/// desktop entry of the same basename. That makes this a behaviour gate wearing
/// a packaging costume — and the failure it guards against is silent, because
/// an id mismatch produces a working portal handshake and a hotkey that never
/// fires.
///
/// **What this file does not observe.** There is no compositor, no
/// `xdg-desktop-portal`, no session bus and no `desktop-file-validate` in this
/// container, so nothing here is evidence about a desktop. It reads bytes, and
/// it runs the installer into a temporary XDG tree and reads the bytes it
/// wrote. That the compositor then honours them is owed on a real session.
void main() {
  // Read inside each row rather than once at the top: a file that has gone
  // missing must fail the rows that depend on it, not fail the suite to load,
  // because a suite that never loads reports nothing about the rows it holds.
  _DesktopEntry entry() => _DesktopEntry.read(_appIdEntryPath);
  _DesktopEntry autostart() => _DesktopEntry.read(_autostartEntryPath);

  group('the three spellings of the app id (AD-11)', () {
    test('AD-11: the packaging file basename, the registered app id and the '
        'GTK APPLICATION_ID are one string', () {
      // Discovered rather than spelled out: a renamed packaging file must fail
      // here, and it cannot if the test names the file it expects to find.
      final packagingFiles = Directory('linux/packaging')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.desktop'))
          .toList();

      expect(
        packagingFiles,
        hasLength(1),
        reason: 'AD-11 fixes exactly one app-id entry',
      );
      final basename = packagingFiles.single.path
          .split('/')
          .last
          .replaceAll('.desktop', '');

      expect(
        basename,
        WaylandPortalGlobalHotkey.applicationId,
        reason:
            'GNOME matches the registered app id against an installed entry '
            'of the same basename; a mismatch loses the bind silently',
      );
      expect(
        _applicationIdInCMake(),
        WaylandPortalGlobalHotkey.applicationId,
        reason:
            'APPLICATION_ID feeds g_set_prgname, which is how the compositor '
            'maps the running process to that entry',
      );
    });

    test('AD-11: the autostart entry ships under the same basename, so both '
        'destinations describe one application', () {
      expect(
        _autostartEntryPath.split('/').last.replaceAll('.desktop', ''),
        WaylandPortalGlobalHotkey.applicationId,
      );
    });

    test('AD-11: the packaging entry names the app id as its icon and window '
        'class, so the association survives more than the bind', () {
      expect(entry().value('Icon'), WaylandPortalGlobalHotkey.applicationId);
      expect(
        entry().value('StartupWMClass'),
        WaylandPortalGlobalHotkey.applicationId,
      );
    });
  });

  group('desktop entry validity', () {
    for (final subject in [
      (name: 'the app-id entry', read: entry),
      (name: 'the autostart entry', read: autostart),
    ]) {
      test('${subject.name} opens with a [Desktop Entry] group', () {
        expect(subject.read().firstMeaningfulLine, '[Desktop Entry]');
      });

      test('${subject.name} declares Type=Application', () {
        expect(subject.read().value('Type'), 'Application');
      });

      test('${subject.name} carries a non-empty Name and Exec', () {
        expect(subject.read().value('Name'), isNotEmpty);
        expect(subject.read().value('Exec'), isNotEmpty);
      });

      test('${subject.name} repeats no key', () {
        expect(
          subject.read().duplicateKeys,
          isEmpty,
          reason: 'a repeated key makes the effective value reader-dependent',
        );
      });

      test('${subject.name} puts no whitespace around any =', () {
        // The desktop entry spec treats " Exec " and "Exec" as different keys
        // and keeps the space in the value, so this is a correctness rule
        // rather than a style one.
        expect(subject.read().linesWithSpacedSeparator, isEmpty);
      });

      test('${subject.name} has no line inside the group that is neither a '
          'comment nor a key/value pair', () {
        expect(
          subject.read().malformedLines,
          isEmpty,
          reason:
              'a line with no = is silently invisible to every other row '
              'here, so a typo would read as an absent key',
        );
      });

      test('${subject.name} states Terminal as a boolean', () {
        expect(subject.read().value('Terminal'), anyOf('true', 'false'));
      });

      test('${subject.name} terminates Categories with a semicolon', () {
        final categories = subject.read().value('Categories');
        expect(categories, isNotEmpty);
        expect(
          categories,
          endsWith(';'),
          reason: 'Categories is a list type; an unterminated list is invalid',
        );
      });
    }

    test('AD-14: the autostart entry declares itself enabled for GNOME', () {
      expect(autostart().value('X-GNOME-Autostart-enabled'), 'true');
    });

    test('AD-14: the two entries run the identical command, so login starts '
        'the same binary a manual launch does', () {
      // Deliberately not claimed: that this is what makes the two resolve to
      // one instance. `SingleInstanceLock` derives its address from
      // `${paths.runtimeDirectory}/daemon.sock` and never reads Exec, so two
      // different commands would meet the same lock anyway. What Exec equality
      // actually protects is that autostart launches *this* application rather
      // than a stale path or a different build. The one-instance claim is a
      // runtime observation, and it is owed by
      // test/platform/desktop_entries_live_test.dart.
      expect(
        autostart().value('Exec'),
        entry().value('Exec'),
        reason:
            'a divergent Exec means the daemon a user launches by hand and '
            'the one their session starts at login are two different things',
      );
    });

    test('the two entries carry their own Comment, because they answer '
        'different questions in different surfaces', () {
      expect(autostart().value('Comment'), isNot(entry().value('Comment')));
    });
  });

  group('the entry reader itself', () {
    test('it reads the [Desktop Entry] group only, so an action group is '
        'neither a duplicate key nor a competing Exec', () {
      // Not hypothetical: a right-click entry on a tray app is spelled exactly
      // this way, and a flattened reader would report duplicates that are not
      // duplicates while answering Exec with the action's command.
      final parsed = _DesktopEntry.parse(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Real\n'
        'Exec=the-real-command\n'
        'Actions=settings;\n'
        '\n'
        '[Desktop Action settings]\n'
        'Name=Settings\n'
        'Exec=the-action-command\n',
      );

      expect(parsed.value('Exec'), 'the-real-command');
      expect(parsed.value('Name'), 'Real');
      expect(parsed.duplicateKeys, isEmpty);
    });

    test('it still reports a key repeated inside the [Desktop Entry] '
        'group', () {
      final parsed = _DesktopEntry.parse(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Exec=one\n'
        'Exec=two\n',
      );

      expect(parsed.duplicateKeys, ['Exec']);
    });

    test('it reports whitespace on either side of the value, not only the '
        'leading side', () {
      // `Exec=/opt/hgc ` used to pass every row in this file: the value was
      // stored trimmed, so the non-empty check, the AD-14 comparison and the
      // spaced-separator check all agreed while the installed byte differed.
      final parsed = _DesktopEntry.parse(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Exec=/opt/hgc \n',
      );

      expect(parsed.linesWithSpacedSeparator, ['Exec=/opt/hgc ']);
    });

    test('it reports a line inside the group that carries no =', () {
      final parsed = _DesktopEntry.parse(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Terminal\n',
      );

      expect(parsed.malformedLines, ['Terminal']);
    });
  });

  group('the installer (AD-11, AD-14)', () {
    test('it writes both entries to their two XDG destinations with the '
        'requested Exec, and a second run leaves the same state', () {
      final tempDir = Directory.systemTemp.createTempSync('desktop_entries_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dataHome = '${tempDir.path}/data';
      final configHome = '${tempDir.path}/config';

      final first = _runInstaller(dataHome: dataHome, configHome: configHome);
      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');

      final installedEntry = File(
        '$dataHome/applications/'
        '${WaylandPortalGlobalHotkey.applicationId}.desktop',
      );
      final installedAutostart = File(
        '$configHome/autostart/'
        '${WaylandPortalGlobalHotkey.applicationId}.desktop',
      );
      final installedIcon = File(
        '$dataHome/icons/hicolor/32x32/apps/'
        '${WaylandPortalGlobalHotkey.applicationId}.png',
      );

      expect(installedEntry.existsSync(), isTrue);
      expect(installedAutostart.existsSync(), isTrue);
      expect(installedIcon.existsSync(), isTrue);
      expect(
        _DesktopEntry.parse(installedEntry.readAsStringSync()).value('Exec'),
        _installedExec,
      );
      expect(
        _DesktopEntry.parse(
          installedAutostart.readAsStringSync(),
        ).value('Exec'),
        _installedExec,
      );
      expect(
        first.stdout,
        allOf(contains(installedEntry.path), contains(installedAutostart.path)),
        reason: 'the installer must print every path it wrote',
      );

      final before = installedEntry.readAsStringSync();
      final second = _runInstaller(dataHome: dataHome, configHome: configHome);

      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
      expect(installedEntry.readAsStringSync(), before);
    });

    test('it refuses an empty --exec instead of quietly installing the bare '
        'name', () {
      // The realistic source is `--exec "$(command -v hgc)"` where the lookup
      // found nothing: without the guard the caller gets a zero exit and an
      // entry that works only by accident of the session PATH.
      final tempDir = Directory.systemTemp.createTempSync('installer_empty_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        exec: '',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('empty'));
      expect(
        Directory('${tempDir.path}/data').existsSync(),
        isFalse,
        reason: 'a refused install writes nothing',
      );
    });

    test('it refuses an --exec carrying a backslash, which the rewrite cannot '
        'keep literal', () {
      final tempDir = Directory.systemTemp.createTempSync('installer_escape_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        exec: r'/opt/hgc\tbin',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('backslash'));
    });

    test('an Exec carrying whitespace is quoted, because the spec would '
        'otherwise read it as a command plus an argument', () {
      final tempDir = Directory.systemTemp.createTempSync('installer_space_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dataHome = '${tempDir.path}/data';

      final result = _runInstaller(
        dataHome: dataHome,
        configHome: '${tempDir.path}/config',
        exec: '/opt/my apps/hotkey_grammar_corrector',
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        File(
          '$dataHome/applications/'
          '${WaylandPortalGlobalHotkey.applicationId}.desktop',
        ).readAsStringSync(),
        contains('Exec="/opt/my apps/hotkey_grammar_corrector"'),
      );
    });

    test('it refuses, naming the file, when a source entry is missing', () {
      // The installer's own guard, driven through a repository copy with one
      // source removed. A silent partial install is the failure mode: half the
      // pair leaves either no hotkey or no autostart, with a zero exit.
      final tempDir = Directory.systemTemp.createTempSync('installer_source_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final root = _copyInstallerTree(tempDir.path);
      File(
        '$root/linux/packaging/autostart/'
        '${WaylandPortalGlobalHotkey.applicationId}.desktop',
      ).deleteSync();

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        installerRoot: root,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('autostart'));
    });

    test('it refuses, naming the destination, when the rewrite produces no '
        'Exec= line at all', () {
      // The rewrite is a substitution, so it is a silent no-op on a source whose
      // [Desktop Entry] group has no Exec — and an entry with no Exec is as dead
      // as one with a wrong Exec, while `wrote …` reported neither. Driven
      // through a repository copy with the line removed.
      final tempDir = Directory.systemTemp.createTempSync('installer_noexec_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final root = _copyInstallerTree(tempDir.path);
      final source = File('$root/$_appIdEntryPath');
      source.writeAsStringSync(
        source
            .readAsLinesSync()
            .where((line) => !line.startsWith('Exec='))
            .join('\n'),
      );

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        installerRoot: root,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('no Exec= line'));
      expect(
        File(
          '${tempDir.path}/data/applications/'
          '${WaylandPortalGlobalHotkey.applicationId}.desktop',
        ).existsSync(),
        isFalse,
        reason: 'the staged file is discarded rather than renamed into place',
      );
    });

    test('run with no arguments it installs both entries with the shipped bare '
        'Exec, which is the invocation the README teaches first', () {
      // Every other row passes --exec, so the `cp` arm — the default path —
      // was executed by nothing. A swapped source/destination, or the app-id
      // entry copied into both places, would have left this whole group green
      // while AD-14's autostart entry was silently absent or wrong.
      final tempDir = Directory.systemTemp.createTempSync('installer_bare_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dataHome = '${tempDir.path}/data';
      final configHome = '${tempDir.path}/config';

      final result = _runInstaller(
        dataHome: dataHome,
        configHome: configHome,
        exec: null,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final entry = _DesktopEntry.read(
        '$dataHome/applications/'
        '${WaylandPortalGlobalHotkey.applicationId}.desktop',
      );
      final autostart = _DesktopEntry.read(
        '$configHome/autostart/'
        '${WaylandPortalGlobalHotkey.applicationId}.desktop',
      );
      expect(entry.value('Exec'), 'hotkey_grammar_corrector');
      expect(autostart.value('Exec'), 'hotkey_grammar_corrector');
      expect(
        autostart.value('X-GNOME-Autostart-enabled'),
        'true',
        reason:
            'the two destinations must receive the two different sources — '
            'only the autostart entry carries this key',
      );
      expect(
        entry.value('X-GNOME-Autostart-enabled'),
        isEmpty,
        reason: 'the app-id entry must not be the autostart entry',
      );
    });

    test('it refuses an --exec carrying a double quote, which would terminate '
        'the quoting the installer adds', () {
      // The sibling of the backslash row. Only one half of the guard's pattern
      // had a row, so dropping the other half would have failed nothing.
      final tempDir = Directory.systemTemp.createTempSync('installer_quote_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        exec: '/opt/"quoted"/hgc',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('quote'));
      expect(Directory('${tempDir.path}/data').existsSync(), isFalse);
    });

    test('it refuses an --exec carrying a newline, which would split Exec '
        'across two lines and forge a second key', () {
      // The worst input the guard set missed: the entry it produced parsed as
      // `Exec="/opt/hgc` plus a second key on the next line — a broken entry,
      // and a zero exit. A crafted value makes that second key a duplicate
      // `Name`, which this file's own duplicate check would flag on a file it
      // never gets to see.
      final tempDir = Directory.systemTemp.createTempSync('installer_nl_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        exec: '/opt/hgc\nName=Hijacked',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('control character'));
      expect(Directory('${tempDir.path}/data').existsSync(), isFalse);
    });

    test('it refuses a relative --exec, which resolves against the '
        "compositor's working directory rather than the caller's", () {
      // The value a developer has to hand after `flutter build linux`. Installed
      // verbatim it produces an entry that exits 0 and never launches.
      final tempDir = Directory.systemTemp.createTempSync('installer_rel_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final result = _runInstaller(
        dataHome: '${tempDir.path}/data',
        configHome: '${tempDir.path}/config',
        exec: 'build/linux/x64/debug/bundle/hotkey_grammar_corrector',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('absolute'));
    });

    test('it ignores a relative XDG root rather than installing under the '
        "caller's working directory", () {
      // The XDG base-directory specification requires a relative value be
      // ignored, and it matters here: honouring it installs the entries
      // somewhere no compositor looks and exits 0.
      final tempDir = Directory.systemTemp.createTempSync('installer_xdg_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final fakeHome = '${tempDir.path}/home';
      Directory(fakeHome).createSync();

      // Run from the temp tree rather than the repository, so a regression that
      // honoured the relative value writes there and not into the working copy.
      // (The installer resolves its own root from BASH_SOURCE, so the working
      // directory is free.)
      final result = Process.runSync(
        '${Directory.current.path}/tool/install_desktop_entries.sh',
        const [],
        workingDirectory: tempDir.path,
        environment: {
          'HOME': fakeHome,
          'XDG_DATA_HOME': 'relative/data',
          'XDG_CONFIG_HOME': 'relative/config',
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('relative'));
      expect(
        File(
          '$fakeHome/.local/share/applications/'
          '${WaylandPortalGlobalHotkey.applicationId}.desktop',
        ).existsSync(),
        isTrue,
        reason: 'the specification default is used when the value is unusable',
      );
      expect(
        Directory('${tempDir.path}/relative').existsSync(),
        isFalse,
        reason: 'nothing may be written under the working directory',
      );
    });
  });

  group('the app id reaches the running process (AD-11)', () {
    test('my_application.cc still feeds APPLICATION_ID to g_set_prgname and to '
        'the GApplication id, rather than a literal', () {
      // The rows above pin three *declarations* against each other. This pins
      // the link that makes the declaration matter: replace APPLICATION_ID at
      // either call site with a literal — the snake_case BINARY_NAME being the
      // obvious slip, since it matches the pubspec name — and every other row in
      // this file stays green while the process announces an id that no
      // installed entry is named for.
      final source = File('linux/runner/my_application.cc').readAsStringSync();

      expect(
        source,
        contains('g_set_prgname(APPLICATION_ID)'),
        reason: 'prgname must be the macro, not a copy of its value',
      );
      expect(
        source,
        contains('"application-id", APPLICATION_ID'),
        reason: 'the GApplication id must be the macro too',
      );
      expect(
        File('linux/runner/CMakeLists.txt').readAsStringSync(),
        contains(r'-DAPPLICATION_ID="${APPLICATION_ID}"'),
        reason:
            'the macro must still be defined from the CMake variable the '
            'rows above read',
      );
    });
  });

  test('the four AD-11/AD-14 claims this container cannot observe are named in '
      'the run output', () {
    // The unobserved half lives in test/platform/desktop_entries_live_test.dart,
    // which imports flutter_test — so `dart test` cannot load it and the CI gate
    // does not include the directory. Its own doc says it exists to make the gap
    // "visible in the same place the green is", and it was visible in neither
    // place a run actually happens. This is the same fix live_smoke_status_test
    // applies to the live smoke: untagged, always runs, prints.
    //
    // ignore: avoid_print
    print(
      'NOT OBSERVED HERE — every row above reads bytes or runs the installer '
      'into a temp XDG tree. No compositor, no xdg-desktop-portal, no session '
      'bus and no desktop-file-validate exist in this container, so none of it '
      'is evidence about a desktop. Owed on a real GNOME (ideally also KDE) '
      'session, and recorded as deferred-work DW-87:\n'
      '  1. the compositor associates the registered app id with the installed '
      '${WaylandPortalGlobalHotkey.applicationId}.desktop\n'
      '  2. the GlobalShortcuts bind survives *because of* that association — '
      'the observable being that removing the file discards the bind\n'
      '  3. the autostart entry starts the daemon at login and the hotkey is '
      'live, with nobody launching it (a tray indicator is convenient extra '
      'evidence, not part of the fact — stock GNOME Wayland hosts none without '
      'the AppIndicator extension)\n'
      '  4. an autostarted daemon plus a manual launch resolve to one instance '
      '(via XDG_RUNTIME_DIR, not via Exec equality)\n'
      '  full detail        : $_liveClaimsSuite\n'
      '  run it with        : flutter test $_liveClaimsSuite\n'
      '  how to observe them: $_desktopSessionChecklist',
    );

    expect(
      File(_liveClaimsSuite).existsSync(),
      isTrue,
      reason: 'the file this row points at must exist',
    );
  });
}

const String _appIdEntryPath =
    'linux/packaging/com.divertedriver.HotkeyGrammarCorrector.desktop';
const String _autostartEntryPath =
    'linux/packaging/autostart/'
    'com.divertedriver.HotkeyGrammarCorrector.desktop';
const String _installedExec = '/tmp/x/bin';
const String _liveClaimsSuite = 'test/platform/desktop_entries_live_test.dart';

/// The manual procedure that turns the four claims above into steps a person at
/// a real GNOME Wayland session can execute.
///
/// This constant's *value* is pinned against the path the skipped rows name, by
/// test/architecture/runtime_checklists_test.dart — which also checks that the
/// print above still interpolates it. Between them the printed line cannot drift
/// away from the file it advertises.
const String _desktopSessionChecklist =
    'test/platform/desktop-session-checklist.md';

/// Runs the installer with both XDG roots pointed into a temporary tree, so no
/// row can write into the developer's real session.
///
/// [exec] is nullable rather than defaulted-only so the no-argument invocation
/// is reachable: passing `--exec ''` is a *different* case, and the row that
/// covers it was the only thing standing in for the default path.
ProcessResult _runInstaller({
  required String dataHome,
  required String configHome,
  String installerRoot = '.',
  String? exec = _installedExec,
}) {
  return Process.runSync(
    '$installerRoot/tool/install_desktop_entries.sh',
    exec == null ? const [] : ['--exec', exec],
    environment: {'XDG_DATA_HOME': dataHome, 'XDG_CONFIG_HOME': configHome},
  );
}

/// The parts of the repository the installer reads, copied so a row can remove
/// one of them without touching the working tree.
String _copyInstallerTree(String destination) {
  for (final relative in [
    'tool/install_desktop_entries.sh',
    _appIdEntryPath,
    _autostartEntryPath,
    'assets/tray/hotkey-grammar-corrector.png',
  ]) {
    final target = File('$destination/$relative');
    target.parent.createSync(recursive: true);
    File(relative).copySync(target.path);
  }
  Process.runSync('chmod', [
    '+x',
    '$destination/tool/install_desktop_entries.sh',
  ]);
  return destination;
}

String _applicationIdInCMake() {
  final source = File('linux/CMakeLists.txt').readAsStringSync();
  final match = RegExp(
    r'^\s*set\(APPLICATION_ID\s+"([^"]+)"\)',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) {
    fail(
      'linux/CMakeLists.txt declares no APPLICATION_ID; this gate cannot '
      'pass vacuously',
    );
  }
  return match.group(1)!;
}

/// The little of the desktop entry format these checks need: a key/value group
/// with comments, read strictly enough that the format's own traps — a spaced
/// separator, a repeated key — are failures rather than shrugs.
final class _DesktopEntry {
  _DesktopEntry({
    required this.firstMeaningfulLine,
    required this.duplicateKeys,
    required this.linesWithSpacedSeparator,
    required this.malformedLines,
    required this._values,
  });

  factory _DesktopEntry.read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      fail('$path does not exist; AD-11 requires it be shipped');
    }
    return _DesktopEntry.parse(file.readAsStringSync());
  }

  /// Reads the `[Desktop Entry]` group only.
  ///
  /// Group-scoped rather than flattened, because the format's namespace is
  /// per-group and a flattened read is wrong in two directions at once. A
  /// `[Desktop Action …]` group — the standard way to give a tray app a
  /// right-click entry — carries its own `Name` and `Exec`, so flattening
  /// would report duplicate keys that are not duplicates, and would answer
  /// `value('Exec')` with the last *action's* command while the AD-14
  /// comparison went on agreeing with itself.
  factory _DesktopEntry.parse(String source) {
    const group = '[Desktop Entry]';
    final values = <String, String>{};
    final duplicates = <String>[];
    final spaced = <String>[];
    final malformed = <String>[];
    String? firstMeaningful;
    var inGroup = false;

    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      firstMeaningful ??= trimmed;
      if (trimmed.startsWith('[')) {
        inGroup = trimmed == group;
        continue;
      }
      if (!inGroup) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator < 0) {
        // Recorded rather than skipped: a line inside the group that is neither
        // a comment nor a key/value pair is malformed, and dropping it silently
        // is how a typo becomes a missing key that reads as an absent one.
        malformed.add(line);
        continue;
      }
      final key = line.substring(0, separator);
      final value = line.substring(separator + 1);
      // Both sides of the value, not just the leading side. `value.trimLeft()`
      // alone let `Exec=/opt/hgc ` through every row in this file — the
      // non-empty check, the spaced-separator check and the AD-14 comparison —
      // while the byte a compositor reads carried a trailing space.
      if (key != key.trim() || value != value.trim()) {
        spaced.add(line);
      }
      if (values.containsKey(key.trim())) {
        duplicates.add(key.trim());
      }
      values[key.trim()] = value.trim();
    }

    return _DesktopEntry(
      firstMeaningfulLine: firstMeaningful ?? '',
      duplicateKeys: duplicates,
      linesWithSpacedSeparator: spaced,
      malformedLines: malformed,
      values: values,
    );
  }

  final String firstMeaningfulLine;
  final List<String> duplicateKeys;
  final List<String> linesWithSpacedSeparator;
  final List<String> malformedLines;
  final Map<String, String> _values;

  String value(String key) => _values[key] ?? '';
}
