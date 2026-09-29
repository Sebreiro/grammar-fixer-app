import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_load_result.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_store.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_status.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/registrable_keys.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/echoing_error.dart';
import '../fakes/fake_config_store.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/throwing_logger.dart';

/// Settings write through to config (CAP-8, CAP-12, AD-13), report which
/// display server's regime the hotkey is under (AD-10), and model every way
/// a mutation can fail (AD-12, AD-13).
void main() {
  late FakeConfigStore configStore;
  late FakeGlobalHotkey hotkey;
  late FakeLogger logger;
  late SettingsController controller;

  setUp(() {
    configStore = FakeConfigStore(current: _config);
    hotkey = FakeGlobalHotkey();
    logger = FakeLogger();
    controller = SettingsController(
      configStore: configStore,
      registrableKeys: _registrableKeys,
      hotkey: hotkey,
      logger: logger,
    );
  });

  // The settings controller never subscribes to `activations` — the panel
  // controller owns that — so the hotkey is not disposed here: closing a
  // single-subscription stream nobody listened to never completes.
  tearDown(() async {
    await controller.dispose();
    configStore.dispose();
  });

  test('CAP-12: changing the hotkey writes the chosen combination through '
      'to config', () async {
    await controller.changeHotkey(_altSpace);

    expect(hotkey.bindCalls.single, same(_altSpace));
    expect(configStore.writes.single.hotkeyBinding, same(_altSpace));
    expect(controller.state.config.hotkeyBinding, same(_altSpace));
  });

  test('CAP-12: on X11 the settings surface is authoritative for the '
      'binding it requested', () async {
    await controller.changeHotkey(_altSpace);

    final registration = _boundRegistration(controller.state);
    expect(registration.authority, equals(BindingAuthority.application));
    expect(
      registration.effective,
      same(_altSpace),
      reason:
          'HOTKEY-07\'s other half: no backend-originated change was observed '
          'after this bind was issued, so the bind\'s own answer stands',
    );
  });

  test('CAP-12: on Wayland the surface reports the compositor\'s binding, '
      'not the requested one', () async {
    hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
        authority: BindingAuthority.compositor,
      ),
    );

    await controller.changeHotkey(_altSpace);

    final registration = _boundRegistration(controller.state);
    expect(registration.authority, equals(BindingAuthority.compositor));
    expect(registration.effective?.key, equals('F1'));
    expect(
      controller.state.config.hotkeyBinding.key,
      equals('F1'),
      reason: 'D-18 stores the compositor-reported effective combination',
    );
  });

  test('CAP-12: a backend that cannot report the effective binding leaves '
      'it absent', () async {
    hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.compositor,
      ),
    );

    await controller.changeHotkey(_altSpace);

    expect(_boundRegistration(controller.state).effective, isNull);
    hotkey.onBind = (binding) => const HotkeyRetained(
      HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.compositor,
      ),
    );
    await controller.changeHotkey(_ctrlShiftG);

    expect(controller.state.hotkeyBindOutcome, isA<HotkeyRetained>());
    expect(controller.state.failure, isNull);
    expect(controller.trayStatus?.unavailable, isFalse);
    expect(configStore.current.hotkeyBinding, _altSpace);
    expect(configStore.writes.last.hotkeyBinding, _altSpace);
    expect(
      configStore.writes,
      everyElement(
        isA<AppConfig>().having(
          (value) => value.hotkeyBinding,
          'restart seed',
          _altSpace,
        ),
      ),
    );

    hotkey.emitBindingChange(
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: 'the desktop removed the shortcut',
      ),
    );
    await pumpEventQueue();
    expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
    expect(controller.trayStatus?.unavailable, isTrue);
    expect(configStore.current.hotkeyBinding, _altSpace);
  });

  test('CAP-8: switching the active preset writes through to config', () async {
    await controller.changeActivePreset('fast-preset');

    expect(configStore.writes.single.activePresetId, equals('fast-preset'));
    expect(controller.state.config.activePresetId, equals('fast-preset'));
    expect(
      configStore.writes.single.presets,
      same(_config.presets),
      reason: 'only the active id changes; the rest of the config is carried',
    );
    expect(
      configStore.writes.single.presets.map((preset) => preset.id),
      contains('fast-preset'),
      reason: 'the store rejects an activePresetId that names no preset',
    );
  });

  test('AD-10: the surface never renders a frame with the new binding and '
      'no registration to qualify it', () async {
    hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
        authority: BindingAuthority.compositor,
      ),
    );
    final frames = <SettingsState>[];
    final subscription = controller.changes.listen(frames.add);

    await controller.changeHotkey(_altSpace);
    await pumpEventQueue();

    // D-18 keeps the reported effective binding in config. The request is
    // never rendered as though it had been granted.
    for (final frame in frames) {
      if (frame.config.hotkeyBinding.key != 'F1') {
        continue;
      }
      expect(
        frame.hotkeyBindOutcome,
        isA<HotkeyBound>(),
        reason: 'a frame carrying the effective binding must qualify it',
      );
      expect(_boundRegistration(frame).effective?.key, equals('F1'));
    }
    expect(
      frames.where((frame) => frame.config.hotkeyBinding.key == 'F1'),
      hasLength(1),
      reason: 'and exactly one frame carries the change, not two',
    );
    expect(
      frames.first.mutationInFlight,
      isTrue,
      reason:
          'the first frame is the in-flight announcement, and it carries the '
          'config as it still is — nothing is written yet',
    );
    expect(frames.first.config.hotkeyBinding, same(_ctrlShiftG));
    await subscription.cancel();
  });

  test('CAP-12: a preset changed on disk while the bind dialog is open survives '
      'the hotkey write', () async {
    // The property is that a mutation derives its value from the store's
    // `current` **at write time**, never from the state this controller was
    // holding when the mutation started — a bind can sit on a portal dialog for
    // seconds (AD-11), and anything that changed meanwhile must not be written
    // back to its old value.
    //
    // Driven by an *external* write rather than by a second in-app mutation,
    // because the second is now refused outright while one is in flight. That is
    // deliberate (it is the last-completion-wins race) and it is also why this
    // path still matters: a config file edited on disk, or a second surface, can
    // still interleave, so the stale-base bug is still reachable.
    final bound = Completer<HotkeyBindOutcome>();
    final slowHotkey = _SlowBindHotkey(bound);
    final slowController = SettingsController(
      configStore: configStore,
      registrableKeys: _registrableKeys,
      hotkey: slowHotkey,
      logger: logger,
    );
    addTearDown(slowController.dispose);

    final changing = slowController.changeHotkey(_altSpace);
    await pumpEventQueue();
    await configStore.write(_config.copyWith(activePresetId: 'fast-preset'));
    bound.complete(
      HotkeyBound(
        HotkeyRegistration(
          effective: _altSpace,
          authority: BindingAuthority.application,
        ),
      ),
    );
    await changing;

    expect(configStore.current.hotkeyBinding, same(_altSpace));
    expect(
      configStore.current.activePresetId,
      equals('fast-preset'),
      reason:
          'the hotkey write carried the preset that landed while it waited, '
          'because it was derived from the store rather than from a snapshot',
    );
  });

  test('AD-13: nothing is written until a setting actually changes', () {
    expect(configStore.writes, isEmpty);
    expect(controller.state.hotkeyBindOutcome, isNull);
    expect(controller.state.failure, isNull);
  });

  test('CAP-8: a config change made elsewhere reaches the settings '
      'surface', () async {
    final emitted = <String>[];
    final subscription = controller.changes.listen(
      (state) => emitted.add(state.config.activePresetId),
    );

    await configStore.write(_config.copyWith(activePresetId: 'edited-in-file'));
    await pumpEventQueue();

    expect(controller.state.config.activePresetId, equals('edited-in-file'));
    expect(emitted, equals(['edited-in-file']));
    await subscription.cancel();
  });

  group('a config store that refuses the write (AD-13)', () {
    test('CAP-12: a rejected write leaves the store the sole owner of the '
        'value and surfaces the failure', () async {
      configStore.writeError = StateError('config.json is read-only');

      await controller.changeHotkey(_altSpace);

      expect(
        controller.state.config.hotkeyBinding,
        same(_ctrlShiftG),
        reason: 'state never claims a config the store did not accept',
      );
      expect(configStore.current.hotkeyBinding, same(_ctrlShiftG));
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
      );
      expect(logger.lines.single.level, equals('error'));
    });

    test('CAP-8: a rejected preset switch surfaces the same failure and '
        'never rethrows', () async {
      configStore.writeError = StateError('config.json is read-only');

      await controller.changeActivePreset('fast-preset');

      expect(controller.state.config.activePresetId, equals(_preset.id));
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
      );
      expect(configStore.writes, isEmpty);
    });

    test('CAP-8: a write that succeeds after a failed one clears the '
        'failure', () async {
      configStore.writeError = StateError('config.json is read-only');
      await controller.changeActivePreset('fast-preset');
      expect(controller.state.failure, isNotNull);

      configStore.writeError = null;
      await controller.changeActivePreset('fast-preset');

      expect(controller.state.failure, isNull);
      expect(controller.state.config.activePresetId, equals('fast-preset'));
    });
  });

  group('a hotkey backend that cannot bind (AD-12)', () {
    test('AD-12: an unavailable backend lands in state as a value, and the '
        'previous binding remains the restart seed', () async {
      hotkey.onBind = (binding) => const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      );

      await controller.changeHotkey(_altSpace);

      expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
      expect(
        controller.state.config.hotkeyBinding,
        same(_ctrlShiftG),
        reason: 'D-18 does not store a request no backend took',
      );
      expect(
        controller.state.failure,
        isNull,
        reason: 'unavailability is a modelled outcome, not a mutation failure',
      );
      expect(logger.lines.single.level, equals('warning'));
    });

    test('AD-12: a backend that throws instead of reporting unavailability '
        'is caught, not propagated', () async {
      hotkey.bindError = StateError('the portal request timed out');

      await controller.changeHotkey(_altSpace);

      expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.hotkeyBindFailed),
      );
      expect(
        controller.state.config.hotkeyBinding,
        same(_ctrlShiftG),
        reason: 'the previous binding remains the restart seed',
      );
      expect(logger.lines.single.level, equals('error'));
    });
  });

  test('AD-13: a value the store refuses is reported as rejected, not as a '
      'write that failed', () async {
    configStore.rejects = (config) => config.activePresetId == 'no-such-preset';

    await controller.changeActivePreset('no-such-preset');

    expect(
      controller.state.failure?.kind,
      equals(SettingsFailureKind.configRejected),
      reason: 'the store validates before any I/O, so nothing was written',
    );
    expect(configStore.writes, isEmpty);
    expect(controller.state.config.activePresetId, equals(_preset.id));

    // The two kinds must be distinguishable: one is the user's change, the
    // other is the disk.
    configStore.rejects = null;
    configStore.writeError = StateError('config.json is read-only');
    await controller.changeActivePreset('fast-preset');

    expect(
      controller.state.failure?.kind,
      equals(SettingsFailureKind.configWriteFailed),
    );
  });

  test('CAP-12: when both the bind and the write fail, the surface reports '
      'the write — the unavailable hotkey is already visible', () async {
    hotkey.bindError = StateError('the portal request timed out');
    configStore.writeError = StateError('config.json is read-only');

    await controller.changeHotkey(_altSpace);

    expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
    expect(
      controller.state.failure?.kind,
      equals(SettingsFailureKind.configWriteFailed),
      reason: 'a lost write would otherwise leave no trace on the surface',
    );
  });

  test('AD-12: a fresh controller knows nothing until the startup outcome is '
      'handed to it', () {
    // Through `applyStartupOutcome`, because that is the only seam there is.
    // A constructor parameter for the same thing used to exist beside it,
    // reachable from nothing in `lib/` and exercised only here: two seeding
    // paths with opposite precedence — assignment against seed — where the
    // unreachable one silently turned every real hand-off into a refused no-op.
    final seeded = SettingsController(
      configStore: configStore,
      registrableKeys: _registrableKeys,
      hotkey: hotkey,
      logger: logger,
    );
    addTearDown(seeded.dispose);

    expect(
      seeded.state.hotkeyBindOutcome,
      isNull,
      reason: 'the bind resolves long after the controller is built',
    );

    seeded.applyStartupOutcome(
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      ),
    );

    expect(seeded.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
    expect(seeded.state.failure, isNull);
    expect(seeded.state.config, same(_config));
  });

  test('CAP-8: a config change made elsewhere does not retire a failure the '
      'user\'s own change earned', () async {
    configStore.writeError = StateError('config.json is read-only');
    await controller.changeActivePreset('fast-preset');
    expect(controller.state.failure, isNotNull);
    configStore.writeError = null;

    await configStore.write(_config.copyWith(activePresetId: 'edited-in-file'));
    await pumpEventQueue();

    expect(controller.state.config.activePresetId, equals('edited-in-file'));
    expect(
      controller.state.failure?.kind,
      equals(SettingsFailureKind.configWriteFailed),
      reason:
          'someone else\'s change landing says nothing about whether '
          'this user\'s did',
    );
  });

  group('one mutation at a time (AD-11, AD-13)', () {
    test('AD-11: a second mutation issued while one is in flight is refused, '
        'not queued', () async {
      // The last-completion-wins race, closed at the only layer that can close
      // it. The surface cannot: it is unmounted by its own Back affordance and by
      // a summon returning to the panel, so a flag it owned would be destroyed
      // mid-mutation. Refused rather than queued, because queueing would keep
      // both writes and still leave the ordering to whichever bind answered
      // first.
      final dialog = Completer<HotkeyBindOutcome>();
      final slow = _SlowBindHotkey(dialog);
      final controller = SettingsController(
        configStore: configStore,
        registrableKeys: _registrableKeys,
        hotkey: slow,
        logger: logger,
      );
      addTearDown(controller.dispose);

      final first = controller.changeHotkey(_altSpace);
      await pumpEventQueue();
      final refused = controller.changeActivePreset('fast-preset');
      await pumpEventQueue();

      expect(
        configStore.writes,
        isEmpty,
        reason: 'the first mutation has not written yet, and the second is out',
      );
      dialog.complete(
        HotkeyBound(
          HotkeyRegistration(
            effective: _altSpace,
            authority: BindingAuthority.application,
          ),
        ),
      );
      await first;
      await refused;

      expect(configStore.writes, hasLength(1));
      expect(configStore.writes.single.hotkeyBinding, equals(_altSpace));
      expect(
        configStore.current.activePresetId,
        equals('default-formal-casual-shorter'),
        reason: 'the refused mutation left nothing behind',
      );
      expect(
        logger.lines.where((line) => line.level == 'info').single.message,
        contains('refused because another is still in flight'),
        reason:
            'not silent: a change that "did nothing" needs a line an operator '
            'can find, and it carries no config value',
      );
    });

    test('AD-11: the in-flight state is on the surface\'s state, so a screen '
        'that remounts reads it rather than guessing', () async {
      final dialog = Completer<HotkeyBindOutcome>();
      final slow = _SlowBindHotkey(dialog);
      final controller = SettingsController(
        configStore: configStore,
        registrableKeys: _registrableKeys,
        hotkey: slow,
        logger: logger,
      );
      addTearDown(controller.dispose);
      final frames = <bool>[];
      controller.changes.listen((state) => frames.add(state.mutationInFlight));

      final mutation = controller.changeHotkey(_altSpace);
      await pumpEventQueue();

      expect(controller.state.mutationInFlight, isTrue);
      expect(frames, [true], reason: 'the transition is emitted, not inferred');

      dialog.complete(
        HotkeyBound(
          HotkeyRegistration(
            effective: _altSpace,
            authority: BindingAuthority.application,
          ),
        ),
      );
      await mutation;
      await pumpEventQueue();

      expect(controller.state.mutationInFlight, isFalse);
      expect(frames, [true, false]);
    });

    test('AD-13: a mutation whose store refuses the write still releases the '
        'slot', () async {
      configStore.writeError = StateError('config.json is read-only');

      await controller.changeActivePreset('fast-preset');

      expect(controller.state.mutationInFlight, isFalse);
      expect(controller.state.failure, isNotNull);

      // And the next mutation is admitted.
      configStore.writeError = null;
      await controller.changeActivePreset('fast-preset');

      expect(configStore.current.activePresetId, equals('fast-preset'));
    });

    test('AD-13: a store whose current value throws refuses the write rather '
        'than deriving one from stale state, and releases the slot', () async {
      // `ConfigStore.current` is the one port call a mutation makes outside an
      // await. Unguarded it escaped the mutation entirely — an unhandled zone
      // error, and a slot never released. Deriving the change from the state this
      // controller was holding is the other wrong answer: the value would be
      // assembled from a stale base and would overwrite whatever else changed.
      configStore.currentError = StateError('the store was never loaded');

      await expectLater(
        controller.changeActivePreset('fast-preset'),
        completes,
      );

      expect(configStore.writes, isEmpty);
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
      );
      expect(controller.state.mutationInFlight, isFalse);
      expect(
        controller.state.config,
        same(_config),
        reason: 'the surface keeps the last value the store did give it',
      );
      // Two lines, one per guarded read, and both wanted. The write guard says
      // the change was not derived; the render guard says what the surface is
      // showing instead. The render one is not redundant with the write one: a
      // store that only starts throwing *after* the write lands reaches the
      // render guard having reported nothing at all, and without its line the
      // surface would show the user their pre-write value in silence.
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(2));
      expect(
        errors.map((line) => line.context),
        everyElement(equals({'error_type': 'StateError'})),
        reason: 'type only — never the store\'s error text or a config value',
      );
      expect(
        errors.map((line) => line.message).toList(),
        containsAll(<Matcher>[
          contains('was not derived or written'),
          contains('while rendering'),
        ]),
      );
      configStore.currentError = null;
    });

    test('AD-13: a store that breaks only after the write lands still reports '
        'that the surface is showing a stale value', () async {
      // The case the render guard's earlier "deliberately silent" reasoning
      // missed. `_writeChange` reads `current` once, at the start, so a getter
      // that starts throwing afterwards has already passed that guard: the write
      // succeeds, the render read fails, and with no line here the user is shown
      // their old setting with no failure beside it and nothing in the log.
      configStore.onWriteComplete = () =>
          configStore.currentError = StateError('the store went away');

      await controller.changeActivePreset('fast-preset');

      expect(
        controller.state.failure,
        isNull,
        reason:
            'the write itself landed — there is nothing to report to the '
            'user, which is exactly why the operator needs the line',
      );
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('while rendering'));
      expect(errors.single.context, equals({'error_type': 'StateError'}));
      configStore.currentError = null;
      configStore.onWriteComplete = null;
    });
  });

  group('a change the backend originated (C5, C6, AD-10, AD-11)', () {
    test('C5 AD-10: a compositor rebind reaching the port lands in state and '
        'emits, with no call of this app\'s behind it', () async {
      final frames = <SettingsState>[];
      controller.changes.listen(frames.add);
      final rebound = HotkeyBound(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
          authority: BindingAuthority.compositor,
        ),
      );

      hotkey.emitBindingChange(rebound);
      await pumpEventQueue();

      expect(controller.state.hotkeyBindOutcome, equals(rebound));
      expect(frames.first.hotkeyBindOutcome, equals(rebound));
      expect(
        hotkey.bindCalls,
        isEmpty,
        reason: 'AD-11: the desktop did this, not this app',
      );
      expect(controller.state.config.hotkeyBinding.key, equals('F1'));
      expect(configStore.writes.single.hotkeyBinding.key, equals('F1'));
    });

    test('C5 AD-12: a shortcut the desktop dropped lands as the unavailable '
        'outcome', () async {
      const dropped = HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: 'your desktop no longer holds this shortcut',
      );

      hotkey.emitBindingChange(dropped);
      await pumpEventQueue();

      expect(controller.state.hotkeyBindOutcome, equals(dropped));
    });

    test('C5 AD-13: a backend-initiated change does not retire a failure the '
        'user\'s own mutation earned', () async {
      configStore.writeError = StateError('config.json is read-only');
      await controller.changeActivePreset('fast-preset');
      expect(controller.state.failure, isNotNull);

      hotkey.emitBindingChange(
        const HotkeyBound(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );
      await pumpEventQueue();

      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
        reason:
            'an external rebind says nothing about whether this user\'s '
            'mutation landed — the same reasoning that keeps an external config '
            'write from clearing the banner',
      );
    });

    test('C5 AD-15: an error on the binding-change stream is logged by type '
        'and the subscription survives it', () async {
      hotkey.emitBindingChangesError(
        const EchoingError(
          'the session bus went away',
          'the user private clipboard text',
        ),
      );
      await pumpEventQueue();

      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(
        errors.single.context,
        equals({'error_type': 'EchoingError'}),
        reason: 'type only — never the error\'s own text',
      );

      final rebound = HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      );
      hotkey.emitBindingChange(rebound);
      await pumpEventQueue();

      expect(controller.state.hotkeyBindOutcome, equals(rebound));
    });

    test('C6 AD-12: the startup bind outcome is a seed, so a newer '
        'compositor-originated one is not overwritten by it', () async {
      // The Wayland adapter subscribes to `ShortcutsChanged` inside `bind()`, so
      // a compositor-originated change can reach this controller *before*
      // `main.dart` hands the startup bind's own answer over. Overwriting would
      // replace a newer fact with an older one, and nothing emits again to
      // correct it.
      final fromCompositor = HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      );
      hotkey.emitBindingChange(fromCompositor);
      await pumpEventQueue();

      controller.applyStartupOutcome(
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'this compositor has no portal',
        ),
      );

      expect(controller.state.hotkeyBindOutcome, equals(fromCompositor));
      expect(
        logger.lines.where((line) => line.level == 'info').single.message,
        contains('already holds a newer one'),
        reason: 'a dropped hand-off is said out loud rather than swallowed',
      );
    });

    test('C6 HOTKEY-07: a compositor change landing while a rebind is in '
        'flight survives, and the rebind\'s own answer is discarded', () async {
      // The reachable half of the port's precedence rule, and the one this
      // controller used to get wrong: AD-11 makes the rebind window seconds
      // wide because a portal dialog sits inside it, and the bind's answer was
      // written over whatever arrived while it waited. The protocol-level
      // inversion at startup is a different case and is unreachable on the
      // shipped adapter, which subscribes only after its bind returns.
      final dialog = Completer<void>();
      hotkey.bindGate = dialog;
      final fromCompositor = HotkeyBound(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
          authority: BindingAuthority.compositor,
        ),
      );

      final rebind = controller.changeHotkey(_altSpace);
      await pumpEventQueue();
      hotkey.emitBindingChange(fromCompositor);
      await pumpEventQueue();
      dialog.complete();
      await rebind;

      expect(
        controller.state.hotkeyBindOutcome,
        equals(fromCompositor),
        reason:
            'the bind answer is by construction older than a change observed '
            'after that bind was issued, and nothing would emit again to '
            'correct an overwrite',
      );
      expect(
        controller.state.config.hotkeyBinding,
        equals(fromCompositor.registration.effective),
        reason:
            'D-18 persists the newer structured effective binding as the '
            'restart seed, not the rejected request',
      );
      final nextDialog = Completer<void>();
      hotkey.bindGate = nextDialog;
      final nextRebind = controller.changeHotkey(_ctrlShiftG);
      await pumpEventQueue();
      hotkey.emitBindingChange(
        const HotkeyBound(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );
      await pumpEventQueue();
      nextDialog.complete();
      await nextRebind;
      expect(
        controller.state.config.hotkeyBinding,
        equals(fromCompositor.registration.effective),
        reason: 'an unstructured newer event preserves the previous saved seed',
      );
      expect(
        logger.lines.where((line) => line.level == 'info').last.message,
        contains('already holds a newer backend-originated one'),
        reason:
            'a silent discard is the failure mode this requirement is about',
      );
    });

    test('C6 AD-12: the startup bind outcome reaches the surface after the '
        'controller was built, and is a no-op after shutdown', () async {
      // The graph is built long before `bindHotkey` runs — a real bind can sit
      // on a portal dialog for seconds (AD-11) — so a constructor argument
      // cannot carry it and the screen would otherwise say "nothing has been
      // requested yet" for the life of a daemon whose hotkey never bound.
      final frames = <SettingsState>[];
      controller.changes.listen(frames.add);
      const startup = HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      );

      controller.applyStartupOutcome(startup);
      await pumpEventQueue();

      expect(controller.state.hotkeyBindOutcome, equals(startup));
      expect(frames.single.hotkeyBindOutcome, equals(startup));

      await controller.dispose();
      controller.applyStartupOutcome(
        const HotkeyBound(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );

      expect(
        controller.state.hotkeyBindOutcome,
        equals(startup),
        reason: 'after dispose a transition is a no-op, like every other one',
      );
    });

    test('AD-4: shutdown completes when cancelling the binding-change '
        'subscription rejects, and the config cancel still runs', () async {
      hotkey.bindingChangesCancelError = StateError(
        'the signal stream refused to close',
      );

      await expectLater(controller.dispose(), completes);

      expect([
        for (final line in logger.lines) line.message,
      ], contains('cancelling the hotkey binding-change subscription failed'));
      hotkey.bindingChangesCancelError = null;
    });

    test('AD-4: a config cancel that rejects does not strand the '
        'binding-change subscription', () async {
      // Guarded independently, or one broken adapter would leave the other
      // subscription live on a torn-down controller.
      configStore.cancelError = StateError('the config watcher refused');
      hotkey.bindingChangesCancelError = StateError('and so did the signal');

      await expectLater(controller.dispose(), completes);

      expect(
        [for (final line in logger.lines) line.message],
        containsAllInOrder(<String>[
          'cancelling the config subscription failed',
          'cancelling the hotkey binding-change subscription failed',
        ]),
      );
      configStore.cancelError = null;
      hotkey.bindingChangesCancelError = null;
    });
  });

  test('AD-4: shutdown completes when cancelling the config subscription '
      'rejects', () async {
    configStore.cancelError = StateError(
      'the config watcher refused to '
      'close',
    );

    await expectLater(controller.dispose(), completes);

    expect(logger.lines.where((line) => line.level == 'error'), hasLength(1));
    configStore.cancelError = null;
  });

  test('CAP-8: a config stream error leaves the surface live for the next '
      'external write', () async {
    configStore.emitChangesError(StateError('the config watcher failed'));
    await pumpEventQueue();

    await configStore.write(_config.copyWith(activePresetId: 'edited-in-file'));
    await pumpEventQueue();

    expect(controller.state.config.activePresetId, equals('edited-in-file'));
    expect(logger.lines.single.level, equals('error'));
  });

  group('echo suppression is by value, not by instance', () {
    test('CAP-8: a store that echoes an equal but not identical config is '
        'still recognised as this controller own write', () async {
      final store = _RebuildingConfigStore(_config);
      final rebuilding = SettingsController(
        configStore: store,
        registrableKeys: _registrableKeys,
        hotkey: hotkey,
        logger: logger,
      );
      final frames = <SettingsState>[];
      final subscription = rebuilding.changes.listen(frames.add);
      addTearDown(() async {
        await subscription.cancel();
        await rebuilding.dispose();
        store.dispose();
      });

      await rebuilding.changeActivePreset('fast-preset');
      await pumpEventQueue();

      // The in-flight announcement is not a rendered config change, so it is
      // filtered out rather than counted: what this row is about is the *echo*,
      // and one mutation must produce exactly one settled frame.
      final settled = frames.where((frame) => !frame.mutationInFlight);
      expect(
        settled,
        hasLength(1),
        reason:
            'the mutation sets state itself; the store echoing the same '
            'value back must not render a second frame, and identity '
            'equality would have missed the rebuilt instance entirely',
      );
      expect(settled.single.config.activePresetId, equals('fast-preset'));
    });

    test('CAP-8: two successive mutations that write equal configs are both '
        'recognised as own writes', () async {
      final store = _RebuildingConfigStore(_config);
      final overlapping = SettingsController(
        configStore: store,
        registrableKeys: _registrableKeys,
        hotkey: hotkey,
        logger: logger,
      );
      final frames = <SettingsState>[];
      final subscription = overlapping.changes.listen(frames.add);
      addTearDown(() async {
        await subscription.cancel();
        await overlapping.dispose();
        store.dispose();
      });

      // Sequential, not overlapping, and the change is worth stating: a second
      // mutation issued while one is in flight is now **refused** (that is the
      // last-completion-wins race), so two writes can no longer be outstanding
      // at once through this API. Setting the same preset twice is still the
      // cheapest way to produce two equal configs, and one echo per write still
      // has to be claimed by the controller rather than handed to
      // `_onConfigChanged` as somebody else's file edit.
      //
      // What that costs is recorded rather than hidden: the *multiplicity* half of
      // the echo bookkeeping — two equal configs pending simultaneously, which is
      // what a counted map buys over a `Set` — is no longer reachable from
      // outside this class, so it is defensive code this row does not pin. See
      // the ledger entry filed with this story.
      await overlapping.changeActivePreset('fast-preset');
      await overlapping.changeActivePreset('fast-preset');
      await pumpEventQueue();

      expect(store.writes, equals(2));
      final settled = frames.where((frame) => !frame.mutationInFlight);
      expect(
        settled,
        hasLength(2),
        reason:
            'one settled frame per mutation. A third would mean an echo was '
            'misread as somebody else editing the file.',
      );
      expect(
        settled.map((frame) => frame.config.activePresetId),
        everyElement(equals('fast-preset')),
      );
    });

    test('CAP-8: a config this controller never wrote updates the surface, '
        'keeping the displayed failure and bind outcome', () async {
      hotkey.onBind = (binding) => const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      );
      configStore.writeError = StateError('the config file is read-only');
      await controller.changeHotkey(_altSpace);
      configStore.writeError = null;
      final failure = controller.state.failure;
      expect(failure?.kind, equals(SettingsFailureKind.configWriteFailed));

      await configStore.write(
        _config.copyWith(activePresetId: 'edited-in-file'),
      );
      await pumpEventQueue();

      expect(controller.state.config.activePresetId, equals('edited-in-file'));
      expect(
        controller.state.failure,
        equals(failure),
        reason:
            'someone else editing the file says nothing about whether '
            'this user change landed',
      );
      expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());
    });
  });

  group('what a transition keeps', () {
    test('AD-12: an unavailable hotkey stays on the surface across a preset '
        'switch and an external config edit', () async {
      hotkey.onBind = (binding) => const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      );
      await controller.changeHotkey(_altSpace);
      expect(controller.state.hotkeyBindOutcome, isA<HotkeyUnavailable>());

      await controller.changeActivePreset('fast-preset');

      expect(
        controller.state.hotkeyBindOutcome,
        isA<HotkeyUnavailable>(),
        reason: 'a preset switch says nothing about whether the hotkey bound',
      );

      await configStore.write(
        _config.copyWith(activePresetId: 'edited-in-file'),
      );
      await pumpEventQueue();

      expect(
        controller.state.hotkeyBindOutcome,
        isA<HotkeyUnavailable>(),
        reason: 'nor does someone else editing the file',
      );
    });

    test('AD-12: a preset switch that lands does not retire a hotkey failure '
        'it did not fix', () async {
      hotkey.bindError = StateError('the portal request timed out');
      await controller.changeHotkey(_altSpace);
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.hotkeyBindFailed),
      );
      hotkey.bindError = null;

      await controller.changeActivePreset('fast-preset');

      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.hotkeyBindFailed),
        reason: 'the shortcut is still dead, so the surface must still say so',
      );
      expect(controller.state.config.activePresetId, equals('fast-preset'));
    });

    test('CAP-8: a hotkey change that lands does not retire a preset failure '
        'it did not fix (AD-13)', () async {
      configStore.writeError = StateError('config.json is read-only');
      await controller.changeActivePreset('fast-preset');
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
      );
      configStore.writeError = null;

      await controller.changeHotkey(_altSpace);

      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
        reason:
            'the preset switch was never written, so the surface must still '
            'say so. The kind alone cannot carry this: a failed hotkey write '
            'produces the very same one',
      );
      expect(
        controller.state.config.activePresetId,
        equals('default-formal-casual-shorter'),
      );
    });

    test('CAP-12: a preset switch that lands does not retire a hotkey write '
        'failure it did not fix (AD-13)', () async {
      configStore.writeError = StateError('config.json is read-only');
      await controller.changeHotkey(_altSpace);
      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
      );
      configStore.writeError = null;

      await controller.changeActivePreset('fast-preset');

      expect(
        controller.state.failure?.kind,
        equals(SettingsFailureKind.configWriteFailed),
        reason: 'the hotkey preference is still unsaved',
      );
      expect(controller.state.config.activePresetId, equals('fast-preset'));
    });

    test(
      'CAP-8: switching the preset again clears the failure it earned',
      () async {
        configStore.writeError = StateError('config.json is read-only');
        await controller.changeActivePreset('fast-preset');
        expect(controller.state.failure, isNotNull);
        configStore.writeError = null;

        await controller.changeActivePreset('fast-preset');

        expect(controller.state.failure, isNull);
        expect(controller.state.config.activePresetId, equals('fast-preset'));
      },
    );

    test(
      'CAP-12: setting the hotkey again clears the failure it earned',
      () async {
        hotkey.bindError = StateError('the portal request timed out');
        await controller.changeHotkey(_altSpace);
        expect(controller.state.failure, isNotNull);
        hotkey.bindError = null;

        await controller.changeHotkey(_ctrlShiftG);

        expect(controller.state.failure, isNull);
        expect(controller.state.hotkeyBindOutcome, isA<HotkeyBound>());
      },
    );
  });

  group('what a failure tells the user', () {
    test('every rendered failure is a sentence the user can act on, not a '
        'stringified exception', () async {
      final rendered = <SettingsFailure>[];

      hotkey.bindError = const EchoingError(
        'the portal request timed out',
        '/home/someone/.config/hgc/config.json',
      );
      await controller.changeHotkey(_altSpace);
      rendered.add(controller.state.failure!);
      hotkey.bindError = null;

      configStore.writeError = const EchoingError(
        'permission denied',
        '/home/someone/.config/hgc/config.json',
      );
      await controller.changeActivePreset('fast-preset');
      rendered.add(controller.state.failure!);
      configStore.writeError = null;

      configStore.rejects = (config) =>
          config.activePresetId == 'no-such-preset';
      await controller.changeActivePreset('no-such-preset');
      rendered.add(controller.state.failure!);

      expect(
        rendered.map((failure) => failure.kind).toSet(),
        equals(SettingsFailureKind.values.toSet()),
        reason: 'every kind the surface can render is covered',
      );
      for (final failure in rendered) {
        expect(failure.message, isNotEmpty);
        expect(
          failure.message,
          isNot(contains('SqliteException')),
          reason:
              'a vendor exception toString() carries the payload and the '
              'absolute paths that caused it; the field is user-facing',
        );
        expect(failure.message, isNot(contains('/home/someone')));
      }
    });

    test('AD-12: an unreachable backend renders a sentence, and the raw '
        'error reaches neither surface nor log', () async {
      const secret = '/home/someone/.config/hgc/config.json';
      hotkey.bindError = const EchoingError('the portal timed out', secret);

      await controller.changeHotkey(_altSpace);

      final outcome = controller.state.hotkeyBindOutcome! as HotkeyUnavailable;
      expect(outcome.message, isNot(contains(secret)));
      expect(
        outcome.message,
        isNotEmpty,
        reason:
            'AD-12 renders this on the tray and the settings screen; a blank '
            'explanation is not a sentence a user can act on',
      );
      expect(controller.state.failure!.message, isNot(contains(secret)));
      expect(
        '${logger.lines.single.message} ${logger.lines.single.context}',
        isNot(contains(secret)),
      );
    });

    test('AD-12: the unavailability warning names what happened and carries '
        'no adapter-authored text', () async {
      hotkey.onBind = (binding) => const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'no portal at /run/user/1000/bus for org.freedesktop.portal',
      );

      await controller.changeHotkey(_altSpace);

      final line = logger.lines.single;
      expect(line.level, equals('warning'));
      expect(line.message, contains('unavailable'));
      expect(line.context, equals({'outcome': 'HotkeyUnavailable'}));
      expect(
        '${line.message} ${line.context}',
        isNot(contains('/run/user/1000/bus')),
        reason:
            'the outcome message is adapter-authored free text, so an adapter '
            'that builds it from a caught error — the shape this controller '
            'itself shipped before review — would leak through it',
      );
    });

    test('nothing sensitive reaches the log on any failure path', () async {
      const secret = 'a path and a payload nobody may log';
      final lines =
          <({String level, String message, Map<String, Object?>? context})>[];

      configStore.writeError = const EchoingError('permission denied', secret);
      await controller.changeActivePreset('fast-preset');
      configStore.writeError = null;

      configStore.rejects = (config) =>
          config.activePresetId == 'no-such-preset';
      configStore.rejectError = EchoingArgumentError(secret);
      await controller.changeActivePreset('no-such-preset');
      configStore.rejects = null;
      configStore.rejectError = null;

      hotkey.bindError = const EchoingError('the portal timed out', secret);
      await controller.changeHotkey(_altSpace);

      configStore.emitChangesError(
        const EchoingError('the watcher failed', secret),
      );
      await pumpEventQueue();

      // The teardown guard reduces a caught error too, and no path above
      // reaches it.
      configStore.cancelError = const EchoingError(
        'the watcher refused to close',
        secret,
      );
      await controller.dispose();
      configStore.cancelError = null;

      lines.addAll(logger.lines);
      expect(lines, hasLength(5), reason: 'every failure path logged once');
      for (final line in lines) {
        expect('${line.message} ${line.context}', isNot(contains(secret)));
      }
    });

    test(
      'AD-13: a rejected write logs what failed without the value',
      () async {
        configStore.writeError = StateError('config.json is read-only');

        await controller.changeActivePreset('fast-preset');

        final line = logger.lines.single;
        expect(line.level, equals('error'));
        expect(line.context, equals({'error_type': 'StateError'}));
      },
    );
  });

  test('AD-15: a logger whose own sink is gone does not turn a guard into an '
      'unhandled error (AD-13)', () async {
    final unhandled = <Object>[];
    final throwingLogger = ThrowingLogger();

    await runZonedGuarded(() async {
      final ownStore = FakeConfigStore(current: _config)
        ..writeError = StateError('config.json is read-only');
      final resilient = SettingsController(
        configStore: ownStore,
        registrableKeys: _registrableKeys,
        hotkey: FakeGlobalHotkey()
          ..bindError = StateError('the portal timed out'),
        logger: throwingLogger,
      );

      await resilient.changeHotkey(_altSpace);
      ownStore.emitChangesError(StateError('the config watcher failed'));
      await pumpEventQueue();
      ownStore.cancelError = StateError('the watcher refused to close');

      await expectLater(resilient.dispose(), completes);
      ownStore.cancelError = null;
      ownStore.dispose();
    }, (error, _) => unhandled.add(error));
    await pumpEventQueue();

    expect(
      throwingLogger.attempts,
      hasLength(4),
      reason: 'bind, write, stream and cancel each still tried to report',
    );
    expect(unhandled, isEmpty);
  });

  test('AD-15: a broken logger does not break the unavailable-bind or the '
      'refused-value path either (AD-12, AD-13)', () async {
    // The test above drives the two guards its harness happens to fail. These
    // are the other two log sites in this controller, and each recovers by
    // logging too — a swallow that covers only the reached ones is a swallow
    // that is half there.
    final unhandled = <Object>[];
    final throwingLogger = ThrowingLogger();

    await runZonedGuarded(() async {
      final ownStore = FakeConfigStore(current: _config)
        ..rejects = (config) => config.activePresetId == 'no-such-preset';
      final resilient = SettingsController(
        configStore: ownStore,
        registrableKeys: _registrableKeys,
        hotkey: FakeGlobalHotkey()
          ..onBind = (binding) => const HotkeyUnavailable(
            cause: HotkeyUnavailableCause.noBackend,
            message: 'this compositor provides no global shortcuts portal',
          ),
        logger: throwingLogger,
      );

      await expectLater(resilient.changeHotkey(_altSpace), completes);
      await expectLater(
        resilient.changeActivePreset('no-such-preset'),
        completes,
      );

      await resilient.dispose();
      ownStore.dispose();
    }, (error, _) => unhandled.add(error));
    await pumpEventQueue();

    expect(
      throwingLogger.attempts,
      equals(['warning', 'error']),
      reason: 'the unavailability warning and the refusal error each tried',
    );
    expect(unhandled, isEmpty);
  });

  test('AD-11: a bind that resolves after shutdown does not mutate the surface '
      'it can no longer report to', () async {
    // A mutation begun before shutdown can still resolve after it: `bind()`
    // can sit on a portal dialog for seconds. The entry guard cannot catch
    // this one — it was already past.
    final bound = Completer<HotkeyBindOutcome>();
    final slowController = SettingsController(
      configStore: configStore,
      registrableKeys: _registrableKeys,
      hotkey: _SlowBindHotkey(bound),
      logger: logger,
    );

    final changing = slowController.changeHotkey(_altSpace);
    await slowController.dispose();
    bound.complete(
      HotkeyBound(
        HotkeyRegistration(
          effective: _altSpace,
          authority: BindingAuthority.application,
        ),
      ),
    );
    await changing;

    expect(
      slowController.state.hotkeyBindOutcome,
      isNull,
      reason:
          'a torn-down controller stops reporting rather than mutating '
          'state nothing is left to read',
    );
  });

  test(
    'AD-13: a disposed controller makes no further writes or binds',
    () async {
      await controller.dispose();

      await controller.changeActivePreset('fast-preset');
      await controller.changeHotkey(_altSpace);

      expect(
        configStore.writes,
        isEmpty,
        reason:
            'a config file written during shutdown is a change no surface '
            'is left to show',
      );
      expect(hotkey.bindCalls, isEmpty);
      expect(
        controller.state.config.activePresetId,
        equals('default-formal-casual-shorter'),
      );
    },
  );
}

