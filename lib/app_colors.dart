import 'package:flutter/material.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color accent;
  final Color accentPurple;
  final Color success;
  final Color danger;
  final Color bg;
  final Color bgGradient1;
  final Color bgGradient2;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;

  const AppColors({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
    required this.accentPurple,
    required this.success,
    required this.danger,
    required this.bg,
    required this.bgGradient1,
    required this.bgGradient2,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
  });

  static const dark = AppColors(
    primary: Color(0xFFE8956A),
    primaryDark: Color(0xFFD4734A),
    primaryLight: Color(0xFFFFB088),
    accent: Color(0xFFFFCBA4),
    accentPurple: Color(0xFF9D7BEA),
    success: Color(0xFF5EEAD4),
    danger: Color(0xFFFF8A8A),
    bg: Color(0xFF121014),
    bgGradient1: Color(0xFF121014),
    bgGradient2: Color(0xFF18161A),
    card: Color(0xFF1C1A1F),
    cardBorder: Color(0xFF2E2A33),
    textPrimary: Color(0xFFF5F0EB),
    textSecondary: Color(0xFF9A918A),
  );

  static const light = AppColors(
    primary: Color(0xFFD4734A),
    primaryDark: Color(0xFFC0613C),
    primaryLight: Color(0xFFFFB088),
    accent: Color(0xFFE8B38A),
    accentPurple: Color(0xFF7C5DC7),
    success: Color(0xFF0D9488),
    danger: Color(0xFFE85454),
    bg: Color(0xFFF8F5F2),
    bgGradient1: Color(0xFFF0EBF5),
    bgGradient2: Color(0xFFF5EEF8),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE8DDF0),
    textPrimary: Color(0xFF1A1020),
    textSecondary: Color(0xFF7A6B88),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primaryLight,
    Color? accent,
    Color? accentPurple,
    Color? success,
    Color? danger,
    Color? bg,
    Color? bgGradient1,
    Color? bgGradient2,
    Color? card,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryLight: primaryLight ?? this.primaryLight,
      accent: accent ?? this.accent,
      accentPurple: accentPurple ?? this.accentPurple,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      bg: bg ?? this.bg,
      bgGradient1: bgGradient1 ?? this.bgGradient1,
      bgGradient2: bgGradient2 ?? this.bgGradient2,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bgGradient1: Color.lerp(bgGradient1, other.bgGradient1, t)!,
      bgGradient2: Color.lerp(bgGradient2, other.bgGradient2, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}
