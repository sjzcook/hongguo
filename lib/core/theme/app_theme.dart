import 'package:flutter/material.dart';

/// 全局色板：深色沉浸式短剧风格，主色取自红果的红橙。
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF0A0A0D);
  static const surface = Color(0xFF15151B);
  static const surfaceHigh = Color(0xFF1F1F27);
  static const surfaceHigher = Color(0xFF2A2A33);

  static const primary = Color(0xFFFF4D3D);
  static const primaryDeep = Color(0xFFE02B1D);
  static const gold = Color(0xFFFFC53D);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFF9A9AA6);
  static const textTertiary = Color(0xFF6B6B78);

  static const divider = Color(0xFF26262F);
  static const success = Color(0xFF2ECC71);

  /// 封面缺省渐变，按标题哈希取色，保证同一部剧色彩稳定。
  static const coverPalettes = <List<Color>>[
    [Color(0xFF3A1C71), Color(0xFFD76D77)],
    [Color(0xFF0F2027), Color(0xFF2C5364)],
    [Color(0xFF41295A), Color(0xFF2F0743)],
    [Color(0xFF614385), Color(0xFF516395)],
    [Color(0xFF1F4037), Color(0xFF99F2C8)],
    [Color(0xFF4B134F), Color(0xFFC94B4B)],
    [Color(0xFF141E30), Color(0xFF243B55)],
    [Color(0xFF5F0A87), Color(0xFFA4508B)],
  ];

  static List<Color> coverFor(String key) {
    if (key.isEmpty) return coverPalettes.first;
    final hash = key.codeUnits.fold<int>(7, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return coverPalettes[hash % coverPalettes.length];
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.6,
        space: 0.6,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          );
        }),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
      ),
    );
  }
}
