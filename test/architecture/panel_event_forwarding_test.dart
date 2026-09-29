import 'dart:io';

import 'package:test/test.dart';

/// `WindowManagerPanelWindow.onWindowEvent` forwards native events while
/// distinguishing a focus-in expected from its own present operation.
///
/// The visibility adapter above it depends on every name its switch has an arm
/// for — seven of them, enumerated below — and each one carries a decision of
/// its own. An arm count is the wrong thing to state loosely here: a stale one
/// stood in this sentence while the list below it grew, which is why the count
/// and the list are now written to be checked against each other:
///
/// - `show` and `hide` reconcile the mirror, and so does `restore` — but only
///   while no request of ours is outstanding. `hide` carries a second condition
///   since DW-30: it reconciles only while the mirror still reads *true*. The
///   event is the GTK widget `hide` signal, so it can only be an echo of one of
///   our own calls, and a focus-loss hide abandoned at the bound would otherwise
///   let its late echo rename the standing `focusLost` to `dismissed`.
/// - `minimize` never invents an absence it did not cause: nothing the adapter
///   calls iconifies, so an iconify can never be an echo of ours (DW-31), but
///   since DW-30 it writes the mirror only from inside `if (_visible)`. A
///   departure now carries a *reason* the next session obeys, so an iconify
///   arriving at a panel that is already away must not replace the reason it is
///   away with a survivable one.
/// - `restore` writes it straight too in the one case where it undoes a
///   `minimize` the adapter believed, which is what keeps that pair symmetric
///   during one of our requests (DW-31).
/// - `focus` records that the window holds the keyboard, which is the only
///   thing that lets a later `blur` mean anything (DW-33). It was missing from
///   this list while the count above already said seven — the same staleness the
///   paragraph above was rewritten to prevent, in the same change that added the
///   name.
/// - `blur` dismisses the panel (CAP-14), but only when a `focus` first said
///   the window ever held the keyboard (DW-33).
/// - `close` puts the panel away for real, rather than merely recording it
///   (DW-12).
///
/// Other event names remain raw; focus-in is labeled by provenance before the
/// visibility adapter decides whether it can cancel a deferred blur.
///
/// Narrow this method with an event-name filter, or swap it for
/// `WindowListener`'s typed callbacks, and
/// the arms that lost their event stop running with nothing to report it: the
/// adapter's own suite drives `FakePanelWindow` directly and never touches this
/// class, and the one row that does — `test/platform/
/// window_manager_panel_window_test.dart`'s event row — needs a Flutter binding
/// and so lives outside the `dart test` set CI runs (`.github/workflows/
/// ci.yml`). For `close` the consequence is silent by construction:
/// `setPreventClose(true)` means GTK will not take the toplevel down either, so
/// a dropped `close` leaves the panel on screen with nothing failing anywhere.
///
/// A source scan rather than a behavioural row, because constructing this class
/// registers a real `window_manager` listener and therefore needs the binding
/// this directory does not have. It is the same trade `hidden_window_test.dart`
/// makes over the same file.
void main() {
  test('DW-12: the panel window forwards events and tags self focus', () {
    final body = _onWindowEventBody();

    expect(
      body,
      contains('_events.add(eventName)'),
      reason:
          'the raw name goes to the seam; anything that rewrites or drops it '
          'silently disconnects an arm of _onWindowEvent above',
    );
    expect(body, contains("'self-focus'"));

    // PANEL-12 classifies focus by origin; every other event stays raw.
    for (final filter in <Pattern>[
      RegExp(r'switch\s*\(\s*eventName'),
      RegExp(r'eventName\.'),
      'contains(',
    ]) {
      expect(
        body,
        isNot(contains(filter)),
        reason:
            'no event-name filter: `close` reaching Dart is what DW-12 rests '
            'on, and the only row that executes this forwarder is outside the '
            'command CI runs',
      );
    }
  });
}

/// The body of `onWindowEvent`, bounded on the method's own closing brace.
///
/// `\n  }\n` rather than `\n}` — this is a method, so its brace is indented,
/// and the file's own class brace is the one at column zero.
String _onWindowEventBody() {
  const path = 'lib/src/infrastructure/panel/window_manager_panel_window.dart';
  final source = File(path).readAsStringSync();
  final start = source.indexOf('void onWindowEvent(String eventName) {');

  expect(
    start,
    isNonNegative,
    reason: 'the untyped hook is the only route to show/hide/close ($path)',
  );

  final end = source.indexOf('\n  }\n', start);
  expect(end, isNonNegative, reason: 'unterminated method body in $path');

  return source.substring(start, end);
}
