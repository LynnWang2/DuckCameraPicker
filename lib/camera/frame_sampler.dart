import 'package:camera/camera.dart';

/// 采样到的像素。
class SampledPixel {
  const SampledPixel(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

/// 从相机帧的**画面中心**区域采样颜色。
///
/// 之所以固定取中心而不是跟随手指，是为了避开预览旋转 / 前后摄镜像等
/// 坐标映射坑：中心点在任何方向下都是稳定的。交互上用户移动手机对准颜色即可。
class FrameSampler {
  /// 取中心 window×window 区域的平均色（降噪）。
  static SampledPixel? sampleCenter(CameraImage image, {int window = 5}) {
    var r = 0, g = 0, b = 0, n = 0;
    void add(int rr, int gg, int bb) {
      r += rr;
      g += gg;
      b += bb;
      n++;
    }

    final w = image.width, h = image.height;
    final cx = w ~/ 2, cy = h ~/ 2;
    final half = window ~/ 2;
    final group = image.format.group;

    if (group == ImageFormatGroup.bgra8888) {
      // iOS：BGRA8888，单 plane。
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      for (var y = cy - half; y <= cy + half; y++) {
        if (y < 0 || y >= h) continue;
        for (var x = cx - half; x <= cx + half; x++) {
          if (x < 0 || x >= w) continue;
          final i = y * rowStride + x * 4;
          if (i + 2 >= bytes.length) continue;
          add(bytes[i + 2], bytes[i + 1], bytes[i]);
        }
      }
    } else if (group == ImageFormatGroup.yuv420) {
      // Android：YUV_420_888，Y/U/V 三个 plane。
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;
      final yRowStride = yPlane.bytesPerRow;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;
      for (var y = cy - half; y <= cy + half; y++) {
        if (y < 0 || y >= h) continue;
        for (var x = cx - half; x <= cx + half; x++) {
          if (x < 0 || x >= w) continue;
          final yi = y * yRowStride + x;
          if (yi >= yBytes.length) continue;
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          if (uvIndex >= uBytes.length || uvIndex >= vBytes.length) continue;
          final yv = yBytes[yi].toDouble();
          final uv = uBytes[uvIndex] - 128;
          final vv = vBytes[uvIndex] - 128;
          // BT.601
          final rr = (yv + 1.402 * vv).clamp(0, 255).round();
          final gg = (yv - 0.344136 * uv - 0.714136 * vv).clamp(0, 255).round();
          final bb = (yv + 1.772 * uv).clamp(0, 255).round();
          add(rr, gg, bb);
        }
      }
    } else {
      return null;
    }

    if (n == 0) return null;
    return SampledPixel(r ~/ n, g ~/ n, b ~/ n);
  }

  /// 取中心 size×size 的像素网格，用于放大镜显示。
  static List<List<SampledPixel>> sampleCenterGrid(
    CameraImage image, {
    int size = 15,
  }) {
    final w = image.width, h = image.height;
    final cx = w ~/ 2, cy = h ~/ 2;
    final half = size ~/ 2;
    final group = image.format.group;

    SampledPixel pixelAt(int x, int y) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      if (group == ImageFormatGroup.bgra8888) {
        final plane = image.planes[0];
        final bytes = plane.bytes;
        final rowStride = plane.bytesPerRow;
        final i = y * rowStride + x * 4;
        if (i + 2 >= bytes.length) return const SampledPixel(0, 0, 0);
        return SampledPixel(bytes[i + 2], bytes[i + 1], bytes[i]);
      } else if (group == ImageFormatGroup.yuv420) {
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];
        final yi = y * (yPlane.bytesPerRow) + x;
        final yBytes = yPlane.bytes;
        if (yi >= yBytes.length) return const SampledPixel(0, 0, 0);
        final uvIndex = (y ~/ 2) * (uPlane.bytesPerRow) +
            (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);
        final uBytes = uPlane.bytes, vBytes = vPlane.bytes;
        if (uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
          return const SampledPixel(0, 0, 0);
        }
        final yv = yBytes[yi].toDouble();
        final uv = uBytes[uvIndex] - 128;
        final vv = vBytes[uvIndex] - 128;
        return SampledPixel(
          (yv + 1.402 * vv).clamp(0, 255).round(),
          (yv - 0.344136 * uv - 0.714136 * vv).clamp(0, 255).round(),
          (yv + 1.772 * uv).clamp(0, 255).round(),
        );
      }
      return const SampledPixel(0, 0, 0);
    }

    return List.generate(
      size,
      (dy) =>
          List.generate(size, (dx) => pixelAt(cx - half + dx, cy - half + dy)),
    );
  }
}