/// The registration a successful bind put in state (AD-10).
HotkeyRegistration _boundRegistration(SettingsState state) {
  final outcome = state.hotkeyBindOutcome;
  expect(outcome, isA<HotkeyBound>());
  return (outcome! as HotkeyBound).registration;
}

const Preset _preset = Preset(
  id: 'default-formal-casual-shorter',
  providerId: 'claude-agent-sdk',
  model: 'claude-sonnet-5',
  systemPrompt: 'correct the text',
);

/// A second described preset, so switching to it produces a config the real
/// store would accept: `activePresetId` must name a preset in `presets`.
const Preset _fastPreset = Preset(
  id: 'fast-preset',
  providerId: 'claude-agent-sdk',
  model: 'claude-haiku-4-5-20251001',
  systemPrompt: 'correct the text',
);

final HotkeyBinding _ctrlShiftG = HotkeyBinding(
  modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
  key: 'G',
);

final HotkeyBinding _altSpace = HotkeyBinding(
  modifiers: {HotkeyModifier.alt},
  key: 'Space',
);

final AppConfig _config = AppConfig(
  providers: {'claude-agent-sdk': ProviderConfig(settings: {})},
  presets: [_preset, _fastPreset],
  activePresetId: 'default-formal-casual-shorter',
  hotkeyBinding: _ctrlShiftG,
);

