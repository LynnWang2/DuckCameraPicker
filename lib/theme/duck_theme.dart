import 'package:flutter/material.dart';

/// 取色鸭设计 token，直接对应桌面端 `src/styles.css` 的 CSS 变量。
class DuckColors {
  // —— 浅色（:root）——
  static const bgLight = Color(0xFFFFFFFF);
  static const cardLight = Color(0xFFFFFFFF);
  static const textLight = Color(0xFF111827);
  static const mutedLight = Color(0xFF6B7280);
  static const lineLight = Color(0xFFDCE2ED);
  static const fieldLight = Color(0xFFFBFCFF);
  static const heroStartLight = Color(0xFFFFF8E9);
  static const heroEndLight = Color(0xFFFFFAF1);

  // —— 深色（暖色降饱和版，v2.0.19）——
  static const bgDark = Color(0xFF221E1B);
  static const cardDark = Color(0xFF201D19);
  static const textDark = Color(0xFFF7F7F9);
  static const mutedDark = Color(0xFFADB2BE);
  static const lineDark = Color(0xFF3F3A32);
  static const fieldDark = Color(0xFF26221D);
  static const heroStartDark = Color(0xFF3F3930);
  static const heroEndDark = Color(0xFF302B25);

  // —— 品牌 ——
  static const accent = Color(0xFFFFBF47);
  static const pickStart = Color(0xFFFFE788);
  static const pickEnd = Color(0xFFFFB72D);
  static const pickText = Color(0xFF111827);

  static const double cardRadius = 17;
  static const double pickRadius = 17;
}

/// 顶部暖色 hero 背景，还原桌面端 `.app` 的渐变。
/// 浅色：hero-start → hero-end → bg 的纵向渐变；
/// 深色：bg 底色 + 右上 / 左中两团暖色 radial。
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              DuckColors.heroStartLight,
              DuckColors.heroEndLight,
              DuckColors.bgLight,
            ],
            stops: [0.0, 0.45, 0.75],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Container(color: DuckColors.bgDark),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, -1.0),
              radius: 1.1,
              colors: [
                DuckColors.heroStartDark.withValues(alpha: 0.9),
                DuckColors.heroStartDark.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.46],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.76, -0.24),
              radius: 1.0,
              colors: [
                DuckColors.heroEndDark.withValues(alpha: 0.85),
                DuckColors.heroEndDark.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.42],
            ),
          ),
        ),
      ],
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
          side: const BorderSide(color: DuckColors.lineLight),
        ),
      ),
      dividerColor: DuckColors.lineLight,
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
          side: const BorderSide(color: DuckColors.lineDark),
        ),
      ),
      dividerColor: DuckColors.lineDark,
    );
  }

  static const _fontFamily = null; // 跟随系统（含苹方 / 微软雅黑）
}

/// 桌面端同款大黄渐变按钮。
class DuckPickButton extends StatelessWidget {
  const DuckPickButton({
    super.key,
    required this.title,
    this.subtitle,
    required this.onPressed,
    this.height = 69,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DuckColors.pickRadius),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [DuckColors.pickStart, DuckColors.pickEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: DuckColors.pickEnd.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DuckColors.pickText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: DuckColors.pickText.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
