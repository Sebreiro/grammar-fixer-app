import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/hotkey_capture.dart';
import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import 'hotkey_binding_label.dart';

/// The combination the user sets by **pressing it** (D-14), with everything the
/// app can already tell will not fire refused at capture (D-15).
///
/// It replaces the key-label text field, and the reason is the field's own: a
/// user should not have to know their key is called `Pause` or
/// `ISO_Level3_Shift` to bind it. What the capture reads is
/// `KeyEvent.physicalKey.usbHidUsage` — exactly the integer the key vocabulary
/// is keyed on and that a grab carries — so the lookup is direct, independent of
/// the keyboard layout, and works for a key whose label the user could never
/// guess.
///
/// Labelled by regime, because the label is the only place the control itself
/// can be honest about what pressing Apply means (AD-10): on X11 it is the
/// shortcut, on Wayland it is a *preference* the compositor may not honour. The
/// regime comes from the outcome the backend returned, so before anything has
/// been attempted the label claims neither.
///
/// Owns only ephemeral UI — the focus node and the combination being edited.
/// The combination that *matters* is the one the config file holds, and the only
/// way this widget changes it is by calling [onApply], which goes through the
/// settings controller and so through the store (AD-13).
///
/// **Nothing here is logged, and that is a rule rather than an omission**
/// (T-01-41). This is the one surface in the app that reads raw key events; a
/// capture control that wrote what it saw to stderr would be a keylogger with a
/// settings screen in front of it. There is no logger in this file.
class HotkeyCaptureField extends StatefulWidget {
  const HotkeyCaptureField({
    required this.binding,
    required this.authority,
    required this.enabled,
    required this.validator,
    required this.onApply,
    super.key,
  });

  /// The preference the config file holds, which is what this control starts
  /// from and what it snaps back to when an external edit changes it.
  final HotkeyBinding binding;

  /// Who owns the binding, or null when no bind has been attempted yet.
  ///
  /// Read for two things: the label above, and whether the standing hint about
  /// the current shortcut applies — see [_CurrentShortcutHint].
  final BindingAuthority? authority;

  /// False while a mutation is in flight (D-16): the control is read-only, and
  /// nothing is displayed as in effect before it is. The controller has no
  /// mutation-generation guard, and two overlapping requests resolve
  /// last-completion-wins, so removing the case a user can cause is the point.
  final bool enabled;

  /// The four-subject capture validator, supplied by `SettingsController`
  /// (DW-71). It is passed in rather than reached for because the vocabulary it
  /// holds is built at the composition root: AD-1 forbids this ring — and the
  /// application ring — from importing the infrastructure key catalogue.
  final HotkeyCaptureValidator validator;

  final ValueChanged<HotkeyBinding> onApply;

  @override
  State<HotkeyCaptureField> createState() => _HotkeyCaptureFieldState();
}

class _HotkeyCaptureFieldState extends State<HotkeyCaptureField> {
  /// Allocated once, as a field, and disposed in [dispose] — never allocated in
  /// `build`, which is the panel editor's rule for the same reason
  /// (`correction_panel.dart:115-125`).
  final FocusNode _capture = FocusNode(debugLabel: 'hotkey capture');

  /// The combination as the user is setting it. Seeded from the preference and
  /// re-seeded only when the preference itself changes underneath — otherwise a
  /// rebuild would discard a combination the user had just pressed.
  late HotkeyBinding _combination = widget.binding;

  /// The last refusal, or null when the last capture was accepted.
  ///
  /// A refusal keeps [_combination] as it was: the user never saves something
  /// broken and never waits until Apply to find out (D-15).
  HotkeyCaptureRefused? _refusal;

  @override
  void initState() {
    super.initState();
    // The surface renders differently while it is listening, so a focus change
    // is a rebuild. Registered here and removed in [dispose].
    _capture.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(HotkeyCaptureField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.binding == oldWidget.binding) {
      return;
    }
    // The config file changed — this controller's own write landing, or somebody
    // editing the file (AD-13). Either way the stored preference is the truth
    // and the control follows it, refusal and all.
    _combination = widget.binding;
    _refusal = null;
  }

