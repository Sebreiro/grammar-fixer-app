import 'dart:async';

import '../domain/config/app_config.dart';
import '../domain/config/config_store.dart';
import '../domain/config/config_write_conflict.dart';
import '../domain/config/provider_config.dart';
import '../domain/correction/preset.dart';
import '../domain/hotkey/global_hotkey.dart';
import '../domain/hotkey/hotkey_bind_outcome.dart';
import '../domain/hotkey/hotkey_binding.dart';
import '../domain/hotkey/registrable_keys.dart';
import '../domain/logger.dart';
import '../domain/tray/hotkey_tray_status.dart';
import 'hotkey_capture.dart';
import 'settings_state.dart';

/// The in-app settings surface's state and its write-through to config.
///
/// Every mutation goes through the [ConfigStore] (AD-13), which is what
/// keeps the two user-facing surfaces — the settings screen and the config
/// file — in sync. The store is the single validation point, so nothing is
/// re-checked here; an invalid mutation surfaces as the store's error.
///
/// No mutation throws. A settings write that cannot land is a user-facing
/// failure the surface renders ([SettingsState.failure]), never an exception
/// that takes a resident daemon down (AD-13). After `dispose()` a mutation is
/// a no-op rather than a late write: the ports it would reach are being torn
/// down, and a config file written during shutdown is a change no surface is
/// left to show.
///
/// **One mutation at a time, and this is where that is decided.** A second
/// mutation issued while one is still in flight is refused, not queued, and the
/// slot lives here rather than on the surface because the surface does not
/// outlive a view swap: the settings screen is unmounted by its own Back
/// affordance and by a summon returning to the panel (CAP-1), so a flag it owned
/// would be destroyed mid-mutation and the second request would go straight
/// through. See [_beginMutation] for why refusing is the right answer.
///
/// [ConfigStore.load] must have completed before construction, since the
/// initial state reads [ConfigStore.current]. That one read is deliberately
/// unguarded: a store that cannot answer it has not been loaded, which is a
/// composition mistake, and the composition root's abort path is what handles a
/// constructor that throws. Every *later* read is guarded — see [_writeChange]
/// and [_currentConfig].
final class SettingsController {
  SettingsController({
    required ConfigStore configStore,
    required RegistrableKeys registrableKeys,
    required this._hotkey,
    required this._logger,
  }) : captureValidator = HotkeyCaptureValidator(registrableKeys),
       _configStore = configStore,
       // No `initialBindOutcome` seam, and its absence is the point. The bind
       // resolves long after this controller is built (see [applyStartupOutcome],
       // whose doc says a constructor argument therefore cannot carry it), so a
       // parameter for it was reachable from nothing in `lib/` and would have
       // been a *second* seeding path with the opposite precedence rule —
       // assignment rather than seed — quietly turning every real hand-off into a
       // refused no-op.
       _state = SettingsState(
         config: configStore.current,
         mutationInFlight: false,
       ) {
    _configChanges = configStore.changes.listen(
      _onConfigChanged,
      // AD-15 backstop: the port promises a plain value stream. An adapter
      // whose file watcher errors must not kill this subscription's zone —
      // and the surface must stay live for the next external write.
      onError: (Object error) => _log(
        () => _logger.error(
          'the config store change stream errored',
          context: _errorContext(error),
        ),
      ),
    );
    _bindingChanges = _hotkey.bindingChanges.listen(
      _onBindingChanged,
      // The same AD-15 backstop, for the same reason: the port promises a plain
      // value stream, and an adapter that errors this one must not take the
      // surface's only link to a compositor-side rebind down with it.
      onError: (Object error) => _log(
        () => _logger.error(
          'the hotkey binding-change stream errored',
          context: _errorContext(error),
        ),
      ),
    );
  }

  /// What the settings surface validates a captured combination against
  /// (D-15, HOTKEY-04, DW-71).
  ///
  /// Public because this is the "supplied by `SettingsController`" DW-71
  /// ratified: the surface asks the controller instead of reaching across AD-1's
  /// rings for the infrastructure catalogue. Held as a field rather than put on
  /// [SettingsState], because it never changes — a value on the state would
  /// have to be carried, unchanged, through all five of that class's
  /// transitions, and 01-06 already paid that cost once for a value that does
  /// change.
  final HotkeyCaptureValidator captureValidator;

