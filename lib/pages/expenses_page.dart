import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';

/// Aggregation granularity for the expense breakdown list.
enum _ExpensePeriod { week, month, year }

/// Ordering for the expense breakdown list.
enum _ExpenseSort { dateDesc, dateAsc, amountDesc, amountAsc }

/// One row in the expense breakdown, normalized across week/month/year so the
/// list rendering and sorting don't care which period produced it.
class _ExpenseBucket {
  const _ExpenseBucket({
    required this.date,
    required this.sent,
    required this.count,
    required this.isCurrent,
  });

  final DateTime date; // representative date (week start / month / year start)
  final double sent;
  final int count;
  final bool isCurrent; // contains "now" for the active period
}

/// Money-out view of the account: totals, spending trend, top recipients and a
/// week/month/year breakdown. Reads the same sources as the dashboard (SMS on
/// mobile, Firestore summaries on web) and applies the same statement
/// reconciliation, so statement-covered periods are never overwritten by SMS.
class ExpensesPage extends StatefulWidget {
  final List<SmsMessage> messages;
  final List<MonthlyTransactionSummary>? firestoreSummaries;
  final bool embeddedInShell;

  const ExpensesPage({
    super.key,
    required this.messages,
    this.firestoreSummaries,
    this.embeddedInShell = false,
  });

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final AuthService _authService = AuthService();

  // Raw SMS-parsed sent transactions (mobile path). Empty on the web/Firestore
  // path, where only monthly aggregates exist.
  List<Transaction> _sentTransactions = const <Transaction>[];
  // Monthly aggregates, statement-reconciled when a baseline exists.
  List<MonthlyTransactionSummary> _monthlySummaries = const [];
  // Weekly aggregates (statement baseline + post-cutoff SMS when backed).
  List<WeeklyTransactionSummary> _weeklySummaries = const [];

  int _selectedMonthIndex = 0;

  _ExpensePeriod _period = _ExpensePeriod.month;
  _ExpenseSort _sort = _ExpenseSort.dateDesc;

  final currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  AppColors get _c => Theme.of(context).extension<AppColors>()!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => _c.primary;
  Color get primaryDark => _c.primaryDark;
  Color get accentPurple => _c.accentPurple;
  Color get successColor => _c.success;
  Color get dangerColor => _c.danger;
  Color get bgColor => _c.bg;
  Color get cardColor => _c.card;
  Color get cardBorder => _c.cardBorder;
  Color get textPrimary => _c.textPrimary;
  Color get textSecondary => _c.textSecondary;

  // True when per-transaction detail (recipients, fees) is available; false on
  // the web/Firestore path which only has monthly aggregates.
  bool get _hasDetail => _sentTransactions.isNotEmpty;

  double get totalSpent =>
      _monthlySummaries.fold<double>(0, (sum, s) => sum + s.totalSent);

  int get totalSentCount => _hasDetail
      ? _sentTransactions.length
      : _monthlySummaries.fold<int>(0, (sum, s) => sum + s.transactionCount);

  double get totalFees =>
      _sentTransactions.fold<double>(0, (sum, t) => sum + t.fee);

  double get averageExpense {
    if (_hasDetail) {
      return _sentTransactions.isEmpty
          ? 0
          : _sentTransactions.fold<double>(0, (s, t) => s + t.amount) /
              _sentTransactions.length;
    }
    final monthsWithSpend =
        _monthlySummaries.where((s) => s.totalSent > 0).length;
    return monthsWithSpend == 0 ? 0 : totalSpent / monthsWithSpend;
  }

  double get highestExpense {
    if (_hasDetail) {
      return _sentTransactions
          .map((t) => t.amount)
          .fold<double>(0, (a, b) => a > b ? a : b);
    }
    return _monthlySummaries
        .map((s) => s.totalSent)
        .fold<double>(0, (a, b) => a > b ? a : b);
  }

  double get totalIncome =>
      _monthlySummaries.fold<double>(0, (sum, s) => sum + s.totalReceived);

  double get averageMonthlySpend {
    final active = _monthlySummaries.where((s) => s.totalSent > 0).length;
    return active == 0 ? 0 : totalSpent / active;
  }

