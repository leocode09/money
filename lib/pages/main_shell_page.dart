import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../app_colors.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../widgets/app_shell_header.dart';
import '../widgets/display_name_dialog.dart';
import 'compare_page.dart';
import 'dashboard_page.dart';
import 'leaderboard_page.dart';
import 'more_tab_page.dart';

class MainShellPage extends StatefulWidget {
  final List<SmsMessage> messages;
  final List<MonthlyTransactionSummary>? firestoreSummaries;

  const MainShellPage({
    super.key,
    required this.messages,
    this.firestoreSummaries,
  });

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  final AuthService _authService = AuthService();
  int _tabIndex = 0;
  bool _isPublic = false;
  bool _isTogglingPublic = false;
  String _accountName = '';

  AppColors get _c => Theme.of(context).extension<AppColors>()!;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final isPublic = await _authService.isPublic();
    var name = await _authService.getCachedDisplayName();
    if (name.isEmpty) {
      name = await _authService.refreshDisplayNameFromFirestore();
    }
    if (!mounted) return;
    setState(() {
      _isPublic = isPublic;
      _accountName = name;
    });

    if (name.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editDisplayName();
      });
    }
  }

  Future<void> _editDisplayName() async {
    final name = await showDisplayNameDialog(
      context,
      initialName: _accountName,
    );
    if (name == null || !mounted) return;

    final ok = await _authService.updateDisplayName(name);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _c.danger,
          behavior: SnackBarBehavior.floating,
          content: const Text('Could not save your name.'),
        ),
      );
      return;
    }

    setState(() => _accountName = name);
  }

  Future<void> _handlePublicChanged(bool next) async {
    if (_isTogglingPublic) return;
    setState(() => _isTogglingPublic = true);

    final ok = await _authService.togglePublic(next);
    if (!mounted) return;

    if (!ok) {
      setState(() => _isTogglingPublic = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _c.danger,
          behavior: SnackBarBehavior.floating,
          content: const Text('Could not update public status.'),
        ),
      );
      return;
    }

    setState(() {
      _isPublic = next;
      _isTogglingPublic = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: next ? _c.success : _c.card,
        behavior: SnackBarBehavior.floating,
        content: Text(
          next
              ? 'You are now public.'
              : 'You are now private.',
          style: TextStyle(
            color: next ? Colors.white : _c.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          AppShellHeader(
            accountName: _accountName,
            isPublic: _isPublic,
            onEditName: _editDisplayName,
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                DashboardPage(
                  messages: widget.messages,
                  firestoreSummaries: widget.firestoreSummaries,
                  embeddedInShell: true,
                  shellIsPublic: _isPublic,
                  onPublicStateChanged: (v) => setState(() => _isPublic = v),
                ),
                const ComparePage(embeddedInShell: true),
                const LeaderboardPage(embeddedInShell: true),
                MoreTabPage(
                  isPublic: _isPublic,
                  isTogglingPublic: _isTogglingPublic,
                  onPublicChanged: _handlePublicChanged,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: c.card,
        indicatorColor: c.primary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.home_rounded, color: c.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.compare_arrows_rounded, color: c.primary),
            label: 'Compare',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.leaderboard_rounded, color: c.primary),
            label: 'Rank',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.settings_rounded, color: c.primary),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
