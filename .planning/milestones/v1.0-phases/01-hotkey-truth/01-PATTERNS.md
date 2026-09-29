# Phase 1: Hotkey Truth - Pattern Map

**Mapped:** 2026-09-01
**Files analyzed:** 16 (2 created, 9 rewritten/modified, 3 deleted, 2 non-source)
**Analogs found:** 14 / 16 (2 partial — see § No Analog Found)

All analog paths below are git-tracked source (`git ls-files` verified for
`lib/src/infrastructure/hotkey/`, `lib/src/domain/hotkey/`, `lib/src/ui/settings/`,
`test/architecture/`). No gitignored install/runtime mirror is cited.

**Where CONTEXT.md and RESEARCH.md disagree, RESEARCH.md wins.** Rows carrying such a
correction say so explicitly.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` **(new)** | infrastructure adapter (registrar seam impl) | event-driven (grab → press stream) | `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart` (the file it replaces) | exact — same port, same seam, same lifecycle contract |
| — its private FFI bindings (`_XlibBindings`, same file) | vendor-confinement helper | request-response (FFI calls) | `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` (keeps `dbus` types private) | role-match (**no in-tree `dart:ffi` exists — see gap G1**) |
| — its helper isolate | background worker | event-driven | **none** | **no analog (gap G2)** |
| `lib/src/infrastructure/hotkey/portal_app_id_regime.dart` **(new)** | infrastructure pure predicate | transform (env → enum) | `lib/src/infrastructure/hotkey/display_server.dart` | exact — RESEARCH.md names it the shape to copy |
| `lib/src/domain/hotkey/hotkey_status.dart` **(new, recommended)** | domain value type | transform | `lib/src/domain/hotkey/global_hotkey.dart` → `HotkeyRegistration` | exact |
| Settings key-**capture** control (replaces `lib/src/ui/settings/hotkey_preference_field.dart`) | UI StatefulWidget | event-driven (key events) | the file itself, plus `lib/src/ui/panel/correction_panel.dart` for `FocusNode`/`Focus` ownership + disposal | role-match |
| `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` | infrastructure adapter | request-response + pub-sub | itself (surgical edits, 4 slices) | self — see § Seam Map |
| `lib/src/domain/hotkey/global_hotkey.dart` | domain port | — | itself, `bindingChanges` doc `:50-54` | exact (the precedent is in-file) |
| `lib/src/domain/hotkey/hotkey_bind_outcome.dart` | domain sum type | — | itself (`sealed class HotkeyBindOutcome`) + `lib/src/domain/correction/correction_event.dart` | exact — **RESEARCH.md rejects the sealed-subtype route**; use a `cause` field, see row note |
| `lib/src/domain/hotkey/hotkey_binding.dart` | domain value type | — | `lib/src/infrastructure/hotkey/hotkey_grab.dart:17-27` | exact — the in-tree defensive-copy precedent |
| `lib/src/ui/settings/hotkey_status_view.dart` | UI StatelessWidget | transform (outcome → sentences) | itself (`_unavailableLines`, `_boundLines`) | self — **collides with SETTINGS-09 in Phase 2** |
| `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` | infrastructure lookup table | transform | itself (`_usages` derivation `:162-164`) | self — **role changes; RESEARCH.md C3 replaces CONTEXT.md's premise** |
| `lib/src/infrastructure/hotkey/xdg_shortcut_trigger.dart` | infrastructure serializer | transform | itself | self — becomes shared by *both* adapters |
| `lib/src/application/settings_controller.dart` | application controller | request-response + state | itself, `applyStartupOutcome:294-312` | exact — the single most reusable pattern in this phase |
| `pubspec.yaml` / `linux/flutter/generated_plugins.cmake` | config | — | n/a (mechanical) | n/a |
| `_bmad-output/implementation-artifacts/deferred-work.md` | ledger (append-only) | — | closed entries `DW-95:71-79`, `DW-96:81-89` | exact |
| `test/architecture/hotkey_confinement_test.dart`, `test/architecture/composition_wiring_test.dart` | existing gates (maintenance) | — | themselves | self |

---

## Pattern Assignments

### `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` (new; infrastructure, event-driven)

**Analog:** `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart` — the file it deletes.
Copy its *structure* wholesale; only the body of `_hotKeyFor`/`register` changes technology.

**Class shape + lifecycle fields** (`hotkey_manager_registrar.dart:33-52`):

```dart
final class HotkeyManagerRegistrar implements HotkeyRegistrar {
  HotkeyManagerRegistrar();

  /// Broadcast so the seam does not impose a one-listener rule of its own.
  final StreamController<void> _presses = StreamController<void>.broadcast();

  HotKey? _held;          // what is registered right now; the handle release() needs
  bool _disposed = false;

