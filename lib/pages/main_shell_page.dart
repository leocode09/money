import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../app_colors.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../services/sms_realtime_service.dart';
import '../widgets/app_shell_header.dart';
import '../widgets/display_name_dialog.dart';
import '../widgets/shop_lock_gate.dart';
import '../widgets/shop_password_dialog.dart';
import 'compare_page.dart';
import 'dashboard_page.dart';
import 'expenses_page.dart';
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

class _MainShellPageState extends State<MainShellPage>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final SmsRealtimeService _smsRealtime = SmsRealtimeService();
  final SmsQuery _smsQuery = SmsQuery();

  // Live copy of the SMS list, seeded from the initial query and grown in
  // realtime as new M-Money messages arrive.
  late List<SmsMessage> _messages = List<SmsMessage>.of(widget.messages);

  int _tabIndex = 0;
  bool _isPublic = false;
  bool _isTogglingPublic = false;
  bool _shopPasswordEnabled = false;
  int _shopLockVersion = 0;
  String _accountName = '';

  // True on the SMS-backed mobile path; false on the web/Firestore path where
  // there is no inbox to listen to.
  bool get _smsBacked => !kIsWeb && widget.firestoreSummaries == null;

  AppColors get _c => Theme.of(context).extension<AppColors>()!;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    if (_smsBacked) {
      WidgetsBinding.instance.addObserver(this);
      _smsRealtime.start(_onIncomingSms);
    }
  }

  @override
  void dispose() {
    if (_smsBacked) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground listening is paused while backgrounded, so reconcile against
    // the system inbox on resume to pick up anything that arrived meanwhile.
    if (state == AppLifecycleState.resumed && _smsBacked) {
      _refreshFromInbox();
    }
  }

  /// Handles a foreground SMS: keeps it only if it looks like an M-Money
  /// message, then prepends it (newest-first) and rebuilds so the pages
  /// re-process their transactions.
  void _onIncomingSms(IncomingSms sms) {
    if (!mounted || !_smsBacked) return;

    final body = sms.body ?? '';
    if (body.isEmpty) return;

    final looksLikeMoMo =
        (sms.sender ?? '').toLowerCase().contains('money');
    final isTransaction = Transaction.fromSmsMessage(body) != null;
    if (!looksLikeMoMo && !isTransaction) return;

    final dateMillis = sms.dateMillis ??
        DateTime.now().millisecondsSinceEpoch;
    final incoming = SmsMessage.fromJson({
      '_id': dateMillis,
      'address': sms.sender ?? 'M-Money',
      'body': body,
      'date': dateMillis,
    });

    // Guard against the same message being delivered twice.
    if (_messages.isNotEmpty) {
      final head = _messages.first;
      if (head.body == incoming.body &&
          head.date?.millisecondsSinceEpoch == dateMillis) {
        return;
      }
    }

    setState(() {
      _messages = [incoming, ..._messages];
    });
  }

  /// Re-reads M-Money messages from the inbox and replaces the live list when
  /// it has changed (new message count or a different newest message).
  Future<void> _refreshFromInbox() async {
    try {
      final latest = await _smsQuery.querySms(
        kinds: [SmsQueryKind.inbox],
        address: 'M-Money',
      );
      if (!mounted || _sameInbox(latest, _messages)) return;
      setState(() {
        _messages = latest;
      });
    } catch (_) {
      // A failed refresh just leaves the current data in place.
    }
  }

  bool _sameInbox(List<SmsMessage> a, List<SmsMessage> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    return a.first.body == b.first.body &&
        a.first.date?.millisecondsSinceEpoch ==
            b.first.date?.millisecondsSinceEpoch;
  }

  Future<void> _loadProfile() async {
    final isPublic = await _authService.isPublic();
    final shopPasswordEnabled = await _authService.isShopPasswordEnabled();
    var name = await _authService.getCachedDisplayName();
    if (name.isEmpty) {
      name = await _authService.refreshDisplayNameFromFirestore();
    }
    if (!mounted) return;
    setState(() {
      _isPublic = isPublic;
      _shopPasswordEnabled = shopPasswordEnabled;
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

  Future<void> _manageShopPassword() async {
    final hasPassword = await _authService.hasShopPassword();
    if (!mounted) return;

    final changed = await showShopPasswordDialog(
      context,
      hasPassword: hasPassword,
    );
    if (!changed || !mounted) return;

    final enabled = await _authService.isShopPasswordEnabled();
    if (!mounted) return;

    setState(() {
      _shopPasswordEnabled = enabled;
      _shopLockVersion++;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: enabled ? _c.success : _c.card,
        behavior: SnackBarBehavior.floating,
        content: Text(
          enabled
              ? 'Shop password enabled.'
              : 'Shop password removed.',
          style: TextStyle(
            color: enabled ? Colors.white : _c.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    return ShopLockGate(
      key: ValueKey(_shopLockVersion),
      child: Scaffold(
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
                  messages: _messages,
                  firestoreSummaries: widget.firestoreSummaries,
                  embeddedInShell: true,
                  shellIsPublic: _isPublic,
                  onPublicStateChanged: (v) => setState(() => _isPublic = v),
                ),
                ExpensesPage(
                  messages: _messages,
                  firestoreSummaries: widget.firestoreSummaries,
                  embeddedInShell: true,
                ),
                const ComparePage(embeddedInShell: true),
                const LeaderboardPage(embeddedInShell: true),
                MoreTabPage(
                  isPublic: _isPublic,
                  isTogglingPublic: _isTogglingPublic,
                  onPublicChanged: _handlePublicChanged,
                  shopPasswordEnabled: _shopPasswordEnabled,
                  onManageShopPassword: _manageShopPassword,
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
            icon: Icon(Icons.payments_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.payments_rounded, color: c.primary),
            label: 'Expenses',
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
    ),
    );
  }
}
