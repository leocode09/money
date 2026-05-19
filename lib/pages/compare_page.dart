import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import 'leaderboard_page.dart';

class ComparePage extends StatefulWidget {
  final bool embeddedInShell;

  const ComparePage({super.key, this.embeddedInShell = false});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final NumberFormat currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  bool _loadingInitial = true;
  bool _loadingOther = false;
  bool _selfIsPublic = false;
  List<MonthlyTransactionSummary> _selfSummaries = const [];
  List<PublicPeer> _publicPeers = const [];
  String? _selectedOtherPhone;
  List<MonthlyTransactionSummary> _otherSummaries = const [];

  late final AnimationController _entranceController;
  late final AnimationController _contentController;
  late final AnimationController _pulseController;

  AppColors get _c => Theme.of(context).extension<AppColors>()!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => _c.primary;
  Color get primaryDark => _c.primaryDark;
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

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _contentController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final selfPhone = await _authService.getCurrentUserPhone();
    final selfIsPublic = await _authService.isPublic();
    final peers = await _authService.getPublicPeers();

    List<MonthlyTransactionSummary> selfSummaries = const [];
    if (selfPhone != null) {
      if (selfIsPublic) {
        selfSummaries = await _authService.getUserSummaries(selfPhone);
      }
    }

    if (!mounted) return;
    setState(() {
      _selfIsPublic = selfIsPublic;
      _selfSummaries = selfSummaries;
      _publicPeers = peers;
      _selectedOtherPhone = peers.isNotEmpty ? peers.first.phone : null;
      _loadingInitial = false;
    });

    _entranceController.forward();

