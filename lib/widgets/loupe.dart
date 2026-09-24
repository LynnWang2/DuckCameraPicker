import 'package:flutter/material.dart';

import '../camera/frame_sampler.dart';

/// 中心取色放大镜：把采样到的像素网格放大显示，中央十字标记取色点。
class LoupeView extends StatelessWidget {
  const LoupeView({
    super.key,
    required this.grid,
    this.size = 132,
  });

  final List<List<SampledPixel>> grid;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _LoupePainter(grid),
            ),
            // 中央十字
            const Center(child: _Crosshair()),
          ],
        ),
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _CrosshairPainter()),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final shadow = Paint()
      ..color = Colors.black54
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    canvas.drawCircle(c, r, shadow);
    canvas.drawCircle(c, r, paint);
    canvas.drawLine(Offset(c.dx - 6, c.dy), Offset(c.dx + 6, c.dy), shadow);
    canvas.drawLine(Offset(c.dx - 6, c.dy), Offset(c.dx + 6, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - 6), Offset(c.dx, c.dy + 6), shadow);
    canvas.drawLine(Offset(c.dx, c.dy - 6), Offset(c.dx, c.dy + 6), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoupePainter extends CustomPainter {
  _LoupePainter(this.grid);

  final List<List<SampledPixel>> grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.isEmpty) return;
    final n = grid.length;
    final cell = size.width / n;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final p = grid[y][x];
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          Paint()..color = Color.fromARGB(255, p.r, p.g, p.b),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoupePainter oldDelegate) =>
      !identical(oldDelegate.grid, grid);
}
