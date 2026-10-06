import 'dart:async';

import 'package:flutter/material.dart';

/// Owns only the entered draft; stored credentials are never read into the field.
class ApiKeyField extends StatefulWidget {
  const ApiKeyField({
    required this.enabled,
    required this.onSave,
    this.controller,
    super.key,
  });

  final bool enabled;
  final Future<bool> Function(String key) onSave;
  final TextEditingController? controller;

  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  TextEditingController? _ownedController;
  TextEditingController get _keyController =>
      widget.controller ??
      _ownedController ??
      (throw StateError('API key field has no controller'));
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _ownedController = TextEditingController();
  }

  @override
  void didUpdateWidget(ApiKeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && _ownedController == null) {
      _ownedController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draft = _keyController.text;
    final saved = await widget.onSave(draft);
    if (!mounted || !saved) return;
    setState(() {
      if (_keyController.text == draft) _keyController.clear();
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _keyController,
        enabled: widget.enabled,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        onChanged: (_) => setState(() => _saved = false),
        decoration: const InputDecoration(
          labelText: 'API key',
          helperText:
              'Saved to your system keyring, or to config if the keyring is '
              'unavailable. Leave blank to keep the existing key.',
          helperMaxLines: 3,
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: widget.enabled && _keyController.text.trim().isNotEmpty
              ? () => unawaited(_save())
              : null,
          child: const Text('Save API key'),
        ),
      ),
      if (_saved) const Text('API key saved.'),
    ],
  );
}