  @override
  Stream<void> get presses => _presses.stream;
```

**Inert-construction rule — load-bearing for D-11** (`:19-25` doc + `composition_wiring_test.dart:878-904`):

> "**Nothing here touches `hotKeyManager` before a grab is asked for.** … a Wayland session that
> constructs this object and never binds pays nothing (`main.dart` builds it before it knows which
> display server it is on)."

The new registrar owes the same promise, one level stronger: no `DynamicLibrary.open`, no
`Isolate.spawn`, no `XOpenDisplay` until the first `grab()`. RESEARCH.md § Pattern 2.

**Disposed-mid-grab undo + `StateError` rejection** (`:63-92`) — copy verbatim in shape:

```dart
  @override
  Future<void> grab(HotkeyGrab grab) async {
    _refuseIfDisposed('grab');
    // Built first, so an unrepresentable request rejects before any channel
    // call is made — including the release below, which would otherwise drop a
    // working shortcut on the way to failing.
    final hotKey = _hotKeyFor(grab);
    await _unregisterHeld();
    await hotKeyManager.register(hotKey, keyDownHandler: _onKeyDown);
    if (_disposed) { /* undo, then */ throw StateError('the hotkey registrar was disposed during this grab'); }
    _held = hotKey;
  }
```

**`dispose()` with the close in a `finally`** (`:112-122`) — copy exactly:

```dart
  Future<void> dispose() async {
    if (_disposed) { return; }
    _disposed = true;
    try {
      await _unregisterHeld();
    } finally {
      await _presses.close();
    }
  }
```

**Press fan-out guard** (`:236-241`):

```dart
  void _onKeyDown(HotKey hotKey) {
    if (_disposed || _presses.isClosed) { return; }
    _presses.add(null);
  }
```

**Vendor-privacy discipline (AD-1/AD-17), analog `wayland_portal_global_hotkey.dart`.** That file is
the only one in `lib/` naming `package:dbus`; its handle is a nullable private field, threaded rather
than null-asserted (`:130-138`):

```dart
  /// Nullable rather than substituted, because there is no honest substitute…
  /// It is threaded into every step that needs it rather than read through a
  /// null-assertion, so the one branch that handles its absence is in [_bind],
  /// where it is an AD-12 value like any other.
  final DBusClient? _client;
```

Apply the same to the `DynamicLibrary` / `Pointer<_Display>` / `SendPort`: private, nullable, never
null-asserted, absence handled as a value.

**Error-context helper — reuse verbatim** (`wayland_portal_global_hotkey.dart:1252-1256`):

```dart
/// The only part of a caught error that is safe to put in a log line.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}
```

**Doc-comment obligation.** `hotkey_registrar.dart:26-41` states two "properties of the backend that
callers must not re-derive" — both become **false** under the replacement (RESEARCH.md § Pattern 1).
Rewrite, do not delete. Also delete the precondition paragraph at `:57-65` (`labelsThatBindTheWrongKey`),
which C3 empties of subject.

---

### `lib/src/infrastructure/hotkey/portal_app_id_regime.dart` (new; infrastructure, transform)

**Analog:** `lib/src/infrastructure/hotkey/display_server.dart` (37 lines) — whole file is the template.

```dart
enum DisplayServer {
  x11,
  wayland;

  static DisplayServer fromEnvironment(Map<String, String> environment) {
    final sessionType = environment['XDG_SESSION_TYPE']?.trim().toLowerCase();
    if (sessionType == 'wayland') { return DisplayServer.wayland; }
    if (sessionType == 'x11')     { return DisplayServer.x11; }
    final waylandDisplay = environment['WAYLAND_DISPLAY']?.trim();
    if (waylandDisplay != null && waylandDisplay.isNotEmpty) {
      return DisplayServer.wayland;
    }
    return DisplayServer.x11;
  }
}
```

Pattern to carry: enum + static `fromEnvironment(Map<String,String>)`, pure, trimmed inputs, a doc
comment stating *why the fallback is the fallback*. RESEARCH.md § "The sandbox predicate" adds one
injected `bool Function(String path) fileExists` for `/.flatpak-info` so a binding-free test drives
both branches. The `/.dockerenv` exclusion is already argued in
`wayland_portal_global_hotkey.dart:363-373` — quote that reasoning forward rather than re-deriving it.

---

### `lib/src/domain/hotkey/global_hotkey.dart` (domain port; gains `current`)

**Analog: this file.** The AD-9 precedent is its own `bindingChanges` doc (`:50-54`) — quote it in
the new member's doc:

```dart
  /// Adding this member is an addition to AD-9's verbatim declaration that
  /// leaves every declared *field* of [HotkeyRegistration] untouched — the same
  /// class of change as the value equality above, recorded in the deferred-work
  /// ledger and the story's Spec Change Log rather than hand-edited into the
  /// spine.
  Stream<HotkeyBindOutcome> get bindingChanges;
```

And the value-equality precedent immediately above it (`:13-27`) for the new `HotkeyStatus` type:

```dart
  /// Value equality, added to AD-9's declaration without touching its fields:
  /// `SettingsState` contains this transitively, and a state that compares by
  /// identity cannot be deduped by any consumer.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) { return true; }
    return other is HotkeyRegistration &&
        effective == other.effective &&
        authority == other.authority;
  }

  @override
  int get hashCode => Object.hash(effective, authority);
