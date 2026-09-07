import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../widgets/display_name_dialog.dart';

/// Aggregation granularity for Home list sections (Receipts, Senders, Insights).
enum _ListPeriod { week, month, year }

/// Ordering for Home list sections.
enum _ListSort { dateDesc, dateAsc, amountDesc, amountAsc }

const int _kListPreviewCount = 5;

/// One row in the Receipts / Insights lists, normalized across week/month/year
/// so rendering and sorting don't care which period produced it.
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

/// One ranked sender in the Top Senders list.
class _SenderEntry {
  const _SenderEntry({
    required this.name,
    required this.amount,
    required this.lastDate,
  });

  final String name;
  final double amount;
  final DateTime lastDate;
}

class _InsightSummary {
  const _InsightSummary({
    required this.grain,
    required this.bestAmount,
    required this.bestSub,
    required this.projected,
    required this.average,
    required this.active,
    required this.total,
  });

  final String grain;
  final double? bestAmount;
  final String? bestSub;
  final double projected;
  final double average;
  final int active;
  final int total;
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
  _ListPeriod _receiptPeriod = _ListPeriod.month;
  _ListSort _receiptSort = _ListSort.dateDesc;
  bool _receiptGrouped = false;
  bool _receiptExpanded = false;

  // Top Senders section controls.
  _ListPeriod _sendersPeriod = _ListPeriod.month;
  _ListSort _sendersSort = _ListSort.amountDesc;
  bool _sendersExpanded = false;

  // Income Insights section controls.
  _ListPeriod _insightsPeriod = _ListPeriod.month;
  _ListSort _insightsSort = _ListSort.dateDesc;
  bool _insightsExpanded = false;

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

  double get totalSentAmount => _transactions
      .where((t) => t.isSent)
      .fold<double>(0, (sum, t) => sum + t.amount);

  int get _activeReceivedMonths =>
      _monthlySummaries.where((s) => s.totalReceived > 0).length;

  double get monthlyAverageReceived => _activeReceivedMonths == 0
      ? 0
      : _monthlySummaries.fold<double>(0, (s, m) => s + m.totalReceived) /
          _activeReceivedMonths;

  double get highestTransaction => _transactions.isEmpty
      ? 0
      : _transactions
            .where((t) => t.isReceived)
            .map((t) => t.amount)
            .reduce((a, b) => a > b ? a : b);

