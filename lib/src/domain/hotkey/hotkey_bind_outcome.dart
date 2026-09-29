import 'global_hotkey.dart';

/// What a bind request resolved to (AD-12).
///
/// Unavailability is a *value*, not an exception: wlroots compositors ship no
/// GlobalShortcuts portal at all, so "no backend would take this binding" is
/// an expected outcome the settings surface and the tray have to render, not
/// a programmer error (Consistency Conventions, "Errors").
sealed class HotkeyBindOutcome {
  const HotkeyBindOutcome();
}

/// A backend took the request. [registration] states what is actually in
/// effect and who owns it (AD-10).
final class HotkeyBound extends HotkeyBindOutcome {
  const HotkeyBound(this.registration);

  final HotkeyRegistration registration;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyBound && registration == other.registration;
  }

  @override
  int get hashCode => registration.hashCode;
}

/// A replacement was refused while [registration] remains held. The rejected
/// request is not an effective binding or a new restart preference.
final class HotkeyRetained extends HotkeyBindOutcome {
  const HotkeyRetained(this.registration);

  final HotkeyRegistration registration;

  @override
  bool operator ==(Object other) =>
      other is HotkeyRetained && registration == other.registration;

  @override
  int get hashCode => registration.hashCode;
}

/// Which of the three distinct things went wrong, as a value a consumer can
/// branch on instead of reading [HotkeyUnavailable.message] (D-06, HOTKEY-08).
///
/// One variant carrying one free-text sentence used to mean three different
/// things, and prose was the only carrier: a consumer could not tell "never
/// retry" from "retry with a different key" from "you just lost the one you
/// had", so anything wanting to act on the difference had to match on English
/// and would break silently the day a sentence was reworded.
///
/// Each value is named for **what it means to the person whose hotkey stopped
/// working**, not for the code path that produced it. The dividing questions
/// are only two: can this attempt reach a usable backend, and was a binding
/// that was genuinely in effect taken away?
///
/// Adding this field edits AD-9's verbatim-fixed declaration rather than adding
/// beside it, so unlike `GlobalHotkey.bindingChanges` it is not covered by the
/// in-tree precedent — it was ratified on 2026-09-01 as its own human decision,
/// recorded in the deferred-work ledger for Phase 7 to reconcile into the spine
/// rather than hand-edited there.
enum HotkeyUnavailableCause {
  /// This attempt cannot reach a usable global-shortcut backend — for example,
  /// a compositor with no GlobalShortcuts portal, a session with no bus, or an
  /// X11 display that cannot be opened.
  ///
  /// Changing the combination cannot help while the backend is inaccessible.
  /// A surface must not invite the user to pick another key for this cause.
  noBackend,

  /// A working backend did not grant this request — most often because the
  /// combination is refused, which is the case that gives this value its name.
  ///
  /// Picking a different combination is the user's move, and it may work: a
  /// backend answered, so the mechanism exists. This value is deliberately
  /// wider than the literal per-key case, because the only alternatives are
  /// worse: a portal that answered unreadably or refused to open a session has
  /// demonstrably *not* left the user without a backend, so reporting
  /// [noBackend] would tell them to give up when retrying is not futile. The
  /// specific diagnosis stays in [HotkeyUnavailable.message], which every
  /// surface renders.
  keyRefused,

  /// A binding that was genuinely in effect was taken away by the desktop.
  ///
  /// The user had a working shortcut and no longer does. They re-apply it when
  /// they want it back, and **the daemon does not re-claim it** (D-08): on
  /// Wayland the compositor is the authority, and fighting it risks an override
  /// loop. Reached only from a backend-originated change, never from a `bind()`
  /// this app made.
  revoked,
}

/// No global hotkey is held. The app stays usable through the
/// tray menu, and the degradation is shown rather than swallowed (AD-12).
final class HotkeyUnavailable extends HotkeyBindOutcome {
  const HotkeyUnavailable({required this.cause, required this.message});

  /// Which of the three meanings this is, readable without parsing [message]
  /// (D-06, HOTKEY-08).
  ///
  /// **Required and deliberately defaultless.** A default would silently label
  /// every construction site with a cause nobody chose, and would let a future
  /// fourth condition be added without anyone deciding what the user should be
  /// told about it. Making it required means a site that names no cause does
  /// not compile, which is the only mechanism that guarantees the decision is
  /// taken rather than inherited.
  final HotkeyUnavailableCause cause;

  /// Why binding was impossible, in terms a user can act on ("this
  /// compositor provides no global shortcuts portal").
  ///
  /// Retained unchanged alongside [cause], not replaced by it: AD-12's rule
  /// that a surface renders this verbatim still holds, and it carries the
  /// specific diagnosis that a three-value enum cannot. Every sentence this
  /// codebase produces ends by naming the tray menu as the way in that still
  /// works.
  final String message;

  /// Value equality over **both** fields, and the second one is load-bearing.
  /// `SettingsState` contains this transitively, so two outcomes that compare
  /// equal suppress a rebuild — and two values differing only in cause say
  /// different things to the user, so they must not be deduped against each
  /// other.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyUnavailable &&
        cause == other.cause &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(cause, message);
}
