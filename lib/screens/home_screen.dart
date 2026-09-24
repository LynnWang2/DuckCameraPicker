import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';
import 'camera_screen.dart';

/// 主页，还原桌面端取色鸭的布局：
/// 品牌区 → 大取色按钮 → 格式开关 → 最近取色 → 取色设置。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final state = context.read<AppState>();
    final result = await Navigator.of(context).push<PickedColor>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (result != null && context.mounted) {
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
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: HeroBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(17, 8, 17, 24),
                  children: [
                    const _Brand(),
                    const SizedBox(height: 10),
                    DuckPickButton(
                      title: '相机取色',
                      subtitle: '对准颜色 · 实时识别',
                      onPressed: () => _openCamera(context),
                    ),
                    const SizedBox(height: 14),
                    const _FormatSegments(),
                    const SizedBox(height: 14),
                    const _HistoryCard(),
                    const SizedBox(height: 14),
                    _SettingsCard(dark: dark),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Image.asset('assets/icon.png', width: 78, height: 78),
        ),
        const SizedBox(height: 5),
        Text(
          '取色鸭',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: dark ? DuckColors.textDark : DuckColors.textLight,
          ),
        ),
        Text(
          'Duck Camera Picker',
          style: TextStyle(
            fontSize: 13,
            color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
          ),
        ),
      ],
    );
  }
}

/// HEX / RGB / HSL / CMYK 显示开关。
class _FormatSegments extends StatelessWidget {
  const _FormatSegments();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    const formats = [
      ColorFormat.hex,
      ColorFormat.rgb,
      ColorFormat.hsl,
      ColorFormat.cmyk,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < formats.length; i++) ...[
          _FormatChip(
            format: formats[i],
            selected: state.formats.contains(formats[i]),
            dark: dark,
            onTap: () => state.toggleFormat(formats[i]),
          ),
          if (i < formats.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.format,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final ColorFormat format;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = dark ? DuckColors.lineDark : DuckColors.lineLight;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? DuckColors.accent.withValues(alpha: 0.22)
              : (dark ? DuckColors.fieldDark : DuckColors.fieldLight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? DuckColors.accent : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          format.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (dark ? DuckColors.textDark : DuckColors.textLight)
                : (dark ? DuckColors.mutedDark : DuckColors.mutedLight),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '最近取色',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: dark ? DuckColors.textDark : DuckColors.textLight,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: DuckColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.history.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DuckColors.accent,
                    ),
                  ),
                ),
                const Spacer(),
                if (state.history.isNotEmpty)
                  TextButton(
                    onPressed: state.clearHistory,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            dark ? DuckColors.mutedDark : DuckColors.mutedLight,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (state.history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    '还没有取色记录，对准颜色开始取色吧',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          dark ? DuckColors.mutedDark : DuckColors.mutedLight,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.history.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) =>
                      _HistoryChip(color: state.history[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.color});

  final PickedColor color;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(
            ClipboardData(text: color.valueFor(state.copyFormat)));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制 ${color.valueFor(state.copyFormat)}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: dark ? DuckColors.lineDark : DuckColors.lineLight,
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: GestureDetector(
                    onTap: () => state.removeColor(color.id),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              color.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: dark ? DuckColors.textDark : DuckColors.textLight,
              ),
            ),
            Text(
              color.hexWithHash,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas'],
                color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '取色设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: dark ? DuckColors.textDark : DuckColors.textLight,
              ),
            ),
            const SizedBox(height: 6),
            _SettingRow(
              icon: Icons.contrast,
              label: '软件外观',
              dark: dark,
              trailing: SegmentedButton<ThemeMode>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (s) => state.setThemeMode(s.first),
              ),
            ),
            _SettingRow(
              icon: Icons.copy,
              label: '取色后复制',
              dark: dark,
              trailing: DropdownButton<ColorFormat>(
                value: state.copyFormat,
                underline: const SizedBox.shrink(),
                style: TextStyle(
                  fontSize: 13,
                  color: dark ? DuckColors.textDark : DuckColors.textLight,
                ),
                dropdownColor: dark ? DuckColors.cardDark : Colors.white,
                items: const [
                  DropdownMenuItem(
                    value: ColorFormat.hex,
                    child: Text('HEX（不含 #）'),
                  ),
                  DropdownMenuItem(
                    value: ColorFormat.hexWithHash,
                    child: Text('HEX（含 #）'),
                  ),
                  DropdownMenuItem(
                    value: ColorFormat.rgb,
                    child: Text('RGB'),
                  ),
                  DropdownMenuItem(
                    value: ColorFormat.hsl,
                    child: Text('HSL'),
                  ),
                  DropdownMenuItem(
                    value: ColorFormat.cmyk,
                    child: Text('CMYK'),
                  ),
                ],
                onChanged: (f) {
                  if (f != null) state.setCopyFormat(f);
                },
              ),
            ),
            _SettingRow(
              icon: Icons.info_outline,
              label: '关于',
              dark: dark,
              trailing: Icon(
                Icons.chevron_right,
                color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
              ),
              onTap: () => _showAbout(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/icon.png', width: 64, height: 64),
            ),
            const SizedBox(height: 12),
            const Text('取色鸭 · 相机版',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '以取色鸭桌面端 UI 为原型\n用相机实时识别颜色',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 0.1.0',
              style: TextStyle(
                fontSize: 12,
                color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.dark,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool dark;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: dark ? DuckColors.textDark : DuckColors.textLight,
              ),
            ),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }
}
