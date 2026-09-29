import 'package:flutter/material.dart';

import '../../domain/correction/suggestion_register.dart';
import 'register_key_slot.dart';

/// One register variant: its selecting key, its label, its text, and its own
/// copy button (CAP-4, CAP-11).
///
/// Both the key hint and the label are *derived* from the enum — the hint from
/// `SuggestionRegister.values.indexOf(register) + 1` (AD-6) and the label from
/// `register.name` — so reordering or renaming a register cannot leave this
/// card claiming the wrong key or the wrong name.
///
/// The card is also where "is this variant actionable" is decided, once, from
/// [completed] and its own [text]: the copy button and the key hint must agree,
/// and a hint that promises a key the controller will ignore is the same broken
/// affordance DW-3 was filed about.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    required this.register,
    required this.text,
    required this.selected,
    required this.completed,
    required this.onSelect,
    required this.onCopy,
    this.copyPending = false,
    this.copySucceeded = false,
    this.copyFailure,
    super.key,
  });

  final SuggestionRegister register;

  /// Whatever the controller currently holds for [register]: the accumulated
  /// deltas while the correction runs (CAP-5), the authoritative completed text
  /// once it has (AD-3).
  final String text;

  /// AD-18's highlight. Selecting never copies, so this changes nothing but
  /// the card's appearance.
  final bool selected;

  /// Whether the session's answer is the authoritative one (AD-3). False while
  /// deltas are still arriving, when nothing on this card is actionable.
  final bool completed;

  final VoidCallback onSelect;
  final VoidCallback onCopy;
  final bool copyPending;
  final bool copySucceeded;
  final String? copyFailure;

  /// Whether this variant can be copied and selected at all.
  ///
  /// The same test the controller applies (`trim()`, not `isEmpty`): a variant
  /// that came back as spaces is not something to put over the user's clipboard
  /// and not something to highlight, so it must not look as though it were.
  bool get actionable => completed && text.trim().isNotEmpty;

  /// The 1/2/3 key that selects this card, or null past the digit row.
  ///
  /// Shares one derivation with the activator the panel listens for, so the
  /// hint cannot promise a key that selects another row (AD-6).
  String? get keyHint =>
      keySlotHintForIndex(SuggestionRegister.values.indexOf(register));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = keyHint;
    final copyStatusText = copyPending
        ? 'Copying…'
        : copySucceeded
        ? 'Copied'
        : copyFailure == null
        ? null
        : copyFailure == 'There is no suggestion text to copy.'
        ? copyFailure
        : "Couldn't copy this suggestion. Try again.";
    return Semantics(
      container: true,
      selected: selected,
      label: '${register.name} suggestion',
      child: Card(
        color: selected ? theme.colorScheme.primaryContainer : null,
        child: InkWell(
          onTap: actionable && !selected ? onSelect : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          hint,
                          style: theme.textTheme.labelLarge?.copyWith(
                            // Dimmed while the key would do nothing, the way the
                            // copy button beside it is disabled: the hint is a
                            // promise about a keystroke and must not outlive it.
                            color: actionable
                                ? theme.colorScheme.onSurface
                                : theme.disabledColor,
                          ),
                        ),
                      ),
                    // Flexible, not bare: nothing sizes the window or sets a
                    // minimum width for it either, so a narrow drag has to
                    // ellipsise the label rather than overflow the row and clip the
                    // copy button out of reach.
                    Flexible(
                      child: Text(
                        register.name,
                        style: theme.textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.check,
                          size: 18,
                          semanticLabel: '${register.name} selected',
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: actionable ? onCopy : null,
                      // Named, because three visually identical buttons are
                      // indistinguishable to a screen reader — and CAP-11 is
                      // "each suggestion has its own button".
                      tooltip: 'Copy the ${register.name} suggestion',
                      icon: const Icon(Icons.copy, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (copyStatusText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      label: '${register.name} suggestion $copyStatusText',
                      child: Row(
                        children: [
                          if (copyPending)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              copyStatusText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: copyFailure == null
                                    ? null
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
