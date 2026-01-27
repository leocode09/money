import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class DashboardPage extends StatefulWidget {
  final List<SmsMessage> messages;

  const DashboardPage({super.key, required this.messages});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late List<Transaction> _transactions;
  late List<MonthlyTransactionSummary> _monthlySummaries;
  int _selectedMonthIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  final currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  // Ripple-inspired epic dark color palette
  static const primaryColor = Color(0xFFE8956A); // Vibrant warm coral
  static const primaryDark = Color(0xFFD4734A); // Rich coral
  static const primaryLight = Color(0xFFFFB088); // Light coral glow
  static const accentColor = Color(0xFFFFCBA4); // Warm golden sand
  static const accentPurple = Color(0xFF9D7BEA); // Soft purple accent
  static const successColor = Color(0xFF5EEAD4); // Vibrant teal
  static const dangerColor = Color(0xFFFF8A8A); // Soft coral red
  static const bgColor = Color(0xFF0D0A0F); // Deep rich black-purple
  static const bgGradient1 = Color(0xFF1A1020); // Dark purple
  static const bgGradient2 = Color(0xFF2A1830); // Warm purple
  static const cardColor = Color(0xFF1E1525); // Dark purple glass
  static const cardBorder = Color(0xFF3D2D4A); // Subtle purple border
  static const textPrimary = Color(0xFFFFF8F0); // Warm white
  static const textSecondary = Color(0xFFCBB9A8); // Muted warm cream

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

  /// Calculates the next month target based on average growth rate
  /// Excludes current month from the calculation
  Map<String, dynamic> get nextMonthTarget {
    if (_monthlySummaries.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    // Sort by month ascending
    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => a.month.compareTo(b.month));

    // Exclude current month
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final completedMonths = sortedSummaries
        .where((s) => s.month.isBefore(currentMonth))
        .toList();

    if (completedMonths.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    // Take last 3 months (or all if less than 3)
    final recentMonths = completedMonths.length <= 3
        ? completedMonths
        : completedMonths.sublist(completedMonths.length - 3);

    // Calculate growth rates for each consecutive pair
    final growthRates = <double>[];
    for (int i = 1; i < recentMonths.length; i++) {
      final previous = recentMonths[i - 1].totalReceived;
      final current = recentMonths[i].totalReceived;
      if (previous > 0) {
        growthRates.add((current - previous) / previous);
      }
    }

    // Average the growth rates, ensure minimum 5% growth
    double avgGrowthRate = 0.05; // Default 5%
    if (growthRates.isNotEmpty) {
      avgGrowthRate = growthRates.reduce((a, b) => a + b) / growthRates.length;
      if (avgGrowthRate < 0.05) avgGrowthRate = 0.05; // Minimum 5%
    }

    // Calculate target: Last Month × (1 + Growth Rate)
    final lastMonthAmount = recentMonths.last.totalReceived;
    final target = lastMonthAmount * (1 + avgGrowthRate);

    return {
      'target': target,
      'growthRate': avgGrowthRate,
      'lastMonth': lastMonthAmount,
      'lastMonthDate': recentMonths.last.month,
    };
  }

  /// Gets current month progress compared to previous month and target
  Map<String, dynamic> get currentMonthProgress {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);

    // Find current month data
    final currentMonthData = _monthlySummaries.firstWhere(
      (s) =>
          s.month.year == currentMonth.year &&
          s.month.month == currentMonth.month,
      orElse: () => MonthlyTransactionSummary(
        month: currentMonth,
        totalReceived: 0,
        totalSent: 0,
        transactionCount: 0,
      ),
    );

    final target = nextMonthTarget;
    final targetAmount = target['target'] as double;
    final previousMonthAmount = target['lastMonth'] as double;

    final currentAmount = currentMonthData.totalReceived;

    // Progress towards previous month
    final previousProgress = previousMonthAmount > 0
        ? (currentAmount / previousMonthAmount * 100).clamp(0.0, 200.0)
        : 0.0;
    final previousRemaining = previousMonthAmount - currentAmount;

    // Progress towards target
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
    };
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    );
    _processTransactions();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _processTransactions() {
    _transactions = widget.messages
        .map(
          (msg) =>
              Transaction.fromSmsMessage(msg.body ?? '', smsDate: msg.date),
        )
        .where((t) => t != null)
        .cast<Transaction>()
        .toList();

    _transactions.sort((a, b) => b.date.compareTo(a.date));

    final monthlyData = <DateTime, List<Transaction>>{};
    for (var transaction in _transactions) {
      final month = DateTime(transaction.date.year, transaction.date.month);
      monthlyData.putIfAbsent(month, () => []).add(transaction);
    }

    _monthlySummaries = monthlyData.entries.map((entry) {
      final receivedAmount = entry.value
          .where((t) => t.type == 'RECEIVED')
          .fold<double>(0, (sum, t) => sum + t.amount);

      final receivedCount = entry.value
          .where((t) => t.type == 'RECEIVED')
          .length;

      return MonthlyTransactionSummary(
        month: entry.key,
        totalReceived: receivedAmount,
        totalSent: 0,
        transactionCount: receivedCount,
      );
    }).toList();

    _monthlySummaries.sort((a, b) => a.month.compareTo(b.month));

    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final currentMonthIndex = _monthlySummaries.indexWhere(
      (summary) =>
          summary.month.year == currentMonth.year &&
          summary.month.month == currentMonth.month,
    );

    if (currentMonthIndex >= 0) {
      _selectedMonthIndex = _monthlySummaries.length - 1 - currentMonthIndex;
    } else {
      _selectedMonthIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: _transactions.isEmpty
          ? const Center(child: Text('No transactions found'))
          : Stack(
              children: [
                // Epic animated gradient background
                _buildGradientBackground(),
                // Main content
                CustomScrollView(
                  slivers: [
                    _buildAppBar(),
                    SliverToBoxAdapter(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.1),
                            end: Offset.zero,
                          ).animate(_slideAnimation),
                          child: Column(
                            children: [
                              const SizedBox(height: 4),
                              _buildMonthProgressChart(),
                              const SizedBox(height: 12),
                              _buildTransactionChart(),
                              const SizedBox(height: 12),
                              _buildMonthlyReceiptsList(),
                              const SizedBox(height: 12),
                              _buildHeroCard(),
                              const SizedBox(height: 12),
                              _buildMonthlySummaryCard(),
                              const SizedBox(height: 12),
                              _buildMetricCards(),
                              const SizedBox(height: 12),
                              _buildNextMonthTargetCard(),
                              const SizedBox(height: 12),
                              _buildTopSendersCard(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Epic flowing gradient background inspired by Ripple
  Widget _buildGradientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgColor, bgGradient1, bgGradient2, bgGradient1, bgColor],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Flowing coral orb - top right
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withOpacity(0.25),
                    primaryColor.withOpacity(0.1),
                    primaryColor.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Purple accent orb - center left
          Positioned(
            top: 300,
            left: -120,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentPurple.withOpacity(0.2),
                    accentPurple.withOpacity(0.05),
                    accentPurple.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Warm coral flow - bottom
          Positioned(
            bottom: 100,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryLight.withOpacity(0.15),
                    primaryColor.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 80,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cardColor.withOpacity(0.8),
                    bgColor.withOpacity(0.6),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [textPrimary, accentColor],
          ).createShader(bounds),
          child: const Text(
            'Transaction Dashboard',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, primaryDark, Color(0xFFB85A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryLight.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Flowing light orbs
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white.withOpacity(0.2), Colors.transparent],
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
                          color: Colors.white.withOpacity(0.2),
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
                  Text(
                    currencyFormat.format(totalReceivedAmount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
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

  /// Glassmorphism card with blur and subtle border
  Widget _buildGlassCard({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: child,
        ),
      ),
    );
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
                const Text(
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withOpacity(0.15),
                        primaryColor.withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedMonthIndex,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: primaryColor,
                      size: 18,
                    ),
                    items: sortedSummaries.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(
                          DateFormat('MMM yy').format(entry.value.month),
                          style: const TextStyle(
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
            Text(
              currencyFormat.format(selectedSummary.totalReceived),
              style: const TextStyle(
                color: textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${selectedSummary.transactionCount} transaction${selectedSummary.transactionCount != 1 ? 's' : ''} this month',
              style: const TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (previousSummary != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: percentageChange >= 0
                        ? [
                            successColor.withOpacity(0.12),
                            successColor.withOpacity(0.05),
                          ]
                        : [
                            dangerColor.withOpacity(0.12),
                            dangerColor.withOpacity(0.05),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: percentageChange >= 0
                        ? successColor.withOpacity(0.3)
                        : dangerColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: percentageChange >= 0
                            ? successColor.withOpacity(0.2)
                            : dangerColor.withOpacity(0.2),
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
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 11,
                      ),
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

    // Epic gradient pairs for metric cards
    const metricGradients = [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo to Purple
      [Color(0xFFEC4899), Color(0xFFF472B6)], // Pink
      [Color(0xFF14B8A6), Color(0xFF5EEAD4)], // Teal
      [Color(0xFFF59E0B), Color(0xFFFBBF24)], // Amber
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Avg Transaction',
                  currencyFormat.format(averageReceivedAmount),
                  Icons.analytics_outlined,
                  metricGradients[0],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'This Month',
                  currencyFormat.format(thisMonthAvg),
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
                  'Highest',
                  currencyFormat.format(highestTransaction),
                  Icons.arrow_upward_rounded,
                  metricGradients[2],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Total Fees',
                  currencyFormat.format(totalFees),
                  Icons.money_off_outlined,
                  metricGradients[3],
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
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder.withOpacity(0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: -3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
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
                  style: const TextStyle(
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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF14B8A6), Color(0xFF5EEAD4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: successColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Flowing light effects
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
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.05),
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
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.transparent,
                      Colors.black.withOpacity(0.1),
                    ],
                    stops: const [0.0, 0.3, 1.0],
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
                          color: Colors.white.withOpacity(0.2),
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
                  Text(
                    currencyFormat.format(target),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
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
                          color: Colors.white.withOpacity(0.3),
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

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Income Trend',
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
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryColor, primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_monthlySummaries.length} mo',
                    style: const TextStyle(
                      color: Colors.white,
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
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: null,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: textSecondary.withOpacity(0.15),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: textSecondary.withOpacity(0.15),
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
                              style: const TextStyle(
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
                              style: const TextStyle(
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
                  maxY:
                      _monthlySummaries
                          .map((s) => s.totalReceived)
                          .reduce((a, b) => a > b ? a : b) *
                      1.15,
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
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: primaryColor,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            primaryColor.withOpacity(0.3),
                            primaryColor.withOpacity(0.1),
                            primaryColor.withOpacity(0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
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
                            const TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            children: [
                              TextSpan(
                                text: currencyFormat.format(spot.y),
                                style: const TextStyle(
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
    final progress = currentMonthProgress;
    final currentAmount = progress['currentAmount'] as double;
    final previousMonthAmount = progress['previousMonthAmount'] as double;
    final targetAmount = progress['targetAmount'] as double;

    if (previousMonthAmount == 0 && targetAmount == 0) {
      return const SizedBox.shrink();
    }

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
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentPurple.withOpacity(0.3),
                        accentPurple.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: accentPurple,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
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
            const SizedBox(height: 16),
            // Current amount display
            Center(
              child: Column(
                children: [
                  Text(
                    currencyFormat.format(currentAmount),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earned this month',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Progress towards Previous Month
            _buildProgressBar(
              label: 'vs Previous Month',
              current: currentAmount,
              goal: previousMonthAmount,
              progress: previousProgress,
              remaining: previousRemaining,
              color: primaryColor,
              icon: Icons.calendar_month_rounded,
            ),
            const SizedBox(height: 16),
            // Progress towards Target
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
                  style: const TextStyle(
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
                    ? successColor.withOpacity(0.2)
                    : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${displayProgress.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isAchieved ? successColor : color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: cardBorder.withOpacity(0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: displayProgress / 100,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Goal and remaining
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Goal: ${currencyFormat.format(goal)}',
              style: TextStyle(
                fontSize: 11,
                color: textSecondary.withOpacity(0.7),
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
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryColor, accentColor],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
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
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      gradientColors[index %
                                          gradientColors.length],
                                      gradientColors[index %
                                              gradientColors.length]
                                          .withOpacity(0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
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
                                  style: const TextStyle(
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
                          style: const TextStyle(
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
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        minHeight: 8,
                        backgroundColor: textSecondary.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          gradientColors[index % gradientColors.length],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyReceiptsList() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((b, a) => a.month.compareTo(b.month));

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [accentPurple, Color(0xFFB794F6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Monthly Receipts',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedSummaries.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: cardBorder.withOpacity(0.3),
            ),
            itemBuilder: (context, index) {
              final summary = sortedSummaries[index];
              final isCurrentMonth =
                  summary.month.year == DateTime.now().year &&
                  summary.month.month == DateTime.now().month;

              return Container(
                decoration: isCurrentMonth
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor.withOpacity(0.08),
                            primaryColor.withOpacity(0.02),
                          ],
                        ),
                      )
                    : null,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: isCurrentMonth
                          ? const LinearGradient(
                              colors: [primaryColor, primaryDark],
                            )
                          : LinearGradient(
                              colors: [
                                textSecondary.withOpacity(0.25),
                                textSecondary.withOpacity(0.15),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('MMM').format(summary.month),
                          style: TextStyle(
                            color: isCurrentMonth
                                ? Colors.white
                                : textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('yy').format(summary.month),
                          style: TextStyle(
                            color: isCurrentMonth
                                ? Colors.white.withOpacity(0.9)
                                : textSecondary.withOpacity(0.7),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    DateFormat('MMM yyyy').format(summary.month),
                    style: TextStyle(
                      fontWeight: isCurrentMonth
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontSize: 13,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${summary.transactionCount} txn${summary.transactionCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: isCurrentMonth ? primaryColor : textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  trailing: Text(
                    currencyFormat.format(summary.totalReceived),
                    style: TextStyle(
                      color: isCurrentMonth ? primaryColor : textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
