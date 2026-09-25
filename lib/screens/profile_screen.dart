import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 我的页：应用图标与名称、取色设置。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static final _githubUri =
      Uri.parse('https://github.com/LynnWang2/DuckCameraPicker');

  Future<void> _openGithub(BuildContext context) async {
    final ok = await launchUrl(_githubUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法打开浏览器'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? DuckColors.textDark : DuckColors.textLight;
    final muted = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 24, 16, bottomPad + 110),
          children: [
            // 图标 + 名称：去掉圆角矩形底。
            Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('assets/icon.png'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '取色鸭相机版',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 0.3.0',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _openGithub(context),
                  child: const Text(
                    'Github主页',
                    style: TextStyle(
                      fontSize: 13,
                      color: DuckColors.saveBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionCard(
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.text_fields_rounded,
                    title: '显示格式',
                    trailing: Text(
                      _formatLabel(state.displayFormat),
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                    onTap: () => _showFormatDialog(context, state),
                  ),
                  _divider(dark),
                  _SwitchRow(
                    icon: Icons.content_copy_rounded,
                    title: '复制HEX去掉#',
                    value: state.stripHashOnCopy,
                    onChanged: state.setStripHashOnCopy,
                  ),
                  _divider(dark),
                  _SettingRow(
                    icon: Icons.dark_mode_outlined,
                    title: '软件外观',
                    trailing: Text(
                      _themeLabel(state.themeMode),
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                    onTap: () => _showThemeDialog(context, state),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(bool dark) {
    return Divider(
      height: 1,
      indent: 52,
      color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
    );
  }

  String _formatLabel(ColorFormat f) {
    switch (f) {
      case ColorFormat.hex:
        return 'HEX';
      case ColorFormat.rgb:
        return 'RGB';
      case ColorFormat.hsl:
        return 'HSL';
      case ColorFormat.cmyk:
        return 'CMYK';
    }
  }

  String _themeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  /// 显示格式：圆角矩形单选框。
  Future<void> _showFormatDialog(BuildContext context, AppState state) {
    return _showOptionDialog<ColorFormat>(
      context: context,
      title: '显示格式',
      options: ColorFormat.values,
      selected: state.displayFormat,
      label: _formatLabel,
      onSelect: state.setDisplayFormat,
    );
  }

  /// 软件外观：圆角矩形单选框。
  Future<void> _showThemeDialog(BuildContext context, AppState state) {
    return _showOptionDialog<ThemeMode>(
      context: context,
      title: '软件外观',
      options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
      selected: state.themeMode,
      label: _themeLabel,
      onSelect: state.setThemeMode,
    );
  }
}

/// 圆角矩形单选框。
Future<void> _showOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T) label,
  required ValueChanged<T> onSelect,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final text = dark ? DuckColors.textDark : DuckColors.textLight;
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text(label(o), style: TextStyle(color: text)),
                trailing: o == selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: DuckColors.saveBlue,
                      )
                    : null,
                onTap: () {
                  onSelect(o);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: duckCardDecoration(dark),
      child: child,
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? DuckColors.textDark : DuckColors.textLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: text),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
            ),
            trailing,
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
            ),
          ],
        ),
      ),
    );
  }
}

/// 开关行（无跳转箭头）。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? DuckColors.textDark : DuckColors.textLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: text),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DuckColors.saveBlue,
          ),
        ],
      ),
    );
  }
}
