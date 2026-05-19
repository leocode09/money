import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme_decorations.dart';

class AppShellHeader extends StatelessWidget {
  final String accountName;
  final bool isPublic;
  final VoidCallback onEditName;

  const AppShellHeader({
    super.key,
    required this.accountName,
    required this.isPublic,
    required this.onEditName,
  });

  String get _subtitle {
    final privacy = isPublic
        ? 'Public aggregates'
        : (accountName.isEmpty ? 'Private' : 'Private');
    if (accountName.isEmpty) {
      return 'Tap to add your name · $privacy';
    }
    return '$accountName · $privacy';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: AppDecorations.logoMark(c, context),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppDecorations.logoIconColor(c, context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'M-Money',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: onEditName,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accountName.isEmpty
                                      ? c.primary
                                      : c.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              accountName.isEmpty
                                  ? Icons.edit_rounded
                                  : Icons.drive_file_rename_outline_rounded,
                              size: 14,
                              color: accountName.isEmpty
                                  ? c.primary
                                  : c.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
