import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/prairie_theme.dart';

/// Asks for a collection name. Resolves to the trimmed name, or null when
/// cancelled. Closing the dialog hands focus back to whatever opened it.
Future<String?> showCollectionNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CollectionNameDialog(title: title, confirmLabel: confirmLabel, initialName: initialName),
  );
}

/// A yes/no confirmation; Cancel takes the initial focus so an accidental
/// OK press can't confirm a destructive action.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: PrairieColors.bgElevated,
      title: Text(title, style: const TextStyle(color: PrairieColors.ink)),
      content: Text(message, style: const TextStyle(color: PrairieColors.muted)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _CollectionNameDialog extends StatefulWidget {
  const _CollectionNameDialog({required this.title, required this.confirmLabel, required this.initialName});

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<_CollectionNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  final _fieldFocus = FocusNode(debugLabel: 'collection-name');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  /// Same rationale as SearchScreen's handler: a focused `TextField`
  /// swallows arrow keys, so D-pad Down onto the buttons is driven explicitly.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) return false;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !identical(focused, _fieldFocus)) return false;
    return focused.focusInDirection(TraversalDirection.down);
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PrairieColors.bgElevated,
      title: Text(widget.title, style: const TextStyle(color: PrairieColors.ink)),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          focusNode: _fieldFocus,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => ElevatedButton(
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
