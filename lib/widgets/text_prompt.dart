/// Dialogs/sheets that ask for one line of text.
///
/// Each OWNS its TextEditingController and disposes it in its own
/// dispose(), i.e. only after the closing animation has finished.
/// Disposing a controller right after `await showDialog(...)` /
/// `showModalBottomSheet(...).whenComplete(...)` crashes in debug
/// ("_dependents.isEmpty is not true"): the route is still animating out
/// and its TextField is still using the controller.
library;

import 'package:flutter/material.dart';

import '../theme/hux_tokens.dart';

/// An AlertDialog with one text field. Pops with the text, or null on Cancel.
class TextPromptDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String initialText;
  final String confirmLabel;
  final TextInputType? keyboardType;

  /// Optional small text under the field.
  final String? helper;

  /// When set, the confirm button only enables once the field equals this
  /// (case-insensitive), e.g. "DELETE".
  final String? requiredText;
  final String? body;
  final Color? confirmColor;

  const TextPromptDialog({
    super.key,
    required this.title,
    this.hint,
    this.initialText = '',
    this.confirmLabel = 'OK',
    this.keyboardType,
    this.helper,
    this.requiredText,
    this.body,
    this.confirmColor,
  });

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      widget.requiredText == null || _controller.text.trim().toUpperCase() == widget.requiredText!.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.body != null) ...[Text(widget.body!), const SizedBox(height: HuxSpacing.md)],
          if (widget.requiredText != null) Text('Type ${widget.requiredText} to confirm.'),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(hintText: widget.hint),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (_canConfirm) Navigator.of(context).pop(v);
            },
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            Text(widget.helper!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: _canConfirm ? () => Navigator.of(context).pop(_controller.text) : null,
          style: widget.confirmColor == null ? null : TextButton.styleFrom(foregroundColor: widget.confirmColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Bottom sheet: "What is it? (optional)" for meal photos. Pops with the
/// text, '' on Skip, or null when dismissed.
class MealDescriptionSheet extends StatefulWidget {
  const MealDescriptionSheet({super.key});

  @override
  State<MealDescriptionSheet> createState() => _MealDescriptionSheetState();
}

class _MealDescriptionSheetState extends State<MealDescriptionSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          HuxSpacing.xl, 0, HuxSpacing.xl, HuxSpacing.xl + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What is it? (optional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: HuxSpacing.sm),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'e.g. rajma chawal, 2 rotis'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: HuxSpacing.md),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Skip')),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('Analyse')),
            ],
          ),
        ],
      ),
    );
  }
}
