import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../camera/frame_renderer.dart';
import '../camera/frame_sampler.dart';
import '../models/picked_color.dart';
import '../state/app_state.dart';
import '../theme/duck_theme.dart';

/// 相机取色页（中间标签页）：实时预览 + 中央取色点。
/// - 标签栏上方的相机按钮：按下定格画面，定格后变成 X 按钮，按下回到实时取色
/// - 定格原理（三级防护，见 _freeze）：
///   1. 优先截取当前预览帧（RepaintBoundary.toImage），不碰相机、无闪屏；
///   2. 若截图全黑（部分机型抓不到 Texture），兜底走 takePicture 拍照；
///      imageCapture 在初始化时已随 preview 一起绑定，takePicture 内部的
///      bindToLifecycle 会直接 early return，不会解绑预览（已用插件源码验证）；
///   3. 任何一步失败都留在实时预览并提示，绝不显示黑图、绝不卡死
/// - 定格后：取色点可跟随单指拖动，取色结果实时变化；
///   双指缩放定格图（数字变焦，矩阵手势驱动）
/// - 定格后：取色点可跟随单指拖动，取色结果实时变化；
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

class _CameraPageState extends State<CameraPage> {  CameraController? _controller;
  CameraImage? _latestFrame;
  Timer? _sampleTimer;
  SampledPixel? _current;
  String? _error;
  bool _flashOn = false;

  // 定格画面：从图像流 YUV 帧纯 Dart 渲染（不调用截图/拍照原生接口，
  // 不碰任何相机用例，所以不会黑屏、不会卡死）。显示用 Image.memory(BMP)，
  // 取色直接读 RGB 像素。
  bool _frozen = false;
  FrozenFrame? _frozenFrame;
  double _frozenOpacity = 0.0;
  bool _capturing = false; // 定格进行中，防止重复点击

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

  /// 定格画面：从图像流取一帧 YUV 数据（与实时取色同源，已知良好），
  /// 纯 Dart 转 RGB 并对齐竖屏，编码为 BMP 显示。
  /// 全程不调用 toImage / takePicture 等原生接口，不碰任何相机用例，
  /// 所以不会黑屏、不会卡死。任何失败都留在实时预览并 toast。
  Future<void> _freeze() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_frozen || _capturing) return;
    final frame = _latestFrame;
    if (frame == null || frame.format.group != ImageFormatGroup.yuv420) {
      _toast('相机未就绪，请稍候再试');
      return;
    }
    _capturing = true;
    // 只停采样流（clearAnalyzer），预览用例保持绑定、一直渲染。
    _stopStream();
    try {
      final rendered = renderFrame(frame);
      if (mounted && rendered != null) {
        _presentFrozen(rendered);
      } else {
        if (mounted) _toast('定格失败，请重试');
        _startStream();
      }
    } catch (_) {
      if (mounted) {
        _toast('定格失败，请重试');
        _startStream();
      }
    } finally {
      _capturing = false;
    }
  }

  /// 显示定格图：淡入 + 中心采样。调用前已保证 mounted。
  void _presentFrozen(FrozenFrame frame) {
    if (!mounted) return;
    _frozenFrame = frame;
    _frozenBaseMatrix = Matrix4.identity();
    _frozenMatrix.value = Matrix4.identity();
    _pickPoint.value = null;
    _lastFrozenSample = null;
    setState(() {
      _frozen = true;
      _frozenOpacity = 0.0;
    });
    // 下一帧开始淡入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _frozen) {
        setState(() => _frozenOpacity = 1.0);
      }
    });
    // 定格瞬间按中心点采一次。
    final size = MediaQuery.of(context).size;
    _sampleFrozenAt(Offset(size.width / 2, size.height / 2));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 回到实时取色：预览从未动过，直接释放定格图、重启采样流。
  Future<void> _unfreeze() async {
    if (!_frozen) return;
    _frozen = false;
    _frozenFrame = null;
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

  /// 在定格帧的 RGB 像素上，按取色点的屏幕坐标采样颜色。
  /// 先去掉数字变焦矩阵，再按 BoxFit.cover 映射到定格图像素。
  void _sampleFrozenAt(Offset point) {
    final frame = _frozenFrame;
    if (frame == null || !mounted) return;
    final bytes = frame.rgb;
    final w = frame.width, h = frame.height;
    if (w == 0 || h == 0) return;
    // 先去掉数字变焦矩阵，再映射到定格图像素（cover）。
    final inv = Matrix4.inverted(_frozenMatrix.value);
    final s = inv.transform3(Vector3(point.dx, point.dy, 0));
    final size = MediaQuery.of(context).size;
    final scale = math.max(size.width / w, size.height / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    final cx = ((s.x - ox) / scale).round().clamp(0, w - 1);
    final cy = ((s.y - oy) / scale).round().clamp(0, h - 1);
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = cy - 2; y <= cy + 2; y++) {
      if (y < 0 || y >= h) continue;
      for (var x = cx - 2; x <= cx + 2; x++) {
        if (x < 0 || x >= w) continue;
        final o = (y * w + x) * 3;
        if (o + 2 >= bytes.length) continue;
        r += bytes[o];
        g += bytes[o + 1];
        b += bytes[o + 2];
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
    _frozenFrame = null;
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
            // 预览常驻底层；定格图是同一帧 YUV 数据渲染的 BMP，
            // 在其上淡入——预览用例全程不被动过，绝不黑屏。
            Positioned.fill(
              child: _buildLive(controller),
            ),
            if (frozen && _frozenFrame != null)
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

  /// 定格画面：Image.memory 显示 BMP（纯 Dart 渲染+编码，无原生解码），
  /// 淡入盖在实时预览上；单指拖动取色点，双指数值变焦。
  /// 显示的就是取色用的同一帧，位置完全对齐。
  Widget _buildFrozen() {
    final frame = _frozenFrame;
    if (frame == null) return const SizedBox.shrink();
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
          child: SizedBox.expand(
            child: Image.memory(
              frame.bmp,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
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
