import 'package:flutter/material.dart';

import '../../domain/correction/preset.dart';

/// One option per configured preset, and CAP-8's caveat about when a switch
/// takes effect.
///
/// Selects a **preset**, never a provider (AD-5). A preset carries its
/// `providerId`, and the composition root is what resolves the
/// `(provider, preset)` pair from it; a screen that picked a provider would be
/// choosing half of an indivisible unit. The provider id and model are shown
/// because that is what a user is actually choosing between — "try a faster
/// model" is the whole point of CAP-8 — but they are shown, not selected.
///
/// A committed choice serves the next correction. A run already streaming
/// keeps the pair it captured when submitted.
class PresetChoiceList extends StatelessWidget {
  const PresetChoiceList({
    required this.presets,
    required this.activePresetId,
    required this.enabled,
    required this.onSelect,
    super.key,
  });

  final List<Preset> presets;
  final String activePresetId;

  /// False while a mutation is in flight — see `HotkeyCaptureField.enabled`.
  final bool enabled;

  /// Called with the chosen preset's **id**.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Preset', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final preset in presets)
          ListTile(
            dense: true,
            enabled: enabled,
            selected: preset.id == activePresetId,
            leading: Icon(
              preset.id == activePresetId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(preset.id),
            // What the preset actually names, so a user choosing between them
            // is choosing on the facts rather than on an id.
            subtitle: Text('${preset.providerId} · ${preset.model}'),
            // The *active* option is inert: selecting what is already selected
            // is not a change, and issuing the mutation anyway means a write
            // that can fail and report "your settings could not be saved" for a
            // change nobody made. Every other option stays live even when it was
            // just tried and lost — a failed write leaves the old id active, so
            // the option the user wanted is still the non-active one, and
            // pressing it again is the retry.
            onTap: enabled && preset.id != activePresetId
                ? () => onSelect(preset.id)
                : null,
          ),
        const SizedBox(height: 4),
        Text(
          'A preset change applies to the next correction. A correction already '
          'running keeps its previous provider and model.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
