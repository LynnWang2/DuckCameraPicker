import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
  // 默认取色；AppState 异步加载完成后会按用户的“启动时打开”设置校准。
  int _index = 1;
  bool _userNavigated = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (state.loaded) {
      _applyLaunchTab(state);
    } else {
      void listener() {
        if (!state.loaded) return;
        state.removeListener(listener);
        _applyLaunchTab(state);
      }

      state.addListener(listener);
    }
  }

  void _applyLaunchTab(AppState state) {
    if (_userNavigated) return;
    final idx = state.launchTab.clamp(0, 2);
    if (idx != _index && mounted) setState(() => _index = idx);
  }

  void _goTo(int index) {
    setState(() {
      _index = index;
      _userNavigated = true;
    });
  }

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
                onHistoryTap: () => _goTo(0),
                onCameraTap: () => _goTo(1),
                onProfileTap: () => _goTo(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
