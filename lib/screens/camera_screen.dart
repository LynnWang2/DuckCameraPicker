import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../camera/frame_sampler.dart';
import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 相机取色页：全屏预览，顶部圆角卡片实时显示颜色
/// （左边色块，右边上面中文颜色名、下面色值），中央小圆圈为取色点。
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
    setState(() => _current = pixel);
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
    final pixel = _current;
    final picked =
        pixel == null ? null : PickedColor.now(pixel.r, pixel.g, pixel.b);
    // 相机页用浅色系统栏图标（白色），与黑色预览形成对比。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
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
            // 顶部：关闭 / 取色卡片 / 闪光灯
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _ColorCard(picked: picked)),
                      const SizedBox(width: 10),
                      _RoundIconButton(
                        icon: _flashOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        onTap: _toggleFlash,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 中央取色点
            const Center(child: _PickDot()),
            // 底部确认按钮
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Center(
                    child: _ConfirmButton(
                      picked: picked,
                      onConfirm: picked == null ? null : _confirm,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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

/// 顶部圆角矩形取色卡片：左边圆形色块，右边上面中文颜色名、下面色值。
class _ColorCard extends StatelessWidget {
  const _ColorCard({required this.picked});

  final PickedColor? picked;

  @override
  Widget build(BuildContext context) {
    final p = picked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p?.color ?? const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p?.name ?? '取色中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p?.hexWithHash ?? '--',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Menlo', 'Consolas'],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 中央取色点：小圆圈。
class _PickDot extends StatelessWidget {
  const _PickDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
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

/// 底部悬浮确认按钮：确认取色并复制。
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.picked, required this.onConfirm});

  final PickedColor? picked;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final enabled = onConfirm != null;
    final label = enabled
        ? '确认取色 · 复制 ${picked!.valueFor(state.copyFormat)}'
        : '把圆圈对准要取的颜色';
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: onConfirm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [DuckColors.pickStart, DuckColors.pickEnd],
            ),
            boxShadow: [
              BoxShadow(
                color: DuckColors.pickEnd.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: DuckColors.pickText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