    if (_selectedOtherPhone != null) {
      _loadOther(_selectedOtherPhone!);
    } else {
      _contentController.forward();
    }
  }

  Future<void> _loadOther(String phone) async {
    setState(() {
      _loadingOther = true;
      _otherSummaries = const [];
    });
    final summaries = await _authService.getUserSummaries(phone);
    if (!mounted) return;
    setState(() {
      _otherSummaries = summaries;
      _loadingOther = false;
    });
    _contentController.forward(from: 0);
  }

  double _total(List<MonthlyTransactionSummary> summaries) =>
      summaries.fold<double>(0, (sum, s) => sum + s.totalReceived);

  double _averageMonthly(List<MonthlyTransactionSummary> summaries) {
    final active = summaries.where((s) => s.totalReceived > 0).toList();
    if (active.isEmpty) return 0;
    return _total(active) / active.length;
  }

  double _growthRate(List<MonthlyTransactionSummary> summaries) {
    final sorted = List<MonthlyTransactionSummary>.from(summaries)
      ..sort((a, b) => a.month.compareTo(b.month));
    final withData = sorted.where((s) => s.totalReceived > 0).toList();
    if (withData.length < 2) return 0;
    final rates = <double>[];
    for (var i = 1; i < withData.length; i++) {
      final prev = withData[i - 1].totalReceived;
      final cur = withData[i].totalReceived;
      if (prev > 0) {
        rates.add((cur - prev) / prev);
      }
    }
    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  int _activeMonths(List<MonthlyTransactionSummary> summaries) =>
      summaries.where((s) => s.totalReceived > 0).length;

  MonthlyTransactionSummary? _highestMonth(
    List<MonthlyTransactionSummary> summaries,
  ) {
    if (summaries.isEmpty) return null;
    return summaries.reduce(
      (a, b) => a.totalReceived >= b.totalReceived ? a : b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        _buildGradientBackground(),
        _loadingInitial
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : CustomScrollView(
                slivers: [
                  if (!widget.embeddedInShell) _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.embeddedInShell) _buildEmbeddedTitle(),
                        _buildBody(),
                      ],
                    ),
                  ),
                ],
              ),
      ],
    );

    if (widget.embeddedInShell) {
      return content;
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(child: content),
    );
  }

  Widget _buildGradientBackground() {
    return Container(decoration: AppDecorations.pageBackground(_c, context));
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'Global leaderboard',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LeaderboardPage()),
            );
          },
          icon: Icon(Icons.leaderboard_rounded, color: primaryColor),
        ),
      ],
      title: AnimatedBuilder(
        animation: _entranceController,
        builder: (context, _) {
          final raw = _entranceController.value / 0.4;
          final t = raw.clamp(0.0, 1.0);
          final shimmerPos = -1.0 + (2.0 * t);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.6 + (0.4 * t),
                child: Opacity(
                  opacity: t,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: AppDecorations.iconBadge(
                      _c,
                      context,
                      [primaryColor, accentPurple],
                    ),
                    child: Icon(
                      Icons.compare_arrows_rounded,
                      color: AppDecorations.iconBadgeForeground(
                        _c,
                        context,
                        [primaryColor, accentPurple],
                      ),
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      textPrimary,
                      primaryColor,
                      accentPurple,
                      textPrimary,
                    ],
                    stops: [
                      (shimmerPos - 0.3).clamp(0.0, 1.0),
                      (shimmerPos - 0.1).clamp(0.0, 1.0),
                      (shimmerPos + 0.1).clamp(0.0, 1.0),
                      (shimmerPos + 0.3).clamp(0.0, 1.0),
                    ],
                  ).createShader(rect);
                },
                child: Text(
                  'Compare',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      flexibleSpace: ClipRRect(
        child: AppDecorations.wrapBlur(
          context,
          Container(decoration: AppDecorations.appBarShell(_c, context)),
        ),
      ),
    );
  }

  Widget _buildEmbeddedTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        'Compare',
        style: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_selfIsPublic) {
      return _buildEmptyState(
        icon: Icons.lock_rounded,
        title: 'You are private',
        message:
            'Turn on Public profile in the More tab to share monthly aggregates and unlock comparisons.',
      );
    }

    if (_publicPeers.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No public users yet',
        message:
            'When other people opt in to public sharing, they\'ll show up here for comparison.',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StaggerItem(
            animation: _entranceController,
            intervalStart: 0.05,
            intervalEnd: 0.40,
            slideFrom: const Offset(0, 16),
            startScale: 0.97,
            child: _buildUserPicker(),
          ),
          const SizedBox(height: 12),
          if (_loadingOther)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: primaryColor),
              ),
            )
          else if (_otherSummaries.isEmpty)
            _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No data shared yet',
              message:
                  'This user is public but hasn\'t synced any monthly aggregates yet.',
            )
          else ...[
            _StaggerItem(
              animation: _contentController,
              intervalStart: 0.05,
              intervalEnd: 0.45,
              slideFrom: const Offset(0, 24),
              startScale: 0.96,
              child: _buildMetricsGrid(),
            ),
            const SizedBox(height: 12),
            _StaggerItem(
              animation: _contentController,
              intervalStart: 0.30,
              intervalEnd: 0.70,
              slideFrom: const Offset(0, 28),
              startScale: 0.94,
              child: _buildTrendChart(),
            ),
            const SizedBox(height: 12),
            _StaggerItem(
              animation: _contentController,
              intervalStart: 0.40,
              intervalEnd: 0.80,
              slideFrom: const Offset(0, 28),
              startScale: 0.96,
              child: _buildMonthDiffList(),
            ),
          ],
          const SizedBox(height: 16),
          _StaggerItem(
            animation: _entranceController,
            intervalStart: 0.75,
            intervalEnd: 1.0,
            slideFrom: const Offset(0, 8),
            startScale: 1.0,
            child: _buildPrivacyFooter(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUserPicker() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.group_rounded,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Public users',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_publicPeers.length}',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _publicPeers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final peer = _publicPeers[index];
                  final phone = peer.phone;
                  final isSelected = phone == _selectedOtherPhone;
                  final start = (index * 0.04).clamp(0.0, 0.6);
                  final end = (start + 0.35).clamp(0.0, 1.0);
                  return _StaggerItem(
                    animation: _entranceController,
                    intervalStart: 0.15 + start,
                    intervalEnd: 0.15 + end,
                    slideFrom: const Offset(24, 0),
                    startScale: 0.9,
                    child: GestureDetector(
                      onTap: () {
                        if (isSelected) return;
                        setState(() {
                          _selectedOtherPhone = phone;
                        });
                        _loadOther(phone);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (_isDark ? primaryColor : null)
                              : cardColor.withValues(
                                  alpha: _isDark ? 0.85 : 0.8,
                                ),
                          gradient: isSelected && !_isDark
                              ? LinearGradient(
                                  colors: [primaryColor, primaryDark],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.6)
                                : cardBorder.withValues(alpha: 0.5),
                            width: 1,
                          ),
                          boxShadow: isSelected && !_isDark
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                    spreadRadius: -2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 14,
                              color: isSelected
                                  ? Colors.white
                                  : textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              peer.chipLabel,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final selfTotal = _total(_selfSummaries);
    final otherTotal = _total(_otherSummaries);
    final selfAvg = _averageMonthly(_selfSummaries);
    final otherAvg = _averageMonthly(_otherSummaries);
    final selfGrowth = _growthRate(_selfSummaries);
    final otherGrowth = _growthRate(_otherSummaries);
    final selfActive = _activeMonths(_selfSummaries);
    final otherActive = _activeMonths(_otherSummaries);
    final selfHighest = _highestMonth(_selfSummaries);
    final otherHighest = _highestMonth(_otherSummaries);

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.compare_arrows_rounded,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Head-to-head',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StaggerItem(
              animation: _contentController,
              intervalStart: 0.10,
              intervalEnd: 0.40,
              slideFrom: const Offset(0, -10),
              startScale: 0.95,
              child: _buildHeaderRow(),
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              rowIndex: 0,
              label: 'Total Received',
              selfNumeric: selfTotal,
              otherNumeric: otherTotal,
              selfFormatter: currencyFormat.format,
              otherFormatter: currencyFormat.format,
              selfBetter: selfTotal >= otherTotal,
              icon: Icons.account_balance_wallet_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              rowIndex: 1,
              label: 'Average Monthly',
              selfNumeric: selfAvg,
              otherNumeric: otherAvg,
              selfFormatter: currencyFormat.format,
              otherFormatter: currencyFormat.format,
              selfBetter: selfAvg >= otherAvg,
              icon: Icons.calendar_month_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              rowIndex: 2,
              label: 'Growth Rate',
              selfNumeric: selfGrowth * 100,
              otherNumeric: otherGrowth * 100,
              selfFormatter: _formatPercentValue,
              otherFormatter: _formatPercentValue,
              selfBetter: selfGrowth >= otherGrowth,
              icon: Icons.trending_up_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              rowIndex: 3,
              label: 'Active Months',
              selfNumeric: selfActive.toDouble(),
              otherNumeric: otherActive.toDouble(),
              selfFormatter: (v) => v.round().toString(),
              otherFormatter: (v) => v.round().toString(),
              selfBetter: selfActive >= otherActive,
              icon: Icons.event_available_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              rowIndex: 4,
              label: 'Highest Month',
              selfNumeric: selfHighest?.totalReceived ?? 0,
              otherNumeric: otherHighest?.totalReceived ?? 0,
              selfFormatter: selfHighest != null
                  ? currencyFormat.format
                  : (_) => '—',
              otherFormatter: otherHighest != null
                  ? currencyFormat.format
                  : (_) => '—',
              selfBetter:
                  (selfHighest?.totalReceived ?? 0) >=
                      (otherHighest?.totalReceived ?? 0),
              icon: Icons.star_rounded,
              subSelf: selfHighest != null
                  ? DateFormat('MMM yy').format(selfHighest.month)
                  : null,
              subOther: otherHighest != null
                  ? DateFormat('MMM yy').format(otherHighest.month)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _formatPercentValue(double percent) {
    return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        const SizedBox(width: 28),
        const Expanded(child: SizedBox.shrink()),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.18),
                  primaryColor.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'You',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentPurple.withValues(alpha: 0.18),
                  accentPurple.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accentPurple.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'Them',
                style: TextStyle(
                  color: accentPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow({
    required int rowIndex,
    required String label,
    required double selfNumeric,
    required double otherNumeric,
    required String Function(double) selfFormatter,
    required String Function(double) otherFormatter,
    required bool selfBetter,
    required IconData icon,
    String? subSelf,
    String? subOther,
  }) {
    final start = (0.18 + rowIndex * 0.08).clamp(0.0, 1.0);
    final end = (start + 0.30).clamp(0.0, 1.0);
    return _StaggerItem(
      animation: _contentController,
      intervalStart: start,
      intervalEnd: end,
      slideFrom: const Offset(-30, 0),
      startScale: 0.97,
      curve: Curves.easeOutCubic,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: primaryColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: _buildValueCell(
              numeric: selfNumeric,
              formatter: selfFormatter,
              sub: subSelf,
              highlight: selfBetter,
              highlightColor: successColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildValueCell(
              numeric: otherNumeric,
              formatter: otherFormatter,
              sub: subOther,
              highlight: !selfBetter,
              highlightColor: successColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueCell({
    required double numeric,
    required String Function(double) formatter,
    String? sub,
    required bool highlight,
    required Color highlightColor,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          key: ValueKey<double>(numeric),
          tween: Tween(begin: 0, end: numeric),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) {
            return Text(
              formatter(animated),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: highlight ? highlightColor : textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            );
          },
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );

    if (!highlight) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: _isDark ? 0.4 : 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cardBorder.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: content,
      );
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final p = _pulseController.value;
        final fillAlpha = 0.14 + 0.10 * p;
        final borderAlpha = 0.35 + 0.20 * p;
        final shadowAlpha = 0.25 + 0.20 * p;
        final blur = 6.0 + 8.0 * p;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: highlightColor.withValues(alpha: fillAlpha),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlightColor.withValues(alpha: borderAlpha),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: highlightColor.withValues(alpha: shadowAlpha),
                blurRadius: blur,
                spreadRadius: -1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: content,
    );
  }

  Widget _buildTrendChart() {
    final allMonths = <DateTime>{};
    for (final s in _selfSummaries) {
      allMonths.add(DateTime.utc(s.month.year, s.month.month, 1));
    }
    for (final s in _otherSummaries) {
      allMonths.add(DateTime.utc(s.month.year, s.month.month, 1));
    }
    final sortedMonths = allMonths.toList()..sort((a, b) => a.compareTo(b));

    if (sortedMonths.isEmpty) {
      return const SizedBox.shrink();
    }

    final selfMap = <DateTime, double>{
      for (final s in _selfSummaries)
        DateTime.utc(s.month.year, s.month.month, 1): s.totalReceived,
    };
    final otherMap = <DateTime, double>{
      for (final s in _otherSummaries)
        DateTime.utc(s.month.year, s.month.month, 1): s.totalReceived,
    };

    final selfSpots = <FlSpot>[];
    final otherSpots = <FlSpot>[];
    double maxY = 0;
    for (var i = 0; i < sortedMonths.length; i++) {
      final m = sortedMonths[i];
      final sv = selfMap[m] ?? 0.0;
      final ov = otherMap[m] ?? 0.0;
      selfSpots.add(FlSpot(i.toDouble(), sv));
      otherSpots.add(FlSpot(i.toDouble(), ov));
      if (sv > maxY) maxY = sv;
      if (ov > maxY) maxY = ov;
    }
    if (maxY <= 0) maxY = 1;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.show_chart_rounded,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Monthly trend',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                _buildLegendDot('You', primaryColor),
                const SizedBox(width: 10),
                _buildLegendDot('Them', accentPurple),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
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
                          final idx = value.toInt();
                          if (idx < 0 || idx >= sortedMonths.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('MMM').format(sortedMonths[idx]),
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: selfSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      preventCurveOverShooting: true,
                      color: primaryColor,
                      barWidth: 3.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: _isDark ? Colors.white : cardColor,
                              strokeWidth: 2.5,
                              strokeColor: primaryColor,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: AppDecorations.chartAreaFill(
                          primaryColor,
                          topAlpha: 0.25,
                          midAlpha: 0.08,
                        ),
                      ),
                    ),
                    LineChartBarData(
                      spots: otherSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      preventCurveOverShooting: true,
                      color: accentPurple,
                      barWidth: 3.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: _isDark ? Colors.white : cardColor,
                              strokeWidth: 2.5,
                              strokeColor: accentPurple,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: AppDecorations.chartAreaFill(
                          accentPurple,
                          topAlpha: 0.25,
                          midAlpha: 0.08,
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
                        horizontal: 14,
                        vertical: 10,
                      ),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final isSelf = spot.barIndex == 0;
                          final monthLabel = DateFormat(
                            'MMM yyyy',
                          ).format(sortedMonths[spot.x.toInt()]);
                          return LineTooltipItem(
                            '${isSelf ? 'You' : 'Them'}  $monthLabel\n',
                            TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            children: [
                              TextSpan(
                                text: currencyFormat.format(spot.y),
                                style: TextStyle(
                                  color: isSelf ? primaryColor : accentPurple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
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

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final p = _pulseController.value;
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.30 + 0.30 * p),
                    blurRadius: 4 + 6 * p,
                    spreadRadius: 0.5 + 1.5 * p,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 6),
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

  Widget _buildMonthDiffList() {
    final selfMap = <DateTime, double>{
      for (final s in _selfSummaries)
        DateTime.utc(s.month.year, s.month.month, 1): s.totalReceived,
    };
    final otherMap = <DateTime, double>{
      for (final s in _otherSummaries)
        DateTime.utc(s.month.year, s.month.month, 1): s.totalReceived,
    };
    final commonMonths =
        selfMap.keys.where((m) => otherMap.containsKey(m)).toList()
          ..sort((a, b) => b.compareTo(a));

    if (commonMonths.isEmpty) {
      return _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.event_busy_rounded,
                color: textSecondary,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                'No overlapping months',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You and this user haven\'t shared activity in the same months yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Month-by-month',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '${commonMonths.length} shared',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...commonMonths.asMap().entries.map((entry) {
              final i = entry.key;
              final month = entry.value;
              final selfValue = selfMap[month] ?? 0;
              final otherValue = otherMap[month] ?? 0;
              final delta = selfValue - otherValue;
              final ahead = delta >= 0;
              final rowStart = (0.45 + i * 0.05).clamp(0.0, 1.0);
              final rowEnd = (rowStart + 0.30).clamp(0.0, 1.0);
              final pillStart = (rowStart + 0.10).clamp(0.0, 1.0);
              final pillEnd = (pillStart + 0.35).clamp(0.0, 1.0);
              return _StaggerItem(
                animation: _contentController,
                intervalStart: rowStart,
                intervalEnd: rowEnd,
                slideFrom: const Offset(-24, 0),
                startScale: 0.97,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(
                        alpha: _isDark ? 0.4 : 0.7,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cardBorder.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            DateFormat('MMM yy').format(month),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currencyFormat.format(selfValue),
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currencyFormat.format(otherValue),
                                style: TextStyle(
                                  color: accentPurple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StaggerItem(
                          animation: _contentController,
                          intervalStart: pillStart,
                          intervalEnd: pillEnd,
                          slideFrom: const Offset(12, 0),
                          startScale: 0.4,
                          curve: Curves.elasticOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: ahead
                                    ? [
                                        successColor.withValues(alpha: 0.18),
                                        successColor.withValues(alpha: 0.08),
                                      ]
                                    : [
                                        dangerColor.withValues(alpha: 0.18),
                                        dangerColor.withValues(alpha: 0.08),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: ahead
                                    ? successColor.withValues(alpha: 0.35)
                                    : dangerColor.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  ahead
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  color: ahead ? successColor : dangerColor,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  currencyFormat.format(delta.abs()),
                                  style: TextStyle(
                                    color: ahead ? successColor : dangerColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: textSecondary,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Only monthly aggregates are shared. Individual transactions, '
              'counterparties, and IDs never leave your device.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StaggerItem(
              animation: _entranceController,
              intervalStart: 0.10,
              intervalEnd: 0.55,
              slideFrom: const Offset(0, 0),
              startScale: 0.3,
              curve: Curves.elasticOut,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final p = _pulseController.value;
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _isDark
                          ? primaryColor.withValues(alpha: 0.14)
                          : null,
                      gradient: _isDark
                          ? null
                          : LinearGradient(
                              colors: [
                                primaryColor.withValues(alpha: 0.18 + 0.06 * p),
                                accentPurple.withValues(alpha: 0.12 + 0.06 * p),
                              ],
                            ),
                      shape: BoxShape.circle,
                      border: _isDark
                          ? Border.all(
                              color: primaryColor.withValues(alpha: 0.28),
                            )
                          : null,
                      boxShadow: _isDark
                          ? null
                          : [
                              BoxShadow(
                                color: primaryColor.withValues(
                                  alpha: 0.15 + 0.15 * p,
                                ),
                                blurRadius: 12 + 12 * p,
                                spreadRadius: 1,
                              ),
                            ],
                    ),
                    child: child,
                  );
                },
                child: Icon(icon, color: primaryColor, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            _StaggerItem(
              animation: _entranceController,
              intervalStart: 0.35,
              intervalEnd: 0.70,
              slideFrom: const Offset(0, 14),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _StaggerItem(
              animation: _entranceController,
              intervalStart: 0.50,
              intervalEnd: 0.85,
              slideFrom: const Offset(0, 8),
              startScale: 1.0,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
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
}

class _StaggerItem extends StatelessWidget {
  final Animation<double> animation;
  final double intervalStart;
  final double intervalEnd;
  final Offset slideFrom;
  final double startScale;
  final Curve curve;
  final Widget child;

  const _StaggerItem({
    required this.animation,
    required this.intervalStart,
    required this.intervalEnd,
    required this.child,
    this.slideFrom = const Offset(0, 24),
    this.startScale = 0.96,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    final start = intervalStart.clamp(0.0, 1.0);
    final end = intervalEnd.clamp(0.0, 1.0);
    final effectiveEnd = end <= start ? (start + 0.0001).clamp(0.0, 1.0) : end;

    final t = CurvedAnimation(
      parent: animation,
      curve: Interval(start, effectiveEnd, curve: curve),
    );

    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final value = t.value.clamp(0.0, 1.0);
        final dx = slideFrom.dx * (1 - value);
        final dy = slideFrom.dy * (1 - value);
        final scale = startScale + ((1 - startScale) * value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
