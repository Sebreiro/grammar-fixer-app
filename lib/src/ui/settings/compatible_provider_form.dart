import 'package:flutter/material.dart';

import '../../domain/config/provider_config.dart';
import '../../domain/correction/preset.dart';

/// Keeps endpoint/model drafts while committed values follow external edits.
class CompatibleProviderForm extends StatefulWidget {
  const CompatibleProviderForm({
    required this.baseUrl,
    required this.preset,
    required this.enabled,
    required this.onSave,
    super.key,
  });

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
  bool _baseUrlChangedWhileEditing = false;
  bool _modelChangedWhileEditing = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = widget.baseUrl;
    _modelController.text = widget.preset?.model ?? '';
  }

  @override
  void didUpdateWidget(CompatibleProviderForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _baseUrlChangedWhileEditing = _syncDraft(_baseUrlController, (
      old: oldWidget.baseUrl,
      current: widget.baseUrl,
    ), _baseUrlChangedWhileEditing);
    if (oldWidget.preset?.id != widget.preset?.id) {
      _modelController.text = widget.preset?.model ?? '';
      _modelChangedWhileEditing = false;
      return;
    }
    _modelChangedWhileEditing = _syncDraft(_modelController, (
      old: oldWidget.preset?.model ?? '',
      current: widget.preset?.model ?? '',
    ), _modelChangedWhileEditing);
  }

  static bool _syncDraft(
    TextEditingController controller,
    ({String old, String current}) values,
    bool changedWhileEditing,
  ) {
    if (values.old != values.current && controller.text == values.old) {
      controller.text = values.current;
    } else if (values.old != values.current &&
        controller.text != values.current) {
      changedWhileEditing = true;
    }
    return controller.text != values.current && changedWhileEditing;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _draftChanged() => setState(() {
    if (_baseUrlController.text == widget.baseUrl) {
      _baseUrlChangedWhileEditing = false;
    }
    if (_modelController.text == (widget.preset?.model ?? '')) {
      _modelChangedWhileEditing = false;
    }
  });

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
        onChanged: (_) => _draftChanged(),
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
        onChanged: (_) => _draftChanged(),
        decoration: InputDecoration(
          labelText: 'Model',
          errorText: _modelController.text.trim().isEmpty ? 'Required' : null,
        ),
      ),
      const SizedBox(height: 8),
      if (_baseUrlChangedWhileEditing || _modelChangedWhileEditing)
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
