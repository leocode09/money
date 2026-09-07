import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../services/auth_service.dart';

enum _ShopPasswordAction { set, change, remove }

/// Opens a dialog to set, change, or remove the shop password.
/// Returns true when the password state changed successfully.
Future<bool> showShopPasswordDialog(
  BuildContext context, {
  required bool hasPassword,
}) async {
  final action = await showDialog<_ShopPasswordAction>(
    context: context,
    builder: (dialogContext) {
      final c = Theme.of(dialogContext).extension<AppColors>()!;
      return AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          hasPassword ? 'Shop password' : 'Set shop password',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          hasPassword
              ? 'Change or remove the password that locks the dashboard when you leave the app.'
              : 'Protect your dashboard with a password when the app is in the background.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          if (hasPassword) ...[
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ShopPasswordAction.remove),
              child: Text('Remove', style: TextStyle(color: c.danger)),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ShopPasswordAction.change),
              style: FilledButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Theme.of(dialogContext).brightness ==
                        Brightness.dark
                    ? c.bg
                    : Colors.white,
              ),
              child: const Text('Change'),
            ),
          ] else
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ShopPasswordAction.set),
              style: FilledButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor:
                    Theme.of(dialogContext).brightness == Brightness.dark
                    ? c.bg
                    : Colors.white,
              ),
              child: const Text('Set password'),
            ),
        ],
      );
    },
  );

  if (action == null || !context.mounted) return false;

  switch (action) {
    case _ShopPasswordAction.set:
      return _promptNewPassword(context);
    case _ShopPasswordAction.change:
      return _promptChangePassword(context);
    case _ShopPasswordAction.remove:
      return _promptRemovePassword(context);
  }
}

Future<bool> _promptNewPassword(BuildContext context) async {
  final fields = await _showPasswordFields(
    context,
    title: 'Set shop password',
    fields: const [
      _PasswordField(label: 'New password', keyName: 'new'),
      _PasswordField(label: 'Confirm password', keyName: 'confirm'),
    ],
  );
  if (fields == null || !context.mounted) return false;

  final password = fields['new'] ?? '';
  final confirm = fields['confirm'] ?? '';
  if (password != confirm) {
    _showError(context, 'Passwords do not match.');
    return false;
  }
  if (password.length < 4) {
    _showError(context, 'Password must be at least 4 characters.');
    return false;
  }

  final ok = await AuthService().setShopPassword(password);
  if (!context.mounted) return ok;
  if (!ok) {
    _showError(context, 'Could not save shop password.');
    return false;
  }
  return true;
}

Future<bool> _promptChangePassword(BuildContext context) async {
  final fields = await _showPasswordFields(
    context,
    title: 'Change shop password',
    fields: const [
      _PasswordField(label: 'Current password', keyName: 'current'),
      _PasswordField(label: 'New password', keyName: 'new'),
      _PasswordField(label: 'Confirm new password', keyName: 'confirm'),
    ],
  );
  if (fields == null || !context.mounted) return false;

  final current = fields['current'] ?? '';
  final password = fields['new'] ?? '';
  final confirm = fields['confirm'] ?? '';
  if (password != confirm) {
    _showError(context, 'New passwords do not match.');
    return false;
  }
  if (password.length < 4) {
    _showError(context, 'Password must be at least 4 characters.');
    return false;
  }

  final ok = await AuthService().changeShopPassword(current, password);
  if (!context.mounted) return ok;
  if (!ok) {
    _showError(context, 'Current password is incorrect.');
    return false;
  }
  return true;
}

Future<bool> _promptRemovePassword(BuildContext context) async {
  final fields = await _showPasswordFields(
    context,
    title: 'Remove shop password',
    fields: const [
      _PasswordField(label: 'Current password', keyName: 'current'),
    ],
  );
  if (fields == null || !context.mounted) return false;

  final ok = await AuthService().removeShopPassword(fields['current'] ?? '');
  if (!context.mounted) return ok;
  if (!ok) {
    _showError(context, 'Current password is incorrect.');
    return false;
  }
  return true;
}

class _PasswordField {
  const _PasswordField({required this.label, required this.keyName});

  final String label;
  final String keyName;
}

Future<Map<String, String>?> _showPasswordFields(
  BuildContext context, {
  required String title,
  required List<_PasswordField> fields,
}) async {
  final c = Theme.of(context).extension<AppColors>()!;
  final formKey = GlobalKey<FormState>();
  final controllers = {
    for (final field in fields) field.keyName: TextEditingController(),
  };
  final obscure = {for (final field in fields) field.keyName: true};

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields) ...[
                    TextFormField(
                      controller: controllers[field.keyName],
                      obscureText: obscure[field.keyName] ?? true,
                      decoration: InputDecoration(
                        labelText: field.label,
                        prefixIcon: Icon(Icons.lock_outline, color: c.primary),
                        suffixIcon: IconButton(
                          icon: Icon(
                            (obscure[field.keyName] ?? true)
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: c.textSecondary,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscure[field.keyName] =
                                  !(obscure[field.keyName] ?? true);
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        if (field.keyName.contains('new') &&
                            value.length < 4) {
                          return 'At least 4 characters';
                        }
                        return null;
                      },
                    ),
                    if (field != fields.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.of(dialogContext).pop({
                    for (final field in fields)
                      field.keyName: controllers[field.keyName]!.text,
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor:
                      Theme.of(dialogContext).brightness == Brightness.dark
                      ? c.bg
                      : Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}

void _showError(BuildContext context, String message) {
  final c = Theme.of(context).extension<AppColors>()!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: c.danger,
      behavior: SnackBarBehavior.floating,
      content: Text(message),
    ),
  );
}
