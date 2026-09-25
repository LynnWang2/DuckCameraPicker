import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 我的页：应用图标与名称、取色设置、关于。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? DuckColors.textDark : DuckColors.textLight;
    final mutedColor = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
        children: [
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 88,
                      height: 88,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '取色鸭 · 相机版',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Duck Camera Picker',
                  style: TextStyle(fontSize: 13, color: mutedColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 0.1.0',
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: '取色设置',
            dark: dark,
            textColor: textColor,
            children: [
              const _FormatChips(),
              _SettingRow(
                icon: Icons.copy_rounded,
                label: '取色后复制',
                dark: dark,
                textColor: textColor,
                trailing: _CopyFormatDropdown(dark: dark, textColor: textColor),
              ),
              _SettingRow(
                icon: Icons.contrast_rounded,
                label: '软件外观',
                dark: dark,
                textColor: textColor,
                trailing: const _ThemeSegmented(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '更多',
            dark: dark,
            textColor: textColor,
            children: [
              _SettingRow(
                icon: Icons.info_outline_rounded,
                label: '关于',
                dark: dark,
                textColor: textColor,
                trailing: Icon(Icons.chevron_right_rounded, color: mutedColor),
                onTap: () => _showAbout(context, dark, textColor, mutedColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAbout(
      BuildContext context, bool dark, Color textColor, Color mutedColor) {
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
            Text(
              '取色鸭 · 相机版',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor),
            ),
            const SizedBox(height: 6),
            Text(
              '以取色鸭桌面端为原型\n用相机实时识别颜色',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: mutedColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 0.1.0',
              style: TextStyle(fontSize: 12, color: mutedColor),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.dark,
    required this.textColor,
    required this.children,
  });

  final String title;
  final bool dark;
  final Color textColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? DuckColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? DuckColors.lineDark : DuckColors.lineLight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.dark,
    required this.textColor,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool dark;
  final Color textColor;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mutedColor = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: mutedColor),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 15, color: textColor)),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// HEX / RGB / HSL / CMYK 显示开关。
class _FormatChips extends StatelessWidget {
  const _FormatChips();

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.palette_outlined,
            size: 20,
            color: dark ? DuckColors.mutedDark : DuckColors.mutedLight,
          ),
          const SizedBox(width: 12),
          Text(
            '显示格式',
            style: TextStyle(
              fontSize: 15,
              color: dark ? DuckColors.textDark : DuckColors.textLight,
            ),
          ),
          const Spacer(),
          for (var i = 0; i < formats.length; i++) ...[
            _FormatChip(
              format: formats[i],
              selected: state.formats.contains(formats[i]),
              dark: dark,
              onTap: () => state.toggleFormat(formats[i]),
            ),
            if (i < formats.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? DuckColors.accent.withValues(alpha: 0.22)
              : (dark ? DuckColors.fieldDark : DuckColors.fieldLight),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? DuckColors.accent : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          format.label,
          style: TextStyle(
            fontSize: 12,
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

class _CopyFormatDropdown extends StatelessWidget {
  const _CopyFormatDropdown({required this.dark, required this.textColor});

  final bool dark;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return DropdownButton<ColorFormat>(
      value: state.copyFormat,
      underline: const SizedBox.shrink(),
      style: TextStyle(fontSize: 13, color: textColor),
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
    );
  }
}

class _ThemeSegmented extends StatelessWidget {
  const _ThemeSegmented();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SegmentedButton<ThemeMode>(
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
    );
  }
}
