import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/duck_theme.dart';

/// 底部 Liquid Glass 风格标签栏：磨砂圆角矩形。
/// iOS 上呈现半透明毛玻璃质感，Android 上用 BackdropFilter 实现磨砂效果。
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.currentIndex,
    required this.onHistoryTap,
    required this.onCameraTap,
    required this.onProfileTap,
  });

  final int currentIndex;
  final VoidCallback onHistoryTap;
  final VoidCallback onCameraTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 0, 28, bottomInset + 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: (dark ? const Color(0xFF1C1C1E) : Colors.white)
                  .withValues(alpha: dark ? 0.62 : 0.66),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.16 : 0.55),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabItem(
                    icon: Icons.history_rounded,
                    label: '取色历史',
                    selected: currentIndex == 0,
                    dark: dark,
                    onTap: onHistoryTap,
                  ),
                ),
                _CameraFab(onTap: onCameraTap),
                Expanded(
                  child: _TabItem(
                    icon: Icons.person_outline_rounded,
                    label: '我的',
                    selected: currentIndex == 2,
                    dark: dark,
                    onTap: onProfileTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? DuckColors.pickEnd
        : (dark ? DuckColors.mutedDark : DuckColors.mutedLight);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 25, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 中间凸起的相机取色按钮。
class _CameraFab extends StatelessWidget {
  const _CameraFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DuckColors.pickStart, DuckColors.pickEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: DuckColors.pickEnd.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.colorize_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
