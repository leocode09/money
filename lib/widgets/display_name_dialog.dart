import 'package:flutter/material.dart';
import '../app_colors.dart';

/// Returns trimmed name on save, or null if cancelled.
Future<String?> showDisplayNameDialog(
  BuildContext context, {
  String initialName = '',
  bool required = false,
}) async {
  final c = Theme.of(context).extension<AppColors>()!;
  final controller = TextEditingController(text: initialName.trim());
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: !required,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          initialName.trim().isEmpty ? 'Set your name' : 'Edit your name',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Your name',
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.person_outline, color: c.primary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your name';
              }
              if (value.trim().length < 2) {
                return 'Name must be at least 2 characters';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor:
                  Theme.of(context).brightness == Brightness.dark
                  ? c.bg
                  : Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  controller.dispose();
  return result;
}
