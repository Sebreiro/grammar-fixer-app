import 'hotkey_bind_outcome.dart';
import 'hotkey_binding.dart';
import 'hotkey_status.dart';

enum BindingAuthority { application, compositor }

final class HotkeyRegistration {
  const HotkeyRegistration({required this.effective, required this.authority});

  /// What is actually in effect. null when the backend cannot report it.
  final HotkeyBinding? effective;
  final BindingAuthority authority;

  /// Value equality, added to AD-9's declaration without touching its fields:
  /// `SettingsState` contains this transitively, and a state that compares by
  /// identity cannot be deduped by any consumer.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyRegistration &&
        effective == other.effective &&
        authority == other.authority;
  }

  @override
  int get hashCode => Object.hash(effective, authority);
}

abstract interface class GlobalHotkey {
  /// One event per press of the currently bound combination.
  Stream<void> get activations;

  /// Changes the **backend** originated — never an answer to a call this app
  /// made, which [bind] already gives.
  ///
  /// Two things reach here, and the sealed pair is why one stream carries both:
  /// the desktop rebound the shortcut ([HotkeyBound], with whatever the backend
  /// can report about it), and the desktop no longer holds it at all
  /// ([HotkeyUnavailable]). AD-10 requires the second half of CAP-12 — "a
  /// rebind made in the compositor updates the UI" — and `bind()` cannot carry
  /// it, so without this member the Wayland adapter's `ShortcutsChanged`
  /// subscription has nowhere to go.
  ///
  /// Broadcast: the settings surface is not promised to be the only consumer.
  /// An adapter whose backend cannot originate a change at all implements this
  /// as an empty stream that closes — an X11 grab is only ever changed by this
  /// app, through [bind], whose return value is already the report.
  ///
  /// **Precedence over [bind]'s answer — the rule for both writers, stated
  /// here because they write one piece of state and nothing above them can
  /// derive the order.** An event that reaches here **supersedes** the return
  /// value of any [bind] that was issued before it. [bind]'s outcome is
  /// authoritative only for the transition it caused, and only until a
  /// backend-originated change is observed; a consumer holding a [bind] answer
  /// discards it and keeps the event. Concretely: stamp a generation when a
  /// [bind] is issued, bump it here, and drop that bind's outcome if the number
  /// moved.
  ///
  /// **The tie is broken toward this member.** A change observed in the *same*
  /// turn as a bind's answer is still a change observed *after* that bind was
  /// issued, so it wins. Only an event observed strictly *before* the bind was
  /// issued is older than the bind's own answer, and only that one loses.
  ///
  /// **"Observed" means the moment the consumer's listener runs**, never the
  /// moment the backend emitted. A consumer can only order what it saw, and
  /// this is a broadcast stream with no replay, so an event that arrived before
  /// anyone subscribed was never observed at all — [current] is what covers
  /// that case, not this ordering.
  ///
  /// **Why this way round, since a rule with no reason gets re-litigated.** On
  /// Wayland the compositor is the authority (AD-10) and D-01 requires the
  /// surface to show what is *currently* in effect. A [bind] answer is by
  /// construction older than any change the backend originated after that call
  /// was issued, and writing the older fact over the newer one leaves the user
  /// looking at a shortcut that is not in effect with nothing left to emit a
  /// correction — the backend already sent its one event.
  ///
  /// **What is reachable today, stated so the rule is not misread as a bug
  /// report.** The GlobalShortcuts documentation specifies no ordering between
  /// the `BindShortcuts` Response and `ShortcutsChanged`, so an event arriving
  /// *before* a bind's answer is protocol-legal. It is nevertheless unreachable
  /// on the shipped Wayland adapter, which subscribes to `ShortcutsChanged`
  /// only after `_bindShortcut` has returned — the subscription does not exist
  /// while the first bind is outstanding, so no such event can be observed
  /// before that Response. The rule is written for the window that *is*
  /// reachable, a change landing during a **rebind**, which AD-11 makes seconds
  /// wide because a portal dialog sits inside it; and it is written in the port
  /// rather than in one consumer so that a second adapter, or a change to that
  /// subscription order, cannot implement the opposite order and still satisfy
  /// every written invariant (FLAT-03, HOTKEY-07).
  ///
  /// Adding this member is an addition to AD-9's verbatim declaration that
  /// leaves every declared *field* of [HotkeyRegistration] untouched — the same
  /// class of change as the value equality above, recorded in the deferred-work
  /// ledger and the story's Spec Change Log rather than hand-edited into the
  /// spine.
  Stream<HotkeyBindOutcome> get bindingChanges;

  /// What this backend reports about the shortcut **right now** — the same
  /// facts [bindingChanges] carries, readable by a consumer that was not
  /// listening when they arrived.
  ///
  /// **Synchronous, and that is the whole point of the member.** AD-8 already
  /// pairs a synchronous `bool get isVisible` with `Stream<bool> get changes`
  /// on `PanelVisibility` for exactly this reason, and the hotkey surface needs
  /// it more sharply: a tray daemon spends almost all of its life with no
  /// settings screen mounted, and [bindingChanges] is a broadcast stream with
  /// no replay, so every desktop-side rebind that happens while the screen is
  /// closed is dropped (FLAT-02). A surface that had only the stream would then
  /// render the startup bind's answer — the shortcut that *was* in effect —
  /// which is the one thing this whole surface exists not to do.
  ///
  /// **Null until anything has been asked of a backend**, which is an absence
  /// of information rather than an error: nothing has been requested, so
  /// nothing about a registration is known. Every later read answers with a
  /// status, including the ones saying no shortcut could be bound.
  ///
  /// **It performs no I/O.** A read is a cached field, never a round trip: the
  /// screen that reads this is mounting, and a member that reached the
  /// compositor here would hang it on the portal for as long as the portal
  /// felt like taking — the failure HOTKEY-06 exists to prevent. A backend
  /// that can re-read what it holds does so on its own explicit path, not on
  /// this one.
  ///
  /// Adding this member is an addition to AD-9's verbatim declaration that
  /// leaves every declared *field* of [HotkeyRegistration] untouched — the same
  /// class of change as the value equality above and as [bindingChanges]
  /// itself, whose own doc records the precedent: "recorded in the
  /// deferred-work ledger and the story's Spec Change Log rather than
  /// hand-edited into the spine". Ratified on 2026-09-01 as the `status-type`
  /// option, which is why [HotkeyStatus] carries HOTKEY-03's backend
  /// description on this member instead of on a second one.
  HotkeyStatus? get current;

  /// Requests [binding]. The return value states what is actually in effect.
  ///
  /// A backend that cannot bind at all resolves to [HotkeyUnavailable]; it
  /// never rejects. AD-12 makes that degradation a state the tray and the
  /// settings screen render, and an exception would instead surface as an
  /// unhandled async error in a daemon that must stay resident.
  /// A refused replacement that leaves the prior registration live returns
  /// [HotkeyRetained], carrying that registration rather than the request.
  ///
  /// **What it states is authoritative only for the transition this call
  /// caused, and only until a [bindingChanges] event is observed.** A
  /// backend-originated change observed at any time after this call was issued
  /// — including in the same turn as this answer — is the newer fact and
  /// supersedes what this returns; one observed strictly before it does not.
  /// See [bindingChanges] for the rule, its rationale, and why a consumer
  /// stamps a generation instead of comparing timestamps.
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding);

  Future<void> dispose();
}
