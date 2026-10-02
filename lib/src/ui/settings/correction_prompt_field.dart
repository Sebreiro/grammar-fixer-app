import 'package:flutter/material.dart';

/// Owns an unsaved prompt draft while committed values follow config edits.
class CorrectionPromptField extends StatefulWidget {
  const CorrectionPromptField({
    required this.prompt,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final String prompt;
  final bool enabled;
  final ValueChanged<String> onSave;

  @override
  State<CorrectionPromptField> createState() => _CorrectionPromptFieldState();
}

class _CorrectionPromptFieldState extends State<CorrectionPromptField> {
  final _promptController = TextEditingController();
  bool _changedWhileEditing = false;

  @override
  void initState() {
    super.initState();
    _promptController.text = widget.prompt;
  }

  @override
  void didUpdateWidget(CorrectionPromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prompt == widget.prompt) return;
    if (_promptController.text == oldWidget.prompt) {
      _promptController.text = widget.prompt;
    }
    _changedWhileEditing = _promptController.text != widget.prompt;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _draftChanged() => setState(() {
    if (_promptController.text == widget.prompt) {
      _changedWhileEditing = false;
    }
  });

  bool get _saveEnabled =>
      widget.enabled &&
      _promptController.text.trim().isNotEmpty &&
      _promptController.text != widget.prompt;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _promptController,
        enabled: widget.enabled,
        minLines: 5,
        maxLines: 12,
        onChanged: (_) => _draftChanged(),
        decoration: InputDecoration(
          labelText: 'Correction prompt',
          errorText: _promptController.text.trim().isEmpty ? 'Required' : null,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Applies to the active preset. The app adds the required response '
        'format automatically.',
      ),
      if (_changedWhileEditing)
        const Text(
          'The correction prompt changed while you were editing. '
          'Saving will replace that change with your draft.',
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _saveEnabled
              ? () => widget.onSave(_promptController.text)
              : null,
          child: const Text('Save prompt'),
        ),
      ),
    ],
  );
}
