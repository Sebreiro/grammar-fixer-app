import 'dart:io';

import 'package:test/test.dart';

/// AD-8: the window is constructed once at startup and left hidden — launching
/// the daemon leaves no visible window, and only the hotkey toggle ever maps
/// it.
///
/// The runtime claim is not provable in this container, and not for want of
/// tools: `xwininfo`, `xdotool` and `xprop` are all installed here — only
/// `wmctrl` is not — and so are `Xvfb` and `xvfb-run`. What is missing is the
/// thing AD-8 is about. There is no compositor and no window manager, so
/// nothing would map a toplevel in the first place and an enumerator would be
/// reading an empty synthetic display. So this pins the two edits the claim
/// rests on
/// against silent reversion — the generated GTK runner's stock "show on first
/// frame" handler, and any window-mapping call creeping onto the startup path.
/// A future `flutter create`-style regeneration of `linux/` would restore the
/// handler without a word, and this is what would notice.
///
/// The startup-path ban is scoped, not blanket. The `PanelVisibility` adapter
/// under `lib/src/infrastructure/panel/` is the one file that *must* map the
/// window — that is its whole job, and AD-8 says the toggle is the only thing
/// allowed to do it. Banning the call everywhere would forbid exactly the code
/// this test exists to protect.
///
/// Since story 5 that exemption has an occupant:
/// `lib/src/infrastructure/panel/window_manager_panel_window.dart` calls
/// `show`, `hide` and `focus`, and it is the *only* file under `lib/` that may.
/// AD-8 is still enforced, in three ways rather than one. The startup-path scan
/// below is unchanged and still admits nothing that can map a window, so
/// nothing `main.dart` reaches before `runApp` can put the panel on screen. The
/// adapter's own allowlist, added here, keeps that file to the three calls the
/// toggle needs — a `restore` or a `setAlwaysOnTop` creeping in has to be
/// justified here first. And the anti-aliasing guard is applied to the adapter
/// as well as to the startup path, in both of the package's spellings, so
/// neither `final wm = WindowManager.instance;` nor `final wm = windowManager;`
/// can hand the API to a receiver the scans do not know the name of.
///
/// Both scans assert a **subset** of what is permitted, never set equality:
/// equality also *requires* every permitted call, so dropping one in a
/// legitimate refactor would turn a green test red for no reason. A subset
/// check can only forbid, though, seven of `main.dart`'s calls carry
/// behaviour rather than merely being allowed — `setSkipTaskbar(false)` allows
/// the visible panel into the taskbar, and `setPreventClose` is what
/// lets application policy answer Close without destroying the toplevel —
/// so those have a presence assertion of their own alongside it.
///
/// Every one of those pins was mutation-verified, each failing exactly the row
/// named and none of them failing before the addition. The original record
/// below predates the taskbar preference change (quick task 261002-3x4): deleting
/// `await windowManager.setSkipTaskbar(true)` from `main.dart` fails the
/// presence row; rewriting the adapter's focus call as
/// `final wm = windowManager; await wm.focus();` fails the adapter's
/// anti-aliasing row; and deleting `await windowManager.setPreventClose(true)`
/// fails the presence row here plus `composition_wiring_test.dart`'s DW-12 row,
/// and nothing else in either suite.
void main() {
  group('the GTK runner maps no toplevel (AD-8)', () {
    test('CAP-1: the runner has no first-frame handler showing the '
        'toplevel', () {
      final runner = _runnerSource();

      expect(
        runner,
        isNot(contains('first_frame_cb')),
        reason:
            'the stock handler shows the toplevel on first frame, which '
            'is exactly what AD-8 forbids for a tray daemon',
      );
      expect(runner, isNot(contains('first-frame')));
      expect(runner, isNot(contains('gtk_widget_get_toplevel')));
    });

    test('CAP-1: every gtk_widget_show in the runner targets a child widget, '
        'never the window', () {
      final shown = _showCalls(_runnerSource());

      expect(
        shown,
        isNot(anyElement(contains('window'))),
        reason:
            'the GtkWindow must be constructed and realized, never shown; '
            'showing the header bar and the view does not map the toplevel',
      );
    });

    test('CAP-1: the view is still realized, so the window stays warm', () {
      expect(
        _runnerSource(),
        contains('gtk_widget_realize(GTK_WIDGET(view))'),
        reason:
            'AD-8 wants the window built and rendering-ready before the '
            'first toggle, not merely unshown',
      );
    });
  });

  group('the runner never maps or raises the toplevel (AD-8)', () {
    test('CAP-1: the runner calls none of GTK own mapping or raising '
        'functions', () {
      final runner = _stripComments(_runnerSource());

      for (final mapping in _gtkMappingCalls) {
        expect(
          runner,
          isNot(contains(mapping)),
          reason:
              '$mapping maps or raises the toplevel, which only the panel '
              'toggle may do',
        );
      }
    });

    test('CAP-1: every GTK call the runner makes against the toplevel is one '
        'of the five known not to map it', () {
      // An allowlist, not another ban. A ban is a list of the ways someone
      // thought of to map a window, and GTK has more of them than anyone
      // enumerates: `gtk_widget_set_visible(window, TRUE)`, `gtk_widget_map`
      // and `gtk_window_set_visible` all map a toplevel and all walk straight
      // past a denylist tuned to `gtk_widget_show`. Inverting it means a new
      // call against `window` has to be justified here before it can ship.
      expect(
        _gtkCallsAgainstTheWindow(_runnerSource()),
        _permittedGtkWindowCalls,
        reason:
            'this call touches the toplevel — confirm it cannot map or raise '
            'the window before adding it to the allowlist',
      );
    });
  });

  group('nothing on the startup path maps the window (AD-8)', () {
    test('CAP-1: no file on the startup path calls a window_manager method '
        'that maps or raises', () {
      final offenders = <String>[];
      for (final file in _startupPathFiles()) {
        final source = _stripComments(file.readAsStringSync());
        for (final call in _mappingCalls) {
          if (source.contains(call)) {
            offenders.add('${file.path}: $call');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'the daemon creates the window hidden; only the PanelVisibility '
            'adapter, reached from the toggle, may ever make it visible:'
            '\n${offenders.join('\n')}',
      );
    });

    test('CAP-1: every window_manager method reached from the startup path is '
        'one of the methods that cannot map a window', () {
      // The ban above is receiver-bound: it matches the literal text
      // `windowManager.show(`, and `windowManager` is only the package's
      // top-level getter for `WindowManager.instance`. So
      // `await WindowManager.instance.show();` is the *same call* and passes
      // the ban untouched — as does any local alias. Since the runtime
      // observation could not be made in this container (DW-9), these scans
      // are the whole of AD-8's pin, and a pin with a known way past it is
      // not one. Hence the inversion: name every method that may be reached,
      // and treat the rest as an error whatever receiver spells it.
      final reached = <String, Set<String>>{};
      for (final file in _startupPathFiles()) {
        final calls = _windowManagerCalls(file.readAsStringSync());
        if (calls.isNotEmpty) {
          reached[file.path] = calls;
        }
      }

      expect(reached.keys, [
        'lib/main.dart',
      ], reason: 'only the composition root touches window_manager');
      expect(
        reached['lib/main.dart']!.difference(_permittedWindowManagerCalls),
        isEmpty,
        reason:
            'the startup path may reach only property setters that cannot map '
            'the toplevel — a subset check, so dropping a call is a refactor '
            'rather than a failure',
      );
    });

    test('CAP-1: the composition root still prepares the hidden window and '
        'its geometry before any summon', () {
      // Initialization and seven properties are required. The geometry calls
      // give the already-warm window a size, minimum and best-effort position.
      //
      // The subset check above bans; it cannot require. That is deliberate —
      // equality would turn a legitimate refactor red — but it means these
      // calls, which carry behaviour rather than merely being
      // permitted, need a pin of their own. The unmapped window stays absent
      // from running-window lists; the visible window must allow a taskbar
      // entry. Deleting
      // `setPreventClose(true)` is the same shape and worse: `on_window_close`
      // then returns a false `_is_prevent_close`, GTK destroys the toplevel,
      // and the application close policy reaches a window that no
      // longer exists — silently restoring exactly the defect DW-12 closed.
      final reached = _windowManagerCalls(
        File('lib/main.dart').readAsStringSync(),
      );

      expect(
        _stripComments(File('lib/main.dart').readAsStringSync()),
        contains('windowManager.setSkipTaskbar(false)'),
        reason: 'the visible warm panel participates in the taskbar/dock',
      );
      expect(
        _stripComments(File('lib/main.dart').readAsStringSync()),
        contains('windowManager.setAlwaysOnTop(true)'),
        reason: 'the visible panel stays above ordinary windows on X11',
      );
      expect(
        reached,
        containsAll(<String>[
          'ensureInitialized',
          'setTitle',
          'setSkipTaskbar',
          'setAlwaysOnTop',
          'setPreventClose',
          'setMinimumSize',
          'setSize',
          'setPosition',
        ]),
        reason:
            'a tray daemon has no business in the task switcher while it is '
            'hidden, an untitled toplevel is what a second launch would '
            'otherwise raise, and a close that destroys the window abandons '
            'the CAP-7 write in flight',
      );
    });

    test('CAP-1: no file on the startup path aliases WindowManager, so the '
        'call scan above cannot be walked around', () {
      expect(_aliasingFiles(_startupPathFiles()), isEmpty);
    });

    test('CAP-1: the composition root prepares the window with property '
        'setters only', () {
      final main = _stripComments(File('lib/main.dart').readAsStringSync());

      expect(main, contains('windowManager.ensureInitialized()'));
      expect(
        main,
        isNot(contains('waitUntilReadyToShow')),
        reason:
            'waitUntilReadyToShow is not inert — its isMinimized/restore '
            'branch is gtk_window_deiconify plus gtk_window_present, which '
            'maps and raises the toplevel',
      );
    });

    test('CAP-1: the panel adapter directory is what the ban exempts, so the '
        'toggle has somewhere to put the call', () {
      final startupPaths = [for (final file in _startupPathFiles()) file.path];

      expect(
        startupPaths,
        isNot(anyElement(contains('lib/src/infrastructure/panel/'))),
        reason:
            'a ban that covered the adapter would forbid the one call AD-8 '
            'permits',
      );
      expect(startupPaths, contains('lib/main.dart'));
    });
  });

  group('the panel adapter is the only file that may map the window (AD-8)', () {
    test('CAP-1: every window_manager method the adapter reaches is one the '
        'toggle needs', () {
      final reached = <String, Set<String>>{};
      for (final file in _panelAdapterFiles()) {
        final calls = _windowManagerCalls(file.readAsStringSync());
        if (calls.isNotEmpty) {
          reached[file.path] = calls;
        }
      }

      expect(
        reached.keys,
        [_panelWindowAdapter],
        reason:
            'AD-1 confines window_manager to one file; the mirror logic sits '
            'behind the PanelWindow seam and must stay binding-free',
      );
      // A subset, not equality: `focus` exists because Linux `show` is
      // `gtk_widget_show` alone, and a future adapter that stopped needing one
      // of the three should not fail this.
      expect(
        reached[_panelWindowAdapter]!.difference(_permittedAdapterCalls),
        isEmpty,
        reason:
            'this call moves the window — confirm the toggle actually needs '
            'it before adding it to the allowlist',
      );
    });

    test('CAP-1: the adapter does not alias WindowManager either, so its own '
        'allowlist cannot be walked around', () {
      // The same hole the startup-path scan closes: any hand-off of the
      // receiver — `final wm = WindowManager.instance;`, an arrow getter, or
      // passing it as an argument — reaches a mapping call that the
      // receiver-bound pattern above never sees.
      expect(_aliasingFiles(_panelAdapterFiles()), isEmpty);
    });
  });

  test(
    'AD-8: the launched daemon maps no window and stays resident',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container. Launching the built binary needs '
        'a session, and there is none: no compositor and no window manager '
        'to map, focus or place a toplevel, no xdg-desktop-portal, no '
        'session bus (DBUS_SESSION_BUS_ADDRESS is unset and /run/user/ is '
        'empty) and no login. The host display is unreachable too — :10 '
        'answers "Authorization required, but no authorization protocol '
        'specified", there is no ~/.Xauthority and no XAUTHORITY, and every '
        'other socket under /tmp/.X11-unix is dead. Correcting what an '
        'earlier version of this reason claimed: Xvfb, xvfb-run, xwininfo, '
        'xdotool and xprop are all installed here (wmctrl is the one that is '
        'not), so a display could be stood up and enumerated. That does not '
        'close the claim, because AD-8 is about what a window manager does '
        'with a toplevel and Xvfb supplies a bare X server with no window '
        'manager, so a synthetic display answers a question nobody asked. '
        'The two source edits the claim rests on are pinned '
        'statically by the rest of this file; the runtime observation is '
        'owed on a machine with a real session (deferred-work DW-9). The '
        'steps that observation needs are written down in '
        'test/platform/runtime-observation-checklist.md — steps 1 to 3 for '
        'the unmapped window and the residency, step 4 for the second '
        'launch.',
  );
}

String _runnerSource() =>
    File('linux/runner/my_application.cc').readAsStringSync();

/// The argument of every `gtk_widget_show*` call in [source], comment lines
/// removed so a comment explaining the absence never reads as a call.
List<String> _showCalls(String source) {
  final pattern = RegExp(r'gtk_widget_show\w*\(([^;]*)\)\s*;');
  return [
    for (final match in pattern.allMatches(_stripComments(source)))
      match.group(1)!.toLowerCase(),
  ];
}

/// Both languages here use the same two comment forms, so one stripper serves
/// the GTK runner and the Dart sources alike.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp('//[^\n]*'), '');

/// Every `window_manager` call that can put the window on screen or in front
/// of another. `.show()` alone was too narrow: `restore` and `present` map a
/// minimised window and `focus` raises it, and all three are one line away on
/// any path that already holds `windowManager`.
/// A literal denylist, and so the weakest of the three scans: it sees only
/// this exact spelling — not `WindowManager.instance.show(`, not a cascade,
/// not an aliased receiver. It is kept because a named offender reads better
/// in a failure message than a set difference; the scans that actually close
/// those shapes are [_windowManagerCalls] and [_aliasingFiles].
const List<String> _mappingCalls = [
  'windowManager.show(',
  'windowManager.restore(',
  'windowManager.focus(',
  'waitUntilReadyToShow(',
];

/// The GTK-side equivalents, for the runner. Kept alongside the allowlist
/// below because a banned name reports *which* call was reintroduced, where the
/// allowlist only reports that something new appeared.
const List<String> _gtkMappingCalls = [
  'gtk_window_present',
  'gtk_window_deiconify',
  'gtk_widget_show_all',
  'gtk_widget_set_visible',
  'gtk_window_set_visible',
  'gtk_widget_map',
];

/// Every GTK function the runner is allowed to call against the toplevel.
/// Each is a property setter or a getter; none of them maps or raises.
const Set<String> _permittedGtkWindowCalls = {
  'gtk_window_get_screen',
  'gtk_window_set_titlebar',
  'gtk_window_set_title',
  'gtk_window_set_default_size',
  'gtk_container_add',
};

/// Every `window_manager` method the startup path is allowed to reach.
/// `ensureInitialized` sets the plugin up, and the setters change window
/// properties on an unmapped toplevel — verified against
/// `window_manager-0.5.2/linux/window_manager_plugin.cc`, where `show` is
/// `gtk_widget_show` on the toplevel and none of these calls is.
const Set<String> _permittedWindowManagerCalls = {
  'ensureInitialized',
  'setTitle',
  'setSkipTaskbar',
  // GTK keep-above prepares state without mapping an unmapped window.
  'setAlwaysOnTop',
  // setMinimumSize updates GTK geometry hints; setSize calls gtk_window_resize;
  // setPosition calls gtk_window_move. None calls gtk_widget_show or present.
  // The requested position is advisory for an ordinary Wayland toplevel.
  'setMinimumSize',
  'setSize',
  'setPosition',
  // DW-12. It makes **no GTK call at all**: `set_prevent_close` assigns
  // `self->_is_prevent_close` and returns (`:70-77` of the same file), so it
  // cannot map, raise or realize anything. That is the argument this allowlist
  // exists to make someone state, and it is why the flag belongs on the startup
  // path rather than behind the `PanelWindow` seam.
  'setPreventClose',
};

/// The one file under `lib/` that AD-8 permits to move the window.
const String _panelWindowAdapter =
    'lib/src/infrastructure/panel/window_manager_panel_window.dart';

/// Every `window_manager` method that file is allowed to reach: the toggle's
/// two directions, plus the focus CAP-1 asks for and Linux `show` does not
/// provide, plus listener registration.
///
/// This governs **direct** calls only, and cannot govern what the package does
/// behind them: `WindowManager.show()` is `if (await isMinimized()) await
/// restore();` before it invokes `show`
/// (`window_manager-0.5.2/lib/src/window_manager.dart:209`), and Linux
/// `restore` is `gtk_window_deiconify` + `gtk_window_present`. So permitting
/// `show` permits a `restore` on a branch no source-text scan can see. That is
/// intended — it is `show`'s own implementation, not a second decision — but
/// the allowlist must not be read as a promise that no `restore` ever runs.
const Set<String> _permittedAdapterCalls = {
  'show',
  'hide',
  'focus',
  'addListener',
  'removeListener',
};

/// The names of every GTK function in [source] whose arguments name the
/// toplevel `window`. The word boundary keeps `gtk_application_window_new` —
/// where "window" sits inside the *function* name — out of the result.
Set<String> _gtkCallsAgainstTheWindow(String source) {
  final stripped = _stripComments(source);
  final pattern = RegExp(r'\b(gtk_\w+)\s*\(([^;]*?)\)\s*;');
  return {
    for (final match in pattern.allMatches(stripped))
      if (RegExp(r'\bwindow\b').hasMatch(match.group(2)!)) match.group(1)!,
  };
}

/// Every method named on a `window_manager` receiver in [source], whichever of
/// the package's two spellings names it.
///
/// Deliberately does not require a following `(`: a tear-off — `_request(
/// windowManager.restore)` — reaches the same method and would otherwise be
/// invisible to both allowlists, the same hole in a different shape from the
/// aliasing one above.
///
/// `\.{1,2}` rather than `\.`, so a cascade — `windowManager..show();` — lands
/// in the allowlist too. It reaches the identical method, and the receiver is
/// followed by a dot, so [_aliasingFiles] deliberately leaves it to this scan.
Set<String> _windowManagerCalls(String source) {
  final stripped = _stripComments(source);
  final pattern = RegExp(
    r'(?:windowManager|WindowManager\.instance)\s*\.{1,2}\s*(\w+)',
  );
  return {for (final match in pattern.allMatches(stripped)) match.group(1)!};
}

/// Every file in [files] that hands the `window_manager` API to something
/// other than an immediate method call.
///
/// `final wm = WindowManager.instance;` hands the API to a receiver no
/// call-scan here knows the name of, which would walk straight past both
/// allowlists. So does the lowercase top-level getter — `final wm =
/// windowManager;` — which is the spelling the shipped adapter actually uses,
/// so covering only the capitalised one would leave the hole open on exactly
/// the file that matters.
///
/// The shape axis matters as much as the spelling axis, and getting only the
/// assignment shape is what made an earlier version of this guard weaker than
/// its own doc claimed: `WindowManager get _wm => windowManager;` plus
/// `_wm.restore();` maps *and* raises the toplevel before `runApp`, and passed
/// every test in this file. So the rule is not "an assignment" but "any
/// mention that is not immediately a member access" — which covers the arrow
/// getter, `_request(windowManager)`, `[windowManager]`, and `return
/// windowManager;` alike. A receiver followed by `.` or `..` is a direct call
/// and belongs to [_windowManagerCalls], which allowlists it by name.
Iterable<String> _aliasingFiles(Iterable<File> files) {
  final pattern = RegExp(
    r'(?<![\w$.])(?:windowManager|WindowManager\.instance)\b(?!\s*\.)',
  );
  return [
    for (final file in files)
      if (pattern.hasMatch(_stripComments(file.readAsStringSync()))) file.path,
  ];
}

/// Everything under `lib/` except the `PanelVisibility` adapter, which is the
/// one place AD-8 permits a mapping call — the toggle's own implementation.
Iterable<File> _startupPathFiles() {
  return _dartFilesUnder(
    'lib',
  ).where((file) => !file.path.startsWith(_adapterDirectory));
}

/// The exempted directory itself, which has an allowlist of its own.
Iterable<File> _panelAdapterFiles() => _dartFilesUnder(
  'lib',
).where((file) => file.path.startsWith(_adapterDirectory));

const String _adapterDirectory = 'lib/src/infrastructure/panel/';

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