  DateTime _periodWindowStart(_ListPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case _ListPeriod.week:
        return WeeklyTransactionSummary.startOfWeek(now);
      case _ListPeriod.month:
        return DateTime(now.year, now.month);
      case _ListPeriod.year:
        return DateTime(now.year);
    }
  }

  List<_SenderEntry> _senderEntries() {
    final start = _periodWindowStart(_sendersPeriod);
    final amounts = <String, double>{};
    final lastDates = <String, DateTime>{};
    for (final tx in _smsTransactions) {
      if (!tx.isReceived || tx.date.isBefore(start)) continue;
      amounts[tx.counterparty] = (amounts[tx.counterparty] ?? 0) + tx.amount;
      final prev = lastDates[tx.counterparty];
      if (prev == null || tx.date.isAfter(prev)) {
        lastDates[tx.counterparty] = tx.date;
      }
    }
    final entries = amounts.entries
        .map(
          (e) => _SenderEntry(
            name: e.key,
            amount: e.value,
            lastDate: lastDates[e.key]!,
          ),
        )
        .toList();
    entries.sort((a, b) {
      switch (_sendersSort) {
        case _ListSort.dateDesc:
          return b.lastDate.compareTo(a.lastDate);
        case _ListSort.dateAsc:
          return a.lastDate.compareTo(b.lastDate);
        case _ListSort.amountDesc:
          return b.amount.compareTo(a.amount);
        case _ListSort.amountAsc:
          return a.amount.compareTo(b.amount);
      }
    });
    return entries;
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

    // A new (or refreshed) batch of SMS arrived in realtime: re-parse so the
    // dashboard, and any Firestore sync it triggers, reflect the latest data.
    if (widget.firestoreSummaries == null &&
        !_sameMessages(oldWidget.messages, widget.messages)) {
      setState(_processTransactions);
    }
  }

  bool _sameMessages(List<SmsMessage> a, List<SmsMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    return a.first.body == b.first.body &&
        a.first.date?.millisecondsSinceEpoch ==
            b.first.date?.millisecondsSinceEpoch;
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
                            delay: const Duration(milliseconds: 75),
                            child: _buildInOutBarChart(),
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
                            delay: const Duration(milliseconds: 225),
                            child: _buildCumulativeChart(),
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
                          const SizedBox(height: 12),
                          _ScrollAnimatedComponent(
                            scrollController: _scrollController,
                            delay: const Duration(milliseconds: 400),
                            child: _buildIncomeInsightsCard(),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _heroInfoPill(
                        Icons.trending_up,
                        '${_transactions.where((t) => t.isReceived).length} transactions',
                      ),
                      if (monthlyAverageReceived > 0)
                        _heroInfoPill(
                          Icons.calendar_month_rounded,
                          '${currencyFormat.format(monthlyAverageReceived)}/mo avg',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroInfoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            child: Icon(icon, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _summaryStat(
                    'Received',
                    selectedSummary.totalReceived,
                    successColor,
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                    'Sent',
                    selectedSummary.totalSent,
                    dangerColor,
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                    'Net',
                    selectedSummary.netAmount,
                    selectedSummary.netAmount >= 0
                        ? successColor
                        : dangerColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            currencyFormat.format(value),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
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
      [Color(0xFFE11D48), Color(0xFFFB7185)],
      [Color(0xFF0EA5E9), Color(0xFF7DD3FC)],
    ];

    final netFlow = totalReceivedAmount - totalSentAmount;

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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildAnimatedMetricCard(
                  'Total Sent',
                  currencyFormat.format(totalSentAmount),
                  Icons.arrow_outward_rounded,
                  metricGradients[4],
                  4,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAnimatedMetricCard(
                  'Net Flow',
                  '${netFlow >= 0 ? '+' : ''}${currencyFormat.format(netFlow)}',
                  Icons.swap_vert_rounded,
                  metricGradients[5],
                  5,
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

  Widget _buildInOutBarChart() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    // Keep the last 8 months so grouped bars stay readable.
    final recent = _monthlySummaries.length <= 8
        ? _monthlySummaries
        : _monthlySummaries.sublist(_monthlySummaries.length - 8);
    final maxVal = recent.fold<double>(
      0,
      (m, s) =>
          [m, s.totalReceived, s.totalSent].reduce((a, b) => a > b ? a : b),
    );
    if (maxVal <= 0) return const SizedBox.shrink();

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Money In vs Out',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                _chartLegendDot('In', successColor),
                const SizedBox(width: 10),
                _chartLegendDot('Out', dangerColor),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxVal * 1.15,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= recent.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('MMM').format(recent[idx].month),
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              value >= 1000000
                                  ? '${(value / 1000000).toStringAsFixed(1)}M'
                                  : '${(value / 1000).toStringAsFixed(0)}K',
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 46,
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
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: cardColor,
                      tooltipRoundedRadius: 12,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final summary = recent[group.x.toInt()];
                        final isIn = rodIndex == 0;
                        return BarTooltipItem(
                          '${DateFormat('MMM yyyy').format(summary.month)}\n',
                          TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  '${isIn ? 'In' : 'Out'}: ${currencyFormat.format(rod.toY)}',
                              style: TextStyle(
                                color: isIn ? successColor : dangerColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  barGroups: recent.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barsSpace: 3,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.totalReceived,
                          color: successColor,
                          width: 7,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                        BarChartRodData(
                          toY: entry.value.totalSent,
                          color: dangerColor,
                          width: 7,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCumulativeChart() {
    if (_monthlySummaries.length < 2) return const SizedBox.shrink();

    double running = 0;
    final spots = <FlSpot>[];
    for (var i = 0; i < _monthlySummaries.length; i++) {
      running += _monthlySummaries[i].totalReceived;
      spots.add(FlSpot(i.toDouble(), running));
    }
    if (running <= 0) return const SizedBox.shrink();

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
                  'Cumulative Income',
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
                  decoration: AppDecorations.iconBadge(
                    _c,
                    context,
                    [accentPurple, accentPurple.withValues(alpha: 0.7)],
                  ),
                  child: Text(
                    currencyFormat.format(running),
                    style: TextStyle(
                      color: AppDecorations.iconBadgeForeground(
                        _c,
                        context,
                        [accentPurple],
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: running * 1.1,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _monthlySummaries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat(
                                'MMM',
                              ).format(_monthlySummaries[idx].month),
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              value >= 1000000
                                  ? '${(value / 1000000).toStringAsFixed(1)}M'
                                  : '${(value / 1000).toStringAsFixed(0)}K',
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 50,
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.25,
                      preventCurveOverShooting: true,
                      color: accentPurple,
                      barWidth: 2.4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: AppDecorations.chartAreaFill(accentPurple),
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
                            'Through ${DateFormat('MMM yyyy').format(monthData.month)}\n',
                            TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            children: [
                              TextSpan(
                                text: currencyFormat.format(spot.y),
                                style: TextStyle(
                                  color: accentPurple,
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

  Widget _chartLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    final hasAnySenders = _smsTransactions.any((t) => t.isReceived);
    if (!hasAnySenders) return const SizedBox.shrink();

    final all = _senderEntries();
    final visible =
        _sendersExpanded ? all : all.take(_kListPreviewCount).toList();
    final windowReceived = all.fold<double>(0, (s, e) => s + e.amount);
    final maxAmount =
        visible.fold<double>(0, (m, e) => e.amount > m ? e.amount : m);
    final barMax = maxAmount > 0 ? maxAmount : 1.0;

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
                Expanded(
                  child: Text(
                    'Top Senders',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                _buildSortButton(
                  current: _sendersSort,
                  onChanged: (v) => setState(() => _sendersSort = v),
                ),
              ],
            ),
          ),
          _periodChipRow(
            current: _sendersPeriod,
            onChanged: (v) => setState(() {
              _sendersPeriod = v;
              _sendersExpanded = false;
            }),
          ),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Text(
                'No senders in this period.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Column(
                children: [
                  for (final entry in visible.asMap().entries)
                    _buildSenderRow(
                      index: entry.key,
                      sender: entry.value,
                      maxAmount: barMax,
                      windowReceived: windowReceived,
                    ),
                ],
              ),
            ),
            _sectionExpandButton(
              total: all.length,
              expanded: _sendersExpanded,
              onToggle: () =>
                  setState(() => _sendersExpanded = !_sendersExpanded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSenderRow({
    required int index,
    required _SenderEntry sender,
    required double maxAmount,
    required double windowReceived,
  }) {
    final percentage = sender.amount / maxAmount * 100;
    const gradientColors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];
    final color = gradientColors[index % gradientColors.length];

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
                          [color, color.withValues(alpha: 0.7)],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: AppDecorations.iconBadgeForeground(
                                _c,
                                context,
                                [color],
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
                          sender.name,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormat.format(sender.amount),
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (windowReceived > 0)
                      Text(
                        '${(sender.amount / windowReceived * 100).toStringAsFixed(1)}% of income',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
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
                    backgroundColor: textSecondary.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeInsightsCard() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final summary = _insightSummaryForPeriod();
    final buckets = _periodBuckets(_insightsPeriod, _insightsSort);
    final consistency =
        summary.total == 0 ? 0.0 : summary.active / summary.total;

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
                    accentColor,
                  ),
                  child: Icon(
                    Icons.insights_rounded,
                    color: AppDecorations.sectionIconForeground(
                      _c,
                      context,
                      accentColor,
                    ),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Income Insights',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                _buildSortButton(
                  current: _insightsSort,
                  onChanged: (v) => setState(() => _insightsSort = v),
                ),
              ],
            ),
          ),
          _periodChipRow(
            current: _insightsPeriod,
            onChanged: (v) => setState(() {
              _insightsPeriod = v;
              _insightsExpanded = false;
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Column(
              children: [
                if (summary.bestAmount != null)
                  _insightRow(
                    Icons.star_rounded,
                    successColor,
                    'Best ${summary.grain}',
                    currencyFormat.format(summary.bestAmount),
                    sub: summary.bestSub,
                  ),
                if (summary.projected > 0)
                  _insightRow(
                    Icons.query_stats_rounded,
                    accentPurple,
                    'Projected this ${summary.grain}',
                    currencyFormat.format(summary.projected),
                    sub: 'At the current daily pace',
                  ),
                if (summary.average > 0)
                  _insightRow(
                    Icons.stacked_line_chart_rounded,
                    primaryColor,
                    '3-${summary.grain} average',
                    currencyFormat.format(summary.average),
                    sub: 'Last completed ${summary.grain}s',
                  ),
                _insightRow(
                  Icons.event_available_rounded,
                  accentColor,
                  'Active ${summary.grain}s',
                  '${summary.active} of ${summary.total}',
                  sub:
                      '${(consistency * 100).toStringAsFixed(0)}% of tracked ${summary.grain}s had income',
                ),
              ],
            ),
          ),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Text(
                _insightsPeriod == _ListPeriod.week
                    ? "Weekly breakdown isn't available for this account yet."
                    : 'No income periods to show.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            )
          else ...[
            ..._receiptRows(
              buckets,
              maxTiles: _insightsExpanded ? null : _kListPreviewCount,
              period: _insightsPeriod,
              showSent: false,
            ),
            _sectionExpandButton(
              total: buckets.length,
              expanded: _insightsExpanded,
              onToggle: () =>
                  setState(() => _insightsExpanded = !_insightsExpanded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _insightRow(
    IconData icon,
    Color color,
    String label,
    String value, {
    String? sub,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: AppDecorations.sectionIcon(_c, context, color),
            child: Icon(
              icon,
              size: 16,
              color: AppDecorations.sectionIconForeground(_c, context, color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: TextStyle(
                      color: textSecondary.withValues(alpha: 0.7),
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsList() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final buckets = _receiptBuckets();
    final title = switch (_receiptPeriod) {
      _ListPeriod.week => 'Weekly Receipts',
      _ListPeriod.month => 'Monthly Receipts',
      _ListPeriod.year => 'Yearly Receipts',
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
                _buildSortButton(
                  current: _receiptSort,
                  onChanged: (v) => setState(() => _receiptSort = v),
                ),
              ],
            ),
          ),
          _periodChipRow(
            current: _receiptPeriod,
            onChanged: (v) => setState(() {
              _receiptPeriod = v;
              _receiptExpanded = false;
            }),
            trailing: _receiptPeriod != _ListPeriod.year
                ? _buildGroupToggle()
                : null,
          ),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Text(
                _receiptPeriod == _ListPeriod.week
                    ? "Weekly breakdown isn't available for this account yet."
                    : 'No receipts to show.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            )
          else ...[
            ..._receiptRows(
              buckets,
              maxTiles: _receiptExpanded ? null : _kListPreviewCount,
            ),
            _sectionExpandButton(
              total: buckets.length,
              expanded: _receiptExpanded,
              onToggle: () =>
                  setState(() => _receiptExpanded = !_receiptExpanded),
            ),
          ],
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
  List<_ReceiptBucket> _receiptBuckets() =>
      _periodBuckets(_receiptPeriod, _receiptSort);

  List<_ReceiptBucket> _periodBuckets(_ListPeriod period, _ListSort sort) {
    final now = DateTime.now();
    final buckets = <_ReceiptBucket>[];

    switch (period) {
      case _ListPeriod.month:
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
      case _ListPeriod.year:
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
      case _ListPeriod.week:
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
      switch (sort) {
        case _ListSort.dateDesc:
          return b.date.compareTo(a.date);
        case _ListSort.dateAsc:
          return a.date.compareTo(b.date);
        case _ListSort.amountDesc:
          return b.received.compareTo(a.received);
        case _ListSort.amountAsc:
          return a.received.compareTo(b.received);
      }
    });
    return buckets;
  }

  _InsightSummary _insightSummaryForPeriod() {
    final period = _insightsPeriod;
    final grain = switch (period) {
      _ListPeriod.week => 'week',
      _ListPeriod.month => 'month',
      _ListPeriod.year => 'year',
    };
    final buckets = _periodBuckets(period, _ListSort.dateAsc);
    final now = DateTime.now();

    _ReceiptBucket? best;
    for (final b in buckets) {
      if (b.received <= 0) continue;
      if (best == null || b.received > best.received) best = b;
    }

    String? bestSub;
    if (best != null) {
      bestSub = switch (period) {
        _ListPeriod.week =>
          '${DateFormat('MMM d').format(best.date)} – ${DateFormat('MMM d').format(best.date.add(const Duration(days: 6)))}',
        _ListPeriod.month => DateFormat('MMMM yyyy').format(best.date),
        _ListPeriod.year => DateFormat('yyyy').format(best.date),
      };
    }

    double projected = 0;
    _ReceiptBucket? current;
    for (final b in buckets) {
      if (b.isCurrent) {
        current = b;
        break;
      }
    }
    if (current != null && current.received > 0) {
      switch (period) {
        case _ListPeriod.week:
          final elapsed =
              (now.difference(current.date).inDays + 1).clamp(1, 7);
          projected = current.received / elapsed * 7;
        case _ListPeriod.month:
          final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
          projected = current.received / now.day * daysInMonth;
        case _ListPeriod.year:
          final yearStart = DateTime(now.year);
          final daysInYear =
              DateTime(now.year, 12, 31).difference(yearStart).inDays + 1;
          final dayOfYear = now.difference(yearStart).inDays + 1;
          projected = current.received / dayOfYear * daysInYear;
      }
    }

    final completed = buckets.where((b) => !b.isCurrent).toList();
    final recent = completed.length <= 3
        ? completed
        : completed.sublist(completed.length - 3);
    final average = recent.isEmpty
        ? 0.0
        : recent.fold<double>(0, (s, b) => s + b.received) / recent.length;

    final active = buckets.where((b) => b.received > 0).length;
    return _InsightSummary(
      grain: grain,
      bestAmount: best?.received,
      bestSub: bestSub,
      projected: projected,
      average: average,
      active: active,
      total: buckets.length,
    );
  }

  // ---- Receipts rendering ---------------------------------------------------

  List<Widget> _receiptRows(
    List<_ReceiptBucket> buckets, {
    int? maxTiles,
    _ListPeriod? period,
    bool showSent = true,
  }) {
    final grain = period ?? _receiptPeriod;
    final divider = Divider(
      height: 1,
      indent: 14,
      endIndent: 14,
      color: cardBorder.withValues(alpha: 0.3),
    );

    Widget tile(_ReceiptBucket bucket) => _buildReceiptTile(
          bucket,
          period: grain,
          showSent: showSent,
        );

    // Flat list (no grouping, or year period which is already the coarsest).
    if (!_receiptGrouped || grain == _ListPeriod.year || period != null) {
      final visible = maxTiles == null
          ? buckets
          : buckets.take(maxTiles).toList();
      final rows = <Widget>[];
      for (var i = 0; i < visible.length; i++) {
        if (i > 0) rows.add(divider);
        rows.add(tile(visible[i]));
      }
      return rows;
    }

    // Grouped: weeks -> by month, months -> by year. Insertion order follows the
    // already-sorted buckets, so group order respects the active sort.
    final groups = <String, List<_ReceiptBucket>>{};
    String keyOf(_ReceiptBucket b) => grain == _ListPeriod.week
        ? DateFormat('yyyy-MM').format(b.date)
        : '${b.date.year}';
    for (final b in buckets) {
      groups.putIfAbsent(keyOf(b), () => <_ReceiptBucket>[]).add(b);
    }

    final rows = <Widget>[];
    var tilesShown = 0;
    for (final items in groups.values) {
      if (maxTiles != null && tilesShown >= maxTiles) break;
      final remaining =
          maxTiles == null ? items.length : maxTiles - tilesShown;
      final visibleItems = items.take(remaining).toList();
      if (visibleItems.isEmpty) continue;
      final subtotal =
          visibleItems.fold<double>(0, (s, b) => s + b.received);
      final label = grain == _ListPeriod.week
          ? DateFormat('MMMM yyyy').format(visibleItems.first.date)
          : '${visibleItems.first.date.year}';
      rows.add(_buildReceiptGroupHeader(label, subtotal));
      for (var i = 0; i < visibleItems.length; i++) {
        rows.add(tile(visibleItems[i]));
        if (i < visibleItems.length - 1) rows.add(divider);
      }
      tilesShown += visibleItems.length;
    }
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

  Widget _buildReceiptTile(
    _ReceiptBucket bucket, {
    _ListPeriod? period,
    bool showSent = true,
  }) {
    final grain = period ?? _receiptPeriod;
    final isCurrent = bucket.isCurrent;
    final top = switch (grain) {
      _ListPeriod.week => DateFormat('MMM').format(bucket.date),
      _ListPeriod.month => DateFormat('MMM').format(bucket.date),
      _ListPeriod.year => 'YR',
    };
    final bottom = switch (grain) {
      _ListPeriod.week => DateFormat('d').format(bucket.date),
      _ListPeriod.month => DateFormat('yy').format(bucket.date),
      _ListPeriod.year => DateFormat('yyyy').format(bucket.date),
    };
    final title = switch (grain) {
      _ListPeriod.week =>
        '${DateFormat('MMM d').format(bucket.date)} – ${DateFormat('MMM d').format(bucket.date.add(const Duration(days: 6)))}',
      _ListPeriod.month => DateFormat('MMMM yyyy').format(bucket.date),
      _ListPeriod.year => DateFormat('yyyy').format(bucket.date),
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
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currencyFormat.format(bucket.received),
              style: TextStyle(
                color: isCurrent ? primaryColor : textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (showSent && bucket.sent > 0)
              Text(
                '-${currencyFormat.format(bucket.sent)}',
                style: TextStyle(
                  color: dangerColor.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Shared list controls -------------------------------------------------

  Widget _periodChip({
    required String label,
    required _ListPeriod value,
    required _ListPeriod current,
    required ValueChanged<_ListPeriod> onChanged,
  }) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onChanged(value),
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

  Widget _periodChipRow({
    required _ListPeriod current,
    required ValueChanged<_ListPeriod> onChanged,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          _periodChip(
            label: 'Week',
            value: _ListPeriod.week,
            current: current,
            onChanged: onChanged,
          ),
          const SizedBox(width: 6),
          _periodChip(
            label: 'Month',
            value: _ListPeriod.month,
            current: current,
            onChanged: onChanged,
          ),
          const SizedBox(width: 6),
          _periodChip(
            label: 'Year',
            value: _ListPeriod.year,
            current: current,
            onChanged: onChanged,
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _sectionExpandButton({
    required int total,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    if (total <= _kListPreviewCount) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onToggle,
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: Text(
            expanded ? 'Show less' : 'Show all ($total)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
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

  Widget _buildSortButton({
    required _ListSort current,
    required ValueChanged<_ListSort> onChanged,
  }) {
    String labelFor(_ListSort s) => switch (s) {
      _ListSort.dateDesc => 'Newest',
      _ListSort.dateAsc => 'Oldest',
      _ListSort.amountDesc => 'Highest',
      _ListSort.amountAsc => 'Lowest',
    };

    return PopupMenuButton<_ListSort>(
      initialValue: current,
      tooltip: 'Sort',
      onSelected: onChanged,
      color: cardColor,
      itemBuilder: (context) => [
        for (final s in _ListSort.values)
          PopupMenuItem<_ListSort>(
            value: s,
            child: Row(
              children: [
                Icon(
                  switch (s) {
                    _ListSort.dateDesc => Icons.arrow_downward_rounded,
                    _ListSort.dateAsc => Icons.arrow_upward_rounded,
                    _ListSort.amountDesc => Icons.trending_down_rounded,
                    _ListSort.amountAsc => Icons.trending_up_rounded,
                  },
                  size: 16,
                  color: current == s ? primaryColor : textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  switch (s) {
                    _ListSort.dateDesc => 'Newest first',
                    _ListSort.dateAsc => 'Oldest first',
                    _ListSort.amountDesc => 'Highest amount',
                    _ListSort.amountAsc => 'Lowest amount',
                  },
                  style: TextStyle(
                    color: current == s ? primaryColor : textPrimary,
                    fontWeight:
                        current == s ? FontWeight.w700 : FontWeight.w500,
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
              labelFor(current),
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
