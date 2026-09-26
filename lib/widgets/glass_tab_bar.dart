import 'dart:ui';

import 'package:flutter/material.dart';

/// 底部标签栏：胶囊形悬浮底栏（参考图一）。
/// - iOS 18 风格磨砂：高斯模糊 + 半透明底，透出后面画面
/// - 选中项：紧包裹图标 + 文字的浅灰小药丸（参考图一比例）
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
      // 外层大胶囊：左右收窄为悬浮胶囊（参考图一比例），上下高度不变。
      padding: EdgeInsets.fromLTRB(56, 0, 56, bottomInset + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: (dark ? const Color(0xFF1B1B1E) : Colors.white)
                  .withValues(alpha: dark ? 0.62 : 0.66),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
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
            child: Center(
              child: Row(
                // 三个按钮居中收拢：固定宽度 + 小间距，缩短按钮之间的距离。
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TabItem(
                    icon: Icons.history_rounded,
                    label: '历史',
                    selected: currentIndex == 0,
                    dark: dark,
                    onTap: onHistoryTap,
                  ),
                  const SizedBox(width: 2),
                  _TabItem(
                    icon: Icons.photo_camera_outlined,
                    label: '取色',
                    selected: currentIndex == 1,
                    dark: dark,
                    onTap: onCameraTap,
                  ),
                  const SizedBox(width: 2),
                  _TabItem(
                    icon: Icons.person_outline_rounded,
                    label: '我的',
                    selected: currentIndex == 2,
                    dark: dark,
                    onTap: onProfileTap,
                  ),
                ],
              ),
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
    // 选中项：加宽的半透明暗色小胶囊（参考图一比例）。
    // 正片叠底等效：半透明黑色直接画在磨砂底上，数学上与 multiply 结果一致。
    final fg = dark ? Colors.white : const Color(0xFF111111);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 88,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 7),
            decoration: selected
                ? BoxDecoration(
                    color: Colors.black.withValues(
                        alpha: dark ? 0.45 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                  )
                : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
      ),
      ),
    );
  }
}
