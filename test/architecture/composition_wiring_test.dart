import 'dart:io';

import 'package:test/test.dart';

/// AD-17's other half, pinned: every seam the graph declares is bound in
/// `main.dart`, and the two calls that make the daemon a daemon are still made.
///
/// `main.dart` is the one file no test can execute — it needs a binding, a
/// window and a display — so its wiring is the one part of the composition
/// root with no behavioural guard. That is not theoretical: deleting `..build()`
/// and `..start()` and the tray override together leaves `dart analyze` clean
/// and the whole suite green, while the daemon it produces builds its
/// controllers lazily (so the first show misses its session, AD-18) and hears
/// no AD-14 show requests at all.
///
/// A source scan is the same idiom `ad19_path_home_test.dart` and
/// `hidden_window_test.dart` use for claims that live in a file's text rather
/// than its behaviour.
void main() {
  test('AD-17: every port seam is overridden in main.dart', () {
    final declared = _declaredSeams();
    final overridden = _overriddenSeams();

    expect(
      declared,
      isNotEmpty,
      reason: 'the scan must actually be finding seams, or it proves nothing',
    );
    expect(
      declared.difference(overridden),
      isEmpty,
      reason:
          'a seam with no override throws on first read, which turns a wiring '
          'mistake into a startup crash — but only for the seams something '
          'reads. One nothing reads yet, like the tray, would go unnoticed '
          'until the story that needs it.',
    );
  });

  test('AD-17: main.dart overrides nothing the graph does not declare', () {
    final declared = _declaredSeams();
    final overridden = _overriddenSeams();

    expect(
      overridden.difference(declared),
      isEmpty,
      reason:
          'an override for a provider that is no longer a seam is dead wiring',
    );
  });

  test('AD-18: main.dart builds the graph eagerly, capturing it before the '
      'build so a partial one is still reachable', () {
    // The eager build is AD-18: a controller is a subscription, and building
    // lazily makes the first event the one that creates the listener, and so
    // the one missed.
    //
    // The *split* is DW-37, and it is why this row no longer looks for
    // `..build()`. A cascade evaluates to the graph only if `build()` returns,
    // so `final graph = DaemonGraph(...)..build();` captures nothing on exactly
    // the path the abort local exists for: `build()` reads three providers in
    // sequence, and a throw partway through leaves the earlier controllers
    // constructed and subscribed with no lifecycle to dispose them.
    expect(
      _mainSource(),
      matches(RegExp(r'openedGraph = graph;\s*graph\.build\(\);')),
      reason:
          'the graph is captured before it is built, or the abort path has no '
          'graph to tear down on the one failure it was widened for',
    );
    expect(
      _mainSource(),
      isNot(contains('..build()')),
      reason:
          'the cascade is what leaves the partial build uncaptured; keeping it '
          'beside the split would just be a second, silent way to build',
    );
  });

  test('DW-21: main.dart installs both framework error handlers, before the '
      'widget tree exists and without ending the process', () {
    // Neither channel reaches `main`'s guard: the framework catches a throw in
    // `build()`, layout, paint or a gesture callback itself, and an uncaught
    // async error goes to the root zone. With these unset, both end at the
    // framework's default — `dumpErrorToConsole`, which prints the exception's
    // `toString()` and its stack. That is the one thing the Logger port
    // forbids: a vendor exception carries the statement and parameters that
    // caused it, and for the CAP-7 history write those parameters are the
    // corrected text itself.
    final main = _mainSource();
    final declaration = main.indexOf('void _installErrorHandlers(Logger ');

    expect(declaration, isNonNegative);
    final body = main.substring(declaration, main.indexOf('\n}', declaration));

    expect(body, contains('FlutterError.onError ='));
    expect(
      body,
      contains('PlatformDispatcher.instance.onError ='),
      reason:
          'the widget-tree half alone leaves every unawaited future the '
          'application ring did not absorb printing a payload to stderr',
    );
    expect(
      body,
      contains('return true;'),
      reason:
          'answering false hands the error back to the platform, which is how '
          'a resident daemon dies of one screen that would not build',
    );
    expect(
      '_log('.allMatches(body),
      hasLength(2),
      reason:
          'both go through this file own swallow: StderrLogger ends in '
          '_sink.writeln, and a throw from a broken stderr inside an error '
          'handler is an error reported from an error handler',
    );
    expect(
      "'error_type'".allMatches(body),
      hasLength(2),
      reason: 'the type is what the Logger port allows, and all it allows',
    );
    // Silent details are dropped: the framework has already handled them, and
    // reporting them here would make a resident daemon noisier than the
    // framework it runs on. Deliberately *not* the same rule as the default
    // this replaces — `dumpErrorToConsole` computes
    // `reportError = isInDebugMode || !details.silent`, so it honours the flag
    // only in a release build. main.dart states that divergence in prose; this
    // row pins the branch, not the parity.
    //
    // Pinned by its sense, not just its identifier. Inverted to
    // `if (!details.silent) return;` this handler drops every error the
    // framework actually wants reported and logs only the ones it has already
    // handled — DW-21's channel open in name, shut in fact — and a bare
    // `contains('details.silent')` cannot tell the two apart.
    expect(
      body,
      matches(RegExp(r'if \(details\.silent\)\s*\{\s*return;\s*\}')),
      reason:
          'a silent detail is one the framework has already handled, and it is '
          'the only kind this handler is allowed to drop',
    );

    // The *payload*, not just its absence of an exit. This row is the only
    // guard on the Logger port's "never log an error's toString()" rule for
    // the process-wide channel these two handlers open, and a bare token
    // blacklist is not enough on its own: swapping
    // `details.exception.runtimeType.toString()` for
    // `details.exception.toString()` and adding a `'stack'` entry leaves
    // `dart analyze --fatal-infos` clean and this whole suite green unless
    // both halves are pinned. A vendor exception routinely carries the
    // statement and parameters that caused it — for the CAP-7 history write,
    // the corrected text and every suggestion body.
    expect(
      'runtimeType.toString()'.allMatches(body),
      hasLength(2),
      reason:
          'each handler logs the type and only the type; one of them logging '
          'the exception itself is a clipboard payload on stderr all day',
    );
    // And `library`, the other half of the framework handler's payload. It is
    // the one field beyond the type the Logger port allows here — the
    // framework authors it, so no user text reaches it — and it is what tells
    // a widgets-library build failure from a rendering-library layout one in a
    // line that is otherwise just `error_type: StateError`. Pinned because
    // nothing else in this suite mentions it: deleting the entry from
    // `main.dart` left `dart analyze --fatal-infos` clean and every row here
    // green, quietly dropping the I/O matrix's stated payload for this row.
    expect(
      body,
      contains("'library': details.library"),
      reason:
          'the framework half logs the library that reported the error; '
          'without it the two framework channels log the same shape and the '
          'line cannot say which subsystem failed',
    );
    for (final forbidden in <String>[
      'presentError',
      'exit(',
      'rethrow',
      'details.exception.toString()',
      'details.toString()',
      'details.stack',
      'stack.toString()',
      'exceptionAsString',
    ]) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason:
            'a handler that presents, exits, rethrows, or renders the error or '
            'its stack is what this replaces: `$forbidden` must not appear here',
      );
    }

    // The call, not just the declaration, and its position: a handler
    // installed after `runApp` misses every error the first build raises.
    final call = main.indexOf('_installErrorHandlers(logger);');

    expect(call, isNonNegative, reason: 'nothing else installs them');
    expect(
      call,
      lessThan(main.indexOf('runApp(')),
      reason: 'the first frame is built inside runApp, and can throw',
    );
  });

  test('DW-22, CAP-1: startup waits for the engine first frame between runApp '
      'and lifecycle.start(), under a bounded guard', () {
    // `runApp` returning schedules the first frame; it does not wait for one.
    // CAP-1 says the window is warm before the first toggle, and until the
    // engine has rendered, a show request maps a toplevel whose tree has been
    // built but never laid out or painted.
    //
    // Bounded, because `my_application.cc` realizes the view and never shows
    // the toplevel (AD-8): an unbounded await on a session that owes no
    // begin-frame would hold the AD-14 address with no subscription, no tray
    // and no hotkey — the state `_abort` exists to prevent, reached without a
    // throw, so `_abort` would never run.
    final main = _mainSource();
    final frame = main.indexOf('WidgetsBinding.instance.endOfFrame');

    expect(frame, isNonNegative, reason: 'nothing else observes a frame');
    expect(
      frame,
      greaterThan(main.indexOf('runApp(')),
      reason: 'there is no frame to wait for before the tree is handed over',
    );
    expect(
      frame,
      lessThan(main.indexOf('lifecycle.start()')),
      reason:
          'the point is that the window is warm before a show request can '
          'reach it, so the await has to precede the subscription',
    );
    // One assertion spanning the whole guard rather than two substring
    // searches, which any unrelated `try` in the file would satisfy between
    // them. Whitespace-tolerant: how dart format wraps it is not the claim.
    expect(
      main,
      matches(
        RegExp(
          r'try\s*\{\s*await WidgetsBinding\.instance\.endOfFrame'
          r'\s*\.timeout\(\s*_firstFrameBudget,?\s*\)\s*;\s*\}'
          r'\s*on TimeoutException',
        ),
      ),
      reason:
          'unbounded, or unguarded, the wait becomes the thing that blocks a '
          'startup the operational envelope says must never be blocked',
    );
    expect(
      main,
      contains('const Duration _firstFrameBudget ='),
      reason:
          'the budget is a named constant, so the number is argued with in '
          'one place rather than inline at the await',
    );
    // And its magnitude, not just its name. A constant is what makes the
    // number arguable; it is not what makes it right. Shrunk to a millisecond
    // the await expires on every launch, and CAP-1's warmth rests on nothing
    // again while every row above stays green; stretched to minutes the bound
    // stops bounding anything and a session that owes no begin-frame holds the
    // AD-14 address with no subscription behind it. Pinned as a range, so
    // re-arguing the number is still allowed and silently voiding it is not.
    final budget = RegExp(
      r'const Duration _firstFrameBudget = Duration\(seconds: (\d+)\)',
    ).firstMatch(main);

    expect(
      budget,
      isNotNull,
      reason: 'the budget is stated in seconds, the scale the argument is in',
    );
    expect(
      int.parse(budget!.group(1)!),
      inInclusiveRange(2, 15),
      reason:
          'below this a rendering session reaches the timeout and the warning '
          'becomes noise on every launch; above it a wedged one waits so long '
          'the bound is not a bound',
    );

    // And the fallback clause, for the synchronous half the timeout cannot
    // reach. `SchedulerBinding.endOfFrame` only ever `complete()`s its
    // completer — it has no `completeError` path — so the future never
    // rejects and a binding that cannot schedule a frame hangs, which is what
    // the timeout above is for. Reading the getter, though, runs
    // `scheduleFrame()`: a binding not in a state to be asked throws before
    // there is a future at all, and without this clause that throw escapes
    // into main's guard and runs _abort → exit(1), making the step whose whole
    // contract is "never blocks startup" the one that ends it.
    expect(
      main,
      matches(
        RegExp(
          r'on TimeoutException\s*\{[\s\S]*?\}\s*on Object catch \(error\)\s*\{',
        ),
      ),
      reason:
          'the timeout clause alone leaves a throw out of the getter itself '
          'aborting the startup this await was written to protect',
    );

    // Each clause sliced on its own, and this is the whole point of the two
    // bounds below. A single span from `on TimeoutException` to
    // `lifecycle.start()` covers *both* clauses, so `contains('logger.warning(')`
    // and `contains("'error_type'")` are each satisfied by a different one and
    // neither assertion can say which — swapping the two log levels between the
    // clauses, or dropping the type from the fallback, leaves such a span green
    // while the behaviour each reason string names is gone.
    final fallbackAt = main.indexOf('on Object catch (error)', frame);
    final expiry = main.substring(
      main.indexOf('on TimeoutException', frame),
      fallbackAt,
    );
    final fallback = main.substring(
      fallbackAt,
      main.indexOf('lifecycle.start()'),
    );

    expect(
      expiry,
      contains('logger.warning('),
      reason:
          'expiry is log-and-continue and nothing worse: a frame that never '
          'came is a slower first toggle, not a failure to report as one',
    );
    expect(
      expiry,
      contains("'budget_ms'"),
      reason:
          'the warning names the budget it waited out, or the line cannot be '
          'told from any other slow-startup complaint',
    );
    expect(
      expiry,
      contains('_log('),
      reason:
          'through the swallow, or a broken stderr turns the step that '
          'promises never to block startup into the one that aborts it',
    );

    expect(
      fallback,
      contains('logger.error('),
      reason:
          'a frame await that failed for a reason other than waiting is not '
          'the same event as the budget expiring, and is the worse one',
    );
    expect(
      fallback,
      contains('error.runtimeType.toString()'),
      reason:
          'the fallback logs the type, and only the type — the Logger port '
          'forbids an exception body on a channel that runs all day',
    );
    expect(fallback, contains('_log('), reason: 'same swallow, same reason');
    // The same blacklist `_installErrorHandlers` gets above, for the same
    // reason and against the same mutation: this clause is the second place in
    // this file where an arbitrary caught `Object` reaches a log call, and a
    // key still named `error_type` carrying `error.toString()` analyzes clean.
    for (final forbidden in <String>[
      'error.toString()',
      'stack',
      'exit(',
      'rethrow',
    ]) {
      expect(
        fallback,
        isNot(contains(forbidden)),
        reason:
            'the frame await must not render the error, its stack, or end the '
            'startup it exists to protect: `$forbidden` must not appear here',
      );
    }
  });

  test('DW-20, DW-28: one unresponsive-call budget is stated here and handed '
      'to both adapters', () {
    // The two entries were bundled to answer the policy question once: how long
    // a single platform call may hold the daemon before it is abandoned. That
    // "once" is only checkable here — each adapter's own suite can see its own
    // bound and nothing else, so two different numbers, or a default quietly
    // reintroduced at one site, would leave both suites green.
    final main = _mainSource();
    final budget = RegExp(
      r'const Duration _unresponsiveCallBudget = Duration\(seconds: (\d+)\)',
    ).firstMatch(main);

    expect(
      budget,
      isNotNull,
      reason:
          'the policy is a named constant stated in seconds, so the number is '
          'argued with in one place rather than inline at two call sites',
    );
    // A range, like the first-frame budget above: re-arguing the number stays
    // allowed, voiding it does not. The floor is prose — below a couple of
    // seconds an ordinary portal dialog, or a drift isolate finishing its last
    // write, reads as unresponsive and the daemon abandons work that was about
    // to land.
    //
    // The ceiling is **derived**, because a fixed one contradicts itself the
    // moment a teardown step is added: the bound is per step, so the worst-case
    // shutdown is the budget times the number of steps, and past the grace its
    // supervisor allows that shutdown ends in `SIGKILL` instead — which is the
    // ending the whole entry exists to avoid. Counted from the source rather
    // than restated here, so adding a step tightens this row rather than
    // silently voiding its argument.
    //
    // Where the 90 comes from: it is systemd's stock `DefaultTimeoutStopSec`,
    // used as a reference because it is the most generous grace this daemon is
    // likely to be stopped under. This project ships **no** `.service` unit —
    // it installs an XDG autostart entry — so the figure is not one its own
    // packaging sets, and a desktop session's logout grace can be shorter.
    // That makes it a ceiling to stay well inside, not a budget to spend.
    final seconds = int.parse(budget!.group(1)!);
    final steps = _teardownStepCount();

    expect(
      steps,
      greaterThan(1),
      reason: 'the count must actually be finding steps, or it proves nothing',
    );
    expect(seconds, greaterThanOrEqualTo(2));

    // Reserved, and compared strictly. The steps are not the whole stop: the
    // signal has to be delivered, `main` has to reach `shutdown()`, and the
    // process still has to flush and `exit(0)` afterwards. A worst case that
    // merely *ties* the SIGKILL instant has already lost, so `lessThan` against
    // a reserved ceiling rather than `lessThanOrEqualTo` against the grace.
    const supervisorStopGrace = 90;
    const reservedForTheRestOfTheStop = supervisorStopGrace ~/ 4;

    expect(
      seconds * steps,
      lessThan(supervisorStopGrace - reservedForTheRestOfTheStop),
      reason:
          'a shutdown that stalls at every step must finish inside the stop '
          'grace with room left for the rest of the stop, or the bound is not '
          'buying the ordered exit it was added for',
    );

    // Located inside each constructor call, not merely somewhere in the file:
    // `[^;]*` cannot cross the statement that ends the call, and it is
    // insensitive to how dart format wraps the argument list.
    expect(
      main,
      matches(
        RegExp(
          r'WindowManagerPanelVisibility\([^;]*'
          r'requestTimeout: _unresponsiveCallBudget',
        ),
      ),
      reason:
          'the panel adapter takes the shared constant; a literal here is a '
          'second policy nobody decided on',
    );
    expect(
      main,
      matches(
        RegExp(r'DaemonLifecycle\([^;]*stepTimeout: _unresponsiveCallBudget'),
      ),
      reason: 'and so does the teardown, from the same constant',
    );
    // And nothing else reaches either parameter. Both are required, so a second
    // number cannot arrive by default — it can only arrive by being written.
    //
    // Read as the *whole* argument rather than as a prefix. A lookahead for the
    // constant's name is satisfied by `_unresponsiveCallBudget * 2`, which is
    // exactly the second policy this row exists to reject: a site deriving its
    // own number from the shared one is not a site sharing it.
    final passed = RegExp(
      r'(?:requestTimeout|stepTimeout):([^,)]*)',
    ).allMatches(main);

    expect(
      passed,
      hasLength(3),
      reason:
          'three sites take a bound, and this row must be reading all of them. '
          'The third is the Wayland portal adapter, threaded through '
          'DaemonStartup.begin: D-17 bounds a portal that never answers so the '
          'settings screen cannot hang, and "a few seconds" is the same policy '
          'question the panel adapter and the teardown already answered once. '
          'Raising this count is how a fourth site joins the policy; lowering '
          'it is how one leaves',
    );
    for (final argument in passed) {
      expect(
        argument.group(1)!.trim(),
        '_unresponsiveCallBudget',
        reason:
            'one policy, two sites: a bound passed as anything but the shared '
            'constant itself — a literal, or an arithmetic on it — reopens the '
            'question these two entries were bundled to answer once',
      );
    }
  });

  test('AD-14: main.dart starts the lifecycle, so show requests reach the '
      'panel', () {
    expect(
      _mainSource(),
      contains('lifecycle.start()'),
      reason:
          'without this a second launch signals the holder, exits 0, and no '
          'panel ever appears',
    );
  });

  test('AD-8: the show-request subscription opens only after runApp, so a '
      'second launch cannot map an empty window', () {
    // Live only since the real PanelVisibility adapter landed: before that a
    // show request reached a placeholder that rejected. Now it maps the real
    // toplevel, so a launch arriving during startup would put an untitled,
    // taskbar-listed, widget-tree-less window on screen.
    final main = _mainSource();
    final runApp = main.indexOf('runApp(');
    final start = main.indexOf('lifecycle.start()');

    expect(runApp, isNonNegative);
    expect(start, isNonNegative);
    expect(
      start,
      greaterThan(runApp),
      reason: 'the window must have its widget tree before it can be raised',
    );
    expect(
      start,
      lessThan(main.indexOf('startup.bindHotkey(')),
      reason:
          'a real backend bind can sit on a portal dialog for seconds '
          '(AD-11), and a launch during that must still be served',
    );
  });

  test('AD-8: main.dart binds the panel seam to the window_manager adapter, '
      'not to a placeholder', () {
    final main = _mainSource();

    expect(
      main,
      contains('WindowManagerPanelVisibility('),
      reason:
          'the two ports the panel sits on are what make CAP-2, CAP-11 and '
          'CAP-14 reach anything; swapping either back to a placeholder must '
          'fail a test rather than pass in silence',
    );
    expect(
      main,
      matches(
        RegExp(
          r'WindowManagerPanelWindow\(\s*activationPresenter: activationPresenter',
        ),
      ),
    );
    expect(
      main,
      contains('const activationPresenter = GtkPanelActivationPresenter()'),
    );
    expect(main, contains('activationContext: activationContext'));
    expect(
      main,
      contains('onActivationToken: activationContext.preparePortal'),
    );
    expect(main, contains('onPanelRequest: activationContext.prepareTray'));
    expect(
      main,
      contains('panelVisibilityProvider.overrideWithValue(panelVisibility)'),
      reason:
          'the seam must see the same instance the lifecycle closes and '
          'main.dart holds — a second one would register a second window '
          'listener and never be disposed',
    );
  });

  test('AD-12: main.dart binds the tray seam to the tray_manager adapter, not '
      'to a placeholder', () {
    final main = _mainSource();

    expect(
      main,
      contains('TrayManagerTray('),
      reason:
          'four shipped strings tell the user that the hotkey is inactive but '
          '"the tray menu still opens the panel"; a placeholder here makes '
          'every one of them false',
    );
    expect(main, contains('TrayManagerTrayIcon()'));

    // The producer half of the abort path, which nothing pinned. The two
    // `if (tray != null)` / `else if (trayIcon != null)` clauses further down
    // are pinned by shape, but the assignments that make either reachable were
    // not — and Dart does not flag a nullable local that is read and never
    // assigned, so both mutations pass `dart analyze` and the whole suite:
    //
    //   * inlining `TrayManagerTrayIcon()` into the `TrayManagerTray(...)`
    //     argument list leaves `openedTrayIcon` permanently null, reopening
    //     exactly the window it was introduced to close — a startup that fails
    //     between the two constructors exits holding a live `TrayListener` on
    //     the `tray_manager` singleton;
    //   * dropping `openedTray = tray;` is worse: `_abort` takes the `else`
    //     arm, so the seam is destroyed but `TrayManagerTray` is never
    //     disposed and its subscription and `_panelRequests` stay open.
    //
    // One regex spans both constructors and the assignment between them, so
    // neither shape can be reintroduced silently.
    expect(
      main,
      matches(
        RegExp(
          r'final trayIcon = TrayManagerTrayIcon\(\);\s*'
          r'openedTrayIcon = trayIcon;\s*'
          r'final tray = TrayManagerTray\(\s*icon: trayIcon,',
        ),
      ),
      reason:
          'the seam must be constructed and captured before the port that '
          'wraps it, or the abort path cannot close an orphaned listener',
    );
    expect(
      main,
      contains('openedTray = tray;'),
      reason:
          'without this the abort path disposes the seam but never the port '
          'holding its subscription',
    );

    expect(
      main,
      contains('trayProvider.overrideWithValue(tray)'),
      reason:
          'the seam must see the same instance the lifecycle closes and '
          'main.dart holds — a second one would register a second listener on '
          'the tray_manager singleton and never be disposed',
    );
  });

  test('AD-12: the tray menu is joined to the lifecycle handler that raises '
      'the panel, and to the ordered teardown', () {
    final main = _mainSource();

    expect(
      main,
      contains('trayRequests: tray.panelRequests'),
      reason:
          'AD-8 requires the menu action reach PanelVisibility.show() through '
          'PanelController.showPanel(); this argument is the only link '
          'between the tray stream and the handler that does it',
    );
    expect(
      main,
      contains('closeTray: tray.dispose'),
      reason:
          'the tray holds a tray_manager listener and a stream; without this '
          'step the daemon exits with both still open',
    );
  });

  test('AD-12: the tray is installed after the lifecycle starts and before '
      'the hotkey bind', () {
    // Both bounds are behaviour, not tidiness. Before `bindHotkey`, because
    // that is what calls `setHotkeyUnavailable` and a menu pushed at an
    // indicator that does not exist yet dereferences a null AppIndicator* in
    // native code. After `lifecycle.start()`, so the open-panel entry has a
    // subscriber the moment a user can pick it.
    final main = _mainSource();
    final install = main.indexOf('tray.install()');

    expect(install, isNonNegative, reason: 'nothing else installs the tray');
    expect(install, greaterThan(main.indexOf('lifecycle.start()')));
    expect(install, lessThan(main.indexOf('startup.bindHotkey(')));
  });

  test('AD-12: the startup bind outcome is handed to the settings surface, not '
      'discarded', () {
    // AD-12 names two consumers of an unavailable hotkey, the tray and the
    // settings screen. `bindHotkey` tells the tray itself; the settings half is
    // this one call, and without it the screen states "nothing has been
    // requested yet" for the life of a daemon whose hotkey never bound.
    //
    // Pinned by source, because this line is in the one file no test can
    // execute: `graph.applyStartupBindOutcome` has behavioural coverage in
    // `test/composition/daemon_graph_test.dart`, and deleting its *call site*
    // here leaves `dart analyze` clean and the whole suite green.
    //
    // **The argument, not just the two calls.** Asserting that each call appears
    // says nothing about the value flowing between them: rewriting the hand-off
    // as `graph.applyStartupBindOutcome(const HotkeyUnavailable(…)); await
    // startup.bindHotkey(tray: tray);` satisfied both, kept `dart analyze` clean
    // and the whole suite green, and would have shipped a settings screen
    // stating a fabricated sentence for the life of the daemon while the tray
    // reported the truth — exactly the disagreement the second assertion below
    // claims to prevent.
    //
    // Both correct spellings are accepted, because a gate with a false positive
    // is a gate someone deletes: the composed call (however `dart format` wraps
    // it) and the two-statement form that names a local in between. Anything
    // else — a literal, a stale variable, no connection at all — fails.
    final main = _mainSource();

    expect(
      _handsBindOutcomeToSettings(main),
      isTrue,
      reason:
          'the settings surface must be handed the value `startup.bindHotkey` '
          'returned — a call that appears near it is not the same as a call '
          'that receives it, and the two surfaces AD-12 names would disagree '
          'from the first frame',
    );
    expect(
      'startup.bindHotkey('.allMatches(main),
      hasLength(1),
      reason:
          'exactly one bind, so the outcome the surface renders is the one the '
          'tray was told about — a second call would be a second answer, and the '
          'two surfaces AD-12 names would disagree from the first frame',
    );
  });

  test('the AD-12 hand-off matcher accepts every correct spelling and no '
      'incorrect one', () {
    // A gate with a false positive is a gate someone deletes, and this one had
    // three: the local's declaration was matched by syntax (`final` or `var`,
    // then at most one bare word of type), so a nullable type, a qualified type
    // or `late final` all read as "no hand-off" and would have failed a correct
    // `main`. The matcher keys on the assignment target now.
    for (final spelling in <String>[
      'graph.applyStartupBindOutcome(await startup.bindHotkey(tray: tray));',
      'final outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(outcome);',
      'final HotkeyBindOutcome outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(outcome);',
      'final HotkeyBindOutcome? outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(outcome);',
      'late final outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(outcome);',
      'var outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(outcome);',
    ]) {
      expect(
        _handsBindOutcomeToSettings(spelling),
        isTrue,
        reason: 'a correct hand-off must not fail the gate:\n$spelling',
      );
    }

    // And the disconnected spellings the gate exists to catch.
    for (final spelling in <String>[
      'graph.applyStartupBindOutcome(const HotkeyUnavailable(message: "x"));\n'
          'await startup.bindHotkey(tray: tray);',
      'final outcome = await startup.bindHotkey(tray: tray);\n'
          'graph.applyStartupBindOutcome(somethingElse);',
      'await startup.bindHotkey(tray: tray);',
    ]) {
      expect(
        _handsBindOutcomeToSettings(spelling),
        isFalse,
        reason: 'a hand-off that carries no value must fail:\n$spelling',
      );
    }
  });

  test('AD-12: the install is guarded, so a session with no tray host still '
      'brings the daemon up', () {
    // The spine's operational envelope: a missing dependency degrades one
    // capability and never blocks startup. Deleting the try/catch around
    // `tray.install()` leaves `dart analyze` clean and the whole suite green,
    // while turning a wlroots or headless session into an aborted launch —
    // `main`'s outer catch runs `_abort` and exits 1.
    final main = _mainSource();
    final window = main.substring(
      main.indexOf('lifecycle.start()'),
      main.indexOf('startup.bindHotkey('),
    );
    final install = window.indexOf('tray.install()');

    expect(install, isNonNegative);
    // One assertion spanning the whole guard rather than two independent
    // substring searches, which any unrelated `try` in this window would have
    // satisfied between them. Whitespace-tolerant, because how dart format
    // wraps the block is not the claim.
    expect(
      window,
      matches(
        RegExp(r'try\s*\{\s*await tray\.install\(\);\s*\}\s*on Object catch'),
      ),
      reason:
          'the install is wrapped in a guard of its own, so a refused install '
          'is a log line rather than an aborted startup',
    );
    expect(
      window.substring(install),
      contains('_log('),
      reason:
          'the log line itself goes through this file own swallow: '
          'StderrLogger ends in _sink.writeln, which throws on a broken '
          'stderr (EPIPE/EBADF for a systemd-launched daemon), and that throw '
          'would escape into main catch and abort the startup this guard '
          'exists to protect',
    );
  });

  test('AD-14: the tray is constructed only after the not-the-daemon branch '
      'has exited', () {
    // AD-14 says the tray is the resident daemon's own icon and nothing here
    // starts a second indicator. That rests entirely on `exit(0)` sitting
    // above this construction: `TrayManagerTrayIcon()`'s constructor registers
    // a listener on the `tray_manager` singleton, so hoisting it above the
    // branch would do that in a process on its way out — and would break no
    // other test in the suite.
    final main = _mainSource();

    expect(
      main.indexOf('TrayManagerTrayIcon()'),
      greaterThan(main.indexOf('if (startup == null)')),
      reason: 'a launch that is not the daemon builds no tray at all',
    );
  });

  test('CAP-2: main.dart binds the clipboard seam to the system clipboard', () {
    expect(
      _mainSource(),
      contains('clipboardProvider.overrideWithValue(const SystemClipboard())'),
      reason:
          'CAP-2 seeds the editor from the *system* clipboard; a placeholder '
          'here is a panel that opens empty every time',
    );
  });

  test('CAP-7: main.dart hands the panel adapter to the ordered teardown', () {
    expect(
      _mainSource(),
      contains('closePanelVisibility: panelVisibility.dispose'),
      reason:
          'the adapter holds a window listener and a stream; without this '
          'step the daemon exits with both still open',
    );
  });

  test('AD-14: the lifecycle is wired to the graph own showPanel, not to some '
      'other handler', () {
    // `..start()` above only proves the subscription exists. Both hops either
    // side are covered behaviourally — `daemon_lifecycle_test.dart` proves the
    // lifecycle delivers to whatever handler it was given, and
    // `daemon_graph_test.dart` proves `showPanel()` raises the panel — so the
    // one unverified link is the argument joining them here. Replacing it with
    // an empty closure leaves every suite green and every second launch
    // signalling a holder that does nothing.
    expect(
      _mainSource(),
      contains('onShowRequest: graph.showPanel'),
      reason: 'AD-14 exists so a second launch raises the resident panel',
    );
  });

  test('AD-9: main.dart binds the hotkey seam to the single adapter startup '
      'chose, not to a second one of its own', () {
    // `_overriddenSeams()` reads only the provider name to the left of
    // `.overrideWithValue(`, so `globalHotkeyProvider.overrideWithValue(
    // X11GlobalHotkey())` satisfies it. That daemon holds two adapters where
    // AD-9 allows exactly one: the startup `bind()` and the tray describe the
    // instance `DaemonStartup` built, `SettingsController` holds the other,
    // and only the first is ever disposed.
    expect(
      _mainSource(),
      contains('globalHotkeyProvider.overrideWithValue(startup.hotkey)'),
      reason:
          'AD-9: exactly one hotkey adapter is constructed at startup, and it '
          'is the one the graph must see',
    );
  });

  test('AD-9: main.dart builds the one X11 key-grab seam and hands it to '
      'startup, rather than letting the adapter build its own', () {
    // The same shape as the tray rows below: the *producer* assignment is what
    // nothing else pins. `X11GlobalHotkey` takes the seam through its
    // constructor, so an adapter that built one internally would satisfy every
    // behavioural test in the suite while leaving `main.dart` holding a second
    // seam that never grabs — and the abort path releasing nothing.
    final main = _mainSource();

    expect(
      main,
      contains('final hotkeyRegistrar = X11KeyGrabRegistrar();'),
      reason:
          'this is the only file allowed to name the X11 key-grab adapter, and '
          'the local is what the abort path closes over',
    );
    expect(
      main,
      contains('registrar: hotkeyRegistrar,'),
      reason:
          'AD-9 keeps the display-server choice in DaemonStartup, where a '
          'test can drive both branches; the vendor object comes from here',
    );
  });

  test('AD-9: the hotkey seam is built before the not-the-daemon branch, '
      'because startup is what needs it and the construction is inert', () {
    // The mirror image of the tray row below, and deliberately so. The tray
    // seam must come *after* `exit(0)` because its constructor registers a
    // listener on the `tray_manager` singleton. This one must come *before*,
    // because `DaemonStartup.begin` takes it — and that is only safe while it
    // stays inert: `X11KeyGrabRegistrar` allocates a stream controller and does
    // nothing else. It makes that promise more strongly than the seam it
    // replaced, which merely avoided reading a lazy singleton: this one opens no
    // library, spawns no isolate and makes no X connection until the first
    // grab, so a Wayland session that never grabs pays nothing. If that ever
    // changes, this row is the one that has to be argued with.
    final main = _mainSource();

    // Both guarded, the way the AD-4 row below guards its two: `indexOf`
    // answers -1 for a marker that is not there, and -1 is less than anything,
    // so an unguarded ordering row passes vacuously the moment either end of it
    // is renamed or deleted — which is exactly when it should fail.
    expect(
      main.indexOf('X11KeyGrabRegistrar()'),
      isNonNegative,
      reason: 'the seam construction is what this row orders',
    );
    expect(main.indexOf('if (startup == null)'), isNonNegative);
    expect(
      main.indexOf('X11KeyGrabRegistrar()'),
      lessThan(main.indexOf('if (startup == null)')),
      reason: 'DaemonStartup.begin cannot choose the X11 adapter without it',
    );
  });

  test('AD-4: an aborted startup closes the hotkey adapter and its seam, in '
      'the same order the lifecycle uses', () {
    // What this pins is that the adapter and the seam are closed at all, and
    // where. The adapter holds a broadcast controller and a subscription to
    // the seam's press stream, and on this branch — `lifecycle == null` —
    // nothing else disposes either; `DaemonLifecycle.shutdown()` does, so
    // without these two steps the two teardown paths disagree about what is
    // left open.
    //
    // Explicitly defensive as to the *grab*, and not evidence of a live path:
    // `_finishStartup` is the only caller of `bindHotkey` and `lifecycle` is
    // assigned before it runs, so a failure reaching this branch cannot have
    // grabbed anything yet. Kept for the same reason as the tray's
    // `else if (trayIcon != null)` arm — see `_abort`'s doc.
    final main = _mainSource();
    final adapter = main.indexOf("('disposing the hotkey adapter'");
    final seam = main.indexOf("('releasing the global hotkey grab'");

    expect(adapter, isNonNegative);
    expect(seam, isNonNegative);
    expect(
      adapter,
      lessThan(seam),
      reason:
          'the adapter owns the seam and disposes it in turn, so it goes '
          'first; the seam step is what closes it on a Wayland session, where '
          'no adapter ever held it',
    );
    expect(
      adapter,
      greaterThan(main.indexOf("('closing the tray'")),
      reason: 'DaemonLifecycle.shutdown() disposes the hotkey after the tray',
    );
    expect(
      seam,
      lessThan(main.indexOf("('closing the database'")),
      reason: 'and before the database, which is the next step there too',
    );
  });

  test('AD-14: a launch that is not the daemon exits the process rather than '
      'returning from main', () {
    // Returning from `main` does not end a Flutter process — the embedder's
    // GTK loop is already running — so a second launch would sit resident
    // forever with no graph and no window. The child-process row in
    // `daemon_startup_test.dart` proves the exit code, but it spawns
    // `test/support/daemon_startup_child.dart`, which carries its own
    // `exit(0)`: it verifies a copy of this branch, never this one.
    final main = _mainSource();
    final branch = main.indexOf('if (startup == null)');

    expect(branch, isNonNegative);
    expect(
      main.substring(branch, main.indexOf('}', branch)),
      contains('exit(0)'),
      reason:
          'the not-the-daemon branch must end the process, not fall through '
          'to the embedder loop',
    );
  });

  test('AD-14: every step taken after the address is held is inside the abort '
      'guard, not just the last one', () {
    // A throw anywhere between `DaemonStartup.begin` returning and `runApp`
    // escapes into a GTK loop that is already running: the process neither
    // exits nor serves, and it still holds the single-instance address, so
    // every later launch is signalled, sees `alreadyRunning`, and exits 0 in
    // silence. Guarding only `_finishStartup` left the graph build, the
    // container and the lifecycle outside — so the guard has to open before
    // them and `_abort` has to be what the catch runs.
    final main = _mainSource();
    final guard = main.indexOf('try {');

    expect(guard, isNonNegative, reason: 'the post-lock work needs a guard');
    expect(
      guard,
      lessThan(main.indexOf('DaemonGraph(')),
      reason: 'the graph build is inside the guard, not before it',
    );
    expect(
      guard,
      lessThan(main.indexOf('DaemonLifecycle(')),
      reason: 'the lifecycle build is inside the guard, not before it',
    );
    expect(
      main,
      matches(
        RegExp(
          r'_abort\(\s*error: error,\s*lifecycle: lifecycle,'
          r'\s*graph: openedGraph,'
          r'\s*panelVisibility: openedPanelVisibility,'
          r'\s*trayIcon: openedTrayIcon,\s*tray: openedTray,'
          r'\s*hotkeyRegistrar: hotkeyRegistrar,'
          r'\s*startup: startup,\s*logger: logger,\s*closeLogs: closeLogs,?\s*\)',
        ),
      ),
      reason:
          'everything the daemon opened before the failure has to reach the '
          'abort, or it is left registered against a process on its way out',
    );
  });

  test('AD-14: every log on the abort path goes through the swallow, so a '
      'broken stderr cannot stop the address going back', () {
    // Newly load-bearing, and the reason this row exists at all.
    // `_installErrorHandlers` answers `true` for everything that reaches the
    // root zone, so a throw out of `_abort` is no longer fatal — it is caught,
    // logged and *handled*, and the `exit(1)` at the end of `_abort` never
    // runs. The process then sits on the embedder's loop holding the AD-14
    // address with no panel, no tray and no hotkey: exactly the state `_abort`
    // exists to prevent, reached by the guard against it failing.
    //
    // `StderrLogger` ends in `_sink.writeln`, and a broken journal socket is
    // ordinary for a daemon started by systemd — this file says so forty lines
    // above, which is why `_log` exists. Inside `_releaseWithoutLifecycle` the
    // consequence is narrower and worse: a throw from the report about a
    // failed step escapes the `for`, skipping every step after it, and the
    // last step is the one that hands the address back.
    final main = _mainSource();
    final abort = main.indexOf('Future<void> _abort(');
    final end = main.indexOf('ProviderContainer _container(');

    expect(abort, isNonNegative);
    expect(end, greaterThan(abort));

    // A logger call not preceded by the `=> ` of a `_log(() => …)` thunk is a
    // bare one. Whitespace-tolerant by construction: the arrow is what makes
    // it deferred, and how dart format wraps the line is not the claim.
    expect(
      RegExp(r'(?<!=> )logger\.\w+\(').allMatches(main.substring(abort, end)),
      isEmpty,
      reason:
          'every log between _abort and the container builder is deferred into '
          '_log; a bare one turns a broken stderr into a daemon that holds the '
          'singleton address forever with nothing behind it',
    );
  });

  test('DW-37: an aborted startup with no lifecycle disposes the controllers '
      'and the container first, in the order shutdown uses', () {
    // `DaemonGraph.build()` reads its three providers in sequence, so a throw
    // partway through leaves the earlier controllers constructed — and
    // subscribed to `PanelVisibility.changes` — with no lifecycle to dispose
    // them. Without these two steps the branch closed that stream under a live
    // `CorrectionController`, the exact inverse of the order
    // `DaemonLifecycle.shutdown()` exists to guarantee.
    final main = _mainSource();
    final release = main.indexOf('Future<void> _releaseWithoutLifecycle(');

    expect(release, isNonNegative);
    expect(
      main,
      matches(RegExp(r'_releaseWithoutLifecycle\(\s*graph: graph,')),
      reason:
          'the captured graph has to reach the step list; a parameter that is '
          'never passed leaves dart analyze clean and the branch unchanged',
    );

    // Each step located by its label *and* the callable beside it, because
    // what this row claims is an order of operations and a label is only what
    // the log line says. Swapping the two callables between their tuples —
    // leaving both strings exactly where they are — restores the inversion
    // DW-37 was filed to fix: the container comes down first, running the
    // onDispose hooks under the controllers instead of behind them. Every
    // ordering assertion below would still read the same two labels in the
    // same two places and stay green.
    final tail = main.substring(release);
    final controllersStep = RegExp(
      r"\('disposing the controllers',\s*graph\.disposeControllers\s*\)",
    ).firstMatch(tail);
    final containerStep = RegExp(
      r"\('disposing the provider graph',\s*\(\) async => graph\.dispose\(\)\s*\)",
    ).firstMatch(tail);

    expect(
      controllersStep,
      isNotNull,
      reason:
          'the controllers step calls disposeControllers, which is what drains '
          'the CAP-7 writes still in flight',
    );
    expect(
      containerStep,
      isNotNull,
      reason:
          'the container step calls the graph dispose, which is the backstop '
          'that runs every provider onDispose behind it',
    );

    final controllers = release + controllersStep!.start;
    final container = release + containerStep!.start;
    final panel = main.indexOf(
      "('closing the panel visibility adapter'",
      release,
    );

    expect(panel, isNonNegative);
    expect(
      controllers,
      lessThan(container),
      reason:
          'CorrectionController.dispose() drains the CAP-7 writes in flight, '
          'and the container onDispose hooks are the backstop behind it',
    );
    expect(
      container,
      lessThan(panel),
      reason:
          'the panel adapter must outlive every controller that can still call '
          'show()/hide() on it — PanelController fires those without awaiting',
    );

    // Both guarded independently, because the failure can precede the graph
    // entirely and a step list that dereferences a null there would abort the
    // abort.
    expect(
      main.substring(0, controllers),
      matches(RegExp(r'if \(graph != null\)\s*$')),
      reason: 'a failure before the graph existed has no controllers to close',
    );
    expect(
      main.substring(0, container),
      matches(RegExp(r'if \(graph != null\)\s*$')),
      reason: 'and no container either',
    );
  });

  test('AD-8: an aborted startup closes the panel adapter even when there is '
      'no lifecycle yet', () {
    // The adapter registers a window listener in its constructor, so a failure
    // between that and the lifecycle leaves one registered against a process
    // on its way out — which `_abort`s own doc used to deny.
    final main = _mainSource();
    final step = main.indexOf("('closing the panel visibility adapter'");

    expect(
      step,
      isNonNegative,
      reason: 'the early-abort branch has its own teardown list',
    );
    // A bare `contains` was the whole pin here, and it could not tell where
    // the step sat: deleting the null guard, or moving the step after the lock
    // release, left it green. Both matter — the parameter is nullable because
    // the failure can precede the adapter, and the address must go back last.
    expect(
      main.substring(0, step),
      endsWith('if (panelVisibility != null)\n      '),
      reason:
          'the step is guarded, because a failure before the adapter was '
          'built has no adapter to close',
    );
    expect(
      step,
      lessThan(main.indexOf("('releasing the single-instance address'")),
      reason:
          'the address goes back last, so nothing is left half-open while '
          'another launch can already take it',
    );
  });

  test('AD-12: an aborted startup closes the tray too, in the same order the '
      'lifecycle uses', () {
    // `TrayManagerTrayIcon`'s constructor registers a listener on the
    // `tray_manager` singleton, so a failure between that and the lifecycle
    // leaves one registered against a process on its way out — the same shape
    // as the panel adapter above.
    final main = _mainSource();
    final step = main.indexOf("('closing the tray'");

    expect(step, isNonNegative);
    expect(
      main.substring(0, step),
      matches(RegExp(r'if\s*\(tray != null\)\s*$')),
      reason:
          'the failure can precede the tray, so the step is guarded — matched '
          'whitespace-tolerantly, because how dart format wraps the line is '
          'not the claim',
    );
    expect(
      step,
      greaterThan(main.indexOf("('closing the panel visibility adapter'")),
    );
    expect(
      step,
      lessThan(main.indexOf("('releasing the single-instance address'")),
    );

    // The other arm, which nothing pinned: the failure can land between the
    // two constructors, where the seam has already registered its listener on
    // the `tray_manager` singleton and no port owns it yet. Deleting the whole
    // clause left `dart analyze` clean — Dart does not flag the now-unused
    // named parameter — and the entire suite green, reopening exactly the
    // window `openedTrayIcon` was introduced to close.
    final iconStep = main.indexOf("('closing the tray icon'");

    expect(iconStep, isNonNegative, reason: 'the orphan seam is closed too');
    expect(
      main.substring(0, iconStep),
      matches(RegExp(r'else if\s*\(trayIcon != null\)\s*$')),
      reason:
          'an `else`, not a second `if`: the tray owns the seam and disposes '
          'it, so exactly one of the two runs — never both',
    );
    expect(
      iconStep,
      lessThan(main.indexOf("('closing the database'")),
      reason: 'it holds the tray step place in the order',
    );
  });

  test('CAP-7: main.dart installs the signal handlers, one of the two triggers '
      'for the ordered teardown', () {
    final main = _mainSource();

    expect(main, contains('ProcessSignal.sigterm'));
    expect(main, contains('ProcessSignal.sigint'));
    expect(
      main,
      contains('ProcessSignal.sighup'),
      reason:
          'a terminal close or session logout delivers SIGHUP, whose default '
          'disposition kills the process past the ordered teardown',
    );

    // `contains('_installSignalHandlers(')` alone is satisfied by the
    // function's own declaration, so it cannot tell a call from a definition
    // and deleting the call site leaves it green. Match the call, and its
    // position: `main.dart` states the before-the-window ordering is
    // deliberate, because the window and the bind are the two slowest steps
    // in startup and a stop signal arriving during either must still reach
    // the ordered teardown.
    final call =
        RegExp(
          r'\n\s+_installSignalHandlers\(lifecycle, closeLogs, logger\);',
        ).firstMatch(main)?.start ??
        -1;
    expect(
      call,
      isNonNegative,
      reason:
          'a signal is one of the two triggers for DaemonLifecycle.shutdown — '
          'the tray Quit entry is the other, pinned by the DW-114 row below',
    );
    expect(
      call,
      lessThan(main.indexOf('_finishStartup(')),
      reason:
          'installed before the window and the bind, not after — otherwise a '
          'signal during either kills the daemon with a history write in '
          'flight (CAP-7)',
    );
  });

  test('DW-114: the tray Quit entry reaches the same ordered teardown a signal '
      'does, and the process exits behind it', () {
    // Two exit triggers, one exit path. The teardown order is what protects the
    // CAP-7 write in flight, and it is tested in `daemon_lifecycle_test.dart` —
    // so what is unpinned is the join, and only here: deleting the handler, or
    // rewriting it to `exit(0)` without the shutdown, leaves `dart analyze`
    // clean and every suite green while a tray Quit kills the daemon mid-write.
    final main = _mainSource();
    final declaration = main.indexOf('void _installQuitHandler(');

    expect(declaration, isNonNegative, reason: 'nothing else quits the daemon');
    // Bounded on `\n}\n` rather than `\n}`, because this declaration opens with
    // a named-parameter block whose own closing brace sits at column zero —
    // `\n}` lands on `\n}) {` and slices away the entire body.
    final body = main.substring(
      declaration,
      main.indexOf('\n}\n', declaration),
    );

    expect(
      body,
      contains("('window Close', panelQuitRequests)"),
      reason:
          'native Close with quit selected shares the tray shutdown handler',
    );

    expect(
      body,
      contains('tray.quitRequests'),
      reason:
          'the handler listens to the port stream the menu emits on; anything '
          'else is a handler wired to nothing',
    );
    expect(
      body,
      contains('lifecycle.shutdown()'),
      reason:
          'the same latched, per-step-bounded sequence a SIGTERM runs — a '
          'second teardown order would be a second thing to keep in step',
    );
    expect(
      body,
      contains('exit(0)'),
      reason:
          'shutdown() deliberately does not end the process, so this is what '
          'does; without it a picked Quit drains the daemon and leaves it '
          'resident with nothing behind it',
    );
    // The order inside the body, not merely both tokens: `exit(0)` before the
    // await ends the process with the CAP-7 write still in flight, which is the
    // exact failure the ordered teardown exists to prevent, and reads almost
    // identically.
    expect(
      body,
      matches(
        RegExp(
          r'await lifecycle\.shutdown\(\);\s*await closeLogs\(\);\s*exit\(0\);',
        ),
      ),
      reason: 'the exit follows the teardown; it does not race it',
    );
    // The repeat branch. A pick landing on a teardown already draining must
    // say so rather than looking ignored, and `isShuttingDown` is the only
    // thing that can tell the two apart — without this the whole branch, and
    // both its lines, delete cleanly with every suite green.
    expect(
      body,
      contains('lifecycle.isShuttingDown'),
      reason:
          'a pick that lands mid-teardown awaits the latched shutdown; the '
          'line is how an operator learns the daemon is draining rather than '
          'ignoring them',
    );

    // And no confirmation step: the intent forbids a prompt, a delay or an
    // "are you sure" state between the pick and the teardown.
    //
    // Scanned over the *code*, not the raw slice: this body is mostly
    // justification prose, so a bare `contains('confirm')` over the text fails
    // the day someone writes "no confirmation step here" in a comment. A guard
    // that fires on its own documentation gets weakened rather than understood.
    final code = body
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    for (final forbidden in <String>[
      'showDialog',
      'confirm',
      'Future.delayed',
    ]) {
      expect(
        code,
        isNot(contains(forbidden)),
        reason:
            'quitting is immediate — every correction is already in history '
            '(CAP-7) and copying is explicit (CAP-11), so `$forbidden` would '
            'guard nothing',
      );
    }
    // The AD-15 arm. The subscription is one of the daemon's two exit
    // triggers, so a seam that breaks the port's promise must leave it alive
    // rather than removing the only way out a tray-only user has.
    expect(
      body,
      contains('onError:'),
      reason:
          'an errored stream must not end the subscription that carries the '
          'exit trigger',
    );
    expect(
      body,
      contains('error.runtimeType'),
      reason:
          'the type and only the type — the Logger port forbids an exception '
          'body on a channel that runs all day',
    );

    // The call, and its position. `contains('_installQuitHandler(')` alone is
    // satisfied by the declaration above, so it cannot tell a call from a
    // definition.
    final quitCall =
        RegExp(
          r'\n\s+_installQuitHandler\(\s*tray: tray,\s*lifecycle: lifecycle,\s*panelQuitRequests: graph\.quitRequests,\s*closeLogs: closeLogs,\s*logger: logger,?\s*\);',
        ).firstMatch(main)?.start ??
        -1;
    final signalCall =
        RegExp(
          r'\n\s+_installSignalHandlers\(lifecycle, closeLogs, logger\);',
        ).firstMatch(main)?.start ??
        -1;

    expect(
      quitCall,
      isNonNegative,
      reason:
          'the handler has to be called with the tray whose menu emits and the '
          'lifecycle that owns the teardown',
    );
    expect(signalCall, isNonNegative);
    expect(
      quitCall,
      greaterThan(signalCall),
      reason:
          'immediately after the signal watchers, for the same reason they are '
          'installed before the window and the bind: both triggers must reach '
          'the ordered teardown from the earliest point they can be used',
    );
    expect(
      quitCall,
      lessThan(main.indexOf('_finishStartup(')),
      reason:
          'the menu carrying the entry is pushed inside _finishStartup, so the '
          'subscription has to exist before it can be picked',
    );
  });

  test('DW-12: the window is prepared so a close is a dismissal, not a '
      'destroyed toplevel', () {
    // `on_window_close` returns `_is_prevent_close`
    // (`window_manager-0.5.2/linux/window_manager_plugin.cc:967-971`), and
    // returning TRUE is the whole of what suppresses GTK's default
    // `delete-event` handler. Without this flag GTK destroys the toplevel: the
    // CAP-7 write in flight is abandoned, and the panel adapter's close arm —
    // which now issues a real `hide` — is left calling at a window that no
    // longer exists. Note the emit-before-return ordering in that function is
    // *not* the guarantee: `_emit_event` is an asynchronous channel invoke, so
    // with the flag false the destroy happens before Dart sees the event at
    // all. Deleting the line leaves `dart analyze` clean, and the only other
    // thing that would notice is `hidden_window_test.dart`'s presence row —
    // mutation-verified, this pass, in both directions.
    final main = _mainSource();
    final create = main.indexOf('Future<void> _createHiddenWindow() async {');

    expect(create, isNonNegative);
    // `\n}\n`, for the reason the DW-114 row above spells out: `\n}` lands on
    // the first line that merely *starts* with a brace, so a declaration that
    // later grows a named-parameter block or an inline closure would silently
    // slice its own body away and leave the `contains` below inspecting a
    // fragment. This declaration takes no parameters today; the bound is the
    // one that stays right when it does.
    final body = main.substring(create, main.indexOf('\n}\n', create));

    expect(
      body,
      contains('windowManager.setPreventClose(true)'),
      reason:
          'a window *property*, set once beside setSkipTaskbar — not a call '
          'behind the PanelWindow seam, whose purpose is the three toggle '
          'requests',
    );
    // Before `runApp`, which is a claim about the call order rather than the
    // file's text: `_createHiddenWindow` is declared far below its own call
    // site, so an index comparison against the declaration would be answering a
    // different question.
    expect(
      main.indexOf('await _createHiddenWindow();'),
      isNonNegative,
      reason: 'nothing else prepares the window',
    );
    expect(
      main.indexOf('await _createHiddenWindow();'),
      lessThan(main.indexOf('runApp(')),
      reason:
          'the flag has to be set before the engine can show anything, so the '
          'first close a user can produce already finds it in effect',
    );
    // And nothing closes, destroys or terminates the window anywhere: the
    // daemon exits through exit(0) after shutdown(), and nothing else.
    for (final forbidden in <String>[
      'windowManager.close(',
      'windowManager.destroy(',
      'windowManager.terminate(',
    ]) {
      expect(
        main,
        isNot(contains(forbidden)),
        reason:
            'the toplevel is never destroyed — `$forbidden` is a second exit '
            'path past the ordered teardown',
      );
    }
  });

  test('AD-9/G-01-13: the display server is read exactly once, and both the '
      'hotkey adapter and the focus witness are chosen from that one read', () {
    // `DaemonStartup`'s own comment states the invariant — "nothing reads the
    // display server again after this line" — and until G-01-13 there was only
    // one consumer, so the invariant was true by having nowhere else to be
    // false. A second consumer is exactly the change that can break it, and it
    // breaks it silently: two `fromEnvironment` calls agree on every host, so
    // no row above this one would ever notice, and the cost only appears where
    // they disagree — an X11 session wired to the Wayland witness has CAP-14's
    // suppression permanently off, and a Wayland session wired to the X11 one
    // opens an X connection on a host that has no X server.
    final startup = _startupSource();
    final reads = RegExp(
      r'DisplayServer\.fromEnvironment\(',
    ).allMatches(startup);

    expect(
      reads,
      hasLength(1),
      reason:
          'AD-9 forbids a runtime switch between the two hotkey adapters, and '
          'the way a second read arrives is a second consumer answering the '
          'question for itself rather than taking the answer',
    );
  });

  test('AD-9/G-01-13: each display-server arm gets its own focus witness — the '
      'X11 one on X11, the null object on Wayland', () {
    // Pinned as text rather than behaviourally because `_focusWitnessFor` is
    // private and its two arms are one-line constructions: what can go wrong
    // is not the logic but the pairing, and swapping the two arms leaves
    // `dart analyze` clean and `daemon_startup_test.dart` green.
    //
    // The Wayland arm being the null object is a decision, not a stub. The XDG
    // GlobalShortcuts portal takes no key grab, so nothing the daemon does can
    // produce the spurious `FocusOut(NotifyGrab)` G-01-13 is about, and no
    // portal call reports the keyboard owner either — so a witness that
    // claimed to know would be inventing an answer, and inventing it in the
    // one direction that disables CAP-14.
    final witnessArms = _bodyOf(
      _startupSource(),
      'static KeyboardFocusWitness _focusWitnessFor',
    );

    expect(
      witnessArms,
      matches(
        RegExp(
          r'DisplayServer\.wayland\s*=>\s*const AbsentKeyboardFocusWitness\(',
        ),
      ),
      reason:
          'the portal grabs nothing, so there is no spurious focus-out to '
          'suppress and no way to prove one spurious either',
    );
    expect(
      witnessArms,
      matches(RegExp(r'DisplayServer\.x11\s*=>\s*X11KeyboardFocusWitness\(')),
      reason:
          'the X11 arm is the one that takes the grab that produces the '
          'defect, and the one where XGetInputFocus can answer',
    );
  });

  test('G-01-13: main.dart hands the panel adapter the witness startup chose, '
      'not one of its own', () {
    // A second witness would be a second X connection nothing disposes — the
    // adapter owns the one it is given and closes it — and, worse, a second
    // *answer*: the whole point of choosing it beside the hotkey adapter is
    // that one display-server read decides both.
    expect(
      _mainSource(),
      matches(
        RegExp(
          r'WindowManagerPanelVisibility\([^;]*'
          r'focusWitness: startup\.focusWitness',
        ),
      ),
      reason:
          'located inside the constructor call, not merely somewhere in the '
          'file: `[^;]*` cannot cross the statement that ends the call',
    );
    for (final forbidden in <String>[
      'X11KeyboardFocusWitness(',
      'AbsentKeyboardFocusWitness(',
    ]) {
      expect(
        _mainSource(),
        isNot(contains(forbidden)),
        reason:
            '`$forbidden` in main.dart is a witness chosen without the '
            'display-server read that is supposed to decide it',
      );
    }
  });
}