  MonthlyTransactionSummary? get _highestSpendMonth {
    final withData = _monthlySummaries.where((s) => s.totalSent > 0);
    if (withData.isEmpty) return null;
    return withData.reduce((a, b) => a.totalSent >= b.totalSent ? a : b);
  }

  /// Current month's spend extrapolated to a full month at the current daily
  /// pace. 0 when the current month has no spending yet.
  double get _projectedThisMonthSpend {
    final now = DateTime.now();
    MonthlyTransactionSummary? current;
    for (final s in _monthlySummaries) {
      if (s.month.year == now.year && s.month.month == now.month) {
        current = s;
        break;
      }
    }
    if (current == null || current.totalSent <= 0) return 0;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return current.totalSent / now.day * daysInMonth;
  }

  /// Weekday with the highest total sent (SMS path only).
  String? get _busiestSpendDay {
    if (!_hasDetail) return null;
    final byDay = <int, double>{};
    for (final t in _sentTransactions) {
      byDay[t.date.weekday] = (byDay[t.date.weekday] ?? 0) + t.amount;
    }
    if (byDay.isEmpty) return null;
    final top = byDay.entries.reduce((a, b) => a.value >= b.value ? a : b);
    const names = [
      'Mondays',
      'Tuesdays',
      'Wednesdays',
      'Thursdays',
      'Fridays',
      'Saturdays',
      'Sundays',
    ];
    return names[top.key - 1];
  }

  Transaction? get _biggestPayment {
    if (_sentTransactions.isEmpty) return null;
    return _sentTransactions.reduce((a, b) => a.amount >= b.amount ? a : b);
  }