```

**RESEARCH.md correction (C2):** there are **four** AD-9 declaration edits, not the roadmap's one or
CONTEXT.md's three. Folding HOTKEY-03's description carrier onto this same new member (a new
`HotkeyStatus` type) collapses edits **A** and **C** into one *addition* covered by the precedent,
leaving only **B** (`HotkeyUnavailable` cause) and **D** (`HotkeyBinding` const) needing fresh human
ratification. RESEARCH.md § "AD-9 Declaration Edits".

**Do not hand-edit `ARCHITECTURE-SPINE.md` in this phase** — the precedent forbids it; record in the
ledger and hand spine reconciliation to Phase 7.

---

### `lib/src/domain/hotkey/hotkey_bind_outcome.dart` (domain sum type; HOTKEY-08 / D-06)

**Analog: this file itself.** It is already the codebase's best `sealed class` + exhaustive-`switch`
example, and it is the exact type being edited (`:9-51`):

```dart
/// What a bind request resolved to (AD-12).
///
/// Unavailability is a *value*, not an exception: wlroots compositors ship no
/// GlobalShortcuts portal at all, so "no backend would take this binding" is
/// an expected outcome the settings surface and the tray have to render, not
/// a programmer error.
sealed class HotkeyBindOutcome {
  const HotkeyBindOutcome();
}

final class HotkeyUnavailable extends HotkeyBindOutcome {
  const HotkeyUnavailable({required this.message});

  /// Why binding was impossible, in terms a user can act on ("this
  /// compositor provides no global shortcuts portal").
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) { return true; }
    return other is HotkeyUnavailable && message == other.message;
  }

  @override
  int get hashCode => message.hashCode;
}
```

Consumer-side exhaustive switch to keep green — `hotkey_status_view.dart:52-60`:

```dart
    final lines = switch (outcome) {
      null => const ['No shortcut has been requested yet, so nothing is in effect.'],
      HotkeyUnavailable(:final message) => _unavailableLines(message),
      HotkeyBound(:final registration) => _boundLines(registration),
    };
```

**RESEARCH.md decides the shape and rejects the alternative:** add a required, **defaultless** `cause`
enum field (`noBackend`, `keyRefused`, `revoked`) beside the retained `message`. The
sealed-subtype-per-cause route is explicitly rejected: it makes the type non-instantiable and churns
all 20 `lib/` construction sites plus every test naming the type, for the same expressiveness.
Equality/`hashCode` must extend to the new field (follow the two-field shape in `HotkeyRegistration`).

**Construction sites to update (20 in `lib/`, per FLAT-04's sibling entry):**
`x11_global_hotkey.dart:176,245,265,302` (+1), `wayland_portal_global_hotkey.dart` (13, including
`:862`), `settings_controller.dart:432`, `daemon_startup.dart:222`. Inside the Wayland adapter the
cause is assigned in `_messageFor`'s switch and carried out of the handshake by `_PortalRefusal`
(`:1245-1250`), which gains a cause field:

```dart
final class _PortalRefusal implements Exception {
  const _PortalRefusal(this.message);

  /// Already in AD-12's terms — a sentence for a user, naming the tray.
  final String message;
}
```

---

### `lib/src/domain/hotkey/hotkey_binding.dart` (domain value type; HOTKEY-09)

**Analog:** `lib/src/infrastructure/hotkey/hotkey_grab.dart:17-27` — the in-tree precedent, and it
even states the price:

```dart
final class HotkeyGrab {
  HotkeyGrab({
    required Set<HotkeyModifier> modifiers,
    required this.usbHidUsage,
  }) : modifiers = Set<HotkeyModifier>.unmodifiable(modifiers);

  /// Copied on construction rather than held by reference. Equality here is
  /// load-bearing — see below — and a caller that mutated the set it passed in
  /// would silently change what an already-recorded grab compares equal to.
  /// The constructor is therefore not `const`, which is the price.
  final Set<HotkeyModifier> modifiers;
```

Current declaration to edit (`hotkey_binding.dart:5-8`):

```dart
final class HotkeyBinding {
  const HotkeyBinding({required this.modifiers, required this.key});
  final Set<HotkeyModifier> modifiers;
  final String key; // logical key label, e.g. 'Space', 'G'
```

**Cost measured by RESEARCH.md:** 1 `const HotkeyBinding(` site in `lib/`
(`lib/src/infrastructure/config/default_app_config.dart:142`, whose enclosing `AppConfig` is not itself
`const`, so the edit is local) and **24** in `test/`. All 25 are mechanical `const` removals. This is
AD-9 edit **D** — a declared-constructor change needing fresh human ratification, and RESEARCH.md
notes honestly that no live defect exists today.

---

### `lib/src/application/settings_controller.dart` (application; HOTKEY-07 precedence)

**Analog: `applyStartupOutcome` in this same file (`:294-312`)** — the "do not overwrite a newer fact"
guard `changeHotkey` must mirror. Excerpt, with its doc:

```dart
  /// A **seed**, not an assignment: it applies only while nothing is known yet.
  /// The startup bind is not the only thing that can resolve first — the Wayland
  /// adapter subscribes to `ShortcutsChanged` inside `bind()`, so a
  /// compositor-originated change can reach [bindingChanges] and land here before
  /// `bindHotkey`'s own answer is handed over. Overwriting unconditionally would
  /// replace that newer fact with an older one, and nothing would emit again to
  /// correct it.
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
        failure: _state.failure,
        mutationInFlight: _state.mutationInFlight,
      ),
    );
  }