  final ConfigStore _configStore;
  final GlobalHotkey _hotkey;
  final Logger _logger;
  Future<String> Function(ProviderConfig)? _apiKeySourceLabel;
  void Function(AppConfig)? _onConfigApplied;

  late final StreamSubscription<AppConfig> _configChanges;

  /// AD-10's other direction: what the *backend* changed, rather than what this
  /// controller asked for.
  late final StreamSubscription<HotkeyBindOutcome> _bindingChanges;

  /// Broadcast: the settings screen and the tray may both watch settings.
  final StreamController<SettingsState> _changes =
      StreamController<SettingsState>.broadcast();

  /// Configs this controller wrote, awaiting their echo on
  /// [ConfigStore.changes].
  ///
  /// Compared by value, not identity: the port promises only that `changes`
  /// emits the config that was written, never that it is the same instance, so
  /// an adapter that rebuilt the value — one that re-read the file after
  /// writing it, say — would silently stop suppressing this controller's own
  /// echo and render a duplicate settings frame.
  ///
  /// [_beginMutation] admits one mutation at a time, so only one own write can
  /// be outstanding. An external edit has no matching set entry and still
  /// reaches [_applyExternalConfig].
  final Set<AppConfig> _ownWrites = <AppConfig>{};

  /// Which mutation earned the displayed [SettingsState.failure] — see
  /// [_resolveFailure], its only writer.
  _Mutation? _failedMutation;

  /// Whether a mutation is still resolving; see [SettingsState.mutationInFlight]
  /// for why the answer lives here rather than on a widget.
  ///
  /// A field beside the state as well as in it, because [_beginMutation] has to
  /// answer *synchronously* — two taps inside one frame both reach the callbacks,
  /// and the state a widget last rendered is a frame behind.
  bool _mutating = false;
  Completer<void>? _mutationFinished;
  Future<void> _externalChanges = Future<void>.value();

  /// How many backend-originated changes this controller has **observed** —
  /// the generation a rebind stamps when it issues its `bind()`, so it can tell
  /// whether the answer it came back holding is still the newest fact about the
  /// binding (HOTKEY-07).
  ///
  /// Beside the state rather than on it, for the reason [_mutating]'s doc
  /// gives and one of its own: this is bookkeeping about *when* a fact arrived,
  /// not a fact a consumer renders, and the comparison that reads it has to be
  /// answerable in the same synchronous turn the outcome is applied in.
  ///
  /// A counter and not a latch. Two changes inside one mutation must not read
  /// as none, which is exactly what clearing a boolean at the end of a mutation
  /// would produce; and a monotonic number is what the port's rule is written
  /// in — see `GlobalHotkey.bindingChanges`, which states the stamp-and-compare
  /// mechanism so a second consumer implements the same order.
  int _backendChangeGeneration = 0;

  bool _disposed = false;

  SettingsState _state;

  SettingsState get state => _state;

  Stream<SettingsState> get changes => _changes.stream;

