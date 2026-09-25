import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/duck_theme.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 取色页按竖屏设计，锁定竖屏避免预览旋转映射问题。
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // 沉浸式状态栏：内容延伸进系统栏，系统栏全透明。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: const DuckApp(),
    ),
  );
}

class DuckApp extends StatelessWidget {
  const DuckApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: '识色鸭',
      debugShowCheckedModeBanner: false,
      theme: DuckTheme.light(),
      darkTheme: DuckTheme.dark(),
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}
