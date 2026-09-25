import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';
import '../widgets/glass_tab_bar.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// 主框架：底部 Liquid Glass 标签栏 + 标签页。
/// 左边取色历史，中间相机取色按钮，右边我的。
/// 中间按钮以全屏路由打开取色页，不占页面栈。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  Future<void> _openCamera() async {
    final state = context.read<AppState>();
    final result = await Navigator.of(context).push<PickedColor>(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已取色 ${result.name}，已复制 ${result.valueFor(state.copyFormat)}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        // 内容延伸到磨砂标签栏后面，透出毛玻璃效果。
        extendBody: true,
        body: Stack(
          children: [
            const Positioned.fill(child: HeroBackground()),
            Positioned.fill(
              child: IndexedStack(
                index: _index,
                children: const [
                  HistoryScreen(),
                  SizedBox.shrink(),
                  ProfileScreen(),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar(
                currentIndex: _index,
                onHistoryTap: () => setState(() => _index = 0),
                onCameraTap: _openCamera,
                onProfileTap: () => setState(() => _index = 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
