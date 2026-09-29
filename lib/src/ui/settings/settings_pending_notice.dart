import 'package:flutter/material.dart';

/// Says that a settings change is still being applied.
///
/// The reason it exists is the one the panel already paid for: a surface whose
/// every control is disabled and which otherwise looks exactly as it did is
/// indistinguishable from a hung app. Here the window is wide by design — AD-11
/// makes a portal dialog the user has to answer part of a normal bind, so the
/// screen can sit like this for seconds while the status block still reads
/// "nothing is in effect".
///
/// Real progress, not fakery: this is rendered from the controller's in-flight
/// state and disappears when the mutation actually resolves, so it never claims
/// something is happening when nothing is. The SPEC rules out staged spinners and
/// placeholder text; it does not rule out reporting work that is genuinely in
/// flight, which is the same distinction the panel's own progress affordance
/// rests on.
///
/// Announced, or it fixes "in flight looks like hung" for sighted users only and
/// leaves everyone else in front of a screen whose controls stopped responding
/// for no stated reason.
class SettingsPendingNotice extends StatelessWidget {
  const SettingsPendingNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Applying your change…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          const LinearProgressIndicator(
            semanticsLabel: 'applying your settings change',
          ),
        ],
      ),
    );
  }
}
