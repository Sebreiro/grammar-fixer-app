import 'package:flutter/material.dart';

import '../../domain/config/provider_config.dart';

/// Provider choices share one radio group; the selected preset owns activation.
class ProviderChoiceList extends StatelessWidget {
  const ProviderChoiceList({
    required this.providerIds,
    required this.selectedProviderId,
    required this.enabled,
    required this.onSelect,
    super.key,
  });

  final Iterable<String> providerIds;
  final String? selectedProviderId;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => RadioGroup<String>(
    groupValue: selectedProviderId,
    onChanged: (providerId) {
      if (enabled && providerId != null && providerId != selectedProviderId) {
        onSelect(providerId);
      }
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('AI provider', style: Theme.of(context).textTheme.titleSmall),
        for (final providerId in providerIds)
          RadioListTile<String>(
            key: ValueKey('provider-$providerId'),
            value: providerId,
            enabled: enabled,
            dense: true,
            title: Text(_label(providerId)),
          ),
      ],
    ),
  );

  static String _label(String providerId) => switch (providerId) {
    'claude-agent-sdk' => 'Claude Agent SDK (Claude Code)',
    ProviderConfig.compatibleProviderId => 'OpenAI-compatible (via URL)',
    _ => providerId,
  };
}