  /// Exposes only the winning source's display label to Settings. The
  /// composition root supplies the credential lookup without handing key text
  /// to this controller or the UI.
  Future<String> keySourceLabel() async {
    final source = _apiKeySourceLabel;
    final provider =
        _state.config.providers[ProviderConfig.compatibleProviderId];
    if (source == null || provider == null) return 'None configured';
    try {
      return await source(provider);
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the API key source could not be read',
          context: _errorContext(error),
        ),
      );
      return 'None configured';
    }
  }

  /// Binds the source-only credential lookup after the graph is constructed.
  void attachApiKeySourceLabel(Future<String> Function(ProviderConfig) source) {
    _apiKeySourceLabel = source;
  }

  /// The tray's view of the same result and notice this controller renders.
  HotkeyTrayStatus? get trayStatus => switch (_state.hotkeyBindOutcome) {
    null => null,
    final outcome => HotkeyTrayStatus(
      outcome: outcome,
      rebindRefused: _state.failure?.previousShortcutWorks ?? false,
    ),
  };

  /// Connects committed in-app writes and external edits to daemon effects.
  /// The composition root installs this once after constructing the graph.
  void attachConfigListener(void Function(AppConfig) listener) {
    _onConfigApplied = listener;
  }

  /// Requests [binding] and persists the effective combination when the
  /// backend can report one. A bound result without a structured combination
  /// uses the submitted binding as a restart seed; an unavailable result keeps
  /// the prior configured binding. The outcome in state still says whether a
  /// shortcut is active.
  Future<void> changeHotkey(HotkeyBinding binding) async {
    if (!_beginMutation()) {
      return;
    }
    try {
      // Stamped at the instant the bind is *issued*, not where its answer is
      // applied: everything this has to survive happens inside the awaits
      // below, and AD-11 makes that window seconds wide because a portal dialog
      // sits inside it.
      final generationAtIssue = _backendChangeGeneration;
      final (outcome, bindFailure) = await _bind(binding);
      final previousBinding = _currentConfig().hotkeyBinding;
      final superseded = _backendChangeGeneration != generationAtIssue;
      final currentOutcome = superseded
          ? (_state.hotkeyBindOutcome ?? _hotkey.current?.outcome ?? outcome)
          : outcome;
      final effective = switch (currentOutcome) {
        HotkeyBound(:final registration) =>
          registration.effective ?? (superseded ? previousBinding : binding),
        HotkeyRetained() => previousBinding,
        HotkeyUnavailable() => previousBinding,
      };
      final writeFailure = await _writeChange(
        (config) => config.copyWith(hotkeyBinding: effective),
      );
      final refusedRebind = switch (currentOutcome) {
        HotkeyBound(:final registration)
            when !superseded &&
                registration.authority == BindingAuthority.application &&
                registration.effective == previousBinding &&
                binding != previousBinding =>
          true,
        _ => false,
      };
      // The tie is broken toward the backend, here rather than left to an
      // operator's choice: any move at all counts, so a change that landed in
      // the same turn as this answer supersedes it. That is what the port's
      // rule says — "observed at any time *after* a `bind()` was issued" — and
      // a same-turn arrival is after the issue. Only a change observed strictly
      // before the stamp above leaves this answer standing, and that one is not
      // a move.
      if (_backendChangeGeneration != generationAtIssue) {
        // Said out loud, for the reason [applyStartupOutcome]'s decline log
        // gives: a silent discard is the failure mode this whole requirement is
        // about, one level up. No key, no combination — only that it happened.
        _log(
          () => _logger.info(
            'the rebind outcome was not applied because the surface '
            'already holds a newer backend-originated one',
          ),
        );
      }
      _setState(
        SettingsState(
          config: _currentConfig(),
          // A stale answer never overwrites a newer fact. When a
          // backend-originated change landed after this bind was issued, the
          // state keeps it — and keeps the description that arrived *with* it,
          // rather than re-reading the port, which the bind may since have
          // written its own answer into.
          hotkeyBindOutcome: superseded ? _state.hotkeyBindOutcome : outcome,
          hotkeyBackendDescription: superseded
              ? _state.hotkeyBackendDescription
              : _backendDescription(),
          // A write failure wins over this mutation's own bind failure: an
          // unavailable hotkey is already visible in [outcome], while a lost
          // write would otherwise leave no trace on the surface at all.
          failure: _resolveFailure(
            writeFailure ??
                bindFailure ??
                (refusedRebind
                    ? const SettingsFailure(
                        kind: SettingsFailureKind.hotkeyBindFailed,
                        previousShortcutWorks: true,
                        message:
                            'That combination was refused. The previous '
                            'shortcut still works; choose another and apply it.',
                      )
                    : null),
            _Mutation.hotkey,
          ),
          // Released here, in the same frame as the result, rather than left to
          // [_endMutation] — one emission per mutation instead of two, and the
          // `finally` then finds the slot already clear. Stated rather than
          // defaulted: an unlock is exactly the transition that must not be
          // something a call site achieved by saying nothing.
          mutationInFlight: false,
        ),
      );
    } finally {
      _endMutation();
    }
  }

  /// Switches which preset — and so which provider — serves the next
  /// correction (CAP-8).
  Future<void> changeActivePreset(String presetId) async {
    if (!_beginMutation()) {
      return;
    }
    try {
      final failure = await _writeChange(
        (config) => config.copyWith(activePresetId: presetId),
      );
      _setState(
        SettingsState(
          config: _currentConfig(),
          hotkeyBindOutcome: _state.hotkeyBindOutcome,
          hotkeyBackendDescription: _state.hotkeyBackendDescription,
          failure: _resolveFailure(failure, _Mutation.preset),
          // Released with the result, as [changeHotkey] does and for the same
          // reason it says so out loud.
          mutationInFlight: false,
        ),
      );
    } finally {
      _endMutation();
    }
  }

  /// Saves the selected compatible endpoint and its preset's model together.
  /// The existing prompt and provider id stay on the same preset value.
  Future<void> changeProviderSettings({
    required String baseUrl,
    required String model,
  }) async {
    if (!_beginMutation()) return;
    try {
      final normalizedUrl = baseUrl.trim();
      final normalizedModel = model.trim();
      final problem = normalizedUrl.isEmpty || normalizedModel.isEmpty
          ? 'Base URL and Model are required.'
          : ProviderConfig.baseUrlProblem(normalizedUrl);
      final failure = problem == null
          ? await _writeChange(
              (config) => _withProviderSettings(
                config,
                baseUrl: normalizedUrl,
                model: normalizedModel,
              ),
            )
          : SettingsFailure(
              kind: SettingsFailureKind.configRejected,
              message: problem,
            );
      _setState(
        SettingsState(
          config: _currentConfig(),
          hotkeyBindOutcome: _state.hotkeyBindOutcome,
          hotkeyBackendDescription: _state.hotkeyBackendDescription,
          failure: _resolveFailure(failure, _Mutation.provider),
          mutationInFlight: false,
        ),
      );
    } finally {
      _endMutation();
    }
  }

  static AppConfig _withProviderSettings(
    AppConfig config, {
    required String baseUrl,
    required String model,
  }) {
    final preset = config.presets
        .where((entry) => entry.id == config.activePresetId)
        .firstOrNull;
    if (preset == null ||
        preset.providerId != ProviderConfig.compatibleProviderId) {
      throw ArgumentError('The active preset is not OpenAI-compatible.');
    }
    final provider = config.providers[preset.providerId];
    if (provider == null) {
      throw ArgumentError('The selected provider is not configured.');
    }
    return config.copyWith(
      providers: {
        ...config.providers,
        preset.providerId: ProviderConfig(
          settings: Map.unmodifiable({
            ...provider.settings,
            ProviderConfig.baseUrlSetting: baseUrl,
          }),
        ),
      },
      presets: [
        for (final entry in config.presets)
          if (entry.id == preset.id)
            Preset(
              id: entry.id,
              providerId: entry.providerId,
              model: model,
              systemPrompt: entry.systemPrompt,
            )
          else
            entry,
      ],
    );
  }

  /// Claims the mutation slot, or refuses because one is already in flight.
  ///
  /// **Refused, never queued**, and that is the point rather than an economy.
  /// This controller has no mutation-generation stamp, so two overlapping
  /// mutations resolve last-completion-wins: the superseded combination is
  /// written to config and rendered as the effective one, discarding the choice
  /// the user actually made last. AD-11 makes the window seconds wide by design,
  /// since a portal dialog sits inside it. Queueing would preserve both writes
  /// and still leave the ordering to whichever `bind()` answered first;
  /// refusing means exactly one mutation is ever in flight, which is also what
  /// the surface's disabled controls already promise.
  ///
  /// Returns false without emitting when it refuses: the surface is already
  /// rendering the in-flight state that explains why.
  bool _beginMutation() {
    if (_disposed) {
      return false; // shutdown has begun; nothing may reach the ports any more
    }
    if (_mutating) {
      // Not silent: a refusal the user caused with a second tap is bounded, and
      // an operator reading a settings change that "did nothing" needs the line.
      // No config value and no key choice — only that one was refused.
      _log(
        () => _logger.info(
          'a settings mutation was refused because another is still in flight',
        ),
      );
      return false;
    }
    _mutating = true;
    _mutationFinished = Completer<void>();
    _setState(_stateWith(mutationInFlight: true));
    return true;
  }

  /// Releases the mutation slot.
  ///
  /// The `if` is a structural belt and **is pinned by no row**, stated rather
  /// than left looking guarded: every mutation body ends in a `_setState` that
  /// carries `mutationInFlight: false`, and every port call inside one is
  /// individually reduced to a value, so nothing reaches this branch today. It
  /// exists because the alternative failure mode is a surface whose every
  /// control is disabled for the life of the daemon.
  ///
  /// One case it deliberately does **not** cover: a controller disposed while a
  /// mutation is still in flight. [_setState] refuses after `dispose()`, so
  /// neither the mutation's own terminal state nor this fallback lands and
  /// [_state] keeps `mutationInFlight: true` for good. That is stated rather than
  /// worked around because the value is unreachable — `dispose()` runs at
  /// shutdown with the window already unmapped, and nothing reads [state]
  /// afterwards — and because writing [_state] directly here would put a second
  /// writer beside the one place that decides whether a transition is allowed.
  void _endMutation() {
    _mutating = false;
    _mutationFinished?.complete();
    _mutationFinished = null;
    if (_state.mutationInFlight) {
      _setState(_stateWith(mutationInFlight: false));
    }
  }

  /// The current state with [mutationInFlight] replaced and everything else
  /// carried — the one transition that changes nothing else.
  SettingsState _stateWith({required bool mutationInFlight}) {
    return SettingsState(
      config: _state.config,
      hotkeyBindOutcome: _state.hotkeyBindOutcome,
      hotkeyBackendDescription: _state.hotkeyBackendDescription,
      failure: _state.failure,
      mutationInFlight: mutationInFlight,
    );
  }

  /// Seeds the outcome the startup bind resolved to, for the surface that did
  /// not exist when it did (AD-12).
  ///
  /// Startup-only, and it exists because of an ordering rather than a
  /// preference: the provider graph — and so this controller — is built before
  /// the hotkey is bound, since a real bind can sit on a portal dialog for
  /// seconds (AD-11) and the window has to be warm first. A constructor argument
  /// therefore cannot carry it, and without this the settings screen would
  /// report "nothing has been requested yet" for the life of a daemon whose
  /// hotkey never bound.
  ///
  /// A **seed**, not an assignment: it applies only while nothing is known yet.
  /// The startup bind is not the only thing that can resolve first — the Wayland
  /// adapter subscribes to `ShortcutsChanged` inside `bind()`, so a
  /// compositor-originated change can reach [bindingChanges] and land here before
  /// `bindHotkey`'s own answer is handed over. Overwriting unconditionally would
  /// replace that newer fact with an older one, and nothing would emit again to
  /// correct it.
  ///
  /// A no-op after `dispose()`, like every other transition here: [_setState]
  /// is what refuses, so there is one place that decides it.
  ///
  /// It is also the *only* way an outcome reaches this controller from outside a
  /// mutation. There is deliberately no constructor parameter for it — see the
  /// note on the initializer list.
  void applyStartupOutcome(HotkeyBindOutcome outcome) {
    if (_state.hotkeyBindOutcome != null) {
      _log(
        () => _logger.info(
          'the startup bind outcome was not applied because the surface '
          'already holds a newer one',
        ),
      );
      return;
    }
    _setState(
      SettingsState(
        config: _state.config,
        hotkeyBindOutcome: outcome,
        hotkeyBackendDescription: _backendDescription(),
        failure: _state.failure,
        mutationInFlight: _state.mutationInFlight,
      ),
    );
    _queueEffectiveBinding(outcome);
  }

  /// A change the backend originated — a compositor-side rebind, or a shortcut
  /// the desktop dropped (AD-10, AD-11, AD-12).
  ///
  /// [SettingsState.failure] is deliberately carried rather than cleared, for
  /// the same reason [_onConfigChanged] carries it: only a successful in-app
  /// mutation retires the banner, and somebody else rebinding the shortcut says
  /// nothing about whether *this* user's change landed. The status lands
  /// immediately. A structured effective binding is then written through the
  /// mutation queue; an unavailable status keeps the configured restart seed.
  void _onBindingChanged(HotkeyBindOutcome outcome) {
    // Between two backend-originated changes the later one is genuinely newer,
    // so this path still overwrites unconditionally. The counter is what lets a
    // rebind in flight discover that this happened while it was waiting; it
    // changes nothing about what lands here.
    _backendChangeGeneration += 1;
    _setState(
      SettingsState(
        config: _state.config,
        hotkeyBindOutcome: outcome,
        hotkeyBackendDescription: _backendDescription(),
        failure: _state.failure,
        mutationInFlight: _state.mutationInFlight,
      ),
    );
    _queueEffectiveBinding(outcome);
  }

  void _queueEffectiveBinding(HotkeyBindOutcome outcome) {
    final effective = switch (outcome) {
      HotkeyBound(:final registration) => registration.effective,
      HotkeyRetained() => null,
      HotkeyUnavailable() => null,
    };
    if (effective == null) {
      return;
    }
    final generation = _backendChangeGeneration;
    _externalChanges = _externalChanges.then(
      (_) => _persistEffectiveBinding(effective, generation),
    );
  }

  Future<void> _persistEffectiveBinding(
    HotkeyBinding effective,
    int generation,
  ) async {
    final pendingMutation = _mutationFinished;
    if (pendingMutation != null) {
      await pendingMutation.future;
    }
    if (_disposed || generation != _backendChangeGeneration) {
      return;
    }
    if (_currentConfig().hotkeyBinding == effective || !_beginMutation()) {
      return;
    }
    try {
      final failure = await _writeChange(
        (config) => config.copyWith(hotkeyBinding: effective),
      );
      _setState(
        SettingsState(
          config: _currentConfig(),
          hotkeyBindOutcome: _state.hotkeyBindOutcome,
          hotkeyBackendDescription: _state.hotkeyBackendDescription,
          failure: failure ?? _state.failure,
          mutationInFlight: false,
        ),
      );
    } finally {
      _endMutation();
    }
  }

  /// The backend's own wording for what is in effect, read from the port at the
  /// moment an outcome lands (HOTKEY-03, HOTKEY-06).
  ///
  /// Read here rather than carried on the outcome, because AD-9's declared
  /// fields are fixed and the ratified addition put the description on
  /// `GlobalHotkey.current` instead — one member carrying both halves. Reading
  /// it in the same synchronous turn as the outcome is what keeps the pair from
  /// describing two different moments.
  ///
  /// Synchronous and free of I/O by the port's contract: it reads the adapter's
  /// cached field and never reaches the compositor, which is the whole reason
  /// that member is not a `Future` — a settings screen mounting must not wait
  /// on a portal.
  String? _backendDescription() => _hotkey.current?.backendDescription;

  /// The failure to display once [mutation] has resolved as [failure], and
  /// the one place [_failedMutation] is maintained.
  ///
  /// State is built directly rather than copied, so a successful mutation
  /// clears the previous failure instead of carrying it forever — but only a
  /// failure it could itself have fixed. A preset switch landing says nothing
  /// about whether the hotkey bound, and a hotkey change landing says nothing
  /// about whether the preset switch was ever written; in both directions the
  /// other change is still unapplied, so the surface must keep saying so. It
  /// is the same reasoning that keeps [_onConfigChanged] from retiring a
  /// banner, applied between the two mutations rather than to one failure
  /// kind — the kind alone cannot carry it, since a failed write of either
  /// mutation produces the same [SettingsFailureKind.configWriteFailed].
  SettingsFailure? _resolveFailure(
    SettingsFailure? failure,
    _Mutation mutation,
  ) {
    if (failure != null) {
      _failedMutation = mutation;
      return failure;
    }
    if (_failedMutation != null && _failedMutation != mutation) {
      return _state.failure; // the other mutation's, and still unfixed
    }
    _failedMutation = null;
    return null;
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _configChanges.cancel();
    } on Object catch (error) {
      // AD-15 backstop: shutdown completes even against a broken adapter.
      _log(
        () => _logger.error(
          'cancelling the config subscription failed',
          context: _errorContext(error),
        ),
      );
    }
    // Guarded independently of the config subscription: one cancel that rejects
    // must not leave the other subscription live on a torn-down controller.
    try {
      await _bindingChanges.cancel();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'cancelling the hotkey binding-change subscription failed',
          context: _errorContext(error),
        ),
      );
    }
    await _changes.close();
  }

  /// Requests the binding, reducing every way that can go wrong to a value.
  ///
  /// A throwing `bind()` is an AD-12 breach by the adapter, so it is caught
  /// here for the same reason the correction controller catches an
  /// AD-3-breaking provider: the contract is the adapter's to keep, and the
  /// daemon's to survive.
  Future<(HotkeyBindOutcome, SettingsFailure?)> _bind(
    HotkeyBinding binding,
  ) async {
    try {
      final outcome = await _hotkey.bind(binding);
      if (outcome is HotkeyUnavailable) {
        // The outcome's own message is adapter-authored free text. It is
        // contractually a user sentence and is rendered as one, but the same
        // AD-15 reasoning behind [_errorContext] applies to putting it on
        // stderr: an adapter that builds it from a caught error — the shape
        // this controller itself shipped before review — would leak through
        // the one context value in this layer that is not reduced to a type.
        _log(
          () => _logger.warning(
            'global hotkeys are unavailable on this backend',
            context: {'outcome': outcome.runtimeType.toString()},
          ),
        );
      }
      return (outcome, null);
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the hotkey backend threw instead of reporting unavailability',
          context: _errorContext(error),
        ),
      );
      // Both halves are rendered — the outcome by the tray and the settings
      // screen, the failure by the settings screen's error line — so both
      // are sentences a user can act on. Neither carries the raw error, for
      // the same reason [_errorContext] keeps it out of the log: a vendor
      // exception's `toString()` routinely carries the payload and the
      // absolute paths that caused it. The type reaches the log; the text
      // reaches nothing.
      return (
        const HotkeyUnavailable(
          // The application-ring twin of `DaemonStartup.requestBinding`'s
          // backstop, and it knows exactly as little: the adapter threw instead
          // of reporting, so nothing here observed a backend working. Same
          // cause for the same reason.
          cause: HotkeyUnavailableCause.noBackend,
          message:
              'the hotkey backend could not be reached, so no global '
              'shortcut is registered — the tray menu still opens the panel',
        ),
        const SettingsFailure(
          kind: SettingsFailureKind.hotkeyBindFailed,
          message:
              'the shortcut could not be registered. Try setting it again, '
              'or restart the app.',
        ),
      );
    }
  }

  /// Applies [change] to the store's current value and persists the result.
  ///
  /// Every mutation is derived from the store's current value **at write time**,
  /// never from the state this controller was holding: `bind()` can sit on a
  /// portal dialog for seconds (AD-11), and a preset changed meanwhile must not
  /// be written back to its old value.
  ///
  /// A store whose `current` getter throws is an AD-13 breach — the port declares
  /// it as the most recently loaded or written value — and the mutation is
  /// **refused** rather than derived from `_state.config`, for exactly the reason
  /// above: a value assembled from a stale base would silently overwrite
  /// whatever else had changed. It is reported as a write failure because that is
  /// what the user experiences and what they can act on; the breach itself
  /// reaches the log, by type.
  Future<SettingsFailure?> _writeChange(
    AppConfig Function(AppConfig config) change,
  ) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final AppConfig current;
      try {
        current = _configStore.current;
      } on Object catch (error) {
        _log(
          () => _logger.error(
            'the config store could not report its current value, so the change '
            'was not derived or written',
            context: _errorContext(error),
          ),
        );
        // Deliberately *not* the disk message [_write] uses. A `current` that
        // throws is the store breaking its own contract, not a file the user can
        // chmod, and sending them to check permissions would be the same
        // wrong-cause misdirection the [configRejected] branch exists to avoid.
        return const SettingsFailure(
          kind: SettingsFailureKind.configWriteFailed,
          message:
              'your settings could not be saved, because the app could not read '
              'the settings it already has. Try again, or restart the app.',
        );
      }
      try {
        return await _write(change(current));
      } on ConfigWriteConflict {
        // The store now exposes the hand edit as current; derive from it again.
      } on ArgumentError catch (error) {
        _log(
          () => _logger.error(
            'the settings change was refused before writing',
            context: _errorContext(error),
          ),
        );
        return const SettingsFailure(
          kind: SettingsFailureKind.configRejected,
          message: 'The selected provider changed. Select it again and retry.',
        );
      }
    }
    return const SettingsFailure(
      kind: SettingsFailureKind.configWriteFailed,
      message: 'the settings file kept changing. Try saving again.',
    );
  }

  /// The store's `current`, or the newest value this controller managed to read
  /// when the store's own getter breaks its contract.
  ///
  /// Only for *rendering*. A write is refused outright in that case — see
  /// [_writeChange] — but a surface still has to show something, and the last
  /// value the store gave us is the truest thing available. Guarded here rather
  /// than at each call site so an AD-13 breach cannot escape a mutation into the
  /// zone, which is what left every control disabled for good.
  ///
  /// **Logged, and the earlier reasoning for keeping it silent was wrong.** The
  /// argument was that every caller has already been through [_writeChange],
  /// which reports the same breach for the same read one step earlier. That only
  /// holds when the getter was already broken *before* the write: [_writeChange]
  /// reads `current` once, at the start, so a store that starts throwing after
  /// the write lands — an adapter that re-read the file and failed, a store torn
  /// down by a concurrent shutdown — reaches here having reported nothing at all.
  /// The surface then renders the pre-write value with no failure beside it, and
  /// the user is shown their old setting as though the change never happened.
  /// One line, type-only, is cheaper than that being invisible; the duplicate an
  /// operator may see is the case where the getter was broken all along.
  AppConfig _currentConfig() {
    try {
      return _configStore.current;
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the config store could not report its current value while rendering, '
          'so the last value it did report is what the surface shows',
          context: _errorContext(error),
        ),
      );
      return _state.config;
    }
  }

  /// Returns the failure to surface, or null when the write landed.
  Future<SettingsFailure?> _write(AppConfig config) async {
    // Marked before the write, because the store schedules its change event
    // inside write() — the echo can reach the listener before write()
    // returns, and would otherwise render a half-applied settings frame.
    _expectEcho(config);
    try {
      await _configStore.write(config);
      _notifyConfigApplied(config);
      return null;
    } on ConfigWriteConflict {
      _forgetEcho(config);
      rethrow;
    } on ArgumentError catch (error) {
      _forgetEcho(config); // a refused write emits no echo
      // The store validates before it touches the file, so this is the value
      // being refused, not a write that failed. Reporting it as a write
      // failure would blame the disk for a mistake in the change itself.
      _log(
        () => _logger.error(
          'the config store refused the value',
          context: _errorContext(error),
        ),
      );
      return const SettingsFailure(
        kind: SettingsFailureKind.configRejected,
        message:
            'that change was refused as invalid, so nothing was saved. Pick '
            'a different value.',
      );
    } on Object catch (error) {
      _forgetEcho(config); // a rejected write emits no echo
      // AD-13: an unwritable config never takes the daemon down. The store
      // stays the sole owner of the value, so state keeps its `current` and
      // the loss is reported rather than rethrown.
      _log(
        () => _logger.error(
          'the config write failed',
          context: _errorContext(error),
        ),
      );
      return const SettingsFailure(
        kind: SettingsFailureKind.configWriteFailed,
        message:
            'your settings could not be saved. Check that the config file is '
            'writable, then try again.',
      );
    }
  }

  void _onConfigChanged(AppConfig config) {
    if (_forgetEcho(config)) {
      return; // this controller's own write; the mutation sets state itself
    }
    _externalChanges = _externalChanges.then(
      (_) => _applyExternalConfig(config),
    );
  }

  Future<void> _applyExternalConfig(AppConfig config) async {
    final pendingMutation = _mutationFinished;
    if (pendingMutation != null) {
      await pendingMutation.future;
    }
    if (_disposed || config != _currentConfig()) {
      return;
    }
    if (config == _state.config) {
      return;
    }
    if (config.hotkeyBinding != _state.config.hotkeyBinding) {
      await changeHotkey(config.hotkeyBinding);
      return;
    }
    _notifyConfigApplied(config);
    // An external edit deliberately does not retire a displayed failure:
    // only a successful in-app mutation does. Someone else's change landing
    // says nothing about whether *this* user's change did, and clearing the
    // banner here would report success for a mutation that never happened.
    // Built directly rather than with copyWith, which cannot express either
    // choice — it can only carry the failure forward by accident.
    _setState(
      SettingsState(
        config: config,
        hotkeyBindOutcome: _state.hotkeyBindOutcome,
        hotkeyBackendDescription: _state.hotkeyBackendDescription,
        failure: _state.failure,
        mutationInFlight: _state.mutationInFlight,
      ),
    );
  }

  void _notifyConfigApplied(AppConfig config) {
    try {
      _onConfigApplied?.call(config);
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'a committed config change could not be applied to the daemon',
          context: _errorContext(error),
        ),
      );
    }
  }

  /// Records that [config] was written and its echo is still owed.
  void _expectEcho(AppConfig config) {
    _ownWrites.add(config);
  }

  /// Claims the one owed echo for [config], returning whether there was one.
  bool _forgetEcho(AppConfig config) => _ownWrites.remove(config);

  void _setState(SettingsState state) {
    if (_disposed) {
      // A mutation begun before shutdown can still resolve after it — `bind()`
      // can sit on a portal dialog for seconds (AD-11). Matching
      // `CorrectionController`, a torn-down controller stops reporting rather
      // than mutating state nothing will ever read.
      return;
    }
    _state = state;
    if (_changes.isClosed) {
      return;
    }
    _changes.add(state);
  }
}

/// Which mutation a [SettingsFailure] belongs to. Private: it disambiguates
/// ownership of the single failure slot and is not part of what the surface
/// renders.
enum _Mutation { hotkey, preset, provider }

/// Emits a log line without letting the logger's own failure escape — see the
/// canonical note in `correction_controller.dart`.
void _log(void Function() emit) {
  try {
    emit();
  } on Object {
    // Nowhere left to report this: the reporting channel is what broke.
  }
}

/// The only part of a caught error that is safe to put in a log line — see
/// the [Logger] port's doc, and the canonical note in
/// `correction_controller.dart`.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}
