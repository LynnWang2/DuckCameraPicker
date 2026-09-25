import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 取色历史页：全部取色记录，点按复制色值（复制格式跟随“显示格式”设置）。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.history;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('取色历史'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmClear(context, state),
              tooltip: '清空历史',
            ),
        ],
      ),
      body: history.isEmpty
          ? const _EmptyHint()
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 110),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _HistoryRow(color: history[i], key: ValueKey(history[i].id)),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要删除全部取色记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) state.clearHistory();
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Text(
            '还没有取色记录',
            style: TextStyle(color: muted, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '去相机页取个颜色，点保存就进来啦',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({super.key, required this.color});

  final PickedColor color;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? DuckColors.textDark : DuckColors.textLight;
    final muted = dark ? DuckColors.mutedDark : DuckColors.mutedLight;
    return Dismissible(
      key: ValueKey(color.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(DuckColors.cardRadius),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      onDismissed: (_) => state.removeColor(color.id),
      child: GestureDetector(
        onTap: () async {
          final value = color.valueFor(state.displayFormat);
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已复制 $value'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: duckCardDecoration(dark),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.color,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      color.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      color.valueFor(state.displayFormat),
                      style: TextStyle(
                        fontSize: 13,
                        color: muted,
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Menlo', 'Consolas'],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(color.createdAt),
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
