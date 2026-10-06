import 'package:flutter/material.dart';
import '../../domain/correction/suggestion_register.dart';
import '../daemon_theme.dart';
import 'register_key_slot.dart';
import 'suggestion_expansion.dart';

/// Compact preview; the complete authoritative string remains available to copy.
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({
    required this.register,
    required this.text,
    required this.selected,
    required this.completed,
    required this.onSelect,
    required this.onCopy,
    this.copyPending = false,
    this.copySucceeded = false,
    this.copyFailure,
    super.key,
  });
  final SuggestionRegister register;
  final String text;
  final bool selected;
  final bool completed;
  final VoidCallback onSelect;
  final VoidCallback onCopy;
  final bool copyPending;
  final bool copySucceeded;
  final String? copyFailure;
  bool get actionable => completed && text.trim().isNotEmpty;
  String? get keyHint =>
      keySlotHintForIndex(SuggestionRegister.values.indexOf(register));
  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  final _overlay = OverlayPortalController();
  final _triggerFocus = FocusNode();
  final _expansionFocus = FocusNode();
  @override
  void didUpdateWidget(SuggestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlay.isShowing &&
        (oldWidget.text != widget.text || !widget.actionable)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _overlay.hide();
      });
    }
  }

  @override
  void dispose() {
    _triggerFocus.dispose();
    _expansionFocus.dispose();
    super.dispose();
  }

  void _close() {
    _overlay.hide();
    _triggerFocus.requestFocus();
  }

  void _open() {
    _overlay.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _expansionFocus.requestFocus();
    });
  }

  void _copyExpanded() {
    widget.onCopy();
    _expansionFocus.requestFocus();
  }

  String get _copyLabel => widget.copyPending
      ? 'Copying…'
      : widget.copySucceeded
      ? 'Copied'
      : 'Copy';

  String? get _copyFailureText => switch (widget.copyFailure) {
    null => null,
    'There is no suggestion text to copy.' => widget.copyFailure,
    _ => "Couldn't copy this suggestion. Try again.",
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = widget.register.label;
    final style = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 13);
    final failure = _copyFailureText;
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => SuggestionExpansion(
        label: label,
        text: widget.text,
        focusNode: _expansionFocus,
        onClose: _close,
        onCopy: widget.copyPending ? null : _copyExpanded,
        copyLabel: _copyLabel,
        copyFailure: failure,
      ),
      child: Semantics(
        container: true,
        selected: widget.selected,
        label: '$label suggestion',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: widget.selected
                ? scheme.primaryContainer
                : scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: widget.selected ? scheme.primary : scheme.outline,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.actionable && !widget.selected
                  ? widget.onSelect
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context);
                    final narrow =
                        constraints.maxWidth <= 460 || scale.scale(13) > 19;
                    final tiny = constraints.maxWidth < 220;
                    final previewWidth = tiny
                        ? constraints.maxWidth
                        : (constraints.maxWidth - (narrow ? 100 : 210)).clamp(
                            1.0,
                            double.infinity,
                          );
                    final painter = TextPainter(
                      text: TextSpan(text: widget.text, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: scale,
                      maxLines: 5,
                    )..layout(maxWidth: previewWidth);
                    final overflow = painter.didExceedMaxLines;
                    painter.dispose();
                    final heading = Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.keyHint case final hint?)
                          Text(
                            hint,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: widget.actionable
                                  ? scheme.onSurface
                                  : theme.disabledColor,
                            ),
                          ),
                        Text(label, style: theme.textTheme.labelMedium),
                        if (widget.selected)
                          Icon(
                            Icons.check,
                            size: 14,
                            semanticLabel: '$label selected',
                          ),
                      ],
                    );
                    final preview = widget.actionable
                        ? SelectableText(
                            widget.text,
                            maxLines: overflow ? 5 : null,
                            style: style,
                            onTap: widget.selected ? null : widget.onSelect,
                          )
                        : Text(
                            widget.text,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          );
                    final actions = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Copy the $label suggestion',
                          child: Semantics(
                            liveRegion: true,
                            label: '$label suggestion $_copyLabel',
                            tooltip: 'Copy the $label suggestion',
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.onSurface,
                                side: BorderSide(color: scheme.outline),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              onPressed:
                                  widget.actionable && !widget.copyPending
                                  ? widget.onCopy
                                  : null,
                              icon: const Icon(Icons.copy_outlined, size: 14),
                              label: Text(
                                _copyLabel,
                                style: widget.copySucceeded
                                    ? TextStyle(
                                        color: DaemonTheme.successFor(
                                          theme.brightness,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        if (widget.actionable && overflow)
                          TextButton(
                            focusNode: _triggerFocus,
                            onPressed: _open,
                            child: const Text('Show more'),
                          ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tiny) ...[
                          heading,
                          actions,
                          preview,
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!narrow) SizedBox(width: 110, child: heading),
                              Expanded(
                                child: narrow
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          heading,
                                          const SizedBox(height: 4),
                                          preview,
                                        ],
                                      )
                                    : preview,
                              ),
                              const SizedBox(width: 6),
                              SizedBox(width: 94, child: actions),
                            ],
                          ),
                        if (failure != null)
                          Semantics(
                            liveRegion: true,
                            child: SelectableText(
                              failure,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