/// A hotkey backend whose `bind()` stays open, standing in for the Wayland
/// portal dialog the user can leave up while changing other settings.
final class _SlowBindHotkey implements GlobalHotkey {
  _SlowBindHotkey(this._bound);

  final Completer<HotkeyBindOutcome> _bound;

  @override
  Stream<void> get activations => const Stream<void>.empty();

  @override
  Stream<HotkeyBindOutcome> get bindingChanges =>
      const Stream<HotkeyBindOutcome>.empty();

  /// Null throughout: this fake exists to hold a bind open, and a bind that has
  /// not answered has produced no status to report.
  @override
  HotkeyStatus? get current => null;

  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) => _bound.future;

  @override
  Future<void> dispose() async {}
}

/// A `ConfigStore` that echoes a *rebuilt* value on `changes` rather than the
/// instance it was handed.
///
/// This is what any adapter that re-reads or re-decodes its file after writing
/// would do, and the port permits it — `changes` promises the config that was
/// written, never the same object. Echo suppression keyed on instance identity
/// silently stops working against this shape, rendering a duplicate settings
/// frame for every mutation, which is why value equality on `AppConfig` is
/// load-bearing rather than cosmetic.
final class _RebuildingConfigStore implements ConfigStore {
  _RebuildingConfigStore(this._current);

