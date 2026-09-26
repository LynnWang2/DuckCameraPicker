import 'dart:typed_data';

import 'package:camera/camera.dart';

/// A standalone bitmap rendered from one camera stream frame.
class FrozenFrame {
  const FrozenFrame({
    required this.rgb,
    required this.bmp,
    required this.width,
    required this.height,
  });

  /// Packed RGB bytes in the displayed portrait orientation.
  final Uint8List rgb;
  final Uint8List bmp;
  final int width;
  final int height;
}

/// Copies a CameraImage into isolate-safe values before the camera stream stops.
Map<String, Object> copyCameraFrame(CameraImage frame) => {
      'format': frame.format.group.name,
      'width': frame.width,
      'height': frame.height,
      'planes': frame.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList(),
      'rowStrides': frame.planes.map((plane) => plane.bytesPerRow).toList(),
      'pixelStrides':
          frame.planes.map((plane) => plane.bytesPerPixel ?? 1).toList(),
    };

/// Renders a copied camera frame into RGB pixels and a BMP on a worker isolate.
/// The camera preview and camera session are never captured or reconfigured.
FrozenFrame? renderCameraFrame(Map<String, Object> data) {
  final width = data['width']! as int;
  final height = data['height']! as int;
  final format = data['format']! as String;
  final planes = (data['planes']! as List).cast<Uint8List>();
  final rowStrides = (data['rowStrides']! as List).cast<int>();
  final pixelStrides = (data['pixelStrides']! as List).cast<int>();
  if (width <= 0 || height <= 0 || planes.isEmpty) return null;

  final portrait = height >= width;
  final outputWidth = portrait ? width : height;
  final outputHeight = portrait ? height : width;
  final rgb = Uint8List(outputWidth * outputHeight * 3);
  final plane0 = planes[0];
  final row0 = rowStrides[0];
  if (row0 <= 0) return null;

  var out = 0;
  for (var dy = 0; dy < outputHeight; dy++) {
    for (var dx = 0; dx < outputWidth; dx++) {
      // Rotate landscape sensor frames clockwise to match the portrait preview.
      final sx = portrait ? dx : dy;
      final sy = portrait ? dy : height - 1 - dx;
      int r;
      int g;
      int b;

      if (format == 'yuv420' && planes.length >= 3) {
        final yIndex = sy * row0 + sx;
        final uIndex = (sy ~/ 2) * rowStrides[1] +
            (sx ~/ 2) * pixelStrides[1];
        final vIndex = (sy ~/ 2) * rowStrides[2] +
            (sx ~/ 2) * pixelStrides[2];
        if (yIndex >= plane0.length ||
            uIndex >= planes[1].length ||
            vIndex >= planes[2].length) {
          return null;
        }
        final y = plane0[yIndex].toDouble();
        final u = planes[1][uIndex] - 128;
        final v = planes[2][vIndex] - 128;
        r = (y + 1.402 * v).round().clamp(0, 255);
        g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
        b = (y + 1.772 * u).round().clamp(0, 255);
      } else if (format == 'bgra8888') {
        final pixelStride = pixelStrides[0];
        final index = sy * row0 + sx * pixelStride;
        if (index + 2 >= plane0.length) return null;
        b = plane0[index];
        g = plane0[index + 1];
        r = plane0[index + 2];
      } else {
        return null;
      }

      rgb[out++] = r;
      rgb[out++] = g;
      rgb[out++] = b;
    }
  }

  final bmp = encodeBmp24(rgb, outputWidth, outputHeight);
  if (bmp == null) return null;
  return FrozenFrame(
    rgb: rgb,
    bmp: bmp,
    width: outputWidth,
    height: outputHeight,
  );
}

/// Encodes packed RGB bytes as an uncompressed, 24-bit BMP.
Uint8List? encodeBmp24(Uint8List rgb, int width, int height) {
  if (width <= 0 || height <= 0 || rgb.length < width * height * 3) {
    return null;
  }
  final rowBytes = width * 3;
  final padding = (4 - rowBytes % 4) % 4;
  final stride = rowBytes + padding;
  final imageBytes = stride * height;
  final output = Uint8List(54 + imageBytes);
  final header = output.buffer.asByteData();
  header.setUint8(0, 0x42);
  header.setUint8(1, 0x4d);
  header.setUint32(2, 54 + imageBytes, Endian.little);
  header.setUint32(10, 54, Endian.little);
  header.setUint32(14, 40, Endian.little);
  header.setInt32(18, width, Endian.little);
  header.setInt32(22, height, Endian.little);
  header.setUint16(26, 1, Endian.little);
  header.setUint16(28, 24, Endian.little);
  header.setUint32(34, imageBytes, Endian.little);

  var offset = 54;
  for (var y = height - 1; y >= 0; y--) {
    for (var x = 0; x < width; x++) {
      final source = (y * width + x) * 3;
      output[offset++] = rgb[source + 2];
      output[offset++] = rgb[source + 1];
      output[offset++] = rgb[source];
    }
    offset += padding;
  }
  return output;
}
