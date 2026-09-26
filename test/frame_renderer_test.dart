import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:duck_camera_picker/camera/frame_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

CameraImage makeYuv420(int w, int h, int y, int u, int v) {
  final yBytes = Uint8List(w * h)..fillRange(0, w * h, y);
  final uvW = (w / 2).ceil(), uvH = (h / 2).ceil();
  final uBytes = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, u);
  final vBytes = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, v);
  final data = CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
    planes: [
      CameraImagePlane(bytes: yBytes, bytesPerRow: w),
      CameraImagePlane(bytes: uBytes, bytesPerRow: uvW, bytesPerPixel: 1),
      CameraImagePlane(bytes: vBytes, bytesPerRow: uvW, bytesPerPixel: 1),
    ],
    width: w,
    height: h,
  );
  return CameraImage.fromPlatformInterface(data);
}

void main() {
  test('横向帧顺时针转 90° 变竖屏', () {
    final f = renderFrame(makeYuv420(4, 2, 235, 128, 128));
    expect(f, isNotNull);
    expect(f!.width, 2);
    expect(f.height, 4);
    expect(f.rgb.length, 2 * 4 * 3);
  });

  test('竖屏帧不旋转', () {
    final f = renderFrame(makeYuv420(2, 4, 235, 128, 128));
    expect(f, isNotNull);
    expect(f!.width, 2);
    expect(f.height, 4);
  });

  test('YUV 白色转出白色 RGB', () {
    final f = renderFrame(makeYuv420(4, 4, 235, 128, 128))!;
    // 全白帧：每个像素都应接近 235
    for (var i = 0; i < f.rgb.length; i++) {
      expect(f.rgb[i], closeTo(235, 2));
    }
  });

  test('YUV 红色转出红色 RGB', () {
    // BT.601 下 (255,0,0) ≈ Y=76 U=85 V=255
    final f = renderFrame(makeYuv420(4, 4, 76, 85, 255))!;
    expect(f.rgb[0], closeTo(254, 3)); // R
    expect(f.rgb[1], closeTo(0, 3)); // G
    expect(f.rgb[2], closeTo(0, 3)); // B
  });

  test('顺时针旋转方向：横向左黑右白 → 竖屏上黑下白', () {
    // 4x2：x=0,1 黑，x=2,3 白
    final w = 4, h = 2;
    final yBytes = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        yBytes[y * w + x] = x < 2 ? 0 : 235;
      }
    }
    final data = CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      planes: [
        CameraImagePlane(bytes: yBytes, bytesPerRow: w),
        CameraImagePlane(
            bytes: Uint8List(2)..fillRange(0, 2, 128),
            bytesPerRow: 2,
            bytesPerPixel: 1),
        CameraImagePlane(
            bytes: Uint8List(2)..fillRange(0, 2, 128),
            bytesPerRow: 2,
            bytesPerPixel: 1),
      ],
      width: w,
      height: h,
    );
    final f = renderFrame(CameraImage.fromPlatformInterface(data))!;
    expect(f.width, 2);
    expect(f.height, 4);
    // 顶行应为黑（原左侧），底行应为白（原右侧）
    expect(f.rgb[0], closeTo(0, 2));
    final lastRow = (f.height - 1) * f.width * 3;
    expect(f.rgb[lastRow], closeTo(235, 2));
  });

  test('BMP 头正确且可被系统解码', () async {
    final f = renderFrame(makeYuv420(6, 4, 100, 128, 128))!;
    final bmp = f.bmp;
    expect(bmp[0], 0x42);
    expect(bmp[1], 0x4D); // 'BM'
    final bd = bmp.buffer.asByteData();
    expect(bd.getInt32(18, Endian.little), f.width);
    expect(bd.getInt32(22, Endian.little), f.height);
    expect(bd.getUint16(28, Endian.little), 24);
    // 系统能解码
    final codec = await ui.instantiateImageCodec(bmp);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, f.width);
    expect(frame.image.height, f.height);
    frame.image.dispose();
  });

  test('BMP 行填充：奇数宽度', () async {
    // 直接测 encodeBmp24 奇宽：宽度 3 → 每行 9 字节 + 3 填充 = 12
    final rgb = Uint8List(3 * 5 * 3)..fillRange(0, 3 * 5 * 3, 200);
    final bmp = encodeBmp24(rgb, 3, 5)!;
    final codec = await ui.instantiateImageCodec(bmp);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 3);
    expect(frame.image.height, 5);
    // 像素值应对上
    final bd = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bd, isNotNull);
    frame.image.dispose();
  });
}
