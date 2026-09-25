import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/duck_theme.dart';
import '../widgets/glass_tab_bar.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// 主框架：底部 Liquid Glass 标签栏 + 三个标签页。
/// 中间取色页直接常驻标签页，不再跳转新页面。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 非相机页用与主题配套的系统栏图标；相机页自己覆盖。
    final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: [
            const HeroBackground(),
            IndexedStack(
              index: _index,
              children: [
                const HistoryScreen(),
                CameraPage(active: _index == 1),
                const ProfileScreen(),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar(
                currentIndex: _index,
                onHistoryTap: () => setState(() => _index = 0),
                onCameraTap: () => setState(() => _index = 1),
                onProfileTap: () => setState(() => _index = 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
