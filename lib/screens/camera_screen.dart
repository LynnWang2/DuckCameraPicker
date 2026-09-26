import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../camera/frame_sampler.dart';
import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 相机取色页（中间标签页）：实时预览 + 中央取色点。
/// - 标签栏上方的相机按钮：按下定格画面，定格后变成 X 按钮，按下回到实时取色
/// - 定格后取色点可跟随单指拖动，取色结果从拍摄的静态照片采样。
/// - 相机按钮上方：高斯模糊圆角矩形颜色卡片（色块 + 中文名 + 色值 + 保存按钮）
/// - 实时预览双指缩放：硬件变焦，非阻塞调用 + 节流，避免卡顿
class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.active});

  /// 是否为当前可见标签页；不可见时暂停预览与采样以省电。
  final bool active;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  CameraImage? _latestFrame;
  Timer? _sampleTimer;
  SampledPixel? _current;
  String? _error;
  bool _flashOn = false;

  // 保留早期已验证的拍照定格流程；静态照片解码后支持拖动取色。
  bool _frozen = false;
  XFile? _frozenFile;
  ByteData? _frozenRgba;
  int _frozenWidth = 0;
  int _frozenHeight = 0;
  bool _capturing = false; // 定格进行中，防止重复点击
  double _frozenOpacity = 0;

  // 定格后取色点位置（屏幕坐标；null = 画面中心）
  final ValueNotifier<Offset?> _pickPoint = ValueNotifier<Offset?>(null);
  DateTime? _lastFrozenSample;

  // 实时预览缩放
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _baseZoom = 1.0;
  final ValueNotifier<double?> _zoomBadge = ValueNotifier<double?>(null);
  Timer? _zoomHideTimer;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  @override
  void didUpdateWidget(covariant CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _onBecameActive();
      } else {
        _onBecameInactive();
      }
    }
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
        // 高分辨率：定格图更清晰，采样也更准。
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
      } catch (_) {
        // 部分设备不支持查询缩放范围，保持 1.0。
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (widget.active) _startStream();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = '相机启动失败：${e.description ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '相机启动失败：$e');
    }
  }

  void _startStream() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_frozen) return;
    try {
      controller.startImageStream((image) {
        _latestFrame = image;
      });
    } catch (_) {}
    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _sample(),
    );
  }

  Future<void> _stopStream() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _latestFrame = null;
    final controller = _controller;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
  }

  void _onBecameActive() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.resumePreview().then((_) {
      if (mounted && widget.active) _startStream();
    }).catchError((_) {
      if (mounted && widget.active) _startStream();
    }));
  }

  void _onBecameInactive() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(() async {
      await _stopStream();
      try {
        await controller.pausePreview();
      } catch (_) {}
    }());
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

  /// 恢复 0.3.0 路径：停止采样定时器后直接 takePicture，显示 JPEG。
  Future<void> _freeze() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_frozen || _capturing) return;
    _capturing = true;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    try {
      if (controller.value.isStreamingImages) {
        unawaited(controller.stopImageStream().catchError((_) {}));
      }
      final photo = await controller.takePicture();
      if (!mounted) return;
      _presentFrozen(photo);
    } catch (_) {
      if (mounted) {
        _toast('定格失败，请重试');
        _startStream();
      }
    } finally {
      _capturing = false;
    }
  }

  void _presentFrozen(XFile photo) {
    _frozenFile = photo;
    _frozenRgba = null;
    _frozenWidth = 0;
    _frozenHeight = 0;
    _pickPoint.value = null;
    _lastFrozenSample = null;
    setState(() {
      _frozen = true;
      _frozenOpacity = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _frozen) setState(() => _frozenOpacity = 1);
    });
    unawaited(_decodeFrozenPhoto(photo));
  }

  /// Decode the captured JPEG once. Sampling then reads only a tiny pixel area
  /// from the cached RGBA bytes and never touches the live camera stream.
  Future<void> _decodeFrozenPhoto(XFile photo) async {
    try {
      final bytes = await photo.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final rgba = await frame.image.toByteData(
            format: ImageByteFormat.rawRgba,
          );
          if (rgba == null || !mounted || !_frozen) return;
          if (_frozenFile?.path != photo.path) return;
          _frozenRgba = rgba;
          _frozenWidth = frame.image.width;
          _frozenHeight = frame.image.height;
          final size = MediaQuery.of(context).size;
          _sampleFrozenAt(
              _pickPoint.value ?? Offset(size.width / 2, size.height / 2));
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted && _frozenFile?.path == photo.path) {
        _toast('定格画面已保留，但暂时无法从照片取色');
      }
    }
  }

  void _movePickPoint(Offset point) {
    final size = MediaQuery.of(context).size;
    final clamped = Offset(
      point.dx.clamp(0.0, size.width),
      point.dy.clamp(0.0, size.height),
    );
    _pickPoint.value = clamped;
    final now = DateTime.now();
    if (_lastFrozenSample == null ||
        now.difference(_lastFrozenSample!) >=
            const Duration(milliseconds: 60)) {
      _lastFrozenSample = now;
      _sampleFrozenAt(clamped);
    }
  }

  void _sampleFrozenAt(Offset point) {
    final rgba = _frozenRgba;
    final width = _frozenWidth;
    final height = _frozenHeight;
    if (rgba == null || width == 0 || height == 0 || !mounted) return;

    final size = MediaQuery.of(context).size;
    final scale = math.max(size.width / width, size.height / height);
    final offsetX = (size.width - width * scale) / 2;
    final offsetY = (size.height - height * scale) / 2;
    final x = ((point.dx - offsetX) / scale).round().clamp(0, width - 1);
    final y = ((point.dy - offsetY) / scale).round().clamp(0, height - 1);

    var red = 0, green = 0, blue = 0, count = 0;
    for (var sampleY = y - 2; sampleY <= y + 2; sampleY++) {
      if (sampleY < 0 || sampleY >= height) continue;
      for (var sampleX = x - 2; sampleX <= x + 2; sampleX++) {
        if (sampleX < 0 || sampleX >= width) continue;
        final offset = (sampleY * width + sampleX) * 4;
        if (offset + 2 >= rgba.lengthInBytes) continue;
        red += rgba.getUint8(offset);
        green += rgba.getUint8(offset + 1);
        blue += rgba.getUint8(offset + 2);
        count++;
      }
    }
    if (count == 0) return;
    setState(() =>
        _current = SampledPixel(red ~/ count, green ~/ count, blue ~/ count));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 回到实时取色并释放定格帧。
  Future<void> _unfreeze() async {
    if (!_frozen) return;
    _frozen = false;
    final photo = _frozenFile;
    _frozenFile = null;
    _frozenRgba = null;
    _frozenWidth = 0;
    _frozenHeight = 0;
    _frozenOpacity = 0;
    _pickPoint.value = null;
    if (photo != null) {
      try {
        await File(photo.path).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {});
    _startStream();
  }

  // —— 实时预览双指缩放：硬件变焦，非阻塞 + 节流，UI 只更新倍数徽标 ——
  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final controller = _controller;
    if (controller == null || _frozen) return;
    final next = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((next - _zoom).abs() < 0.005) return;
    _zoom = next;
    // 不 await：平台调用排队是之前卡顿的主因。
    unawaited(controller.setZoomLevel(_zoom).then((_) {}).catchError((_) {}));
    _zoomBadge.value = _zoom;
    _zoomHideTimer?.cancel();
    _zoomHideTimer = Timer(const Duration(seconds: 1), () {
      _zoomBadge.value = null;
    });
  }

  /// 保存当前颜色到取色历史。
  void _save() {
    final pixel = _current;
    if (pixel == null) return;
    final state = context.read<AppState>();
    final color = PickedColor.now(pixel.r, pixel.g, pixel.b);
    state.addColor(color);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存 ${color.name} 到取色历史'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _disposeController(CameraController c) async {
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _zoomHideTimer?.cancel();
    _pickPoint.dispose();
    _zoomBadge.dispose();
    _frozenFile = null;
    _frozenRgba = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_disposeController(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final pixel = _current;
    final picked =
        pixel == null ? null : PickedColor.now(pixel.r, pixel.g, pixel.b);
    final frozen = _frozen;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // 相机页用浅色系统栏图标（白色），与预览形成对比。
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
            // 保持预览层常驻，早期 JPEG 照片显示在预览上层。
            Positioned.fill(child: _buildLive(controller)),
            if (frozen && _frozenFile != null)
              Positioned.fill(child: _buildFrozen()),
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
            if (!frozen)
              const Center(child: _PickDot())
            else
              ValueListenableBuilder<Offset?>(
                valueListenable: _pickPoint,
                builder: (context, point, _) {
                  final size = MediaQuery.of(context).size;
                  final position =
                      point ?? Offset(size.width / 2, size.height / 2);
                  return Positioned(
                    left: position.dx - 9,
                    top: position.dy - 9,
                    child: const _PickDot(),
                  );
                },
              ),
            // 缩放倍数指示（只重建徽标本身）：与右上角闪光灯按钮垂直居中对齐
            // （闪光灯 40 高、顶部 8；徽标放在同样的 40 高区域内居中）。
            ValueListenableBuilder<double?>(
              valueListenable: _zoomBadge,
              builder: (context, z, _) {
                if (z == null) return const SizedBox.shrink();
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: SizedBox(
                          height: 40,
                          child: Center(child: _ZoomBadge(zoom: z)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 闪光灯
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 16),
                  child: _RoundIconButton(
                    icon: _flashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    onTap: _toggleFlash,
                  ),
                ),
              ),
            ),
            // 底部：颜色卡片 + 相机/定格按钮（标签栏上方）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 104),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ColorCard(
                      picked: picked,
                      onSave: picked == null ? null : _save,
                    ),
                    const SizedBox(height: 16),
                    _ShutterButton(
                      frozen: frozen,
                      onTap: frozen ? _unfreeze : _freeze,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 实时预览（双指硬件缩放）。
  Widget _buildLive(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: DuckColors.accent),
      );
    }
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: _PreviewFill(controller: controller),
    );
  }

  /// Show the captured photo and let a finger drag the sample point over it.
  Widget _buildFrozen() {
    final photo = _frozenFile;
    if (photo == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _movePickPoint(details.localPosition),
      onPanUpdate: (details) => _movePickPoint(details.localPosition),
      onPanEnd: (_) {
        final size = MediaQuery.of(context).size;
        _sampleFrozenAt(
          _pickPoint.value ?? Offset(size.width / 2, size.height / 2),
        );
      },
      child: AnimatedOpacity(
        opacity: _frozenOpacity,
        duration: const Duration(milliseconds: 160),
        child: SizedBox.expand(
          child: Image.file(
            File(photo.path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
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

/// 高斯模糊圆角矩形颜色卡片：左边色块 + 中文名 + 色值，右边保存按钮。
/// iOS 18 风格磨砂：高 sigma 模糊 + 半透明底，透出后面画面。
class _ColorCard extends StatelessWidget {
  const _ColorCard({required this.picked, required this.onSave});

  final PickedColor? picked;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = picked;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: (dark ? const Color(0xFF1C1C1E) : Colors.white)
                .withValues(alpha: dark ? 0.52 : 0.58),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.14 : 0.55),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: p?.color ?? Colors.white24,
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p?.name ?? '取色中…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p == null ? '--' : p.valueFor(state.displayFormat),
                      style: TextStyle(
                        fontSize: 14,
                        color: dark ? Colors.white70 : const Color(0xFF6B7280),
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Menlo', 'Consolas'],
                      ),
                    ),
                  ],
                ),
              ),
              _SaveButton(onTap: onSave),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: DuckColors.saveBlue,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: DuckColors.saveBlue.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                '保存',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 相机按钮：按下定格画面；定格后变成 X 按钮，按下回到实时取色。
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.frozen, required this.onTap});

  final bool frozen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          frozen ? Icons.close_rounded : Icons.photo_camera_rounded,
          color: Colors.black,
          size: 30,
        ),
      ),
    );
  }
}

/// 缩放倍数指示。
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: Colors.black.withValues(alpha: 0.45),
          child: Text(
            '${zoom.toStringAsFixed(1)}×',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

/// 取色点：小圆圈。
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
