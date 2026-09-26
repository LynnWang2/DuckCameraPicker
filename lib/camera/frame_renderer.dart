import 'dart:typed_data';

import 'package:camera/camera.dart';

/// 定格帧：从图像流 YUV 数据纯 Dart 渲染出的竖屏 RGB，
/// 以及编码后的 24 位 BMP 字节（Image.memory 直接显示，无原生解码）。
class FrozenFrame {
  final Uint8List rgb; // 3 字节/像素，竖屏
  final Uint8List bmp;
  final int width;
  final int height;
  FrozenFrame(this.rgb, this.bmp, this.width, this.height);
}

/// 把一帧 YUV_420_888 转为竖屏 RGB 并编码为 24 位 BMP。
/// 帧若已是竖屏（插件按目标旋转输出）则直接转；若是横向 sensor 方向则
/// 顺时针转 90° 对齐竖屏预览。失败返回 null。
/// 纯 Dart，不调用任何原生接口。
FrozenFrame? renderFrame(CameraImage frame) {
  if (frame.planes.length < 3) return null;
  final w = frame.width, h = frame.height;
  if (w <= 0 || h <= 0) return null;
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;
  final yRow = yPlane.bytesPerRow;
  final uvRow = uPlane.bytesPerRow;
  final uvPx = uPlane.bytesPerPixel ?? 1;
  if (yRow <= 0 || uvRow <= 0) return null;

  // 目标：竖屏。若帧已是竖屏直接转，否则顺时针 90°。
  final portrait = h >= w;
  final dw = portrait ? w : h;
  final dh = portrait ? h : w;
  final rgb = Uint8List(dw * dh * 3);

  var p = 0;
  for (var dy = 0; dy < dh; dy++) {
    for (var dx = 0; dx < dw; dx++) {
      // 顺时针 90°：dest(dx,dy) <- src(sx,sy)，sx = dy，sy = h-1-dx。
      final sx = portrait ? dx : dy;
      final sy = portrait ? dy : (h - 1 - dx);
      final yi = sy * yRow + sx;
      final yv = (yi >= 0 && yi < yBytes.length) ? yBytes[yi] : 0;
      final uvi = (sy ~/ 2) * uvRow + (sx ~/ 2) * uvPx;
      final uv = (uvi >= 0 && uvi < uBytes.length) ? uBytes[uvi] - 128 : 0;
      final vv = (uvi >= 0 && uvi < vBytes.length) ? vBytes[uvi] - 128 : 0;
      // BT.601
      rgb[p++] = (yv + 1.402 * vv).clamp(0, 255).round();
      rgb[p++] = (yv - 0.344136 * uv - 0.714136 * vv).clamp(0, 255).round();
      rgb[p++] = (yv + 1.772 * uv).clamp(0, 255).round();
    }
  }
  final bmp = encodeBmp24(rgb, dw, dh);
  if (bmp == null) return null;
  return FrozenFrame(rgb, bmp, dw, dh);
}

/// 24 位 BMP 编码（BGR，bottom-up，无压缩）。失败返回 null。
Uint8List? encodeBmp24(Uint8List rgb, int w, int h) {
  if (rgb.length < w * h * 3) return null;
  final rowBytes = w * 3;
  final pad = (4 - rowBytes % 4) % 4;
  final stride = rowBytes + pad;
  final dataSize = stride * h;
  final out = Uint8List(54 + dataSize);
  final bd = out.buffer.asByteData();
  bd.setUint8(0, 0x42);
  bd.setUint8(1, 0x4D); // 'BM'
  bd.setUint32(2, 54 + dataSize, Endian.little);
  bd.setUint32(10, 54, Endian.little); // 数据偏移
  bd.setUint32(14, 40, Endian.little); // DIB 头大小
  bd.setInt32(18, w, Endian.little);
  bd.setInt32(22, h, Endian.little); // 正数 = bottom-up
  bd.setUint16(26, 1, Endian.little); // planes
  bd.setUint16(28, 24, Endian.little); // bpp
  bd.setUint32(34, dataSize, Endian.little);
  var p = 54;
  for (var y = h - 1; y >= 0; y--) {
    for (var x = 0; x < w; x++) {
      final s = (y * w + x) * 3;
      out[p++] = rgb[s + 2]; // B
      out[p++] = rgb[s + 1]; // G
      out[p++] = rgb[s]; // R
    }
    p += pad;
  }
  return out;
}
