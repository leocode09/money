import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware surfaces: flat and minimal in dark mode, richer in light mode.
class AppDecorations {
  AppDecorations._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static AppColors colors(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  static bool useBackdropBlur(BuildContext context) => !isDark(context);

  static Widget wrapBlur(
    BuildContext context,
    Widget child, {
    double sigma = 8,
  }) {
    if (!useBackdropBlur(context)) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }

  /// Solid page backdrop — no scenic gradients.
  static BoxDecoration pageBackground(AppColors c, BuildContext context) {
    return BoxDecoration(color: c.bg);
  }

  /// Line-chart area fill (used in dashboard & compare).
  static LinearGradient chartAreaFill(
    Color color, {
    double topAlpha = 0.3,
    double midAlpha = 0.1,
  }) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withValues(alpha: topAlpha),
        color.withValues(alpha: midAlpha),
        color.withValues(alpha: 0.0),
      ],
    );
  }

  static List<BoxShadow> cardShadows(BuildContext context) {
    if (isDark(context)) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 6),
        spreadRadius: -3,
      ),
    ];
  }

  static List<BoxShadow> accentShadow(
    BuildContext context,
    Color accent, {
    double alpha = 0.4,
  }) {
    if (isDark(context)) return const [];
    return [
      BoxShadow(
        color: accent.withValues(alpha: alpha),
        blurRadius: 20,
        offset: const Offset(0, 10),
        spreadRadius: -5,
      ),
    ];
  }

  static BoxDecoration card(
    AppColors c,
    BuildContext context, {
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(16)),
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? c.card : c.card.withValues(alpha: 0.85),
      borderRadius: borderRadius,
      border: Border.all(
        color: c.cardBorder.withValues(alpha: dark ? 0.35 : 0.5),
        width: 1,
      ),
      boxShadow: cardShadows(context),
    );
  }

  static BoxDecoration appBarShell(AppColors c, BuildContext context) {
    if (isDark(context)) {
      return BoxDecoration(color: c.bg);
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          c.bg.withValues(alpha: 0.78),
          c.card.withValues(alpha: 0.62),
          c.bg.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
  }

  static BoxDecoration appBarCard(AppColors c, BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? c.card : c.card.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: c.cardBorder.withValues(alpha: dark ? 0.35 : 0.75),
        width: 1,
      ),
      boxShadow: dark
          ? const []
          : [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -12,
              ),
            ],
    );
  }

  static BoxDecoration logoMark(AppColors c, BuildContext context) {
    if (isDark(context)) {
      return BoxDecoration(
        color: c.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary.withValues(alpha: 0.4)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [c.primary, c.primaryDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: c.primary.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 8),
          spreadRadius: -8,
        ),
      ],
    );
  }

  static Color logoIconColor(AppColors c, BuildContext context) =>
      isDark(context) ? c.primary : Colors.white;

  static BoxDecoration hero(
    AppColors c,
    BuildContext context, {
    required List<Color> gradientColors,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(20)),
  }) {
    if (isDark(context)) {
      return BoxDecoration(
        color: c.primary,
        borderRadius: borderRadius,
        border: Border.all(
          color: c.cardBorder.withValues(alpha: 0.4),
          width: 1,
        ),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: gradientColors.length >= 3
            ? const [0.0, 0.6, 1.0]
            : null,
      ),
      borderRadius: borderRadius,
      border: Border.all(
        color: gradientColors.first.withValues(alpha: 0.3),
        width: 1,
      ),
      boxShadow: accentShadow(context, gradientColors.first),
    );
  }

  static BoxDecoration accentHero(
    AppColors c,
    BuildContext context, {
    required List<Color> gradientColors,
    Color? borderTint,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(20)),
  }) {
    if (isDark(context)) {
      final base = gradientColors.first;
      return BoxDecoration(
        color: base,
        borderRadius: borderRadius,
        border: Border.all(
          color: (borderTint ?? base).withValues(alpha: 0.35),
          width: 1,
        ),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: gradientColors.length >= 3
            ? const [0.0, 0.5, 1.0]
            : null,
      ),
      borderRadius: borderRadius,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.2),
        width: 1,
      ),
      boxShadow: accentShadow(context, gradientColors.first),
    );
  }

  static BoxDecoration metricSurface(AppColors c, BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? c.card : c.card.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: c.cardBorder.withValues(alpha: dark ? 0.35 : 0.4),
        width: 1,
      ),
      boxShadow: dark
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: -3,
              ),
            ],
    );
  }

  static BoxDecoration iconBadge(
    AppColors c,
    BuildContext context,
    List<Color> gradientColors, {
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(10)),
  }) {
    if (isDark(context)) {
      final tint = gradientColors.first;
      return BoxDecoration(
        color: tint.withValues(alpha: 0.18),
        borderRadius: borderRadius,
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: borderRadius,
      boxShadow: [
        BoxShadow(
          color: gradientColors.first.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 3),
          spreadRadius: -2,
        ),
      ],
    );
  }

  static Color iconBadgeForeground(
    AppColors c,
    BuildContext context,
    List<Color> gradientColors,
  ) => isDark(context) ? gradientColors.first : Colors.white;

  static BoxDecoration sectionIcon(AppColors c, BuildContext context, Color tint) {
    if (isDark(context)) {
      return BoxDecoration(
        color: tint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [tint.withValues(alpha: 0.3), tint.withValues(alpha: 0.1)],
      ),
      borderRadius: BorderRadius.circular(10),
    );
  }

  static Color sectionIconForeground(
    AppColors c,
    BuildContext context,
    Color tint,
  ) => isDark(context) ? tint : Colors.white;

  static BoxDecoration tintedChip(
    BuildContext context,
    Color tint, {
    bool positive = true,
  }) {
    if (isDark(context)) {
      return BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [tint.withValues(alpha: 0.12), tint.withValues(alpha: 0.05)],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tint.withValues(alpha: 0.3)),
    );
  }

  static BoxDecoration dropdownChip(AppColors c, BuildContext context) {
    if (isDark(context)) {
      return BoxDecoration(
        color: c.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.primary.withValues(alpha: 0.28)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          c.accent.withValues(alpha: 0.15),
          c.primary.withValues(alpha: 0.15),
        ],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.primary.withValues(alpha: 0.3)),
    );
  }

  static BoxDecoration progressFill(BuildContext context, Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [color, color.withValues(alpha: 0.7)],
      ),
      borderRadius: BorderRadius.circular(5),
      boxShadow: isDark(context)
          ? const []
          : [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  static BoxDecoration rankAvatar(
    BuildContext context,
    Color medalColor, {
    BoxBorder? border,
  }) {
    if (isDark(context)) {
      return BoxDecoration(
        shape: BoxShape.circle,
        color: medalColor.withValues(alpha: 0.22),
        border:
            border ?? Border.all(color: medalColor.withValues(alpha: 0.55)),
      );
    }
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [medalColor, medalColor.withValues(alpha: 0.7)],
      ),
      border: border,
    );
  }

  static BoxDecoration podiumBar(BuildContext context, Color medalColor) {
    if (isDark(context)) {
      return BoxDecoration(
        color: medalColor.withValues(alpha: 0.22),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: medalColor.withValues(alpha: 0.45)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          medalColor.withValues(alpha: 0.55),
          medalColor.withValues(alpha: 0.2),
        ],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      border: Border.all(color: medalColor.withValues(alpha: 0.5)),
    );
  }

  static Widget titleText(
    BuildContext context, {
    required String text,
    required TextStyle style,
    List<Color>? shimmerColors,
  }) {
    if (isDark(context) || shimmerColors == null) {
      return Text(text, style: style);
    }
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: shimmerColors,
      ).createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class AppGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const AppGlassCard({
    super.key,
    required this.child,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppDecorations.colors(context);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.card(c, context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AppDecorations.wrapBlur(context, child),
      ),
    );
  }
}