String _startupSource() => _stripComments(
  File('lib/src/infrastructure/system/daemon_startup.dart').readAsStringSync(),
);

/// How many steps `DaemonLifecycle.shutdown()` runs, each under its own bound.
///
/// Counted from the source because the ceiling on the shared budget is a claim
/// about the *product* of the two: a step added without re-arguing the number
/// lengthens the worst-case shutdown, and this is what makes that show up as a
/// failing assertion rather than as a comment that has quietly gone stale.
int _teardownStepCount() {
  final source = _stripComments(
    File(
      'lib/src/infrastructure/system/daemon_lifecycle.dart',
    ).readAsStringSync(),
  );
  // Scoped to `_run()`'s body, and matched on the call rather than on `await
  // _step(`. Dropping the `await` is what stops a step being missed because
  // `dart format` wrapped it onto the next line; the scope is what stops
  // `_step`'s own declaration being counted as a step.
  //
  // Scoping alone cannot see a step reached through a helper, though — a body
  // in another method is out of reach of any pattern matched in here — and the
  // count only ever comes out too *low*, which loosens the ceiling above
  // instead of failing. So the scoped count is checked against the file-wide
  // one: every `_step(` in the file must be either the declaration or a call
  // inside `_run()`. Extract three steps into a `_closeStores()` helper and
  // the two numbers part company, which is the failure this row owes its
  // reader — the alternative is a ceiling that silently goes stale, which is
  // the staleness deriving it was supposed to prevent.
  final body = _bodyOf(source, 'Future<void> _run() async {');
  final scoped = RegExp(r'_step\(').allMatches(body).length;
  final fileWide = RegExp(r'_step\(').allMatches(source).length;

  expect(
    scoped,
    fileWide - 1,
    reason:
        'every `_step(` in daemon_lifecycle.dart must be the declaration or a '
        'call inside `_run()`; a step reached through a helper or a loop body '
        'is invisible to the scoped count and would understate the worst-case '
        'teardown the budget ceiling is argued against',
  );

  return scoped;
}

