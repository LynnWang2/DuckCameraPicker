import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 取色历史页：全部取色记录，点按复制色值。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  void _confirmClear(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('清空历史', style: TextStyle(fontSize: 17)),
        content: const Text('确定要删除全部取色记录吗？', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              state.clearHistory();
              Navigator.of(context).pop();
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? DuckColors.textDark : DuckColors.textLight;
    final mutedColor = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
        children: [
          Row(
            children: [
              Text(
                '取色历史',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: DuckColors.accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${state.history.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DuckColors.pickEnd,
                  ),
                ),
              ),
              const Spacer(),
              if (state.history.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context, state),
                  child: Text('清空', style: TextStyle(color: mutedColor)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 72),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.colorize_rounded,
                      size: 52,
                      color: mutedColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有取色记录',
                      style: TextStyle(fontSize: 15, color: mutedColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点底部中间的按钮开始取色吧',
                      style: TextStyle(fontSize: 13, color: mutedColor),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final c in state.history)
              _HistoryRow(
                color: c,
                dark: dark,
                textColor: textColor,
                mutedColor: mutedColor,
              ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.color,
    required this.dark,
    required this.textColor,
    required this.mutedColor,
  });

  final PickedColor color;
  final bool dark;
  final Color textColor;
  final Color mutedColor;

  String get _time {
    final t = color.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: dark ? DuckColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? DuckColors.lineDark : DuckColors.lineLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
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
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.color,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: dark ? DuckColors.lineDark : DuckColors.lineLight,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        color.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${color.hexWithHash} · $_time',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Menlo', 'Consolas'],
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 20, color: mutedColor),
                  onPressed: () => state.removeColor(color.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
