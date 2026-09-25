import 'package:flutter/material.dart';

/// 底部标签栏：胶囊形悬浮底栏（参考图一）。
/// - 白底胶囊、很圆的圆角、细描边 + 柔和投影
/// - 选中项：浅灰圆角矩形底包裹图标 + 文字
/// - 描边风图标，图标下有文字标签
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
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 12),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          // 参考图：不透明的白底胶囊；深色下用深灰。
          color: dark ? const Color(0xFF1B1B1E) : Colors.white,
          borderRadius: BorderRadius.circular(35),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE4E4E9),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
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
                icon: Icons.photo_camera_outlined,
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
    // 简约黑（深色下为白）描边图标，选中时浅灰圆角矩形底高亮。
    final fg = dark ? Colors.white : const Color(0xFF111111);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
        decoration: selected
            ? BoxDecoration(
                color: dark
                    ? const Color(0xFF2C2C30)
                    : const Color(0xFFE9E9EE),
                borderRadius: BorderRadius.circular(26),
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
