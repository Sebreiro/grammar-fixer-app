import '../domain/config/app_config.dart';
import '../domain/config/provider_config.dart';
import '../domain/correction/preset.dart';
import '../domain/hotkey/hotkey_bind_outcome.dart';

/// What went wrong on the last settings mutation, in terms the surface can
/// render (Consistency Conventions, "Errors").
enum SettingsFailureKind {
  /// The write itself failed — the store accepted the value and could not
  /// persist it (an unwritable file, a full disk). A settings screen that
  /// silently kept showing the change would be lying about what CAP-8 and
  /// CAP-12 promise.
  configWriteFailed,

  /// The store refused the value; nothing was written. AD-13 makes the store
  /// the single validation point, and it validates before touching the file,
  /// so this is the change being wrong rather than the disk — a distinction
  /// the user needs, since only one of the two is theirs to fix.
  configRejected,

  /// A bind failed, including a refused new X11 key whose old grab remains.
  hotkeyBindFailed,
}

/// A settings failure the user can act on — retry the change, fix file
/// permissions, or pick a different combination.
final class SettingsFailure {
  const SettingsFailure({
    required this.kind,
    required this.message,
    this.previousShortcutWorks = false,
  });

  final SettingsFailureKind kind;
  final String message;
  final bool previousShortcutWorks;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SettingsFailure &&
        kind == other.kind &&
        message == other.message &&
        previousShortcutWorks == other.previousShortcutWorks;
  }

  @override
  int get hashCode => Object.hash(kind, message, previousShortcutWorks);
}

/// What the settings surface renders (CAP-8, CAP-12).
final class SettingsState {
  const SettingsState({
    required this.config,
    required this.mutationInFlight,
    this.hotkeyBindOutcome,
    this.hotkeyBackendDescription,
    this.failure,
  });

  /// The config exactly as the ConfigStore last loaded or wrote it — the one
  /// owner of that value (AD-13). A rejected write leaves this unchanged, so
  /// the surface never claims a value the store did not accept.
  final AppConfig config;

  /// The selected prompt/model pair is the only one this form may edit.
  Preset? get compatiblePreset => config.presets
      .where(
        (preset) =>
            preset.id == config.activePresetId &&
            preset.providerId == ProviderConfig.compatibleProviderId,
      )
      .firstOrNull;

  String get compatibleBaseUrl =>
      config
          .providers[ProviderConfig.compatibleProviderId]
          ?.settings[ProviderConfig.baseUrlSetting] ??
      '';

  /// What the backend most recently reported (AD-12). [HotkeyBound] carries a
  /// successful registration, [HotkeyRetained] carries the prior registration
  /// after a refused replacement, and [HotkeyUnavailable] means nothing is held.
  /// An `application` authority means the setting is authoritative (X11);
  /// `compositor` means it is advisory (Wayland). The config binding is the
  /// restart seed when the compositor reports no structured effective binding.
  ///
  /// The authority is still carried here because it is a fact about the
  /// machine; since D-03 the settings screen no longer *renders* which regime
  /// is active, so a consumer that finds a use for it should say what the use
  /// is rather than assume the old read-out.
  ///
  /// Null until a bind has been attempted: nothing effective is known yet.
  final HotkeyBindOutcome? hotkeyBindOutcome;

  /// The backend's own user-readable wording for the shortcut in effect,
  /// verbatim, or null when the backend authors none (HOTKEY-03).
  ///
  /// Read from `GlobalHotkey.current` at the same moment as
  /// [hotkeyBindOutcome], because the pair is what the surface renders: on
  /// Wayland the portal reports no machine-readable combination at all, so this
  /// text is the *only* thing that can be shown about the shortcut in force,
  /// and without it the screen would either say nothing or fall back to the
  /// requested combination — the AD-10 breach the whole surface exists to
  /// prevent.
  ///
  /// Null on X11, where the combination itself is in the registration and the
  /// surface renders that instead. Null also on an unavailable outcome: there
  /// is no shortcut for wording to be about.
  final String? hotkeyBackendDescription;

  /// The last mutation's failure, or null when the last one succeeded.
  ///
  /// There is deliberately no `copyWith`: a `failure ?? this.failure` cannot
  /// express clearing, which is what every successful mutation does, so the
  /// three transitions build a state directly and each writes down what it
  /// keeps. An optional-parameter copy here would only re-arm that trap.
  final SettingsFailure? failure;

  /// Whether a mutation is still resolving.
  ///
  /// State rather than a widget's flag, and the difference is load-bearing. A
  /// bind can sit on a portal dialog for seconds (AD-11) while the controller
  /// has no mutation-generation guard, so a second mutation issued inside that
  /// window resolves last-completion-wins. Anything a *widget* owned would be
  /// destroyed by the settings screen unmounting — going back to the panel, or a
  /// summon returning to it — and the user could then issue the second mutation
  /// in three taps. The controller outlives every surface, so this is where the
  /// answer has to live.
  ///
  /// It is also what the surface renders as a pending affordance: a screen whose
  /// controls are all disabled and which says nothing about why is the "running
  /// looks like idle" defect the panel already paid for.
  ///
  /// **Required, not defaulted**, for the reason [failure] gives two fields up
  /// and this one would otherwise have re-armed: a mutation clearing the slot by
  /// *omitting* the parameter is an unlock nothing states. Every transition here
  /// says what it does with the slot, so a fourth one added later cannot silently
  /// re-enable the controls with a bind still parked on a portal dialog.
  final bool mutationInFlight;

  /// Value equality, deep through [config] and [hotkeyBindOutcome], so a
  /// consumer can dedupe: an external config write that changes nothing this
  /// surface renders should not rebuild it.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SettingsState &&
        config == other.config &&
        hotkeyBindOutcome == other.hotkeyBindOutcome &&
        hotkeyBackendDescription == other.hotkeyBackendDescription &&
        failure == other.failure &&
        mutationInFlight == other.mutationInFlight;
  }

  @override
  int get hashCode => Object.hash(
    config,
    hotkeyBindOutcome,
    hotkeyBackendDescription,
    failure,
    mutationInFlight,
  );
}
