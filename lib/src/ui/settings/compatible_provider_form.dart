import 'package:flutter/material.dart';

import '../../domain/config/provider_config.dart';
import '../../domain/correction/preset.dart';
import 'settings_draft_state.dart';

/// Keeps endpoint/model drafts while committed values follow external edits.
class CompatibleProviderForm extends StatefulWidget {
  const CompatibleProviderForm({
    required this.baseUrl,
    required this.preset,
    required this.enabled,
    required this.onSave,
    required this.drafts,
    required this.onUrlChanged,
    required this.onModelChanged,
    super.key,
  });

  final SettingsDraftState drafts;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onModelChanged;
  final String baseUrl;
  final Preset? preset;
  final bool enabled;
  final void Function({required String baseUrl, required String model}) onSave;

  @override
  State<CompatibleProviderForm> createState() => _CompatibleProviderFormState();
}

class _CompatibleProviderFormState extends State<CompatibleProviderForm> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = widget.drafts.url;
    _modelController.text = widget.drafts.model;
  }

  @override
  void didUpdateWidget(CompatibleProviderForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_baseUrlController.text != widget.drafts.url) {
      _baseUrlController.text = widget.drafts.url;
    }
    if (_modelController.text != widget.drafts.model) {
      _modelController.text = widget.drafts.model;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _saveEnabled =>
      widget.enabled &&
      _baseUrlController.text.trim().isNotEmpty &&
      _modelController.text.trim().isNotEmpty &&
      ProviderConfig.baseUrlProblem(_baseUrlController.text) == null;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.preset == null)
        const Text(
          'Save the URL and model to activate this provider. '
          'Your current provider stays active until then.',
        ),
      const SizedBox(height: 8),
      TextField(
        controller: _baseUrlController,
        enabled: widget.enabled,
        onChanged: widget.onUrlChanged,
        decoration: InputDecoration(
          labelText: 'Base URL',
          errorText: _baseUrlController.text.trim().isEmpty
              ? 'Required'
              : ProviderConfig.baseUrlProblem(_baseUrlController.text),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _modelController,
        enabled: widget.enabled,
        onChanged: widget.onModelChanged,
        decoration: InputDecoration(
          labelText: 'Model',
          errorText: _modelController.text.trim().isEmpty ? 'Required' : null,
        ),
      ),
      const SizedBox(height: 8),
      if (widget.drafts.urlConflict || widget.drafts.modelConflict)
        const Text(
          'Provider settings changed while you were editing. '
          'Saving will replace those changes with your draft.',
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _saveEnabled
              ? () => widget.onSave(
                  baseUrl: _baseUrlController.text,
                  model: _modelController.text,
                )
              : null,
          child: const Text('Save provider settings'),
        ),
      ),
    ],
  );
}