  AppConfig _current;

  /// How many writes landed, so a test can tell "two mutations, two frames"
  /// from "two mutations, one collapsed".
  int writes = 0;

  final StreamController<AppConfig> _changes =
      StreamController<AppConfig>.broadcast();

  @override
  AppConfig get current => _current;

  @override
  Stream<AppConfig> get changes => _changes.stream;

  @override
  Future<ConfigLoadResult> load() async => ConfigLoadResult(config: _current);

  @override
  Future<void> write(AppConfig config) async {
    writes += 1;
    _current = _rebuilt(config);
    _changes.add(_rebuilt(config));
  }

  /// Test teardown only — not part of the port.
  void dispose() {
    unawaited(_changes.close());
  }

  /// An equal value that is deliberately a different instance all the way
  /// down, collections included — what decoding what was just written yields.
  static AppConfig _rebuilt(AppConfig config) => AppConfig(
    providers: {
      for (final MapEntry(:key, :value) in config.providers.entries)
        key: ProviderConfig(settings: {...value.settings}),
    },
    presets: [
      for (final preset in config.presets)
        Preset(
          id: preset.id,
          providerId: preset.providerId,
          model: preset.model,
          systemPrompt: preset.systemPrompt,
        ),
    ],
    activePresetId: config.activePresetId,
    hotkeyBinding: HotkeyBinding(
      modifiers: {...config.hotkeyBinding.modifiers},
      key: config.hotkeyBinding.key,
    ),
  );
}

/// The vocabulary the composition root injects, so these rows validate against
/// the one this build actually ships rather than a hand-built stand-in. A test
/// may name the catalogue; AD-1's scans cover `lib/src/` only, and the whole
/// point of the seam is that nothing under `lib/src/application/` can.
final RegistrableKeys _registrableKeys = HotkeyKeyCatalogue.registrableKeys();
