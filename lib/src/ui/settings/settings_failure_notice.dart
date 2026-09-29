import 'package:flutter/material.dart';

import '../../application/settings_state.dart';

/// The one thing on this screen that tells a user their change did not land, so
/// it is announced rather than merely coloured.
///
/// A notice assistive technology never reads is as good as no notice at all —
/// the lesson the panel paid for twice — and this one matters more than most:
/// every other sentence on this screen describes state, while this one describes
/// a change the user asked for and did not get.
///
/// The message is the failure's own. Nothing is composed on top of it: the store
/// is what knows whether a value was refused or a write was lost, and it says so
/// in terms a user can act on.
class SettingsFailureNotice extends StatelessWidget {
  const SettingsFailureNotice({required this.failure, super.key});

  final SettingsFailure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      // `container: true` for the reason `HotkeyStatusView` and
      // `SettingsPendingNotice` both give, and this was the one live region on
      // the screen without it. Without its own node the flag lands on whichever
      // node the surrounding layout happened to form — an ancestor carrying other
      // text, or none at all — and a live region with the wrong label, or an
      // empty one, announces the wrong thing or nothing. That failure is silent,
      // and it would be silent on the single sentence that tells a user their
      // change did not land.
      //
      // **Pinned by no row, and said so rather than left looking guarded**, the
      // same way `HotkeyStatusView` says it: measured, removing it fails zero
      // rows, because on today's tree the annotation merges into an ancestor
      // carrying this sentence and nothing else. That is a property of this
      // widget's neighbours — a screen someone else will edit — not of this
      // widget. The flag and the label landing on one node *is* pinned, by the
      // A12 rows below and beside it.
      container: true,
      child: Text(
        failure.message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
