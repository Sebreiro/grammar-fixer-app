import 'package:flutter/material.dart';

import '../../domain/correction/suggestion_register.dart';
import 'suggestion_card.dart';

/// The register variants, top to bottom in `SuggestionRegister.values` order
/// (AD-6), in a scrollable of their own.
///
/// The scrollable is what makes CAP-10 hold: the original keeps its share of
/// the panel however long the suggestions get, so a variant is always readable
/// beside it rather than pushed off the bottom.
/// Selecting also brings the selected card into view. The highlight is the only
/// answer a digit key gives (AD-18 keeps it from copying), so a highlight
/// painted below the fold is CAP-4's key doing nothing visible — the same
/// broken affordance DW-3 was filed about. Where this list is scrolled to is its
/// own ephemeral UI concern, which is exactly what the "State mutation"
/// convention leaves to a widget.
class SuggestionList extends StatefulWidget {
  const SuggestionList({
    required this.texts,
    required this.selectedRegister,
    required this.completed,
    required this.onSelect,
    required this.onCopy,
    this.copyRegister,
    this.copyPending = false,
    this.copySucceeded = false,
    this.copyFailure,
    super.key,
  });

  /// Text per register, as the controller holds it. A register with no entry
  /// yet renders as an empty card rather than disappearing, so the list does
  /// not reflow as deltas arrive (CAP-5).
  final Map<SuggestionRegister, String> texts;

  final SuggestionRegister? selectedRegister;

  /// Whether the session's answer is authoritative (AD-3). Passed down rather
  /// than resolved into a nullable callback here, so each card decides whether
  /// it is actionable from this *and* its own text, in one place.
  final bool completed;

  final void Function(SuggestionRegister register) onCopy;
  final void Function(SuggestionRegister register) onSelect;
  final SuggestionRegister? copyRegister;
  final bool copyPending;
  final bool copySucceeded;
  final String? copyFailure;

  @override
  State<SuggestionList> createState() => _SuggestionListState();
}

class _SuggestionListState extends State<SuggestionList> {
  /// One stable key per register, so the newly selected card can be located
  /// after the frame that highlighted it. Keyed by the enum (AD-6), not by
  /// position.
  final Map<SuggestionRegister, GlobalKey> _cardKeys = {
    for (final register in SuggestionRegister.values) register: GlobalKey(),
  };

  /// This list's own viewport, so that bringing a card into view scrolls *this*
  /// list and nothing else.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SuggestionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedRegister;
    if (selected == null || selected == oldWidget.selectedRegister) {
      // Nothing new is selected: a deselect leaves the list where the user
      // scrolled it, and re-scrolling on every unrelated rebuild would fight
      // them for the scroll position.
      return;
    }
    // After the frame, because this card's geometry is what decides how far to
    // scroll and it has not been laid out yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cardContext = _cardKeys[selected]?.currentContext;
      final renderObject = cardContext?.findRenderObject();
      if (cardContext == null ||
          !cardContext.mounted ||
          renderObject == null ||
          !_scroll.hasClients) {
        return;
      }
      // This position, not `Scrollable.ensureVisible`: that walks *every*
      // scrollable ancestor, and below the panel's height floor the panel
      // itself is one. A digit press then scrolled the user's own text
      // entirely off the top of the panel — CAP-10 defeated by CAP-4's key,
      // with no way back and the offset surviving into the next session.
      _scroll.position.ensureVisible(renderObject, duration: Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    // A scroll view over a `Column`, not a `ListView`: the list is one card per
    // `SuggestionRegister.values` — three, fixed at compile time — and a lazy
    // sliver would not build a card below the fold at all, which is exactly the
    // card [didUpdateWidget] has to scroll to.
    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final register in SuggestionRegister.values)
            SuggestionCard(
              key: _cardKeys[register],
              register: register,
              text: widget.texts[register] ?? '',
              selected: register == widget.selectedRegister,
              completed: widget.completed,
              onSelect: () => widget.onSelect(register),
              onCopy: () => widget.onCopy(register),
              copyPending:
                  register == widget.copyRegister && widget.copyPending,
              copySucceeded:
                  register == widget.copyRegister && widget.copySucceeded,
              copyFailure: register == widget.copyRegister
                  ? widget.copyFailure
                  : null,
            ),
        ],
      ),
    );
  }
}
