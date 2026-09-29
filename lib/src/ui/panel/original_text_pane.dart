import 'package:flutter/material.dart';

/// The panel's micro-editor (CAP-3) and its Correct action.
///
/// Owns nothing but its own ephemeral UI — a [TextEditingController] and a
/// [FocusNode] (Consistency Conventions, "State mutation"). The text itself
/// belongs to `CorrectionController`, which re-seeds it from the clipboard when
/// a session begins — the summon after a dismissal, not every show (CAP-2,
/// AD-18, DW-30); this widget renders that re-seed rather than holding a copy of
/// it.
class OriginalTextPane extends StatefulWidget {
  const OriginalTextPane({
    required this.text,
    required this.focusNode,
    required this.onChanged,
    required this.onCorrect,
    super.key,
  });

  /// The session's editor text, as the controller currently holds it.
  final String text;

  /// Owned by the panel, because where the caret belongs is a *session*
  /// question: `autofocus` fires once per mount, and a session can begin without
  /// one — the window stays up between summons (AD-8) and the panel is rebuilt
  /// rather than remounted — so only something that sees a session begin can
  /// bring focus back for the second summon.
  ///
  /// The premise used to be stated as "this tree is never rebuilt", which the
  /// settings view swap made false: returning from settings unmounts and
  /// remounts this pane, and `autofocus` does fire on that path.
  ///
  /// That correction also said "the behaviour is unchanged", which DW-30 has
  /// since made too strong. While every show began a session, the two signals
  /// could not disagree: a remount and a session arrived together. Under the
  /// three-way rule a return can begin no session at all, so the remount path is
  /// now the one place where `autofocus` puts the caret in the editor without a
  /// session having asked for it — a summon after a click-away or an iconify,
  /// arriving while settings is up. Left as it is rather than removed: the user
  /// is being handed the panel, and the editor is where a panel's caret belongs.
  /// What changed is that this is now `autofocus`'s own decision on that path
  /// instead of an echo of the session rule, and the two no longer agree by
  /// construction.
  final FocusNode focusNode;

  final ValueChanged<String> onChanged;

  /// Null renders the Correct action disabled — DW-3's missing affordance for
  /// the controller's empty-submit invariant. The panel owns the predicate, so
  /// the keyboard accelerator and this button cannot disagree about it.
  final VoidCallback? onCorrect;

  @override
  State<OriginalTextPane> createState() => _OriginalTextPaneState();
}

class _OriginalTextPaneState extends State<OriginalTextPane> {
  late final TextEditingController _text = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(OriginalTextPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _text.text) {
      // The common case: this rebuild is the controller echoing back the
      // keystroke that caused it. Writing the field again would move the caret
      // to the end of the line the user is editing in the middle of.
      return;
    }
    _text.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: widget.text.length),
    );
  }

  @override
  void dispose() {
    // The focus node is the panel's and is disposed there; this pane owns only
    // the editing controller.
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your text', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        // Expanded plus `expands`: the editor takes a bounded share of the
        // panel and scrolls inside it, so a long original cannot push the
        // variants off screen (CAP-10).
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: widget.focusNode,
            autofocus: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            onChanged: widget.onChanged,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          // The accelerator, said out loud. The panel dims a variant's 1/2/3
          // hint when the key would do nothing, so the one keystroke it never
          // mentioned at all was the one that starts the correction — on a
          // surface whose whole premise is that it is driven from the keyboard.
          child: Tooltip(
            message: 'Correct (Ctrl+Enter)',
            child: ElevatedButton(
              onPressed: widget.onCorrect,
              child: const Text('Correct'),
            ),
          ),
        ),
      ],
    );
  }
}