/// The brace-matched body of the declaration [signature] opens.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) {
    throw StateError('no declaration matching `$signature`');
  }
  var depth = 0;
  for (var i = start + signature.length - 1; i < source.length; i++) {
    if (source[i] == '{') {
      depth += 1;
    } else if (source[i] == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('`$signature` is never closed');
}

/// The provider names declared as seams in `port_providers.dart`.
Set<String> _declaredSeams() {
  final source = _stripComments(
    File(
      'lib/src/application/composition/port_providers.dart',
    ).readAsStringSync(),
  );
  final pattern = RegExp(r'final\s+(\w+)\s*=\s*Provider<');
  return {for (final match in pattern.allMatches(source)) match.group(1)!};
}

/// The provider names `main.dart` binds with `overrideWithValue`.
Set<String> _overriddenSeams() {
  final pattern = RegExp(r'(\w+)\.overrideWithValue\(');
  return {
    for (final match in pattern.allMatches(_mainSource())) match.group(1)!,
  };
}

String _mainSource() =>
    _stripComments(File('lib/main.dart').readAsStringSync());

/// Whether [source] hands `startup.bindHotkey`'s **value** to the settings
/// surface, in either of the two correct spellings.
///
/// The composed call is one expression. The two-statement form names a local,
/// and the local's declaration is matched by its *assignment target* rather than
/// by declaration syntax: keying on `(?:final|var)\s+(?:\w+\s+)?` accepted only
/// an untyped local or one whose type is a single bare word, so
/// `final HotkeyBindOutcome? outcome = …`, `late final …` and a qualified type
/// all read as no hand-off at all. That is a false positive on the line pinning
/// AD-12's whole settings half — the shape that gets a gate deleted rather than
/// fixed.
bool _handsBindOutcomeToSettings(String source) {
  final composed = RegExp(
    r'applyStartupBindOutcome\(\s*await\s+startup\.bindHotkey',
  ).hasMatch(source);
  if (composed) {
    return true;
  }
  return RegExp(
    r'(?:late\s+)?(?:final|const|var)\s+(?:[\w<>,?.\s]+?\s+)?(\w+)\s*=\s*'
    r'await\s+startup\.bindHotkey',
  ).allMatches(source).any((match) {
    final local = match.group(1)!;
    return RegExp(
      'applyStartupBindOutcome\\(\\s*${RegExp.escape(local)}\\s*[,)]',
    ).hasMatch(source);
  });
}

String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp('//[^\n]*'), '');
