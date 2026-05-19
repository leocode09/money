import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme_decorations.dart';
import 'terms_page.dart';

class MoreTabPage extends StatelessWidget {
  final bool isPublic;
  final bool isTogglingPublic;
  final ValueChanged<bool> onPublicChanged;

  const MoreTabPage({
    super.key,
    required this.isPublic,
    required this.isTogglingPublic,
    required this.onPublicChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Privacy, appearance, and legal',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          child: SwitchListTile(
            value: isPublic,
            onChanged: isTogglingPublic ? null : (v) => onPublicChanged(v),
            secondary: Icon(
              isPublic ? Icons.public_rounded : Icons.lock_rounded,
              color: isPublic ? c.success : c.textSecondary,
            ),
            title: Text(
              'Public profile',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              isPublic
                  ? 'Monthly totals are visible on the leaderboard and compare tab.'
                  : 'Only you can see your data. Turn on to compare with others.',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
            activeThumbColor: c.primary,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                iconColor: c.primary,
                title: isDark ? 'Light mode' : 'Dark mode',
                subtitle: 'Switch app theme',
                onTap: () {
                  themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              Divider(height: 1, color: c.cardBorder.withValues(alpha: 0.5)),
              _SettingsTile(
                icon: Icons.gavel_rounded,
                iconColor: c.textSecondary,
                title: 'Terms & conditions',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TermsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: c.accentPurple,
            title: 'About',
            subtitle: 'M-Money transaction dashboard',
            onTap: () {},
            showChevron: false,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Container(
      decoration: AppDecorations.card(c, context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            )
          : null,
      trailing: showChevron
          ? Icon(Icons.chevron_right_rounded, color: c.textSecondary)
          : null,
    );
  }
}