  @override
  void dispose() {
    _capture.removeListener(_onFocusChanged);
    _capture.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  /// Every key event the capture surface sees, answered `handled` whether or not
  /// it committed anything.
  ///
  /// **`handled` is what makes `Tab` and `Escape` reachable at all**: returning
  /// `ignored` hands them to focus traversal and to whatever else is listening,
  /// so the two keys the user is most likely to want in a shortcut are the two
  /// they could never capture. It matters more now than it used to — the seven
  /// labels the removed vendor plugin bound to the wrong key included `Tab`, and
  /// with the plugin gone `Tab` is bindable again.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      // D-16: read-only while a bind is in flight. `ignored` rather than
      // `handled`, so a disabled control does not swallow the keyboard.
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) {
      // `HardwareKeyboard` delivers one `KeyDownEvent`, zero or more
      // `KeyRepeatEvent`s and one `KeyUpEvent`, all with the same keys. Acting
      // on a repeat would re-commit the capture for as long as the user held
      // the key down — the defect `correction_panel.dart:130-134` keeps out
      // with `includeRepeats: false`, one layer below this one.
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      // A key-up carries nothing the key-down did not already say.
      return KeyEventResult.handled;
    }

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifiers = _modifiersHeld(pressed);
    final levelThree = _usesLevelThree(pressed, event.logicalKey);

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        modifiers.isEmpty &&
        !levelThree) {
      // The one key treated as an exit rather than as a capture, and it has to
      // be one: this handler answers `handled` for everything, so focus
      // traversal cannot move the user out of the control with the keyboard.
      // `Escape` is still bindable — with a modifier, which every shortcut
      // needs anyway (D-13) — so nothing is lost by spending the bare press.
      setState(() => _refusal = null);
      _capture.unfocus();
      return KeyEventResult.handled;
    }

    final verdict = widget.validator.verdictFor(
      HotkeyCapture(
        modifiers: modifiers,
        usbHidUsage: event.physicalKey.usbHidUsage,
        keyIsModifier: _isModifierKey(event.logicalKey),
        usesLevelThreeModifier: levelThree,
      ),
    );
    setState(() {
      switch (verdict) {
        case HotkeyCaptureAccepted(:final binding):
          _combination = binding;
          _refusal = null;
        case HotkeyCaptureRefused():
          _refusal = verdict;
      }
    });
    return KeyEventResult.handled;
  }

  void _apply() {
    if (!widget.enabled) {
      return;
    }
    // A fresh set, never the one this widget goes on holding.
    widget.onApply(
      HotkeyBinding(
        modifiers: {..._combination.modifiers},
        key: _combination.key,
      ),
    );
  }

  /// Abandons whatever was captured and goes back to the stored preference —
  /// the "keep current" affordance Task 1's `explain-in-place` answer asks for.
  ///
  /// It writes nothing and binds nothing. Keeping the current shortcut *is* the
  /// absence of a change, so an affordance that wrote would be claiming to do
  /// something it should not.
  void _keepCurrent() {
    setState(() {
      _combination = widget.binding;
      _refusal = null;
    });
    _capture.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final refusal = _refusal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_fieldLabel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Focus(
          focusNode: _capture,
          onKeyEvent: _onKeyEvent,
          child: _CaptureSurface(
            combination: hotkeyBindingLabel(_combination),
            capturing: _capture.hasFocus && widget.enabled,
            enabled: widget.enabled,
            onTap: widget.enabled ? _capture.requestFocus : null,
          ),
        ),
        if (refusal != null) ...[
          const SizedBox(height: 8),
          _CaptureNotice(
            text: refusal.reason,
            // A modifier on its own is not a mistake — it is the first half of
            // every legitimate combination — so it is said in the ordinary
            // voice. Every other refusal is a change the user asked for and did
            // not get, which is what the error colour is for.
            isRefusal: refusal.refusal != HotkeyCaptureRefusal.modifierOnly,
          ),
        ],
        // Standing text, up before anything is pressed rather than after a
        // capture that looked broken.
        if (widget.authority == BindingAuthority.application) ...[
          const SizedBox(height: 8),
          _CurrentShortcutHint(
            binding: widget.binding,
            onKeepCurrent: widget.enabled ? _keepCurrent : null,
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: widget.enabled ? _apply : null,
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }

  /// Names what Apply does under this regime, exhaustively over
  /// [BindingAuthority] plus the not-yet-known case.
  String get _fieldLabel => switch (widget.authority) {
    BindingAuthority.application => 'Shortcut',
    BindingAuthority.compositor => 'Shortcut preference',
    // Nothing has been asked of a backend yet, so neither claim is available.
    null => 'Shortcut to request',
  };
}

/// The surface the combination is pressed into.
///
/// Deliberately not a `TextField`: there is nothing to type. It reads as a field
/// so it is recognisable as the control that holds the shortcut, and it says
/// which of its two states it is in, because a control that looks the same
/// whether or not it is listening is a control that looks broken while it waits.
class _CaptureSurface extends StatelessWidget {
  const _CaptureSurface({
    required this.combination,
    required this.capturing,
    required this.enabled,
    required this.onTap,
  });

  final String combination;
  final bool capturing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = capturing
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Shortcut, currently $combination',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: outline, width: capturing ? 2 : 1),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          // A column, not a row. The row this replaces overflowed by 76px the
          // first time a narrow window was measured: two texts side by side
          // with only one of them flexible cannot both fit, and nothing sizes
          // this window (deferred work) so a user can drag it to any width.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                combination,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: enabled
                      ? null
                      : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              Text(
                capturing
                    ? 'Press the combination'
                    : 'Click here, then press a combination',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the capture refused, or what it is still waiting for, said where the
/// user is looking.
///
/// Carried over in shape from the caution this replaces: its own semantics node,
/// because it is a consequence the user is about to cause — or has just failed
/// to — and a reader who cannot see it gets it only if it is announced as its
/// own statement rather than merged into the control above it. D-13 turned that
/// caution into a refusal, so the shape survives and the text does not.
///
/// No notification, no dialog, no sound (D-09): a refusal is inline text.
class _CaptureNotice extends StatelessWidget {
  const _CaptureNotice({required this.text, required this.isRefusal});

  final String text;

  /// Whether this is a refusal rather than the capture saying what it is
  /// waiting for.
  final bool isRefusal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isRefusal
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Why the shortcut the user already has cannot be pressed into this control,
/// said before they try it.
///
/// **The mechanism, stated out loud, on purpose.** While the app holds an X11
/// passive grab on the current combination, the X server delivers it to the
/// grabbing client rather than to the focused window — measured on 2026-09-02
/// against a private X server: the focused window receives the modifier
/// down/up events and never the terminating key. So a user who presses their
/// existing shortcut here gets a control that appears to ignore them. The
/// alternatives were to release the grab for the duration of the capture (a new
/// lifecycle obligation on a path that has none, and a window where the
/// shortcut does not work) or to infer "that is already your shortcut" from the
/// absence of a key event (a heuristic, and the measurement shows the absence
/// is indistinguishable from a user idly pressing Ctrl and Shift). Both were
/// rejected in favour of telling the user the truth. Recorded cost: this states
/// a difference between the display servers, which D-03's "one UI everywhere,
/// mechanism hidden" argues against. It was weighed and accepted.
///
/// It is standing text and not a transient, and it renders **before** the first
/// keypress: a hint that appeared only after a failed capture would be
/// indistinguishable from the control being broken.
///
/// Shown only where the claim is true — when the *application* owns the binding,
/// which is the X11 grab. Under the portal the compositor owns it and ordinary
/// key events still reach a focused window, and before any backend has answered
/// nothing is held for the grab to swallow.
class _CurrentShortcutHint extends StatelessWidget {
  const _CurrentShortcutHint({
    required this.binding,
    required this.onKeepCurrent,
  });

  final HotkeyBinding binding;

  /// Null while a bind is in flight, for the reason every other control is
  /// disabled then (D-16).
  final VoidCallback? onKeepCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your current shortcut, ${hotkeyBindingLabel(binding)}, cannot be '
            'pressed into this box: while it is registered it goes to this app '
            'instead of to this window. Press a different combination, or keep '
            'the one you have.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onKeepCurrent,
              child: const Text('Keep current'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The modifiers held, out of the keys Flutter reports as pressed.
///
/// Derived from [HotkeyModifier.values] rather than written out, so a fifth
/// modifier is read here without anyone remembering to add it.
Set<HotkeyModifier> _modifiersHeld(Set<LogicalKeyboardKey> pressed) {
  return <HotkeyModifier>{
    for (final modifier in HotkeyModifier.values)
      if (_keysFor(modifier).any(pressed.contains)) modifier,
  };
}

/// Whether the combination uses AltGr / Level 3, which must be **refused** and
/// never folded into [HotkeyModifier.alt].
///
/// The predicate is the **logical** key `altGraph`, not the physical
/// `altRight`. That distinction is the whole of what makes the refusal correct
/// rather than merely safe: on a layout that maps Level 3 to the right Alt key
/// the embedder reports `altGraph`, and on one that does not the same physical
/// key reports an ordinary `altRight` — so keying on the physical key would
/// refuse a legitimate `Alt` combination for every user on a US layout.
///
/// Folding it into `alt` was the alternative and is worse than refusing:
/// `HotkeyModifier` has exactly four values and none of them is Level 3, so the
/// combination would serialize to a plain Alt shortcut that fires on a
/// different physical key — a shortcut that looks right on screen and is wrong
/// on the keyboard.
///
/// That AltGr surfaces on Linux GTK as a logical `altGraph` is what makes this
/// predicate fire at all, and it is observed rather than assumed — it was
/// flagged assumption A3, settled twice on a live GTK session. The 01-07 run
/// (2026-09-02) drove `ISO_Level3_Shift+g` at the running daemon and got the
/// Level 3 refusal; UAT test 9 (2026-09-04) repeated it under an `altgr-intl`
/// layout, where AltGr alone and AltGr+E each rendered the refusal and the
/// shortcut stayed as it was. Both drove the keys with XTEST, not a physical
/// keyboard — which is enough for this claim rather than a gap in it, because
/// what is under test is a keymap translation that never learns how the event
/// was produced. `settings_screen_hotkey_test.dart`'s AltGr row is what pins
/// the behaviour now.
///
/// The consequence stands on its own either way — `hotkey_binding.dart`
/// declares four modifiers and no Level 3 — so if the mapping ever differed,
/// this predicate is what would have to change, not the refusal.
bool _usesLevelThree(Set<LogicalKeyboardKey> pressed, LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altGraph ||
    pressed.contains(LogicalKeyboardKey.altGraph);

/// Whether [key] is a modifier, so that pressing it commits nothing and the
/// capture keeps waiting for the key to go with it.
bool _isModifierKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altGraph ||
    key == LogicalKeyboardKey.fn ||
    HotkeyModifier.values.any((modifier) => _keysFor(modifier).contains(key));

/// The logical keys that produce [modifier].
///
/// Both sides of each pair, plus Flutter's own synonym: `logicalKeysPressed`
/// reports the side-specific key, and the synonym is what a synthesized event
/// may carry. An exhaustive `switch` with no default, so a fifth
/// [HotkeyModifier] does not compile until someone says which keys produce it.
///
/// The sets are not `const`, and cannot be: `LogicalKeyboardKey` overrides
/// `==`, which a constant set may not contain.
Set<LogicalKeyboardKey> _keysFor(HotkeyModifier modifier) => switch (modifier) {
  HotkeyModifier.control => {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  },
  HotkeyModifier.alt => {
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  },
  HotkeyModifier.shift => {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  },
  HotkeyModifier.meta => {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  },
};
