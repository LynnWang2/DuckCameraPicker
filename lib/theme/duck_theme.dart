import 'package:flutter/material.dart';

/// 取色鸭设计 token（2026-09-25 新版）：
/// 浅色为非常浅的灰底 + 白色卡片（无描边，底部浅灰小投影）；
/// 深色为灰黑底 + 深灰卡片。
class DuckColors {
  // —— 浅色 ——
  static const bgLight = Color(0xFFF2F2F6);
  static const cardLight = Color(0xFFFFFFFF);
  static const textLight = Color(0xFF111827);
  static const mutedLight = Color(0xFF8E8E93);

  // —— 深色（更深的灰黑）——
  static const bgDark = Color(0xFF101013);
  static const cardDark = Color(0xFF1C1C1F);
  static const textDark = Color(0xFFF5F5F7);
  static const mutedDark = Color(0xFF9A9AA0);

  // —— 品牌 ——
  static const accent = Color(0xFFFFBF47);
  static const saveBlue = Color(0xFF3B82F6);

  static const double cardRadius = 17;
}

/// 白色卡片装饰：无描边，底部浅灰小投影。
BoxDecoration duckCardDecoration(bool dark) {
  return BoxDecoration(
    color: dark ? DuckColors.cardDark : DuckColors.cardLight,
    borderRadius: BorderRadius.circular(DuckColors.cardRadius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.28 : 0.07),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// 中性背景（浅灰 / 灰黑）。
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? DuckColors.bgDark : DuckColors.bgLight,
    );
  }
}

class DuckTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: DuckColors.accent,
      surface: DuckColors.cardLight,
      onSurface: DuckColors.textLight,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DuckColors.bgLight,
      fontFamily: _fontFamily,
      cardTheme: CardThemeData(
        color: DuckColors.cardLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DuckColors.cardRadius),
        ),
      ),
      dividerColor: DuckColors.bgLight,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: DuckColors.accent,
      surface: DuckColors.cardDark,
      onSurface: DuckColors.textDark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DuckColors.bgDark,
      fontFamily: _fontFamily,
      cardTheme: CardThemeData(
        color: DuckColors.cardDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DuckColors.cardRadius),
        ),
      ),
      dividerColor: DuckColors.bgDark,
    );
  }

  static const _fontFamily = null; // 跟随系统（含苹方 / 微软雅黑）
}
