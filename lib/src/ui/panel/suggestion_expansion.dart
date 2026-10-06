import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../daemon_theme.dart';

/// Full authoritative text bounded inside the existing daemon window.
class SuggestionExpansion extends StatelessWidget {
  const SuggestionExpansion({
    required this.label,
    required this.text,
    required this.focusNode,
    required this.onClose,
    required this.onCopy,
    required this.copyLabel,
    this.copyFailure,
    super.key,
  });
  final String label;
  final String text;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback? onCopy;
  final String copyLabel;
  final String? copyFailure;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: .18)),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 560,
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(7),
                  child: Focus(
                    focusNode: focusNode,
                    autofocus: true,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        onClose();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              TextButton(
                                onPressed: onClose,
                                child: const Text('Show less'),
                              ),
                              Tooltip(
                                message: 'Copy expanded $label suggestion',
                                child: TextButton(
                                  onPressed: onCopy,
                                  child: Text(
                                    copyLabel,
                                    style: copyLabel == 'Copied'
                                        ? TextStyle(
                                            color: DaemonTheme.successFor(
                                              Theme.of(context).brightness,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (copyFailure case final failure?)
                            Flexible(
                              child: SingleChildScrollView(
                                child: Semantics(
                                  liveRegion: true,
                                  child: SelectableText(
                                    failure,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          Flexible(
                            flex: 4,
                            child: SingleChildScrollView(
                              child: SelectableText(text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
