import 'package:flutter/material.dart';

import '../../domain/config/app_config.dart';

class LogSizeField extends StatelessWidget {
  const LogSizeField({
    required this.maxBytes,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final int maxBytes;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const mebibyte = AppConfig.defaultLogMaxBytes;
    final sizes = {mebibyte, 5 * mebibyte, 10 * mebibyte, maxBytes}.toList()
      ..sort();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Log file size limit',
        enabled: enabled,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: maxBytes,
          isExpanded: true,
          items: [
            for (final size in sizes)
              DropdownMenuItem(
                value: size,
                child: Text(
                  size % mebibyte == 0
                      ? '${size ~/ mebibyte} MiB'
                      : '$size bytes',
                ),
              ),
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
}
