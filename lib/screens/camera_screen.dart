import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../camera/frame_sampler.dart';
import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';
import '../widgets/loupe.dart';

/// 相机取色页：全屏预览，把中央准星对准颜色即可实时取色。
/// 取色点固定为画面中心，避开预览旋转带来的坐标映射问题。
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  CameraImage? _latestFrame;
  Timer? _sampleTimer;
  SampledPixel? _current;
  List<List<SampledPixel>>? _loupeGrid;
  String? _error;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = '没有找到可用相机');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.startImageStream((image) {
        _latestFrame = image;
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _sampleTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) => _sample(),
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = '相机启动失败：${e.description ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '相机启动失败：$e');
    }
  }

  void _sample() {
    final frame = _latestFrame;
    if (frame == null || !mounted) return;
    final pixel = FrameSampler.sampleCenter(frame);
    if (pixel == null) return;
    // 变化不大就不刷新，避免抖动。
    final cur = _current;
    if (cur != null &&
        (cur.r - pixel.r).abs() +
                (cur.g - pixel.g).abs() +
                (cur.b - pixel.b).abs() <
            6) {
      return;
    }
    setState(() {
      _current = pixel;
      _loupeGrid = FrameSampler.sampleCenterGrid(frame);
    });
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final next = !_flashOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = next);
    } catch (_) {
      // 部分设备不支持闪光灯，忽略。
    }
  }

  void _confirm() {
    final pixel = _current;
    if (pixel == null) return;
    final state = context.read<AppState>();
    final color = PickedColor.now(pixel.r, pixel.g, pixel.b);
    state.addColor(color);
    Clipboard.setData(ClipboardData(text: color.valueFor(state.copyFormat)));
    if (mounted) Navigator.of(context).pop(color);
  }

  Future<void> _disposeController(CameraController c) async {
    try {
      await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) _disposeController(controller).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (controller != null && controller.value.isInitialized)
            Positioned.fill(child: _PreviewFill(controller: controller))
          else
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: DuckColors.accent),
              ),
            ),
          if (_error != null)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _setupCamera,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 中央准星
          const Center(child: _Reticle()),
          // 顶部栏
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _RoundIconButton(
                    icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                    onTap: _toggleFlash,
                  ),
                ],
              ),
            ),
          ),
          // 底部取色面板
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              current: _current,
              loupeGrid: _loupeGrid,
              onConfirm: _current == null ? null : _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预览填满屏幕（cover 裁剪，不变形）。
/// 应用锁定竖屏，sensor 输出为横向尺寸，显示时宽高互换。
class _PreviewFill extends StatelessWidget {
  const _PreviewFill({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final ps = controller.value.previewSize!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: ps.height,
        height: ps.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(painter: _ReticlePainter()),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final ringShadow = Paint()
      ..color = Colors.black45
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, 34, ringShadow);
    canvas.drawCircle(c, 34, ring);
    final tick = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const gap = 40.0, len = 10.0;
    canvas.drawLine(
        Offset(c.dx - gap - len, c.dy), Offset(c.dx - gap, c.dy), tick);
    canvas.drawLine(
        Offset(c.dx + gap, c.dy), Offset(c.dx + gap + len, c.dy), tick);
    canvas.drawLine(
        Offset(c.dx, c.dy - gap - len), Offset(c.dx, c.dy - gap), tick);
    canvas.drawLine(
        Offset(c.dx, c.dy + gap), Offset(c.dx, c.dy + gap + len), tick);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.current,
    required this.loupeGrid,
    required this.onConfirm,
  });

  final SampledPixel? current;
  final List<List<SampledPixel>>? loupeGrid;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pixel = current;
    final picked = pixel == null
        ? null
        : PickedColor(
            id: 'preview',
            r: pixel.r,
            g: pixel.g,
            b: pixel.b,
            name: colorName(pixel.r, pixel.g, pixel.b),
            createdAt: DateTime.now(),
          );

    final formats = state.formats.isEmpty ? {ColorFormat.hex} : state.formats;

    return Container(
      decoration: BoxDecoration(
        color: dark ? DuckColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 24, offset: Offset(0, -6))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (loupeGrid != null)
                    LoupeView(grid: loupeGrid!, size: 104)
                  else
                    Container(
                      width: 104,
                      height: 104,
                      decoration: const BoxDecoration(
                        color: Colors.black12,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: picked == null
                        ? Text(
                            '把准星对准要取的颜色',
                            style: TextStyle(
                              fontSize: 15,
                              color: dark
                                  ? DuckColors.mutedDark
                                  : DuckColors.mutedLight,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: picked.color,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: dark
                                            ? DuckColors.lineDark
                                            : DuckColors.lineLight,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    picked.name,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: dark
                                          ? DuckColors.textDark
                                          : DuckColors.textLight,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              for (final f in ColorFormat.values)
                                if (formats.contains(f))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 52,
                                          child: Text(
                                            f.displayLabel,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: dark
                                                  ? DuckColors.mutedDark
                                                  : DuckColors.mutedLight,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            picked.valueFor(f),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontFamily: 'monospace',
                                              fontFamilyFallback: const [
                                                'Menlo',
                                                'Consolas'
                                              ],
                                              color: dark
                                                  ? DuckColors.textDark
                                                  : DuckColors.textLight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Opacity(
                opacity: onConfirm == null ? 0.45 : 1.0,
                child: DuckPickButton(
                  title: '确认取色',
                  subtitle: picked == null
                      ? null
                      : '将复制 ${picked.valueFor(state.copyFormat)}',
                  height: 60,
                  onPressed: onConfirm ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