```

The two paths that contradict it today:

```dart
  // :324-333 — last writer wins, unconditional
  void _onBindingChanged(HotkeyBindOutcome outcome) {
    _setState(SettingsState(config: _state.config, hotkeyBindOutcome: outcome, ...));
  }

  // :142-172 — bind() wins unconditionally, with no check for a newer event
  Future<void> changeHotkey(HotkeyBinding binding) async {
    if (!_beginMutation()) { return; }
    try {
      final (outcome, bindFailure) = await _bind(binding);
      final writeFailure = await _writeChange(
        (config) => config.copyWith(hotkeyBinding: binding),
      );
      _setState(SettingsState(config: _currentConfig(), hotkeyBindOutcome: outcome, ...));
    } finally {
      _endMutation();
    }
  }
```

**Existing mechanism to reuse rather than invent:** `_mutating` is already a field *beside* the state
because `_beginMutation` must answer synchronously (`:117-123` doc). A generation counter / latch set
by `_onBindingChanged` during a mutation fits the same slot.

**Collision to flag:** SETTINGS-02 (DW-68) in **Phase 2** also edits `changeHotkey` (bind-before-write
ordering). Two edits to one method across two phases.

---

### Settings key-**capture** control (replaces `lib/src/ui/settings/hotkey_preference_field.dart`)

**Analog A — the file being replaced.** Keep its widget contract and its `didUpdateWidget` re-seed:

```dart
class HotkeyPreferenceField extends StatefulWidget {
  const HotkeyPreferenceField({
    required this.binding,
    required this.authority,
    required this.enabled,     // D-16's busy/read-only lock already exists here
    required this.onApply,
    super.key,
  });
```

```dart
  @override
  void didUpdateWidget(HotkeyPreferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.binding == oldWidget.binding) { return; }
    // The config file changed — this controller's own write landing, or somebody
    // editing the file (AD-13). Either way the stored preference is the truth
    // and the field follows it.
    _modifiers = {...widget.binding.modifiers};
    ...
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }
```

Its `_apply` already builds a **fresh set literal** (`:137-139`), which is why HOTKEY-09 is hardening
rather than a bug fix:

```dart
    widget.onApply(
      HotkeyBinding(modifiers: {..._modifiers}, key: _key.text.trim()),
    );
```

**Analog B — `FocusNode` ownership and disposal**, `lib/src/ui/panel/correction_panel.dart:115-125`
and `:158-164` (allocate as a field / in `initState`, dispose in `dispose`, never in `build`):

```dart
  /// The editor's node lives here, not in [OriginalTextPane], because a
  /// *session* is what decides where the caret belongs…
  final FocusNode _editorFocus = FocusNode(debugLabel: 'panel editor');
  final FocusNode _suggestionsFocus = FocusNode(debugLabel: 'panel suggestions');

  @override
  void dispose() {
    unawaited(_changes.cancel());
    _editorFocus.dispose();
    _suggestionsFocus.dispose();
    super.dispose();
  }
