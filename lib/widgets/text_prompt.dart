import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The route owns its controller through the closing animation.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String cancel,
  required String confirm,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder:
      (_) => _TextPrompt(
        title: title,
        label: label,
        cancel: cancel,
        confirm: confirm,
        initial: initial,
      ),
);

class _TextPrompt extends StatefulWidget {
  final String title, label, cancel, confirm, initial;
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.cancel,
    required this.confirm,
    required this.initial,
  });
  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
    },
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 1,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (text) => Navigator.pop(context, text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirm),
        ),
      ],
    ),
  );
}
