import 'package:duck_camera_picker/models/picked_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('色值格式', () {
    final red = PickedColor.now(255, 0, 0);
    final black = PickedColor.now(0, 0, 0);
    final white = PickedColor.now(255, 255, 255);
    final gray = PickedColor.now(128, 128, 128);

    test('HEX 大写补零', () {
      expect(red.hexNoHash, 'FF0000');
      expect(black.hexNoHash, '000000');
      expect(white.hexNoHash, 'FFFFFF');
      expect(PickedColor.now(1, 2, 3).hexNoHash, '010203');
    });

    test('HEX# 带井号', () {
      expect(red.hexWithHash, '#FF0000');
      expect(gray.hexWithHash, '#808080');
    });

    test('RGB', () {
      expect(red.rgb, 'rgb(255, 0, 0)');
      expect(gray.rgb, 'rgb(128, 128, 128)');
    });

    test('HSL', () {
      expect(red.hsl, 'hsl(0, 100%, 50%)');
      expect(black.hsl, 'hsl(0, 0%, 0%)');
      expect(white.hsl, 'hsl(0, 0%, 100%)');
      expect(PickedColor.now(255, 255, 0).hsl, 'hsl(60, 100%, 50%)');
      expect(PickedColor.now(0, 0, 255).hsl, 'hsl(240, 100%, 50%)');
    });

    test('CMYK', () {
      expect(red.cmyk, 'cmyk(0%, 100%, 100%, 0%)');
      expect(black.cmyk, 'cmyk(0%, 0%, 0%, 100%)');
      expect(white.cmyk, 'cmyk(0%, 0%, 0%, 0%)');
      expect(gray.cmyk, 'cmyk(0%, 0%, 0%, 50%)');
    });

    test('valueFor 按设置输出对应格式（HEX 统一含 #）', () {
      expect(red.valueFor(ColorFormat.hex), '#FF0000');
      expect(red.valueFor(ColorFormat.rgb), 'rgb(255, 0, 0)');
      expect(red.valueFor(ColorFormat.hsl), 'hsl(0, 100%, 50%)');
      expect(red.valueFor(ColorFormat.cmyk), 'cmyk(0%, 100%, 100%, 0%)');
    });

    test('valueForCopy：复制HEX去掉# 只影响复制', () {
      expect(
          red.valueForCopy(ColorFormat.hex, stripHash: false), '#FF0000');
      expect(red.valueForCopy(ColorFormat.hex, stripHash: true), 'FF0000');
      expect(red.valueForCopy(ColorFormat.rgb, stripHash: true),
          'rgb(255, 0, 0)');
    });
  });

  group('中文颜色命名（与桌面端一致）', () {
    test('黑白灰', () {
      expect(colorName(0, 0, 0), '黑色');
      expect(colorName(10, 10, 10), '黑色');
      expect(colorName(255, 255, 255), '白色');
      expect(colorName(128, 128, 128), '灰色');
      expect(colorName(40, 40, 40), '深灰色');
      expect(colorName(200, 200, 200), '浅灰色');
    });

    test('三原色', () {
      expect(colorName(255, 0, 0), '红色');
      expect(colorName(0, 255, 0), '绿色');
      expect(colorName(0, 0, 255), '蓝色');
    });

    test('常见色', () {
      expect(colorName(255, 255, 0), '黄色');
      expect(colorName(255, 165, 0), '橙色');
      expect(colorName(255, 0, 255), '紫色');
      expect(colorName(0, 255, 255), '青绿色');
      expect(colorName(139, 69, 19), '棕色');
      expect(colorName(0, 128, 0), '深绿色');
    });
  });

  group('序列化', () {
    test('toJson/fromJson 往返', () {
      final c = PickedColor.now(12, 34, 56);
      final restored = PickedColor.fromJson(c.toJson());
      expect(restored.id, c.id);
      expect(restored.r, 12);
      expect(restored.g, 34);
      expect(restored.b, 56);
      expect(restored.name, c.name);
      expect(
        restored.createdAt.toIso8601String(),
        c.createdAt.toIso8601String(),
      );
    });
  });
}