```

And the `Focus` wrapper the capture surface needs so `Tab`/`Escape` are not eaten by traversal
(`correction_panel.dart:335-336`):

```dart
                          child: Focus(
                            focusNode: _suggestionsFocus,
```

Also copy the `includeRepeats: false` reasoning at `:130-134` — RESEARCH.md's "ignore
`KeyRepeatEvent`" pitfall is the same defect one layer down.

**Analog C — the refusal-notice widget** for D-15's reject-at-capture message:
`_NoModifierCaution` (`hotkey_preference_field.dart:239-259`) — a private `StatelessWidget` with
`Semantics(container: true)` and `theme.colorScheme.error`. D-13 turns its caution into a refusal, so
the widget survives as shape and changes as text.

**Vocabulary route — already ratified, do not re-litigate.** DW-71's `decision:` (ledger `:1182`):
the catalogue is supplied **through `SettingsController`**, not imported by `ui` (AD-1 forbids that).
`offeredKeyExamples` (`:19`) and its gate rows go away with the free-text field.

---

### `lib/src/ui/settings/hotkey_status_view.dart` (UI; D-06 three messages + D-07 tray line)

**Analog: this file.** Two things it already does that must survive:

1. **Renders `message` verbatim, appends nothing** (`:94-130`) — the doc is the contract:

```dart
  /// The adapter's [message] is rendered as it stands and nothing is appended to
  /// it: every `HotkeyUnavailable` this codebase produces already ends by naming
  /// the tray as the way in that still works, and a screen that added the
  /// sentence itself printed it twice.
  List<String> _unavailableLines(String message) => [
    message,
    'Whether this app or your desktop would own the shortcut is not known '
        'until one is registered.',
  ];
```

So **D-07's tray line belongs in each adapter's message**, not in this widget — every existing
`HotkeyUnavailable` already ends "the tray menu still opens the panel"
(`x11_global_hotkey.dart:176-180`, `wayland_portal_global_hotkey.dart:862-866`). Verify all three
D-06 causes keep it.

2. **Exhaustive `switch` over `BindingAuthority`, regime and combination chosen together**
(`:153-177`) — but **D-03 drops the regime label from the UI**, which is an amendment to AD-10's
ratified rule (spine line 620). `_regimeOf` and `_regimeWithoutCombination` are what D-03 deletes,
and `_boundLines` is where D-04's verbatim `trigger_description` goes in their place:

```dart
  List<String> _boundLines(HotkeyRegistration registration) {
    final effective = registration.effective;
    if (effective == null) {
      return [_regimeWithoutCombination(registration.authority)];
    }
    return [
      _regimeOf(registration.authority),
      'In effect: ${hotkeyBindingLabel(effective)}',
      if (effective != preference)
        'That differs from your preference, ${hotkeyBindingLabel(preference)}.',
    ];
  }
```

**Coordinate note:** this file is also **SETTINGS-09's subject in Phase 2**. Two phases edit the same
178-line widget; sequence, do not collide.

---

### `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` (validator, not allowlist)

**RESEARCH.md correction C3 replaces CONTEXT.md's premise.** The seven labels are an artefact of
`hotkey_manager`'s own reverse-lookup table (`uni_platform` scanning `kGtkToLogicalKey`), **not** of
X11, keybinder or GTK — measured directly against `libX11.so.6` and GTK3 on 2026-09-01. Once the
plugin is gone the set becomes **empty** and DW-43 closes here.

Current state (`:134-151`):

```dart
  static const Set<String> labelsThatBindTheWrongKey = <String>{
    'Space', 'Tab', 'Enter', 'F1', 'F2', 'F3', 'F4',
  };

  static bool bindsTheWrongKey(String label) =>
      _wrongKeyLabelsByUpperCase.contains(label.trim().toUpperCase());
```

**The validator's new subject** (RESEARCH.md § "HOTKEY-04 after the replacement"): no modifier at all
(D-13), a modifier-only press, a key outside the catalogue, an AltGr/`ISO_Level3_Shift` combination
`HotkeyModifier` cannot represent, and a combination whose `preferred_trigger` cannot be built
(`XdgShortcutTrigger.keysymNameFor(label) == null`).

**The reverse lookup D-14 needs (usage → label) is a derivation, not new data** — copy the shape of
`_usages` (`:162-164`):

```dart
  static final Set<int> _usages = <int>{
    for (final label in labels) usbHidUsageFor(label)!,
  };
```

Capture reads `event.physicalKey.usbHidUsage`, which is exactly the integer this table is keyed on
and that `HotkeyGrab` carries.

---

### `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` — Seam Map (1307 lines)

RESEARCH.md's structural map, cross-checked against the file. **All five CONTEXT.md line numbers
verified correct** (342, 874, 971, 1124, 1135).

| Lines | Section | Exposure |
|---|---|---|
| 1–63 | imports + class doc (a measurement record) | **Edit** — the "`effective` is always null" paragraph becomes "the localized description is carried, never parsed" |
| 64–112 | factory + private ctor (guards `DBusClient.session()` throw) | none |
| 113–221 | fields | **Add** — cached `trigger_description`, `HotkeyStatus?`, sandbox regime |
| 223–256 | `activations`, `bindingChanges`, `bind()` (queue head + 2 pre-queue fast paths) | **Add** — `current` getter |
| 257–357 | `_bind` — the linear AD-11 sequence; terminal `HotkeyBound(effective: null…)` at **:340-345** | **Edit** — step 1 conditional; carry the description |
| 363–456 | `_registerApplicationIdOnce` — step 1, 5 tolerated exception arms | **Edit** — early return when sandboxed (D-18) |
| 462–495 | `_createSession` — step 2 | possibly bounded |
| 497–546 | `_bindShortcut` — step 3 incl. read-back check | **Edit** — capture the description |
| 548–580 | `_shortcutRequest` — builds `description` + `preferred_trigger` | none |
| 582–716 | `_callThroughRequest` — Request/Response machinery | **Edit** — per-call budget lands here (D-17) |
| 718–753 | `_portalSender` | none |
| 755–787 | `_listenForShortcutSignals` — step 4 | consider |
| 789–817 | `_onActivated` — CAP-1 press path, AD-8 budget | none |
| 819–878 | `_onShortcutsChanged`; `effective: null` at **:874** | **Edit** — D-08 forbids any re-claim |
| 887–898 | `_pushBindingChange` | none |
| 906–979 | `_closeSessionBeforeRebinding`; `effective: null` at **:971** | **Edit** — carry the *previous* description |
| 1008–1056 | `dispose()` (has `_teardownBudget`) | none |
| 1058–1066 | `_shutDownDuringBind` | **Edit** — gains a cause |
| 1068–1118 | `_readResponse`, `_shortcutsIn` (null = unreadable, `{}` = discarded — load-bearing) | none |
| 1120–1141 | `_logTriggerDescription` | **Edit** — return it, don't only log it |
| 1143–1240 | `_messageFor`, `_guard`, `_log`, … | **Edit** — cause assignment |
| 1243–1307 | `_PortalRefusal`, `_errorContext`, constants | **Edit** — `_PortalRefusal` gains a cause |

**Four independent slices — plan as four tasks, not one 1307-line task:**
1. sandbox predicate (~30 adapter lines; gated by the ARCH-02 checkpoint, per D-18's reversibility note)
2. cause discriminator (13 sites, mechanical once the domain type exists)
3. description carrier (~60 lines across five methods)
4. bounded bind (one budget through the ctor into `_callThroughRequest`)

Slices 2–4 are independent of each other; all depend on slice 1 only in commit order.

**Description carrier — the value is already extracted** (`:1120-1141`); the edit is to *keep* it:

```dart
  void _logTriggerDescription(
    Map<String, DBusValue>? properties, {
    bool changed = false,
  }) {
    final description = properties?['trigger_description'];
    _log(() => _logger.info(..., context: {
          // Not parsed into a binding on purpose: it is localized,
          // backend-specific, user-readable text…
          'trigger_description': description is DBusString ? description.value : null,
        }));
  }
```

**Sandbox conditional — the reason is already written in-file** (`:363-373`), including why
`/.dockerenv` is not a signal and that the rule is filed as DW-89. Amend that doc; don't replace it
with a fresh justification.

**D-17 carries a reversal the plan must state (RESEARCH.md C4).** `:1300-1307` says the bind path has
**no** timeout *by intent*: "AD-11 makes a portal dialog the user must answer normal, and cancelling
one out from under them would be worse than waiting." D-17 overrides that as a product call and wins —
but the new rule must carry the old reason forward (RESEARCH.md § Pitfall 4).

---

## Shared Patterns

### Bounded request (D-17) — reuse, do not invent a second timeout
**Source:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart:534-553`
**Apply to:** the Wayland adapter's bind path

```dart
  Future<bool> _answered(String call, Future<void> Function() issue) async {
    var answered = true;
    await issue().timeout(
      _requestTimeout,
      onTimeout: () {
        answered = false;
      },
    );
    if (!answered) {
      _log(
        () => _logger.error(
          'the window did not answer $call within '
          '${_requestTimeout.inMilliseconds} ms; the request was abandoned so '
          'the next press is still served',
          context: {'call': call, 'timeout_ms': _requestTimeout.inMilliseconds},
        ),
      );
    }
    return answered;
  }
```

Note the doc at `:530-533`: reported through `onTimeout` + a local flag rather than by catching a
`TimeoutException`, because a seam's own deadline expiring is a *refusal*, not this policy firing.
The budget is injected from `main.dart:114` (`requestTimeout: _unresponsiveCallBudget`), defined at
`main.dart:242` — the new adapter budget follows the same injection route.

### Failure as value (AD-12)
**Source:** `hotkey_bind_outcome.dart:3-11`; `x11_global_hotkey.dart:112-124`, `:176-180`
**Apply to:** every new failure path in this phase (library absent, `XOpenDisplay` null, `BadAccess`,
portal timeout, refused capture)

```dart
    // Answered without the backend: the catalogue is the whole of what this
    // build can register, so a key outside it is a settled "no" rather than a
    // request worth making.
    final usbHidUsage = HotkeyKeyCatalogue.usbHidUsageFor(binding.key);
    if (usbHidUsage == null) {
      return _refusedBeforeBackend(
        key: binding.key,
        message:
            'the key "${binding.key}" is not one this build can register as '
            'an X11 shortcut, so the hotkey is inactive — the tray menu still '
            'opens the panel',
      );
    }
```

`bind()` never throws; every message ends by naming the tray (D-07).

### Logging — never `error.toString()`
**Source:** `wayland_portal_global_hotkey.dart:1252-1256` (identical helper in both adapters)
**Apply to:** all new adapter code.

### Idioms to match verbatim (AGENTS.md §1, "consistency beats taste")
`_queue`, `_guard`, `_log`, `_errorContext`, `_disposed`, `_refuseIfDisposed(String what)` —
identical across both hotkey adapters and the panel adapter.

### Ledger closure (append-only)
**Source:** `_bmad-output/implementation-artifacts/deferred-work.md`
**Apply to:** DW-39, DW-40, DW-42, DW-43, DW-66, DW-71, DW-89; FLAT-02..05, FLAT-11

**Format 1 — canonical `### DW-n:` entries, all fields at column 0.** Open entry, live shape
(`DW-39`, ledger `:766-774`):

```
### DW-39: `keybinder_bind`'s discarded result makes AD-10's "a failed grab must not report success" unsatisfiable through `hotkey_manager`

origin: story 7-x11-global-hotkey-adapter.md, 2026-08-08
location: `hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:95-99`; consumed by lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart
severity: medium
reason: <paragraph, plus an indented continuation paragraph>
status: open
decision: 2026-08-14 Build the `dart:ffi` keybinder registrar — engineering call, …
```

Closed entry, live shape (`DW-95`, ledger `:71-79`) — `resolution:` goes **immediately after**
`status:`, `decision:` (where present) stays:

```
### DW-95: PanelVisibility must flip its isVisible mirror synchronously inside show()/hide()

origin: migrated from legacy ledger (pre-DW-format entries above DW-1), 2026-08-13
source_spec: `_bmad-output/implementation-artifacts/spec-application-layer-controllers.md`
location: n/a
reason: …
status: done 2026-08-07
resolution: Closed by story 5. `WindowManagerPanelVisibility` sets the mirror and emits on `changes` before the first await of `show()`/`hide()` … <file:line evidence, house style>
evidence: …
```

So the edit per entry is: replace `status: open` → `status: done 2026-09-XX`, and insert one
`resolution:` line directly beneath it. Nothing is deleted.

**Format 2 — flat `- source_spec:` entries, bullet at column 0, fields indented exactly two spaces.**
Live shape (`FLAT-02`, ledger `:1438-1441`):

```
- source_spec: `_bmad-output/implementation-artifacts/spec-dw-2-spine-currency-refresh.md`
  summary: `GlobalHotkey.bindingChanges` is a broadcast stream with no replay and the port offers no synchronous current-registration accessor…
  evidence: AD-8 already solves this shape for the panel by pairing a synchronous `bool get isVisible` with `Stream<bool> get changes`…
  status: open
```

No `origin:`, `location:`, `severity:`, `reason:` or `decision:` on these. Closure:

```
  status: done 2026-09-XX
  resolution: <what closed it, with file:line evidence>
```

**Two-space indent is load-bearing** — get it wrong and the entry is invisible to `bmad-loop sweep`.

**Ledger line index (verified):** DW-39 `:766`, DW-40 `:776`, DW-66 `:1129`, DW-71 `:1175`,
DW-89 `:1342` (its `decision:` at `:1349` names **four** packaging formats vs D-18's three — C1's
contradiction, for the human at the ARCH-02 checkpoint). FLAT-02 `:1438`, FLAT-03 `:1443`,
FLAT-04 `:1448`, FLAT-05 `:1453`, FLAT-11 `:1483`. Verify each is still `status: open` before writing.

---

## Existing-Gate Maintenance (not new test work)

Rows that go red when `hotkey_manager` and its seam are deleted. Current text so the planner can
instruct a precise re-point.

**`test/architecture/hotkey_confinement_test.dart`**

`:48-62` — becomes `[]` vs `[_seamFile]`:

```dart
  test('AD-1: exactly one file under lib/ names package:hotkey_manager', () {
    expect(
      _filesReferencing('package:hotkey_manager/'),
      [_seamFile],
      reason: 'nothing above the seam may see a HotKey, a keyval or a channel …',
    );
  });
```

`:78-112` — the Flutter-import scan; the `package:flutter/` arm expects `[_seamFile]` and becomes `[]`:

```dart
      expect(
        _filesReferencing(reference).where((path) => path.startsWith(_hotkeyDirectory)),
        reference == 'package:flutter/' ? [_seamFile] : isEmpty,
        reason: '… The exemption list stays at exactly one file, the hotkey_manager seam …',
      );
```

**Re-point, do not weaken:** with the seam gone the exemption list should become **empty for every
reference**, which is a strictly stronger gate — and the new registrar's `dart:ffi` / `dart:isolate`
imports are not in the scanned list. RESEARCH.md § Pitfall 2 warns this red will look like a regression.

`:365-380` — the "the scan actually finds something" row:

```dart
    expect(_filesReferencing('package:hotkey_manager'), isNotEmpty);
    ...
    expect(File(_seamFile).existsSync(), isTrue);
```

`:533-538` — the constants to re-point or delete:

```dart
const String _settingsDirectory = 'lib/src/ui/settings/';
const String _hotkeyDirectory = 'lib/src/infrastructure/hotkey/';
const String _seamFile =
    'lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart';
const String _waylandAdapterFile =
    'lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart';
```

`:221-313` — two rows read `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` and `offeredKeyExamples`
from `hotkey_preference_field.dart`; D-14 deletes that widget and C3 empties that set.

**`test/architecture/composition_wiring_test.dart:862-868, 894-903`** — asserts the literal:

```dart
    expect(
      main,
      contains('final hotkeyRegistrar = HotkeyManagerRegistrar();'),
      reason: 'this is the only file allowed to name the hotkey_manager adapter, '
          'and the local is what the abort path closes over',
    );
    ...
    expect(main.indexOf('HotkeyManagerRegistrar()'), isNonNegative, …);
    expect(main.indexOf('if (startup == null)'), isNonNegative);
    expect(
      main.indexOf('HotkeyManagerRegistrar()'),
      lessThan(main.indexOf('if (startup == null)')),
      reason: 'DaemonStartup.begin cannot choose the X11 adapter without it',
    );
```

The composition sites those rows mirror: `lib/main.dart:65` (`final hotkeyRegistrar = HotkeyManagerRegistrar();`),
`:70` (`registrar: hotkeyRegistrar,`), `:418` (a doc comment naming the type), and
`daemon_lifecycle.dart:55-64` (`_closeHotkeyRegistrar`). Substituting the type is a one-word change at
each site; the *gate* rows are the work.

**Deleted with the seam:** `test/platform/hotkey_manager_registrar_test.dart` (608 lines).
**Comment-only:** `test/fakes/fake_hotkey_registrar.dart:24`.
**Survives:** `test/infrastructure/hotkey/x11_global_hotkey_test.dart` (739 lines) — the port stays.

**Baseline command (C10) — a bare `dart test` is wrong in this tree:**

```
dart test --exclude-tags=live \
  test/application test/architecture test/domain test/infrastructure \
  test/fakes_smoke_test.dart      # 946 passed / 2 skipped / 0 failed, 58 s
```

---

## Deletions

| File | Lines | Note |
|---|---|---|
| `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart` | 242 | Its two measured facts (the `keybinder_bind` discard, `std::map::insert` non-overwrite, `keybinder_unbind`-on-uninitialised-pointer) live **only** in its doc comments. RESEARCH.md § Pitfall 5: re-home them into the ledger closures or retire them deliberately, never silently. |
| `test/platform/hotkey_manager_registrar_test.dart` | 608 | goes with the seam |
| `pubspec.yaml:37` `hotkey_manager: 0.2.3` | 1 | load-bearing: `generated_plugins.cmake` links every `FLUTTER_PLUGIN_LIST` entry unconditionally, putting `libhotkey_manager_linux_plugin.so` in the runner's own `DT_NEEDED`. `FLUTTER_FFI_PLUGIN_LIST` does **not** call `target_link_libraries` — which is why an FFI route closes D-11 where `dlopen` inside a linked plugin would not. Add `ffi: 2.2.0` (already `dependency: transitive` at that exact version). |

Current `pubspec.yaml` block:

```yaml
dependencies:
  flutter:
    sdk: flutter

  dbus: 0.7.14
  drift: 2.34.3
  flutter_riverpod: 3.4.2
  hotkey_manager: 0.2.3        # <- delete this line
  sqlite3: 3.5.1
  tray_manager: 0.5.3
  window_manager: 0.5.2
```

---

## No Analog Found

Stated as gaps rather than filled with a distant analog.

| Gap | File | Role | Data Flow | Why |
|---|---|---|---|---|
| **G1** | the `dart:ffi` binding block in `x11_key_grab_registrar.dart` | vendor binding | request-response | **No `dart:ffi` code exists anywhere in `lib/`.** The only `lib/` mentions of "ffi" are prose in `hotkey_registrar.dart` and `hotkey_key_catalogue.dart` doc comments; the rest are test/checklist references. There is no in-tree example of `DynamicLibrary.open`, a `typedef`d native signature, `Pointer` arithmetic, `NativeCallable`, or `calloc`/`Utf8`. Nearest *discipline* analog is the Wayland adapter's private-`DBusClient` confinement (cited above), which teaches confinement but not FFI mechanics. Use RESEARCH.md § Pattern 1's skeleton and constants (`_lockMask`, `_mod2Mask`, `_badAccess = 10`, `_xGrabKeyRequest = 33`, the four ignored-modifier states) as the primary source. |
| **G2** | the helper isolate | background worker | event-driven | **No `Isolate.spawn`, no `SendPort`, no background isolate anywhere in `lib/`.** The daemon is explicitly single-isolate ("no worker threads or isolates" — CLAUDE.md § Architectural Constraints). This is the first, and the `dispose()` ordering it needs has no precedent. Closest lifecycle analog is `HotkeyManagerRegistrar.dispose()`'s `finally`-close discipline; the isolate teardown itself is new. RESEARCH.md offers a documented fallback if isolate lifecycle proves awkward under `dispose()`: a `Timer.periodic` on the main isolate calling `XPending`/`XNextEvent` (non-blocking), at the cost of FFI calls on the Flutter isolate. |
| — | Flatpak manifest / `.deb` / AppImage recipes | packaging | — | Out of scope by design: ARCH-02 requires only the **decision, recorded**. No packaging analog is needed, and none exists (`linux/` holds only the Flutter runner scaffolding). |

Two further items are *decisions*, not code, and have no analog by nature: the ARCH-02
three-vs-four-format contradiction (C1) and the two AD-9 ratifications (edits **B** and **D**).

---

## Open behaviour the analogs cannot settle (flag to the human)

RESEARCH.md raises one user-visible behaviour D-14/D-16 do not cover: **on X11 the currently-bound
combination cannot be re-captured** — while the passive grab is held, pressing it goes to the grab,
not to the settings window. Two workable answers (release the grab for the duration of capture, or
treat "no key event arrived" as "that is already your shortcut"). No in-tree analog exists for either.

---

## Metadata

**Analog search scope:** `lib/src/domain/hotkey/`, `lib/src/domain/correction/`,
`lib/src/infrastructure/hotkey/`, `lib/src/infrastructure/panel/`, `lib/src/infrastructure/system/`,
`lib/src/application/`, `lib/src/ui/settings/`, `lib/src/ui/panel/`, `lib/main.dart`,
`test/architecture/`, `pubspec.yaml`, `_bmad-output/implementation-artifacts/deferred-work.md`
**Files read in full or in targeted ranges:** 18
**Tracked-source check:** `git ls-files` run over every cited `lib/` and `test/` path — all tracked
**Pattern extraction date:** 2026-09-01
