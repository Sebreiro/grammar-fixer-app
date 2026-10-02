import 'package:flutter/material.dart';

import '../../domain/config/close_behavior.dart';

class CloseBehaviorField extends StatelessWidget {
  const CloseBehaviorField({
    required this.behavior,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final CloseBehavior behavior;
  final bool enabled;
  final ValueChanged<CloseBehavior> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: 'When closing the window',
      enabled: enabled,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<CloseBehavior>(
        value: behavior,
        isExpanded: true,
        items: const [
          DropdownMenuItem(
            value: CloseBehavior.closeToTray,
            child: Text('Close to tray'),
          ),
          DropdownMenuItem(value: CloseBehavior.quit, child: Text('Quit app')),
        ],
        onChanged: enabled
            ? (value) {
                if (value != null) onChanged(value);
              }
            : null,
      ),
    ),
  );
}
