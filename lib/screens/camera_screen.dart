import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../camera/frame_sampler.dart';
import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// JPEG 解码（跑在后台 isolate，避免阻塞 UI）：解码 + 按 EXIF 摆正，
/// 使采样坐标与 Image.file 的显示方向一致。
img.Image? _decodeJpg(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return null;
  return img.bakeOrientation(decoded);
}

/// 相机取色页（中间标签页）：实时预览 + 中央取色点。
/// - 标签栏上方的相机按钮：按下定格画面，定格后变成 X 按钮，按下回到实时取色
/// - 定格后：画面暂停，取色点可跟随单指拖动，取色结果实时变化；
///   双指缩放定格图（数字变焦，矩阵手势驱动）
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

  // 定格画面：预览常驻底层，定格图在其上交叉淡入——任何时刻都有画面，绝不黑屏。
  bool _frozen = false;
  Uint8List? _frozenBytes;
  double _frozenOpacity = 0.0;
  bool _capturing = false; // 拍照进行中，防止重复点击

  // 定格图全分辨率解码（用于按图像坐标采样）
  img.Image? _frozenDecoded;

  // 定格后取色点位置（屏幕坐标；null = 画面中心）
  final ValueNotifier<Offset?> _pickPoint = ValueNotifier<Offset?>(null);
  DateTime? _lastFrozenSample;

  // 定格图数字变焦矩阵（手势直接驱动，不重建整棵树）
  final ValueNotifier<Matrix4> _frozenMatrix =
      ValueNotifier<Matrix4>(Matrix4.identity());
  Matrix4 _frozenBaseMatrix = Matrix4.identity();

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

  void _stopStream() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    final controller = _controller;
    if (controller == null) return;
    try {
      controller.stopImageStream();
    } catch (_) {}
  }

  void _onBecameActive() {
    final controller = _controller;
    if (controller == null) return;
    try {
      controller.resumePreview();
    } catch (_) {}
    _startStream();
  }

  void _onBecameInactive() {
    _stopStream();
    final controller = _controller;
    if (controller == null) return;
    try {
      controller.pausePreview();
    } catch (_) {}
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

  /// 定格画面：不暂停预览——预览纹理一直在底层渲染；
  /// takePicture() 拿到 bytes 后再把定格图交叉淡入盖在上面。
  /// 任何一步失败（拍照异常、bytes 为空）都留在实时预览，
  /// 绝不出现"预览已拆、定格图未显示"的全黑中间态。
  Future<void> _freeze() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_frozen || _capturing) return;
    _capturing = true;
    // 停掉采样流（拍照更稳），预览纹理继续渲染，做淡入的底。
    _stopStream();
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      try {
        await File(file.path).delete();
      } catch (_) {}
      if (!mounted || bytes.isEmpty) {
        _startStream();
        return;
      }
      _frozenDecoded = null;
      _frozenBaseMatrix = Matrix4.identity();
      _frozenMatrix.value = Matrix4.identity();
      _pickPoint.value = null;
      _lastFrozenSample = null;
      setState(() {
        _frozen = true;
        _frozenBytes = bytes;
        _frozenOpacity = 0.0;
      });
      // 下一帧开始淡入：下面是实时预览，上面是定格图，交叉过渡无黑帧。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _frozen) {
          setState(() => _frozenOpacity = 1.0);
        }
      });
      // 全分辨率解码只用于取色采样，放后台 isolate，不阻塞显示。
      unawaited(_decodeFrozenBytes(bytes));
    } catch (_) {
      // 拍照失败：回到实时预览。
      if (mounted) _startStream();
    } finally {
      _capturing = false;
    }
  }

  Future<void> _decodeFrozenBytes(Uint8List bytes) async {
    try {
      final decoded = await compute(_decodeJpg, bytes);
      if (!mounted || !_frozen) return;
      _frozenDecoded = decoded;
      // 解码完成后按当前取色点位置采一次。
      final size = MediaQuery.of(context).size;
      _sampleFrozenAt(
          _pickPoint.value ?? Offset(size.width / 2, size.height / 2));
    } catch (_) {
      // 解码失败就不支持定格采样，定格图照常显示。
    }
  }

  /// 回到实时取色：预览从未暂停，直接撤掉定格图、重启采样流。
  Future<void> _unfreeze() async {
    if (!_frozen) return;
    _frozen = false;
    _frozenBytes = null;
    _frozenDecoded = null;
    _frozenOpacity = 0.0;
    _pickPoint.value = null;
    _frozenMatrix.value = Matrix4.identity();
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

  // —— 定格后：单指拖动取色点 ——
  void _movePickPoint(Offset localPosition) {
    final size = MediaQuery.of(context).size;
    final p = Offset(
      localPosition.dx.clamp(0.0, size.width),
      localPosition.dy.clamp(0.0, size.height),
    );
    _pickPoint.value = p;
    // 采样节流：拖动时最高约 11Hz，避免频繁 setState。
    final now = DateTime.now();
    if (_lastFrozenSample == null ||
        now.difference(_lastFrozenSample!) >
            const Duration(milliseconds: 90)) {
      _lastFrozenSample = now;
      _sampleFrozenAt(p);
    }
  }

  void _onFrozenPanUpdate(DragUpdateDetails details) {
    _movePickPoint(details.localPosition);
  }

  void _onFrozenPanEnd(DragEndDetails details) {
    // 抬手时按最终位置再采一次，保证准确。
    final p = _pickPoint.value;
    if (p != null) {
      _lastFrozenSample = DateTime.now();
      _sampleFrozenAt(p);
    }
  }

  void _onFrozenTapDown(TapDownDetails details) {
    _lastFrozenSample = DateTime.now();
    _movePickPoint(details.localPosition);
    final p = _pickPoint.value;
    if (p != null) _sampleFrozenAt(p);
  }

  /// 在定格的全分辨率帧上，按取色点的屏幕坐标采样像素颜色。
  void _sampleFrozenAt(Offset point) {
    final decoded = _frozenDecoded;
    if (decoded == null || !mounted) return;
    final iw = decoded.width, ih = decoded.height;
    if (iw == 0 || ih == 0) return;
    final size = MediaQuery.of(context).size;
    // 屏幕坐标 -> 去掉数字变焦矩阵 -> cover 映射到图像坐标。
    final inv = Matrix4.inverted(_frozenMatrix.value);
    final q = inv.transform3(Vector3(point.dx, point.dy, 0));
    final s = math.max(size.width / iw, size.height / ih);
    final ox = (size.width - iw * s) / 2;
    final oy = (size.height - ih * s) / 2;
    final ix = ((q.x - ox) / s).round().clamp(0, iw - 1);
    final iy = ((q.y - oy) / s).round().clamp(0, ih - 1);
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = iy - 2; y <= iy + 2; y++) {
      if (y < 0 || y >= ih) continue;
      for (var x = ix - 2; x <= ix + 2; x++) {
        if (x < 0 || x >= iw) continue;
        final px = decoded.getPixel(x, y);
        r += px.r.toInt();
        g += px.g.toInt();
        b += px.b.toInt();
        n++;
      }
    }
    if (n == 0) return;
    setState(() => _current = SampledPixel(r ~/ n, g ~/ n, b ~/ n));
  }

  // —— 定格图双指缩放：数字变焦，矩阵手势直接驱动 ——
  void _onFrozenScaleStart(ScaleStartDetails details) {
    _frozenBaseMatrix = _frozenMatrix.value.clone();
  }

  void _onFrozenScaleUpdate(ScaleUpdateDetails details) {
    if ((details.scale - 1.0).abs() < 0.002) return;
    final base = _frozenBaseMatrix;
    final baseScale = base.getMaxScaleOnAxis();
    final targetScale = (baseScale * details.scale).clamp(1.0, 5.0);
    final s = targetScale / baseScale;
    final f = details.localFocalPoint;
    final m = Matrix4.identity()
      ..translateByDouble(f.dx, f.dy, 0.0, 1.0)
      ..scaleByDouble(s, s, 1.0, 1.0)
      ..translateByDouble(-f.dx, -f.dy, 0.0, 1.0);
    m.multiply(base);
    _frozenMatrix.value = m;
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
      await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _zoomHideTimer?.cancel();
    _pickPoint.dispose();
    _frozenMatrix.dispose();
    _zoomBadge.dispose();
    _frozenBytes = null;
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
            // 预览常驻底层；定格图在其上交叉淡入——任何时刻都有画面，不黑屏。
            Positioned.fill(
              child: _buildLive(controller),
            ),
            if (frozen && _frozenBytes != null)
              Positioned.fill(
                child: _buildFrozen(),
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
            // 取色点：实时模式固定中央；定格后可拖动
            if (!frozen)
              const Center(child: _PickDot())
            else
              ValueListenableBuilder<Offset?>(
                valueListenable: _pickPoint,
                builder: (context, p, _) {
                  final size = MediaQuery.of(context).size;
                  final c = p ?? Offset(size.width / 2, size.height / 2);
                  return Positioned(
                    left: c.dx - 9,
                    top: c.dy - 9,
                    child: const _PickDot(),
                  );
                },
              ),
            // 缩放倍数指示（只重建徽标本身）
            ValueListenableBuilder<double?>(
              valueListenable: _zoomBadge,
              builder: (context, z, _) {
                if (z == null) return const SizedBox.shrink();
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(child: _ZoomBadge(zoom: z)),
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

  /// 定格画面：Image.memory 直接渲染原始 bytes（Flutter 异步解码，
  /// 不等 image 包），淡入盖在实时预览上；单指拖动取色点，双指数值变焦。
  Widget _buildFrozen() {
    final bytes = _frozenBytes;
    if (bytes == null) return const SizedBox.shrink();
    return GestureDetector(
      onTapDown: _onFrozenTapDown,
      onPanUpdate: _onFrozenPanUpdate,
      onPanEnd: _onFrozenPanEnd,
      onScaleStart: _onFrozenScaleStart,
      onScaleUpdate: _onFrozenScaleUpdate,
      child: AnimatedOpacity(
        opacity: _frozenOpacity,
        duration: const Duration(milliseconds: 160),
        child: ValueListenableBuilder<Matrix4>(
          valueListenable: _frozenMatrix,
          builder: (context, m, child) => Transform(
            transform: m,
            child: child,
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
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
                        color: dark
                            ? Colors.white70
                            : const Color(0xFF6B7280),
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
