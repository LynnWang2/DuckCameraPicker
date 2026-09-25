import 'dart:ui';

import 'package:flutter/material.dart';

/// 底部标签栏：高级高斯模糊的圆角矩形底 + 简约黑色图标，
/// 选中项带浅灰色圆角高亮。
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: (dark ? Colors.black : Colors.white)
                  .withValues(alpha: dark ? 0.55 : 0.68),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.14 : 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
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
                Expanded(
                  child: _TabItem(
                    icon: Icons.colorize_rounded,
                    label: '取色',
                    selected: currentIndex == 1,
                    dark: dark,
                    onTap: onCameraTap,
                  ),
                ),
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
    // 简约黑（深色下为白）图标，选中时浅灰圆角底高亮。
    final fg = dark ? Colors.white : Colors.black;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: selected
            ? BoxDecoration(
                color: dark
                    ? const Color(0xFF3A3A3C).withValues(alpha: 0.85)
                    : const Color(0xFFE9E9EE),
                borderRadius: BorderRadius.circular(22),
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: fg),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
