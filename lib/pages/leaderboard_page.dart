import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';

class LeaderboardPage extends StatefulWidget {
  final bool embeddedInShell;

  const LeaderboardPage({super.key, this.embeddedInShell = false});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final AuthService _authService = AuthService();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  LeaderboardPeriod _period = LeaderboardPeriod.thisMonth;
  List<LeaderboardEntry> _entries = const [];
  bool _loading = true;
  bool _selfIsPublic = false;

  AppColors get _c => Theme.of(context).extension<AppColors>()!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => _c.primary;
  Color get primaryDark => _c.primaryDark;
  Color get accentPurple => _c.accentPurple;
  Color get successColor => _c.success;
  Color get bgColor => _c.bg;
  Color get bgGradient1 => _c.bgGradient1;
  Color get bgGradient2 => _c.bgGradient2;
  Color get cardColor => _c.card;
  Color get cardBorder => _c.cardBorder;
  Color get textPrimary => _c.textPrimary;
  Color get textSecondary => _c.textSecondary;

  String get _periodLabel => switch (_period) {
    LeaderboardPeriod.thisWeek => 'This week',
    LeaderboardPeriod.thisMonth => 'This month',
    LeaderboardPeriod.allTime => 'All time',
  };

  String get _periodSubtitle {
    final base = 'Ranked by total received';
    return switch (_period) {
      LeaderboardPeriod.thisWeek => () {
        final start = WeeklyTransactionSummary.startOfWeek(DateTime.now());
        final end = start.add(const Duration(days: 6));
        final fmt = DateFormat('d MMM');
        return '$base · ${fmt.format(start)} – ${fmt.format(end)}';
      }(),
      LeaderboardPeriod.thisMonth =>
        '$base · ${DateFormat('MMMM yyyy').format(DateTime.now())}',
      LeaderboardPeriod.allTime => '$base · all months',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final selfIsPublic = await _authService.isPublic();
    final entries = await _authService.getGlobalLeaderboard(_period);

    if (!mounted) return;
    setState(() {
      _selfIsPublic = selfIsPublic;
      _entries = entries;
      _loading = false;
    });
  }

  void _onPeriodChanged(LeaderboardPeriod? value) {
    if (value == null || value == _period) return;
    setState(() {
      _period = value;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        _buildGradientBackground(),
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                color: primaryColor,
                onRefresh: _load,
                child: _buildBody(),
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

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embeddedInShell ? 16 : 8,
        8,
        12,
        0,
      ),
      child: Row(
        children: [
          if (!widget.embeddedInShell)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leaderboard',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: widget.embeddedInShell ? 18 : 20,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  _periodSubtitle,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _buildPeriodDropdown(),
        ],
      ),
    );
  }

  Widget _buildPeriodDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _isDark ? cardColor : cardColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder.withValues(alpha: 0.55)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LeaderboardPeriod>(
          value: _period,
          isDense: true,
          icon: Icon(Icons.expand_more_rounded, color: primaryColor, size: 20),
          borderRadius: BorderRadius.circular(12),
          dropdownColor: cardColor,
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          onChanged: _loading ? null : _onPeriodChanged,
          items: const [
            DropdownMenuItem(
              value: LeaderboardPeriod.thisWeek,
              child: Text('This week'),
            ),
            DropdownMenuItem(
              value: LeaderboardPeriod.thisMonth,
              child: Text('This month'),
            ),
            DropdownMenuItem(
              value: LeaderboardPeriod.allTime,
              child: Text('All time'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (!_selfIsPublic) _buildPrivateBanner(),
        if (_entries.isEmpty)
          _buildEmptyState()
        else ...[
          _buildTopThree(),
          const SizedBox(height: 12),
          if (_entries.length > 3) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'All rankings',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            ..._entries.skip(3).map(_buildLeaderboardRow),
          ],
        ],
        const SizedBox(height: 8),
        _buildPrivacyNote(),
      ],
    );
  }

  Widget _buildPrivateBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentPurple.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: accentPurple, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are private and will not appear here. Enable public mode on the dashboard to join the leaderboard.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: _isDark ? 0.7 : 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.emoji_events_outlined, size: 48, color: textSecondary),
          const SizedBox(height: 12),
          Text(
            'No rankings for $_periodLabel',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Public users with shared aggregates will appear here once they sync data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopThree() {
    final top = _entries.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, color: primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Top 3 · $_periodLabel',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (top.length > 1) Expanded(child: _buildPodium(top[1], 72)),
                const SizedBox(width: 8),
                Expanded(child: _buildPodium(top[0], 96)),
                const SizedBox(width: 8),
                if (top.length > 2) Expanded(child: _buildPodium(top[2], 60)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium(LeaderboardEntry entry, double height) {
    final medalColor = switch (entry.rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      _ => const Color(0xFFCD7F32),
    };

    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: AppDecorations.rankAvatar(
            context,
            medalColor,
            border: entry.isSelf
                ? Border.all(color: primaryColor, width: 2)
                : null,
          ),
          child: Center(
            child: Text(
              '${entry.rank}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.displayLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currencyFormat.format(entry.totalReceived),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: successColor,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: height,
          decoration: AppDecorations.podiumBar(context, medalColor),
        ),
      ],
    );
  }

  Widget _buildLeaderboardRow(LeaderboardEntry entry) {
    final isTopThree = entry.rank <= 3;
    return Padding(
      padding: EdgeInsets.only(bottom: isTopThree ? 0 : 8, top: isTopThree ? 0 : 0),
      child: _buildGlassCard(
        margin: EdgeInsets.zero,
        child: Container(
          decoration: entry.isSelf
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                )
              : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: _buildRankBadge(entry),
            title: Text(
              entry.isSelf ? '${entry.displayLabel} (You)' : entry.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            subtitle: entry.isSelf
                ? Text(
                    'Your public rank',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
            trailing: Text(
              _currencyFormat.format(entry.totalReceived),
              style: TextStyle(
                color: successColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge(LeaderboardEntry entry) {
    final color = switch (entry.rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFCD7F32),
      _ => primaryColor.withValues(alpha: 0.2),
    };
    final textColor = entry.rank <= 3 ? Colors.white : primaryColor;

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: entry.rank <= 3 ? color : color.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '#${entry.rank}',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Only users who opted in to public sharing appear. This week uses weekly aggregates synced from the app; month and all-time use monthly totals. Never raw transactions.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets? margin}) {
    return AppGlassCard(
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      child: child,
    );
  }
}