  List<MapEntry<String, double>> get topRecipients {
    final totals = <String, double>{};
    for (final tx in _sentTransactions) {
      totals[tx.counterparty] = (totals[tx.counterparty] ?? 0) + tx.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  @override
  void initState() {
    super.initState();
    _processTransactions();
  }

  @override
  void didUpdateWidget(ExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-parse when a new (or refreshed) batch of SMS arrives in realtime.
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

  void _processTransactions() {
    final firestoreSummaries = widget.firestoreSummaries;
    if (firestoreSummaries != null) {
      // Web path: monthly aggregates only, nothing to reconcile.
      _monthlySummaries = List<MonthlyTransactionSummary>.from(
        firestoreSummaries,
      )..sort((a, b) => a.month.compareTo(b.month));
      _selectCurrentMonth();
      return;
    }

    final transactions = widget.messages
        .map(
          (msg) =>
              Transaction.fromSmsMessage(msg.body ?? '', smsDate: msg.date),
        )
        .where((t) => t != null)
        .cast<Transaction>()
        .toList();

    _sentTransactions = transactions.where((t) => t.isSent).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final monthlyData = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
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
          .where((t) => t.isReceived)
          .fold<double>(0, (sum, t) => sum + t.amount);
      final sentAmount = entry.value
          .where((t) => t.isSent)
          .fold<double>(0, (sum, t) => sum + t.amount);
      return MonthlyTransactionSummary(
        month: entry.key,
        totalReceived: receivedAmount,
        totalSent: sentAmount,
        transactionCount: entry.value.length,
      );
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    _weeklySummaries = WeeklyTransactionSummary.fromTransactions(transactions);

    _selectCurrentMonth();

    // Reconcile against any official MoMo-statement baseline so SMS can only
    // ever extend statement-covered periods, never overwrite them.
    _reconcileWithStatement().ignore();
  }

  Future<void> _reconcileWithStatement() async {
    final backing = await _authService.getStatementBacking();
    if (!mounted || backing == null) return;

    final smsAfterCutoff = widget.messages
        .map(
          (msg) =>
              Transaction.fromSmsMessage(msg.body ?? '', smsDate: msg.date),
        )
        .where((t) => t != null)
        .cast<Transaction>()
        .where((t) => t.date.isAfter(backing.through))
        .toList();

    setState(() {
      _monthlySummaries =
          _mergeMonthly(backing.monthly, smsAfterCutoff);
      _weeklySummaries = _mergeWeekly(backing.weekly, smsAfterCutoff);
      _selectCurrentMonth();
    });
  }

  /// Baseline months + post-cutoff SMS transactions, summed per month. Months
  /// covered by the statement keep their authoritative baseline value.
  List<MonthlyTransactionSummary> _mergeMonthly(
    List<MonthlyTransactionSummary> baseline,
    List<Transaction> extraTransactions,
  ) {
    final byMonth = <DateTime, MonthlyTransactionSummary>{
      for (final s in baseline) DateTime(s.month.year, s.month.month): s,
    };
    final extra = <DateTime, List<Transaction>>{};
    for (final t in extraTransactions) {
      final m = DateTime(t.date.year, t.date.month);
      extra.putIfAbsent(m, () => []).add(t);
    }

    final months = <DateTime>{...byMonth.keys, ...extra.keys};
    return months.map((m) {
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
  }

  /// Weekly analogue of [_mergeMonthly] (weeks start on Monday).
  List<WeeklyTransactionSummary> _mergeWeekly(
    List<WeeklyTransactionSummary> baseline,
    List<Transaction> extraTransactions,
  ) {
    final byWeek = <DateTime, WeeklyTransactionSummary>{
      for (final s in baseline)
        DateTime(s.weekStart.year, s.weekStart.month, s.weekStart.day): s,
    };
    final extra = <DateTime, List<Transaction>>{};
    for (final t in extraTransactions) {
      final w = WeeklyTransactionSummary.startOfWeek(t.date);
      extra.putIfAbsent(w, () => []).add(t);
    }

    final weeks = <DateTime>{...byWeek.keys, ...extra.keys};
    return weeks.map((w) {
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
  }

  void _selectCurrentMonth() {
    final now = DateTime.now();
    final currentMonthIndex = _monthlySummaries.indexWhere(
      (summary) =>
          summary.month.year == now.year && summary.month.month == now.month,
    );
    _selectedMonthIndex = currentMonthIndex >= 0
        ? _monthlySummaries.length - 1 - currentMonthIndex
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final hasSpending = _monthlySummaries.any((s) => s.totalSent > 0);

    final body = !hasSpending
        ? Center(
            child: Text(
              'No expenses found',
              style: TextStyle(color: textSecondary),
            ),
          )
        : Stack(
            children: [
              Container(
                decoration: AppDecorations.pageBackground(_c, context),
              ),
              ListView(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: widget.embeddedInShell ? 88 : 24,
                ),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 12),
                  _buildSpendingChart(),
                  const SizedBox(height: 12),
                  if (_hasDetail) ...[
                    _buildWeekdayChart(),
                    const SizedBox(height: 12),
                  ],
                  _buildMonthlySummaryCard(),
                  const SizedBox(height: 12),
                  _buildMetricCards(),
                  const SizedBox(height: 12),
                  _buildSpendingInsightsCard(),
                  const SizedBox(height: 12),
                  if (_hasDetail && topRecipients.isNotEmpty) ...[
                    _buildRecipientDonut(),
                    const SizedBox(height: 12),
                    _buildTopRecipientsCard(),
                    const SizedBox(height: 12),
                  ],
                  _buildBreakdownList(),
                ],
              ),
            ],
          );

    if (widget.embeddedInShell) {
      return body;
    }

    return Scaffold(backgroundColor: bgColor, body: body);
  }

  // ---- Hero -----------------------------------------------------------------

  Widget _buildHeroCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.hero(
        _c,
        context,
        gradientColors: const [
          Color(0xFFE11D48),
          Color(0xFFBE123C),
          Color(0xFF9F1239),
        ],
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
                          Icons.arrow_outward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Total Spent',
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
                    tween: Tween(begin: 0.0, end: totalSpent),
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
                      _heroPill(
                        Icons.trending_down,
                        _hasDetail
                            ? '$totalSentCount payments'
                            : '${_monthlySummaries.where((s) => s.totalSent > 0).length} months',
                      ),
                      if (averageMonthlySpend > 0)
                        _heroPill(
                          Icons.calendar_month_rounded,
                          '${currencyFormat.format(averageMonthlySpend)}/mo avg',
                        ),
                      if (_hasDetail && totalFees > 0)
                        _heroPill(
                          Icons.money_off_outlined,
                          '${currencyFormat.format(totalFees)} fees',
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

  Widget _heroPill(IconData icon, String label) {
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

  // ---- Spending trend ---------------------------------------------------------

  Widget _buildSpendingChart() {
    if (_monthlySummaries.length < 2) return const SizedBox.shrink();

    final maxDataValue = _monthlySummaries
        .map((s) => s.totalSent)
        .reduce((a, b) => a > b ? a : b);
    if (maxDataValue <= 0) return const SizedBox.shrink();

    return AppGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spending Trend',
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
                    [dangerColor, dangerColor.withValues(alpha: 0.7)],
                  ),
                  child: Text(
                    '${_monthlySummaries.length} mo',
                    style: TextStyle(
                      color: AppDecorations.iconBadgeForeground(
                        _c,
                        context,
                        [dangerColor],
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
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
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
                  minY: 0,
                  maxY: maxDataValue * 1.15,
                  extraLinesData: ExtraLinesData(
                    horizontalLines: averageMonthlySpend > 0
                        ? [
                            HorizontalLine(
                              y: averageMonthlySpend,
                              color: accentPurple,
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
                                  color: accentPurple,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                labelResolver: (line) =>
                                    'Avg: ${currencyFormat.format(line.y)}',
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
                          entry.value.totalSent,
                        );
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.35,
                      preventCurveOverShooting: true,
                      color: dangerColor,
                      barWidth: 2.4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: _isDark ? Colors.white : cardColor,
                            strokeWidth: 2,
                            strokeColor: dangerColor,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: AppDecorations.chartAreaFill(dangerColor),
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
                                  color: dangerColor,
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

  // ---- Weekday pattern ---------------------------------------------------------

  Widget _buildWeekdayChart() {
    if (!_hasDetail) return const SizedBox.shrink();

    final totals = List<double>.filled(7, 0);
    for (final t in _sentTransactions) {
      totals[t.date.weekday - 1] += t.amount;
    }
    final maxVal = totals.reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) return const SizedBox.shrink();
    final maxIndex = totals.indexOf(maxVal);

    const shortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const fullNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return AppGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Spending by Day',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: AppDecorations.tintedChip(context, dangerColor),
                  child: Text(
                    'Peak: ${shortNames[maxIndex]}',
                    style: TextStyle(
                      color: dangerColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
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
                          if (idx < 0 || idx >= 7) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              shortNames[idx],
                              style: TextStyle(
                                fontSize: 10,
                                color: idx == maxIndex
                                    ? dangerColor
                                    : textSecondary,
                                fontWeight: idx == maxIndex
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 26,
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
                        return BarTooltipItem(
                          '${fullNames[group.x.toInt()]}\n',
                          TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: currencyFormat.format(rod.toY),
                              style: TextStyle(
                                color: dangerColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  barGroups: List.generate(7, (i) {
                    final isPeak = i == maxIndex;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: totals[i],
                          color: isPeak
                              ? dangerColor
                              : dangerColor.withValues(alpha: 0.45),
                          width: 16,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Recipient share donut -----------------------------------------------------

  Widget _buildRecipientDonut() {
    final recipients = topRecipients;
    if (recipients.isEmpty) return const SizedBox.shrink();

    final sentTotal = _sentTransactions.fold<double>(0, (s, t) => s + t.amount);
    if (sentTotal <= 0) return const SizedBox.shrink();

    final topSum = recipients.fold<double>(0, (s, e) => s + e.value);
    final other = (sentTotal - topSum).clamp(0.0, double.infinity);
    final otherColor = textSecondary.withValues(alpha: 0.3);

    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];

    return AppGlassCard(
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
                    Icons.donut_large_rounded,
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
                  'Where It Goes',
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
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 36,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                          sections: [
                            for (var i = 0; i < recipients.length; i++)
                              PieChartSectionData(
                                value: recipients[i].value,
                                color: colors[i % colors.length],
                                radius: 26,
                                showTitle: false,
                              ),
                            if (other > 0)
                              PieChartSectionData(
                                value: other,
                                color: otherColor,
                                radius: 26,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Top ${recipients.length}',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(topSum / sentTotal * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < recipients.length; i++)
                        _donutLegendRow(
                          colors[i % colors.length],
                          recipients[i].key,
                          recipients[i].value / sentTotal,
                        ),
                      if (other > 0)
                        _donutLegendRow(otherColor, 'Other', other / sentTotal),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _donutLegendRow(Color color, String label, double share) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${(share * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Monthly summary --------------------------------------------------------

  Widget _buildMonthlySummaryCard() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((b, a) => a.month.compareTo(b.month));

    final selectedIndex =
        _selectedMonthIndex.clamp(0, sortedSummaries.length - 1);
    final selectedSummary = sortedSummaries[selectedIndex];
    final previousIndex = selectedIndex + 1;
    final previousSummary = previousIndex < sortedSummaries.length
        ? sortedSummaries[previousIndex]
        : null;

    final percentageChange =
        previousSummary != null && previousSummary.totalSent > 0
            ? ((selectedSummary.totalSent - previousSummary.totalSent) /
                previousSummary.totalSent *
                100)
            : null;
    // For spending, a decrease is the good outcome.
    final spentLess = (percentageChange ?? 0) <= 0;

    return AppGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Spending',
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
                    value: selectedIndex,
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
                        setState(() => _selectedMonthIndex = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: selectedSummary.totalSent),
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
              'Spent in ${DateFormat('MMMM yyyy').format(selectedSummary.month)}',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (percentageChange != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.tintedChip(
                  context,
                  spentLess ? successColor : dangerColor,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: spentLess
                            ? successColor.withValues(alpha: 0.2)
                            : dangerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        spentLess
                            ? Icons.trending_down
                            : Icons.trending_up,
                        color: spentLess ? successColor : dangerColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${percentageChange >= 0 ? '+' : ''}${percentageChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: spentLess ? successColor : dangerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'vs ${DateFormat('MMM').format(previousSummary!.month)}',
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
                  child: _monthStat(
                    'Income',
                    currencyFormat.format(selectedSummary.totalReceived),
                    successColor,
                  ),
                ),
                Expanded(
                  child: _monthStat(
                    'Spent',
                    currencyFormat.format(selectedSummary.totalSent),
                    dangerColor,
                  ),
                ),
                Expanded(
                  child: _monthStat(
                    'Of income',
                    selectedSummary.totalReceived > 0
                        ? '${(selectedSummary.totalSent / selectedSummary.totalReceived * 100).toStringAsFixed(0)}%'
                        : '—',
                    accentPurple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthStat(String label, String value, Color color) {
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
            value,
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

  // ---- Metric cards -------------------------------------------------------------

  Widget _buildMetricCards() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final thisMonthSummary = _monthlySummaries.firstWhere(
      (s) => s.month.year == thisMonth.year && s.month.month == thisMonth.month,
      orElse: () => MonthlyTransactionSummary(
        month: thisMonth,
        totalReceived: 0,
        totalSent: 0,
        transactionCount: 0,
      ),
    );

    const metricGradients = [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFFEC4899), Color(0xFFF472B6)],
      [Color(0xFF14B8A6), Color(0xFF5EEAD4)],
      [Color(0xFFF59E0B), Color(0xFFFBBF24)],
      [Color(0xFF0EA5E9), Color(0xFF7DD3FC)],
      [Color(0xFFE11D48), Color(0xFFFB7185)],
    ];

    final netFlow = totalIncome - totalSpent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  _hasDetail ? 'Avg Payment' : 'Avg per Month',
                  currencyFormat.format(averageExpense),
                  Icons.analytics_outlined,
                  metricGradients[0],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'This Month',
                  currencyFormat.format(thisMonthSummary.totalSent),
                  Icons.calendar_today_outlined,
                  metricGradients[1],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  _hasDetail ? 'Biggest Payment' : 'Highest Month',
                  currencyFormat.format(highestExpense),
                  Icons.arrow_upward_rounded,
                  metricGradients[2],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Total Fees',
                  _hasDetail ? currencyFormat.format(totalFees) : '—',
                  Icons.money_off_outlined,
                  metricGradients[3],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Net Flow',
                  '${netFlow >= 0 ? '+' : ''}${currencyFormat.format(netFlow)}',
                  Icons.swap_vert_rounded,
                  metricGradients[4],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Spend Rate',
                  totalIncome > 0
                      ? '${(totalSpent / totalIncome * 100).toStringAsFixed(1)}% of income'
                      : '—',
                  Icons.speed_rounded,
                  metricGradients[5],
                ),
              ),
            ],
          ),
        ],
      ),
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

  // ---- Top recipients ---------------------------------------------------------

  Widget _buildTopRecipientsCard() {
    final recipients = topRecipients;
    final maxAmount = recipients.first.value;
    final paymentCounts = <String, int>{};
    for (final tx in _sentTransactions) {
      paymentCounts[tx.counterparty] =
          (paymentCounts[tx.counterparty] ?? 0) + 1;
    }
    final sentTotal =
        _sentTransactions.fold<double>(0, (s, t) => s + t.amount);

    const gradientColors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];

    return AppGlassCard(
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
                    dangerColor,
                  ),
                  child: Icon(
                    Icons.outbox_rounded,
                    color: AppDecorations.sectionIconForeground(
                      _c,
                      context,
                      dangerColor,
                    ),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Top Recipients',
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
            ...recipients.asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value;
              final percentage = data.value / maxAmount * 100;
              final color = gradientColors[index % gradientColors.length];

              return Padding(
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
                                      color:
                                          AppDecorations.iconBadgeForeground(
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currencyFormat.format(data.value),
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              sentTotal > 0
                                  ? '${paymentCounts[data.key] ?? 0} payment${(paymentCounts[data.key] ?? 0) != 1 ? 's' : ''} · ${(data.value / sentTotal * 100).toStringAsFixed(1)}%'
                                  : '${paymentCounts[data.key] ?? 0} payments',
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
                            backgroundColor:
                                textSecondary.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---- Insights ---------------------------------------------------------------

  Widget _buildSpendingInsightsCard() {
    final highest = _highestSpendMonth;
    final projected = _projectedThisMonthSpend;
    final busiestDay = _busiestSpendDay;
    final biggest = _biggestPayment;
    final feeRatio = _hasDetail && totalSpent > 0 ? totalFees / totalSpent : 0.0;

    final rows = <Widget>[
      if (highest != null)
        _insightRow(
          Icons.local_fire_department_rounded,
          dangerColor,
          'Highest spending month',
          currencyFormat.format(highest.totalSent),
          sub: DateFormat('MMMM yyyy').format(highest.month),
        ),
      if (projected > 0)
        _insightRow(
          Icons.query_stats_rounded,
          accentPurple,
          'Projected this month',
          currencyFormat.format(projected),
          sub: 'At the current daily pace',
        ),
      if (biggest != null)
        _insightRow(
          Icons.payments_rounded,
          primaryColor,
          'Biggest payment',
          currencyFormat.format(biggest.amount),
          sub:
              '${biggest.counterparty} · ${DateFormat('MMM d, yyyy').format(biggest.date)}',
        ),
      if (busiestDay != null)
        _insightRow(
          Icons.event_repeat_rounded,
          successColor,
          'You spend most on',
          busiestDay,
          sub: 'By total amount sent',
        ),
      if (feeRatio > 0)
        _insightRow(
          Icons.percent_rounded,
          const Color(0xFFF59E0B),
          'Fees eat up',
          '${(feeRatio * 100).toStringAsFixed(1)}%',
          sub: 'Of everything you send',
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return AppGlassCard(
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
                    accentPurple,
                  ),
                  child: Icon(
                    Icons.insights_rounded,
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
                  'Spending Insights',
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
            ...rows,
          ],
        ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  // ---- Breakdown list -----------------------------------------------------------

  Widget _buildBreakdownList() {
    final buckets = _expenseBuckets();
    final title = switch (_period) {
      _ExpensePeriod.week => 'Weekly Spending',
      _ExpensePeriod.month => 'Monthly Breakdown',
      _ExpensePeriod.year => 'Yearly Breakdown',
    };

    return AppGlassCard(
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
                _buildSortButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                _periodChip('Week', _ExpensePeriod.week),
                const SizedBox(width: 6),
                _periodChip('Month', _ExpensePeriod.month),
                const SizedBox(width: 6),
                _periodChip('Year', _ExpensePeriod.year),
              ],
            ),
          ),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Text(
                _period == _ExpensePeriod.week
                    ? "Weekly breakdown isn't available for this account yet."
                    : 'No spending to show.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            )
          else
            ..._expenseRows(buckets),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// Builds normalized, sorted buckets for the selected period. Periods with no
  /// spending are skipped so the list only shows months/weeks money went out.
  List<_ExpenseBucket> _expenseBuckets() {
    final now = DateTime.now();
    final buckets = <_ExpenseBucket>[];

    switch (_period) {
      case _ExpensePeriod.month:
        for (final s in _monthlySummaries) {
          if (s.totalSent <= 0) continue;
          buckets.add(_ExpenseBucket(
            date: DateTime(s.month.year, s.month.month),
            sent: s.totalSent,
            count: _sentCountForMonth(s),
            isCurrent: s.month.year == now.year && s.month.month == now.month,
          ));
        }
        break;
      case _ExpensePeriod.year:
        final byYear = <int, List<double>>{}; // year -> [sent, count]
        for (final s in _monthlySummaries) {
          if (s.totalSent <= 0) continue;
          final acc = byYear.putIfAbsent(s.month.year, () => [0.0, 0.0]);
          acc[0] += s.totalSent;
          acc[1] += _sentCountForMonth(s);
        }
        byYear.forEach((year, acc) {
          buckets.add(_ExpenseBucket(
            date: DateTime(year),
            sent: acc[0],
            count: acc[1].toInt(),
            isCurrent: year == now.year,
          ));
        });
        break;
      case _ExpensePeriod.week:
        final weekNow = WeeklyTransactionSummary.startOfWeek(now);
        for (final w in _weeklySummaries) {
          if (w.totalSent <= 0) continue;
          buckets.add(_ExpenseBucket(
            date: w.weekStart,
            sent: w.totalSent,
            count: _sentCountForWeek(w),
            isCurrent: w.weekStart == weekNow,
          ));
        }
        break;
    }

    buckets.sort((a, b) {
      switch (_sort) {
        case _ExpenseSort.dateDesc:
          return b.date.compareTo(a.date);
        case _ExpenseSort.dateAsc:
          return a.date.compareTo(b.date);
        case _ExpenseSort.amountDesc:
          return b.sent.compareTo(a.sent);
        case _ExpenseSort.amountAsc:
          return a.sent.compareTo(b.sent);
      }
    });
    return buckets;
  }

  /// Sent-transaction count for a month: exact when SMS detail exists, else the
  /// aggregate count (which includes received transactions).
  int _sentCountForMonth(MonthlyTransactionSummary s) {
    if (!_hasDetail) return s.transactionCount;
    return _sentTransactions
        .where((t) =>
            t.date.year == s.month.year && t.date.month == s.month.month)
        .length;
  }

  int _sentCountForWeek(WeeklyTransactionSummary w) {
    if (!_hasDetail) return w.transactionCount;
    return _sentTransactions
        .where(
            (t) => WeeklyTransactionSummary.startOfWeek(t.date) == w.weekStart)
        .length;
  }

  List<Widget> _expenseRows(List<_ExpenseBucket> buckets) {
    final divider = Divider(
      height: 1,
      indent: 14,
      endIndent: 14,
      color: cardBorder.withValues(alpha: 0.3),
    );

    final periodTotal = buckets.fold<double>(0, (s, b) => s + b.sent);
    final rows = <Widget>[];
    for (var i = 0; i < buckets.length; i++) {
      if (i > 0) rows.add(divider);
      rows.add(_buildExpenseTile(buckets[i], periodTotal));
    }
    return rows;
  }

  Widget _buildExpenseTile(_ExpenseBucket bucket, double periodTotal) {
    final isCurrent = bucket.isCurrent;
    final top = switch (_period) {
      _ExpensePeriod.week => DateFormat('MMM').format(bucket.date),
      _ExpensePeriod.month => DateFormat('MMM').format(bucket.date),
      _ExpensePeriod.year => 'YR',
    };
    final bottom = switch (_period) {
      _ExpensePeriod.week => DateFormat('d').format(bucket.date),
      _ExpensePeriod.month => DateFormat('yy').format(bucket.date),
      _ExpensePeriod.year => DateFormat('yyyy').format(bucket.date),
    };
    final title = switch (_period) {
      _ExpensePeriod.week =>
        '${DateFormat('MMM d').format(bucket.date)} – ${DateFormat('MMM d').format(bucket.date.add(const Duration(days: 6)))}',
      _ExpensePeriod.month => DateFormat('MMMM yyyy').format(bucket.date),
      _ExpensePeriod.year => DateFormat('yyyy').format(bucket.date),
    };

    return Container(
      decoration: isCurrent
          ? BoxDecoration(
              color: _isDark ? dangerColor.withValues(alpha: 0.08) : null,
              gradient: _isDark
                  ? null
                  : LinearGradient(
                      colors: [
                        dangerColor.withValues(alpha: 0.08),
                        dangerColor.withValues(alpha: 0.02),
                      ],
                    ),
            )
          : null,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: isCurrent
              ? AppDecorations.iconBadge(
                  _c,
                  context,
                  [dangerColor, dangerColor.withValues(alpha: 0.7)],
                )
              : BoxDecoration(
                  color:
                      textSecondary.withValues(alpha: _isDark ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: cardBorder.withValues(alpha: 0.35)),
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
          periodTotal > 0
              ? '${bucket.count} payment${bucket.count != 1 ? 's' : ''} · ${(bucket.sent / periodTotal * 100).toStringAsFixed(1)}% of total'
              : '${bucket.count} payment${bucket.count != 1 ? 's' : ''}',
          style: TextStyle(
            color: isCurrent ? dangerColor : textSecondary,
            fontSize: 10,
          ),
        ),
        trailing: Text(
          '-${currencyFormat.format(bucket.sent)}',
          style: TextStyle(
            color: isCurrent ? dangerColor : textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ---- Breakdown controls ---------------------------------------------------

  Widget _periodChip(String label, _ExpensePeriod value) {
    final selected = _period == value;
    return GestureDetector(
      onTap: () => setState(() => _period = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? dangerColor.withValues(alpha: 0.15)
              : textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? dangerColor.withValues(alpha: 0.4)
                : cardBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? dangerColor : textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSortButton() {
    String labelFor(_ExpenseSort s) => switch (s) {
          _ExpenseSort.dateDesc => 'Newest',
          _ExpenseSort.dateAsc => 'Oldest',
          _ExpenseSort.amountDesc => 'Highest',
          _ExpenseSort.amountAsc => 'Lowest',
        };

    return PopupMenuButton<_ExpenseSort>(
      initialValue: _sort,
      tooltip: 'Sort',
      onSelected: (v) => setState(() => _sort = v),
      color: cardColor,
      itemBuilder: (context) => [
        for (final s in _ExpenseSort.values)
          PopupMenuItem<_ExpenseSort>(
            value: s,
            child: Row(
              children: [
                Icon(
                  switch (s) {
                    _ExpenseSort.dateDesc => Icons.arrow_downward_rounded,
                    _ExpenseSort.dateAsc => Icons.arrow_upward_rounded,
                    _ExpenseSort.amountDesc => Icons.trending_down_rounded,
                    _ExpenseSort.amountAsc => Icons.trending_up_rounded,
                  },
                  size: 16,
                  color: _sort == s ? dangerColor : textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  switch (s) {
                    _ExpenseSort.dateDesc => 'Newest first',
                    _ExpenseSort.dateAsc => 'Oldest first',
                    _ExpenseSort.amountDesc => 'Highest amount',
                    _ExpenseSort.amountAsc => 'Lowest amount',
                  },
                  style: TextStyle(
                    color: _sort == s ? dangerColor : textPrimary,
                    fontWeight:
                        _sort == s ? FontWeight.w700 : FontWeight.w500,
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
              labelFor(_sort),
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
