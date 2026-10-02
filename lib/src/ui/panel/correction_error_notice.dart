import 'package:flutter/material.dart';

/// CAP-13's inline failure: the provider's own message, with a Retry beside it,
/// rendered *in place of* the empty or half-streamed variants.
///
/// Deliberately a widget in the panel's own tree and nothing else — no
/// `SnackBar`, no `showDialog`, no second window. CAP-13 says the user learns a
/// correction failed "without leaving the panel they are already looking at".
///
/// Needs no bounded-height parent: the message scrolls inside a scroll view that
/// sizes to its child, rather than claiming a share of a `Column` with
/// `Expanded`. A notice that threw at layout in an unbounded parent would take
/// the whole panel down at exactly the moment something has already gone wrong.
class CorrectionErrorNotice extends StatelessWidget {
  const CorrectionErrorNotice({
    required this.message,
    required this.onRetry,
    super.key,
  });

  /// `CorrectionFailed.message`, rendered as it is. The panel adds nothing to
  /// it: the adapter that translated the failure is what knows what happened.
  final String message;

  /// Re-runs the correction on the captured submitted text (AD-18) — never on
  /// what the editor holds now.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable as a whole, because a provider message is a sentence this
    // panel did not write and the region it replaces is small (CAP-10).
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Announced, for the reason the copy-failure notice is: the variants
          // this replaces simply vanish, so a user who cannot see the message
          // is left in front of a panel that lost its answer without saying so.
          // The bigger of the panel's two messages should not be the quieter.
          Semantics(
            liveRegion: true,
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
