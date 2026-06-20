import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../widgets/display_name_dialog.dart';

/// Aggregation granularity for the Receipts section.
enum _ReceiptPeriod { week, month, year }

/// Ordering for the Receipts section.
enum _ReceiptSort { dateDesc, dateAsc, amountDesc, amountAsc }

/// One row in the Receipts list, normalized across week/month/year so the list
/// rendering and sorting don't care which period produced it.
class _ReceiptBucket {
  const _ReceiptBucket({
    required this.date,
    required this.received,
    required this.sent,
    required this.count,
    required this.isCurrent,
  });

  final DateTime date; // representative date (week start / month / year start)
  final double received;
  final double sent;
  final int count;
  final bool isCurrent; // contains "now" for the active period
}

class DashboardPage extends StatefulWidget {
  final List<SmsMessage> messages;
  final List<MonthlyTransactionSummary>? firestoreSummaries;
  final bool embeddedInShell;
  final bool? shellIsPublic;
  final ValueChanged<bool>? onPublicStateChanged;

  const DashboardPage({
    super.key,
    required this.messages,
    this.firestoreSummaries,
    this.embeddedInShell = false,
    this.shellIsPublic,
    this.onPublicStateChanged,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  late List<Transaction> _transactions;
  late List<MonthlyTransactionSummary> _monthlySummaries;
  int _selectedMonthIndex = 0;
  int _selectedProgressMonthIndex = 0;
  late AnimationController _animationController;
  late AnimationController _staggerController;
  late ScrollController _scrollController;
  bool _showTargetLine = true;

  late Animation<double> _bgAnimation;

  final AuthService _authService = AuthService();
  bool _isPublic = false;
  String _accountName = '';
  bool _promptedForName = false;

  // Raw SMS-parsed transactions (mobile). Kept separate from [_transactions],
  // which may be replaced with statement-backed aggregates after reconciliation.
  List<Transaction> _smsTransactions = const <Transaction>[];
  // Merged weekly aggregates (statement baseline + post-cutoff SMS), used for
  // public sync so the weekly leaderboard stays statement-accurate.
  List<WeeklyTransactionSummary>? _mergedWeekly;
  // True once statement reconciliation has run (or is not applicable, e.g. the
  // web/Firestore path), gating the initial public sync so SMS-only data is
  // never pushed over statement-covered periods.
  bool _statementReconcileDone = false;

  // Receipts section controls.
  _ReceiptPeriod _receiptPeriod = _ReceiptPeriod.month;
  _ReceiptSort _receiptSort = _ReceiptSort.dateDesc;
  bool _receiptGrouped = false;

  final currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  AppColors get _c => Theme.of(context).extension<AppColors>()!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => _c.primary;
  Color get primaryDark => _c.primaryDark;
  Color get primaryLight => _c.primaryLight;
  Color get accentColor => _c.accent;
  Color get accentPurple => _c.accentPurple;
  Color get successColor => _c.success;
  Color get dangerColor => _c.danger;
  Color get bgColor => _c.bg;
  Color get bgGradient1 => _c.bgGradient1;
  Color get bgGradient2 => _c.bgGradient2;
  Color get cardColor => _c.card;
  Color get cardBorder => _c.cardBorder;
  Color get textPrimary => _c.textPrimary;
  Color get textSecondary => _c.textSecondary;

  double get totalReceivedAmount => _transactions
      .where((t) => t.isReceived)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get averageReceivedAmount => _transactions.isEmpty
      ? 0
      : totalReceivedAmount / _transactions.where((t) => t.isReceived).length;

  double get totalFees =>
      _transactions.fold<double>(0, (sum, t) => sum + t.fee);

  double get highestTransaction => _transactions.isEmpty
      ? 0
      : _transactions
            .where((t) => t.isReceived)
            .map((t) => t.amount)
            .reduce((a, b) => a > b ? a : b);

  Map<String, double> get counterpartyTotals {
    final totals = <String, double>{};
    for (var tx in _transactions.where((t) => t.isReceived)) {
      totals[tx.counterparty] = (totals[tx.counterparty] ?? 0) + tx.amount;
    }
    return totals;
  }

  List<MapEntry<String, double>> get topCounterparties {
    final totals = counterpartyTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return totals.take(5).toList();
  }

  Map<String, dynamic> _calculateTargetForDate(DateTime referenceDate) {
    if (_monthlySummaries.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => a.month.compareTo(b.month));

    final completedMonths = sortedSummaries
        .where((s) => s.month.isBefore(referenceDate))
        .toList();

    if (completedMonths.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final recentMonths = completedMonths.length <= 3
        ? completedMonths
        : completedMonths.sublist(completedMonths.length - 3);

    final growthRates = <double>[];
    for (int i = 1; i < recentMonths.length; i++) {
      final previous = recentMonths[i - 1].totalReceived;
      final current = recentMonths[i].totalReceived;
      if (previous > 0) {
        growthRates.add((current - previous) / previous);
      }
    }

    double avgGrowthRate = 0.05;
    if (growthRates.isNotEmpty) {
      avgGrowthRate = growthRates.reduce((a, b) => a + b) / growthRates.length;
      avgGrowthRate += 0.02;
      if (avgGrowthRate < 0.0) avgGrowthRate = 0.0;
    }

    final lastMonthAmount = recentMonths.last.totalReceived;
    final target = lastMonthAmount * (1 + avgGrowthRate);

    return {
      'target': target,
      'growthRate': avgGrowthRate,
      'lastMonth': lastMonthAmount,
      'lastMonthDate': recentMonths.last.month,
    };
  }

  Map<String, dynamic> get nextMonthTarget {
    if (_monthlySummaries.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final descendingSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    if (_selectedMonthIndex < 0 ||
        _selectedMonthIndex >= descendingSummaries.length) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final selectedDate = descendingSummaries[_selectedMonthIndex].month;
    return _calculateTargetForDate(selectedDate);
  }

  Map<String, dynamic> getMonthProgress(int monthIndex) {
    if (_monthlySummaries.isEmpty) {
      return {
        'currentAmount': 0.0,
        'previousMonthAmount': 0.0,
        'previousProgress': 0.0,
        'previousRemaining': 0.0,
        'selectedMonth': DateTime.now(),
      };
    }

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    final clampedIndex = monthIndex.clamp(0, sortedSummaries.length - 1);
    final selectedMonthData = sortedSummaries[clampedIndex];

    final previousMonthDate = DateTime(
      selectedMonthData.month.year,
      selectedMonthData.month.month - 1,
    );
    final previousMonthData = _monthlySummaries.firstWhere(
      (s) =>
          s.month.year == previousMonthDate.year &&
          s.month.month == previousMonthDate.month,
      orElse: () => MonthlyTransactionSummary(
        month: previousMonthDate,
        totalReceived: 0,
        totalSent: 0,
        transactionCount: 0,
      ),
    );

    final currentAmount = selectedMonthData.totalReceived;
    final previousMonthAmount = previousMonthData.totalReceived;

    final previousProgress = previousMonthAmount > 0
        ? (currentAmount / previousMonthAmount * 100).clamp(0.0, 200.0)
        : 0.0;
    final previousRemaining = previousMonthAmount - currentAmount;

    final targetMap = _calculateTargetForDate(selectedMonthData.month);
    final targetAmount = targetMap['target'] as double;
    final targetProgress = targetAmount > 0
        ? (currentAmount / targetAmount * 100).clamp(0.0, 200.0)
        : 0.0;
    final targetRemaining = targetAmount - currentAmount;

    return {
      'currentAmount': currentAmount,
      'previousMonthAmount': previousMonthAmount,
      'previousProgress': previousProgress,
      'previousRemaining': previousRemaining,
      'targetAmount': targetAmount,
      'targetProgress': targetProgress,
      'targetRemaining': targetRemaining,
      'selectedMonth': selectedMonthData.month,
      'previousMonth': previousMonthDate,
    };
  }

  Map<String, dynamic> get currentMonthProgress {
    return getMonthProgress(_selectedProgressMonthIndex);
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shellIsPublic != null &&
        widget.shellIsPublic != oldWidget.shellIsPublic) {
      final next = widget.shellIsPublic!;
      if (next != _isPublic) {
        setState(() => _isPublic = next);
      }
      if (next && _monthlySummaries.isNotEmpty) {
        _syncPublicSummaries().ignore();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _bgAnimation = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOutCubic),
    );

    _processTransactions();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });

    _loadPublicState();
    if (!widget.embeddedInShell) {
      _loadAccountName();
    } else if (widget.shellIsPublic != null) {
      _isPublic = widget.shellIsPublic!;
    }
  }

  Future<void> _loadAccountName() async {
    var name = await _authService.getCachedDisplayName();
    if (name.isEmpty) {
      name = await _authService.refreshDisplayNameFromFirestore();
    }
    if (!mounted) return;
    setState(() {
      _accountName = name;
    });
    if (name.isEmpty && !_promptedForName) {
      _promptedForName = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editDisplayName();
      });
    }
  }

  String get _topBarSubtitle {
    final privacy =
        _isPublic ? 'Public aggregates' : (_accountName.isEmpty ? 'Private by default' : 'Private');
    if (_accountName.isEmpty) {
      return 'Tap to add your name · $privacy';
    }
    return '$_accountName · $privacy';
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
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
          content: const Text(
            'Could not save your name. Check your connection and try again.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _accountName = name;
    });
  }

  Future<void> _loadPublicState() async {
    final isPublic = await _authService.isPublic();
    if (!mounted) return;
    setState(() {
      _isPublic = isPublic;
    });
    widget.onPublicStateChanged?.call(isPublic);
    // Only push public data once reconciliation has settled what the live
    // summaries are; otherwise reconcile (see below) performs the public sync.
    if (isPublic && _monthlySummaries.isNotEmpty && _statementReconcileDone) {
      _syncPublicSummaries().ignore();
    }
  }

  List<WeeklyTransactionSummary>? _weeklySummariesForPublicSync() {
    if (widget.firestoreSummaries != null) return null;
    if (_mergedWeekly != null) return _mergedWeekly;
    return WeeklyTransactionSummary.fromTransactions(_smsTransactions);
  }

  Future<void> _syncPublicSummaries() {
    return _authService.syncPublicSummaries(
      _monthlySummaries,
      weeklySummaries: _weeklySummariesForPublicSync(),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _staggerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _processTransactions() {
    final firestoreSummaries = widget.firestoreSummaries;
    if (firestoreSummaries != null) {
      _monthlySummaries = List<MonthlyTransactionSummary>.from(
        firestoreSummaries,
      )..sort((a, b) => a.month.compareTo(b.month));
      _transactions = _transactionsFromSummaries(_monthlySummaries);
      _selectCurrentMonth();
      _statementReconcileDone = true; // web path: nothing to reconcile.
      return;
    }

    _transactions = widget.messages
        .map(
          (msg) =>
              Transaction.fromSmsMessage(msg.body ?? '', smsDate: msg.date),
        )
        .where((t) => t != null)
        .cast<Transaction>()
        .toList();

    _transactions.sort((a, b) => b.date.compareTo(a.date));
    _smsTransactions = _transactions;

    final monthlyData = <DateTime, List<Transaction>>{};
    for (var transaction in _transactions) {
      final month = DateTime(transaction.date.year, transaction.date.month);
      monthlyData.putIfAbsent(month, () => []).add(transaction);
    }

    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    if (!monthlyData.containsKey(currentMonth)) {
      monthlyData[currentMonth] = [];
    }

    _monthlySummaries = monthlyData.entries.map((entry) {
      final receivedAmount = entry.value
          .where((t) => t.type == 'RECEIVED')
          .fold<double>(0, (sum, t) => sum + t.amount);

      final sentAmount = entry.value
          .where((t) => t.type == 'SENT')
          .fold<double>(0, (sum, t) => sum + t.amount);

      return MonthlyTransactionSummary(
        month: entry.key,
        totalReceived: receivedAmount,
        totalSent: sentAmount,
        transactionCount: entry.value.length,
      );
    }).toList();

    _monthlySummaries.sort((a, b) => a.month.compareTo(b.month));

    _selectCurrentMonth();

    // Reconcile against any official MoMo-statement baseline before syncing, so
    // SMS can only ever extend statement-covered periods, never overwrite them.
    _reconcileWithStatement().ignore();
  }

  /// Merges the official-statement baseline (if any) with SMS transactions that
  /// occur strictly after the statement cutoff, then displays and persists the
  /// result. Statement-covered periods are never overwritten by SMS. Idempotent:
  /// the baseline is immutable, so re-running always yields baseline + new SMS.
  Future<void> _reconcileWithStatement() async {
    final backing = await _authService.getStatementBacking();
    if (!mounted) return;

    if (backing == null) {
      // No statement backing: preserve the original SMS-only behaviour.
      _statementReconcileDone = true;
      if (_monthlySummaries.isNotEmpty) {
        _authService.syncDashboardSummaries(_monthlySummaries).ignore();
      }
      if (_isPublic && _monthlySummaries.isNotEmpty) {
        _syncPublicSummaries().ignore();
      }
      return;
    }

    final mergedMonthly = _mergeMonthlyWithStatement(
      backing.monthly,
      _smsTransactions,
      backing.through,
    );
    final mergedWeekly = _mergeWeeklyWithStatement(
      backing.weekly,
      _smsTransactions,
      backing.through,
    );

    setState(() {
      _mergedWeekly = mergedWeekly;
      _monthlySummaries = mergedMonthly;
      _transactions = _transactionsFromSummaries(mergedMonthly);
      _selectCurrentMonth();
      _statementReconcileDone = true;
    });

    if (mergedMonthly.isNotEmpty) {
      _authService.syncDashboardSummaries(mergedMonthly).ignore();
    }
    if (_isPublic && mergedMonthly.isNotEmpty) {
      _authService
          .syncPublicSummaries(mergedMonthly, weeklySummaries: mergedWeekly)
          .ignore();
    }
  }

  /// baseline months + SMS transactions strictly after [cutoff], summed per
  /// month. Months at/under the cutoff keep their authoritative baseline value.
  List<MonthlyTransactionSummary> _mergeMonthlyWithStatement(
    List<MonthlyTransactionSummary> baseline,
    List<Transaction> smsTransactions,
    DateTime cutoff,
  ) {
    final byMonth = <DateTime, MonthlyTransactionSummary>{
      for (final s in baseline) DateTime(s.month.year, s.month.month): s,
    };
    final extra = <DateTime, List<Transaction>>{};
    for (final t in smsTransactions) {
      if (!t.date.isAfter(cutoff)) continue; // statement owns this period
      final m = DateTime(t.date.year, t.date.month);
      extra.putIfAbsent(m, () => []).add(t);
    }

    final months = <DateTime>{...byMonth.keys, ...extra.keys};
    final result = months.map((m) {
      final base = byMonth[m];
      final tx = extra[m] ?? const <Transaction>[];
      final extraReceived =
          tx.where((t) => t.isReceived).fold<double>(0, (s, t) => s + t.amount);
      final extraSent =
          tx.where((t) => t.isSent).fold<double>(0, (s, t) => s + t.amount);
      return MonthlyTransactionSummary(
        month: m,
        totalReceived: (base?.totalReceived ?? 0) + extraReceived,
        totalSent: (base?.totalSent ?? 0) + extraSent,
        transactionCount: (base?.transactionCount ?? 0) + tx.length,
      );
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  /// Weekly analogue of [_mergeMonthlyWithStatement] (weeks start on Monday).
  List<WeeklyTransactionSummary> _mergeWeeklyWithStatement(
    List<WeeklyTransactionSummary> baseline,
    List<Transaction> smsTransactions,
    DateTime cutoff,
  ) {
    final byWeek = <DateTime, WeeklyTransactionSummary>{
      for (final s in baseline)
        DateTime(s.weekStart.year, s.weekStart.month, s.weekStart.day): s,
    };
    final extra = <DateTime, List<Transaction>>{};
    for (final t in smsTransactions) {
      if (!t.date.isAfter(cutoff)) continue;
      final w = WeeklyTransactionSummary.startOfWeek(t.date);
      extra.putIfAbsent(w, () => []).add(t);
    }

    final weeks = <DateTime>{...byWeek.keys, ...extra.keys};
    final result = weeks.map((w) {
      final base = byWeek[w];
      final tx = extra[w] ?? const <Transaction>[];
      final extraReceived =
          tx.where((t) => t.isReceived).fold<double>(0, (s, t) => s + t.amount);
      final extraSent =
          tx.where((t) => t.isSent).fold<double>(0, (s, t) => s + t.amount);
      return WeeklyTransactionSummary(
        weekStart: w,
        totalReceived: (base?.totalReceived ?? 0) + extraReceived,
        totalSent: (base?.totalSent ?? 0) + extraSent,
        transactionCount: (base?.transactionCount ?? 0) + tx.length,
      );
    }).toList()
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return result;
  }

  List<Transaction> _transactionsFromSummaries(
    List<MonthlyTransactionSummary> summaries,
  ) {
    final transactions = <Transaction>[];
    for (final summary in summaries) {
      if (summary.totalReceived > 0) {
        transactions.add(
          Transaction(
            amount: summary.totalReceived,
            date: summary.month,
            transactionId:
                'firestore-received-${summary.month.toIso8601String()}',
            counterparty: 'Monthly received',
            type: 'RECEIVED',
            fee: 0,
            balance: 0,
          ),
        );
      }
      if (summary.totalSent > 0) {
        transactions.add(
          Transaction(
            amount: summary.totalSent,
            date: summary.month,
            transactionId: 'firestore-sent-${summary.month.toIso8601String()}',
            counterparty: 'Monthly sent',
            type: 'SENT',
            fee: 0,
            balance: 0,
          ),
        );
      }
    }
    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }

  void _selectCurrentMonth() {
    final now = DateTime.now();
    final currentMonthIndex = _monthlySummaries.indexWhere(
      (summary) =>
          summary.month.year == now.year && summary.month.month == now.month,
    );

    if (currentMonthIndex >= 0) {
      _selectedMonthIndex = _monthlySummaries.length - 1 - currentMonthIndex;
    } else {
      _selectedMonthIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _transactions.isEmpty
        ? const Center(child: Text('No transactions found'))
        : Stack(
            children: [
              AnimatedBuilder(
                animation: _bgAnimation,
                builder: (context, child) {
                  return Opacity(opacity: _bgAnimation.value, child: child);
                },
                child: _buildGradientBackground(),
              ),
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (!widget.embeddedInShell) _buildAppBar(),
                  SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 0),
                            child: _buildMonthProgressChart(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 50),
                            child: _buildTransactionChart(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 100),
                            child: _buildReceiptsList(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 150),
                            child: _buildHeroCard(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 200),
                            child: _buildMonthlySummaryCard(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 250),
                            child: _buildMetricCards(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 300),
                            child: _buildNextMonthTargetCard(),
                          ),
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 350),
                            child: _buildTopSendersCard(),
                          ),
                          SizedBox(
                            height: widget.embeddedInShell ? 88 : 24,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );

    if (widget.embeddedInShell) {
      return body;
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: body,
    );
  }

  Widget _buildGradientBackground() {
    return Container(decoration: AppDecorations.pageBackground(_c, context));
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 112,
      collapsedHeight: 96,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: ClipRRect(
        child: AppDecorations.wrapBlur(
          context,
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: AppDecorations.appBarShell(_c, context),
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: AppDecorations.appBarCard(_c, context),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: AppDecorations.logoMark(_c, context),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppDecorations.logoIconColor(_c, context),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppDecorations.titleText(
                            context,
                            text: 'Transaction Dashboard',
                            shimmerColors: [textPrimary, accentColor],
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                              fontSize: 21,
                              letterSpacing: -0.8,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _editDisplayName,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _topBarSubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _accountName.isEmpty
                                            ? primaryColor
                                            : textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _accountName.isEmpty
                                        ? Icons.edit_rounded
                                        : Icons.drive_file_rename_outline_rounded,
                                    size: 14,
                                    color: _accountName.isEmpty
                                        ? primaryColor
                                        : textSecondary.withValues(alpha: 0.85),
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
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.hero(
        _c,
        context,
        gradientColors: [primaryColor, primaryDark, const Color(0xFFB85A3A)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (!_isDark)
              Positioned(
                top: -40,
                right: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Total Received',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: totalReceivedAmount),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedAmount, child) {
                      return Text(
                        currencyFormat.format(animatedAmount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          height: 1.0,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.trending_up,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_transactions.where((t) => t.isReceived).length} transactions',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets? margin}) {
    return AppGlassCard(margin: margin, child: child);
  }

  Widget _buildMonthlySummaryCard() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((b, a) => a.month.compareTo(b.month));

    final selectedSummary = sortedSummaries[_selectedMonthIndex];
    final previousIndex = _selectedMonthIndex + 1;
    final previousSummary = previousIndex < sortedSummaries.length
        ? sortedSummaries[previousIndex]
        : null;

    final percentageChange = previousSummary != null
        ? ((selectedSummary.totalReceived - previousSummary.totalReceived) /
              previousSummary.totalReceived *
              100)
        : 0.0;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: AppDecorations.dropdownChip(_c, context),
                  child: DropdownButton<int>(
                    value: _selectedMonthIndex,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: primaryColor,
                      size: 18,
                    ),
                    items: sortedSummaries.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(
                          DateFormat('MMM yy').format(entry.value.month),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedMonthIndex = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: selectedSummary.totalReceived),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, animatedAmount, child) {
                return Text(
                  currencyFormat.format(animatedAmount),
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              '${selectedSummary.transactionCount} transaction${selectedSummary.transactionCount != 1 ? 's' : ''} this month',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (previousSummary != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.tintedChip(
                  context,
                  percentageChange >= 0 ? successColor : dangerColor,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: percentageChange >= 0
                            ? successColor.withValues(alpha: 0.2)
                            : dangerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        percentageChange >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        color: percentageChange >= 0
                            ? successColor
                            : dangerColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${percentageChange >= 0 ? '+' : ''}${percentageChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: percentageChange >= 0
                            ? successColor
                            : dangerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'vs ${DateFormat('MMM').format(previousSummary.month)}',
                      style: TextStyle(color: textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCards() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final thisMonthTransactions = _transactions
        .where((t) => t.isReceived)
        .where((t) => DateTime(t.date.year, t.date.month) == thisMonth);

    final thisMonthTotal = thisMonthTransactions.fold<double>(
      0,
      (sum, t) => sum + t.amount,
    );
    final thisMonthAvg = thisMonthTransactions.isEmpty
        ? 0.0
        : thisMonthTotal / thisMonthTransactions.length;

    const metricGradients = [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFFEC4899), Color(0xFFF472B6)],
      [Color(0xFF14B8A6), Color(0xFF5EEAD4)],
      [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildAnimatedMetricCard(
                  'Avg Transaction',
                  currencyFormat.format(averageReceivedAmount),
                  Icons.analytics_outlined,
                  metricGradients[0],
                  0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAnimatedMetricCard(
                  'This Month',
                  currencyFormat.format(thisMonthAvg),
                  Icons.calendar_today_outlined,
                  metricGradients[1],
                  1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildAnimatedMetricCard(
                  'Highest',
                  currencyFormat.format(highestTransaction),
                  Icons.arrow_upward_rounded,
                  metricGradients[2],
                  2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAnimatedMetricCard(
                  'Total Fees',
                  currencyFormat.format(totalFees),
                  Icons.money_off_outlined,
                  metricGradients[3],
                  3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMetricCard(
    String label,
    String value,
    IconData icon,
    List<Color> gradientColors,
    int index,
  ) {
    final startDelay = 0.30 + (index * 0.05);
    final endDelay = 0.60 + (index * 0.05);

    final animation = CurvedAnimation(
      parent: _staggerController,
      curve: Interval(
        startDelay.clamp(0.0, 1.0),
        endDelay.clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.9 + (0.1 * animation.value),
              child: child,
            ),
          ),
        );
      },
      child: _buildMetricCard(label, value, icon, gradientColors),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    List<Color> gradientColors,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.metricSurface(_c, context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AppDecorations.wrapBlur(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: AppDecorations.iconBadge(
                  _c,
                  context,
                  gradientColors,
                ),
                child: Icon(
                  icon,
                  color: AppDecorations.iconBadgeForeground(
                    _c,
                    context,
                    gradientColors,
                  ),
                  size: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextMonthTargetCard() {
    final targetData = nextMonthTarget;
    final target = targetData['target'] as double;
    final growthRate = targetData['growthRate'] as double;
    final lastMonth = targetData['lastMonth'] as double;
    final lastMonthDate = targetData['lastMonthDate'] as DateTime?;

    if (target <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.accentHero(
        _c,
        context,
        gradientColors: const [
          Color(0xFF0D9488),
          Color(0xFF14B8A6),
          Color(0xFF5EEAD4),
        ],
        borderTint: successColor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (!_isDark) ...[
              Positioned(
                top: -60,
                right: -50,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.03),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                      ],
                      stops: const [0.0, 0.3, 1.0],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Next Month Target',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Based on growth trend',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: target),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedTarget, child) {
                      return Text(
                        currencyFormat.format(animatedTarget),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Growth',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '+${(growthRate * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lastMonthDate != null
                                      ? DateFormat(
                                          'MMM yy',
                                        ).format(lastMonthDate)
                                      : 'Last',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currencyFormat.format(lastMonth),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionChart() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final targetValue = nextMonthTarget['target'] as double;
    final maxDataValue = _monthlySummaries
        .map((s) => s.totalReceived)
        .reduce((a, b) => a > b ? a : b);
    final maxY = _showTargetLine
        ? [maxDataValue, targetValue].reduce((a, b) => a > b ? a : b) * 1.15
        : maxDataValue * 1.15;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Income Trend',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showTargetLine = !_showTargetLine;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _showTargetLine
                              ? successColor.withValues(alpha: 0.15)
                              : textSecondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showTargetLine
                                ? successColor.withValues(alpha: 0.3)
                                : textSecondary.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showTargetLine
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: _showTargetLine
                                  ? successColor
                                  : textSecondary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Target',
                              style: TextStyle(
                                color: _showTargetLine
                                    ? successColor
                                    : textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: AppDecorations.iconBadge(
                        _c,
                        context,
                        [primaryColor, primaryDark],
                      ),
                      child: Text(
                        '${_monthlySummaries.length} mo',
                        style: TextStyle(
                          color: AppDecorations.iconBadgeForeground(
                            _c,
                            context,
                            [primaryColor, primaryDark],
                          ),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: null,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value >= _monthlySummaries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat(
                                'MMM',
                              ).format(_monthlySummaries[value.toInt()].month),
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 32,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              value >= 1000000
                                  ? '${(value / 1000000).toStringAsFixed(1)}M'
                                  : '${(value / 1000).toStringAsFixed(0)}K',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 50,
                        interval: null,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY:
                      _monthlySummaries
                          .map((s) => s.totalReceived)
                          .reduce((a, b) => a < b ? a : b) *
                      0.7,
                  maxY: maxY,
                  extraLinesData: ExtraLinesData(
                    horizontalLines: _showTargetLine
                        ? [
                            HorizontalLine(
                              y: targetValue,
                              color: successColor,
                              strokeWidth: 2,
                              dashArray: [8, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  bottom: 4,
                                ),
                                style: TextStyle(
                                  color: successColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                labelResolver: (line) =>
                                    'Target: ${currencyFormat.format(line.y)}',
                              ),
                            ),
                          ]
                        : [],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _monthlySummaries.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.totalReceived,
                        );
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.35,
                      preventCurveOverShooting: true,
                      color: primaryColor,
                      barWidth: 2.4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: _isDark ? Colors.white : cardColor,
                            strokeWidth: 2,
                            strokeColor: primaryColor,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: AppDecorations.chartAreaFill(primaryColor),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: cardColor,
                      tooltipRoundedRadius: 12,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final monthData = _monthlySummaries[spot.x.toInt()];
                          return LineTooltipItem(
                            '${DateFormat('MMM yyyy').format(monthData.month)}\n',
                            TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            children: [
                              TextSpan(
                                text: currencyFormat.format(spot.y),
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthProgressChart() {
    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    if (sortedSummaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final progress = getMonthProgress(_selectedProgressMonthIndex);
    final currentAmount = progress['currentAmount'] as double;
    final previousMonthAmount = progress['previousMonthAmount'] as double;
    final targetAmount = progress['targetAmount'] as double;
    final selectedMonth = progress['selectedMonth'] as DateTime;
    final previousMonth = progress['previousMonth'] as DateTime?;

    final previousProgress = progress['previousProgress'] as double;
    final previousRemaining = progress['previousRemaining'] as double;
    final targetProgress = progress['targetProgress'] as double;
    final targetRemaining = progress['targetRemaining'] as double;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: AppDecorations.sectionIcon(
                        _c,
                        context,
                        accentPurple,
                      ),
                      child: Icon(
                        Icons.trending_up_rounded,
                        color: AppDecorations.sectionIconForeground(
                          _c,
                          context,
                          accentPurple,
                        ),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Monthly Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: AppDecorations.tintedChip(context, accentPurple),
                  child: DropdownButton<int>(
                    value: _selectedProgressMonthIndex.clamp(
                      0,
                      sortedSummaries.length - 1,
                    ),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: accentPurple,
                      size: 18,
                    ),
                    items: sortedSummaries.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(
                          DateFormat('MMM yy').format(entry.value.month),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentPurple,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedProgressMonthIndex = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: currentAmount),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedAmount, child) {
                      return Text(
                        currencyFormat.format(animatedAmount),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                          letterSpacing: -0.5,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earned in ${DateFormat('MMMM yyyy').format(selectedMonth)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildProgressBar(
              label: previousMonth != null
                  ? 'vs ${DateFormat('MMM').format(previousMonth)}'
                  : 'vs Previous Month',
              current: currentAmount,
              goal: previousMonthAmount,
              progress: previousProgress,
              remaining: previousRemaining,
              color: primaryColor,
              icon: Icons.calendar_month_rounded,
            ),
            const SizedBox(height: 16),
            _buildProgressBar(
              label: 'vs Target',
              current: currentAmount,
              goal: targetAmount,
              progress: targetProgress,
              remaining: targetRemaining,
              color: successColor,
              icon: Icons.flag_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required String label,
    required double current,
    required double goal,
    required double progress,
    required double remaining,
    required Color color,
    required IconData icon,
  }) {
    final isAchieved = remaining <= 0;
    final displayProgress = progress.clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isAchieved
                    ? successColor.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: displayProgress),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, animatedProgress, child) {
                  return Text(
                    '${animatedProgress.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isAchieved ? successColor : color,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: cardBorder.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0.0,
                end: (displayProgress / 100).clamp(0.0, 1.0),
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, animatedWidth, child) {
                return FractionallySizedBox(
                  widthFactor: animatedWidth,
                  child: Container(
                    height: 10,
                    decoration: AppDecorations.progressFill(context, color),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Goal: ${currencyFormat.format(goal)}',
              style: TextStyle(
                fontSize: 11,
                color: textSecondary.withValues(alpha: 0.7),
              ),
            ),
            Text(
              isAchieved
                  ? '✓ Exceeded by ${currencyFormat.format(-remaining)}'
                  : '${currencyFormat.format(remaining)} left',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isAchieved ? successColor : color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopSendersCard() {
    if (_transactions.isEmpty) return const SizedBox.shrink();

    final maxAmount = topCounterparties.isEmpty
        ? 1.0
        : topCounterparties.first.value;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: AppDecorations.sectionIcon(
                    _c,
                    context,
                    primaryColor,
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: AppDecorations.sectionIconForeground(
                      _c,
                      context,
                      primaryColor,
                    ),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Top Senders',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...topCounterparties.asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value;
              final percentage = (data.value / maxAmount * 100);

              final gradientColors = [
                const Color(0xFF6366F1),
                const Color(0xFF8B5CF6),
                const Color(0xFFEC4899),
                const Color(0xFFF59E0B),
                const Color(0xFF10B981),
              ];

              final rowAnimation = CurvedAnimation(
                parent: _staggerController,
                curve: Interval(
                  (0.40 + (index * 0.04)).clamp(0.0, 1.0),
                  (0.70 + (index * 0.04)).clamp(0.0, 1.0),
                  curve: Curves.easeOutCubic,
                ),
              );

              return AnimatedBuilder(
                animation: rowAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(30 * (1 - rowAnimation.value), 0),
                    child: Opacity(
                      opacity: rowAnimation.value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: AppDecorations.iconBadge(
                                    _c,
                                    context,
                                    [
                                      gradientColors[index %
                                          gradientColors.length],
                                      gradientColors[index %
                                              gradientColors.length]
                                          .withValues(alpha: 0.7),
                                    ],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: AppDecorations.iconBadgeForeground(
                                          _c,
                                          context,
                                          [
                                            gradientColors[index %
                                                gradientColors.length],
                                          ],
                                        ),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    data.key,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            currencyFormat.format(data.value),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: percentage / 100),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedValue, child) {
                            return LinearProgressIndicator(
                              value: animatedValue,
                              minHeight: 8,
                              backgroundColor: textSecondary.withValues(
                                alpha: 0.2,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                gradientColors[index % gradientColors.length],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptsList() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final buckets = _receiptBuckets();
    final title = switch (_receiptPeriod) {
      _ReceiptPeriod.week => 'Weekly Receipts',
      _ReceiptPeriod.month => 'Monthly Receipts',
      _ReceiptPeriod.year => 'Yearly Receipts',
    };

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: AppDecorations.sectionIcon(
                    _c,
                    context,
                    accentPurple,
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppDecorations.sectionIconForeground(
                      _c,
                      context,
                      accentPurple,
                    ),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                _buildReceiptSortButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                _periodChip('Week', _ReceiptPeriod.week),
                const SizedBox(width: 6),
                _periodChip('Month', _ReceiptPeriod.month),
                const SizedBox(width: 6),
                _periodChip('Year', _ReceiptPeriod.year),
                const Spacer(),
                if (_receiptPeriod != _ReceiptPeriod.year) _buildGroupToggle(),
              ],
            ),
          ),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Text(
                _receiptPeriod == _ReceiptPeriod.week
                    ? "Weekly breakdown isn't available for this account yet."
                    : 'No receipts to show.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            )
          else
            ..._receiptRows(buckets),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ---- Receipts data --------------------------------------------------------

  /// Weekly aggregates for the Receipts list: prefer the statement-backed merged
  /// weeks; otherwise derive from raw SMS transactions. Empty when neither is
  /// available (e.g. the web/Firestore path, which only has monthly data).
  List<WeeklyTransactionSummary> _displayWeekly() {
    if (_mergedWeekly != null) return _mergedWeekly!;
    if (_smsTransactions.isNotEmpty) {
      return WeeklyTransactionSummary.fromTransactions(_smsTransactions);
    }
    return const <WeeklyTransactionSummary>[];
  }

  /// Builds normalized, sorted buckets for the selected period.
  List<_ReceiptBucket> _receiptBuckets() {
    final now = DateTime.now();
    final buckets = <_ReceiptBucket>[];

    switch (_receiptPeriod) {
      case _ReceiptPeriod.month:
        for (final s in _monthlySummaries) {
          buckets.add(_ReceiptBucket(
            date: DateTime(s.month.year, s.month.month),
            received: s.totalReceived,
            sent: s.totalSent,
            count: s.transactionCount,
            isCurrent: s.month.year == now.year && s.month.month == now.month,
          ));
        }
        break;
      case _ReceiptPeriod.year:
        final byYear = <int, List<double>>{}; // year -> [received, sent, count]
        for (final s in _monthlySummaries) {
          final acc = byYear.putIfAbsent(s.month.year, () => [0.0, 0.0, 0.0]);
          acc[0] += s.totalReceived;
          acc[1] += s.totalSent;
          acc[2] += s.transactionCount;
        }
        byYear.forEach((year, acc) {
          buckets.add(_ReceiptBucket(
            date: DateTime(year),
            received: acc[0],
            sent: acc[1],
            count: acc[2].toInt(),
            isCurrent: year == now.year,
          ));
        });
        break;
      case _ReceiptPeriod.week:
        final weekNow = WeeklyTransactionSummary.startOfWeek(now);
        for (final w in _displayWeekly()) {
          buckets.add(_ReceiptBucket(
            date: w.weekStart,
            received: w.totalReceived,
            sent: w.totalSent,
            count: w.transactionCount,
            isCurrent: w.weekStart.year == weekNow.year &&
                w.weekStart.month == weekNow.month &&
                w.weekStart.day == weekNow.day,
          ));
        }
        break;
    }

    buckets.sort((a, b) {
      switch (_receiptSort) {
        case _ReceiptSort.dateDesc:
          return b.date.compareTo(a.date);
        case _ReceiptSort.dateAsc:
          return a.date.compareTo(b.date);
        case _ReceiptSort.amountDesc:
          return b.received.compareTo(a.received);
        case _ReceiptSort.amountAsc:
          return a.received.compareTo(b.received);
      }
    });
    return buckets;
  }

  // ---- Receipts rendering ---------------------------------------------------

  List<Widget> _receiptRows(List<_ReceiptBucket> buckets) {
    final divider = Divider(
      height: 1,
      indent: 14,
      endIndent: 14,
      color: cardBorder.withValues(alpha: 0.3),
    );

    // Flat list (no grouping, or year period which is already the coarsest).
    if (!_receiptGrouped || _receiptPeriod == _ReceiptPeriod.year) {
      final rows = <Widget>[];
      for (var i = 0; i < buckets.length; i++) {
        if (i > 0) rows.add(divider);
        rows.add(_buildReceiptTile(buckets[i]));
      }
      return rows;
    }

    // Grouped: weeks -> by month, months -> by year. Insertion order follows the
    // already-sorted buckets, so group order respects the active sort.
    final groups = <String, List<_ReceiptBucket>>{};
    String keyOf(_ReceiptBucket b) => _receiptPeriod == _ReceiptPeriod.week
        ? DateFormat('yyyy-MM').format(b.date)
        : '${b.date.year}';
    for (final b in buckets) {
      groups.putIfAbsent(keyOf(b), () => <_ReceiptBucket>[]).add(b);
    }

    final rows = <Widget>[];
    groups.forEach((_, items) {
      final subtotal = items.fold<double>(0, (s, b) => s + b.received);
      final label = _receiptPeriod == _ReceiptPeriod.week
          ? DateFormat('MMMM yyyy').format(items.first.date)
          : '${items.first.date.year}';
      rows.add(_buildReceiptGroupHeader(label, subtotal));
      for (var i = 0; i < items.length; i++) {
        rows.add(_buildReceiptTile(items[i]));
        if (i < items.length - 1) rows.add(divider);
      }
    });
    return rows;
  }

  Widget _buildReceiptGroupHeader(String label, double subtotal) {
    return Container(
      width: double.infinity,
      color: textSecondary.withValues(alpha: _isDark ? 0.06 : 0.05),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Text(
            currencyFormat.format(subtotal),
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptTile(_ReceiptBucket bucket) {
    final isCurrent = bucket.isCurrent;
    final top = switch (_receiptPeriod) {
      _ReceiptPeriod.week => DateFormat('MMM').format(bucket.date),
      _ReceiptPeriod.month => DateFormat('MMM').format(bucket.date),
      _ReceiptPeriod.year => 'YR',
    };
    final bottom = switch (_receiptPeriod) {
      _ReceiptPeriod.week => DateFormat('d').format(bucket.date),
      _ReceiptPeriod.month => DateFormat('yy').format(bucket.date),
      _ReceiptPeriod.year => DateFormat('yyyy').format(bucket.date),
    };
    final title = switch (_receiptPeriod) {
      _ReceiptPeriod.week =>
        '${DateFormat('MMM d').format(bucket.date)} – ${DateFormat('MMM d').format(bucket.date.add(const Duration(days: 6)))}',
      _ReceiptPeriod.month => DateFormat('MMMM yyyy').format(bucket.date),
      _ReceiptPeriod.year => DateFormat('yyyy').format(bucket.date),
    };

    return Container(
      decoration: isCurrent
          ? BoxDecoration(
              color: _isDark ? primaryColor.withValues(alpha: 0.08) : null,
              gradient: _isDark
                  ? null
                  : LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.08),
                        primaryColor.withValues(alpha: 0.02),
                      ],
                    ),
            )
          : null,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: isCurrent
              ? AppDecorations.iconBadge(_c, context, [primaryColor, primaryDark])
              : BoxDecoration(
                  color: textSecondary.withValues(alpha: _isDark ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cardBorder.withValues(alpha: 0.35)),
                ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                top,
                style: TextStyle(
                  color: isCurrent ? Colors.white : textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                bottom,
                style: TextStyle(
                  color: isCurrent
                      ? Colors.white.withValues(alpha: 0.9)
                      : textSecondary.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
            color: textPrimary,
          ),
        ),
        subtitle: Text(
          '${bucket.count} txn${bucket.count != 1 ? 's' : ''}',
          style: TextStyle(
            color: isCurrent ? primaryColor : textSecondary,
            fontSize: 10,
          ),
        ),
        trailing: Text(
          currencyFormat.format(bucket.received),
          style: TextStyle(
            color: isCurrent ? primaryColor : textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ---- Receipts controls ----------------------------------------------------

  Widget _periodChip(String label, _ReceiptPeriod value) {
    final selected = _receiptPeriod == value;
    return GestureDetector(
      onTap: () => setState(() => _receiptPeriod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? primaryColor.withValues(alpha: 0.15)
              : textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? primaryColor.withValues(alpha: 0.4)
                : cardBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primaryColor : textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupToggle() {
    final on = _receiptGrouped;
    return GestureDetector(
      onTap: () => setState(() => _receiptGrouped = !on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? accentPurple.withValues(alpha: 0.15)
              : textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on
                ? accentPurple.withValues(alpha: 0.4)
                : cardBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.layers_rounded : Icons.layers_clear_rounded,
              size: 14,
              color: on ? accentPurple : textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Group',
              style: TextStyle(
                color: on ? accentPurple : textSecondary,
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptSortButton() {
    String labelFor(_ReceiptSort s) => switch (s) {
      _ReceiptSort.dateDesc => 'Newest',
      _ReceiptSort.dateAsc => 'Oldest',
      _ReceiptSort.amountDesc => 'Highest',
      _ReceiptSort.amountAsc => 'Lowest',
    };

    return PopupMenuButton<_ReceiptSort>(
      initialValue: _receiptSort,
      tooltip: 'Sort',
      onSelected: (v) => setState(() => _receiptSort = v),
      color: cardColor,
      itemBuilder: (context) => [
        for (final s in _ReceiptSort.values)
          PopupMenuItem<_ReceiptSort>(
            value: s,
            child: Row(
              children: [
                Icon(
                  switch (s) {
                    _ReceiptSort.dateDesc => Icons.arrow_downward_rounded,
                    _ReceiptSort.dateAsc => Icons.arrow_upward_rounded,
                    _ReceiptSort.amountDesc => Icons.trending_down_rounded,
                    _ReceiptSort.amountAsc => Icons.trending_up_rounded,
                  },
                  size: 16,
                  color: _receiptSort == s ? primaryColor : textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  switch (s) {
                    _ReceiptSort.dateDesc => 'Newest first',
                    _ReceiptSort.dateAsc => 'Oldest first',
                    _ReceiptSort.amountDesc => 'Highest amount',
                    _ReceiptSort.amountAsc => 'Lowest amount',
                  },
                  style: TextStyle(
                    color: _receiptSort == s ? primaryColor : textPrimary,
                    fontWeight:
                        _receiptSort == s ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cardBorder.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 4),
            Text(
              labelFor(_receiptSort),
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollAnimatedComponent extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final Duration delay;

  const _ScrollAnimatedComponent({
    required this.child,
    required this.scrollController,
    this.delay = Duration.zero,
  });

  @override
  State<_ScrollAnimatedComponent> createState() =>
      _ScrollAnimatedComponentState();
}

class _ScrollAnimatedComponentState extends State<_ScrollAnimatedComponent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _hasAnimated = false;
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    widget.scrollController.addListener(_checkVisibility);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkVisibility);
    _controller.dispose();
    super.dispose();
  }

  void _checkVisibility() {
    if (_hasAnimated || !mounted) return;

    final RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return;

    final position = renderObject.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;

    final bool isVisible =
        position.dy < screenHeight + 50 &&
        position.dy + renderObject.size.height > -50;

    if (isVisible) {
      _hasAnimated = true;
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: _key,
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - _animation.value)),
          child: Opacity(
            opacity: _animation.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.95 + (0.05 * _animation.value),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
