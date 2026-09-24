import 'package:flutter/material.dart';

/// 色值格式，与桌面端取色鸭的格式开关保持一致。
enum ColorFormat {
  hex('HEX', '不含 #'),
  hexWithHash('HEX', '含 #'),
  rgb('RGB', ''),
  hsl('HSL', ''),
  cmyk('CMYK', '');

  const ColorFormat(this.label, this.hint);
  final String label;
  final String hint;

  String get displayLabel => this == ColorFormat.hexWithHash ? 'HEX#' : label;
}

/// 一次取色结果。命名与色值算法直接移植自桌面端取色鸭（Rust 实现），
/// 保证同一颜色在两端显示相同的中文名与色值字符串。
class PickedColor {
  PickedColor({
    required this.id,
    required this.r,
    required this.g,
    required this.b,
    required this.name,
    required this.createdAt,
  });

  factory PickedColor.now(int r, int g, int b) => PickedColor(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        r: r,
        g: g,
        b: b,
        name: colorName(r, g, b),
        createdAt: DateTime.now(),
      );

  final String id;
  final int r;
  final int g;
  final int b;
  final String name;
  final DateTime createdAt;

  Color get color => Color.fromARGB(255, r, g, b);

  String get hexNoHash => '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();

  String get hexWithHash => '#$hexNoHash';

  String get rgb => 'rgb($r, $g, $b)';
  String get hsl => toHsl(r, g, b);
  String get cmyk => toCmyk(r, g, b);

  /// 取色后复制的文本，按用户设置的格式输出。
  String valueFor(ColorFormat format) {
    switch (format) {
      case ColorFormat.hex:
        return hexNoHash; // 不含 #
      case ColorFormat.hexWithHash:
        return hexWithHash; // 含 #
      case ColorFormat.rgb:
        return rgb;
      case ColorFormat.hsl:
        return hsl;
      case ColorFormat.cmyk:
        return cmyk;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'r': r,
        'g': g,
        'b': b,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PickedColor.fromJson(Map<String, dynamic> json) => PickedColor(
        id: json['id'] as String,
        r: json['r'] as int,
        g: json['g'] as int,
        b: json['b'] as int,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 中文颜色名，移植自桌面端 `color_name`（src-tauri/src/lib.rs）。
String colorName(int r, int g, int b) {
  final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final delta = mx - mn;
  final light = (mx + mn) ~/ 2;
  if (mx < 25) return '黑色';
  if (delta < 8) {
    if (mn > 242) return '白色';
    if (light < 65) return '深灰色';
    if (light < 155) return '灰色';
    if (light < 220) return '浅灰色';
    return '近白色';
  }
  final saturation = delta / mx;
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final d = (mx - mn) / 255.0;
  double hue;
  if (mx == r) {
    hue = 60.0 * (((gf - bf) / d) % 6.0);
  } else if (mx == g) {
    hue = 60.0 * ((bf - rf) / d + 2.0);
  } else {
    hue = 60.0 * ((rf - gf) / d + 4.0);
  }
  if (hue < 0) hue += 360.0;

  if (light >= 200 && delta >= 8) {
    if (hue >= 315.0 && hue <= 340.0) return '浅粉色';
    if (hue > 340.0 || hue <= 10.0) return '粉红色';
    if (hue >= 35.0 && hue <= 78.0) return '浅黄色';
    if (hue >= 79.0 && hue <= 180.0) return '浅绿色';
    if (hue >= 181.0 && hue <= 250.0) {
      return saturation < 0.12 ? '浅灰蓝色' : '浅蓝色';
    }
    if (hue >= 251.0 && hue <= 315.0) {
      return saturation < 0.12 ? '浅灰紫色' : '淡紫色';
    }
    if (hue > 11.0 && hue < 35.0) return '浅橙色';
  }
  if (mn > 242) return '白色';
  if (delta < 10) {
    if (light < 65) return '深灰色';
    if (light < 155) return '灰色';
    if (light < 220) return '浅灰色';
    return '近白色';
  }
  if (saturation < 0.35) {
    if (hue >= 190.0 && hue <= 260.0) return '灰蓝色';
    if (hue >= 35.0 && hue <= 75.0) return '灰黄色';
    if (saturation < 0.14) {
      if (light < 80) return '深灰色';
      if (light > 210) return '浅灰色';
      return '灰色';
    }
  }
  if (hue >= 12.0 && hue <= 48.0 && light < 145 && r < 190 && r > g && g >= b) {
    return light < 70 ? '深棕色' : '棕色';
  }
  if (light < 70) {
    final h = hue.toInt();
    if (h >= 15 && h <= 55) return '深棕色';
    if (h >= 56 && h <= 175) return '深绿色';
    if (h >= 176 && h <= 260) return '深蓝色';
    if (h >= 261 && h <= 335) return '深紫色';
    return '深红色';
  }
  final h = hue.toInt();
  if ((h >= 0 && h <= 10) || (h >= 350 && h <= 359)) {
    return light > 200 ? '浅红色' : '红色';
  }
  if (h >= 11 && h <= 24) return '橘红色';
  if (h >= 25 && h <= 44) return light > 190 ? '浅橙色' : '橙色';
  if (h >= 45 && h <= 69) return light > 205 ? '浅黄色' : '黄色';
  if (h >= 70 && h <= 94) return '黄绿色';
  if (h >= 95 && h <= 154) return light > 195 ? '浅绿色' : '绿色';
  if (h >= 155 && h <= 184) return '青绿色';
  if (h >= 185 && h <= 204) return '青色';
  if (h >= 205 && h <= 249) return light > 190 ? '浅蓝色' : '蓝色';
  if (h >= 250 && h <= 274) return '蓝紫色';
  if (h >= 275 && h <= 314) return light > 195 ? '浅紫色' : '紫色';
  if (h >= 315 && h <= 339) return light > 200 ? '浅粉色' : '粉色';
  return '玫红色';
}

/// HSL 字符串，移植自桌面端 `hsl`。
String toHsl(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final mx = rf > gf ? (rf > bf ? rf : bf) : (gf > bf ? gf : bf);
  final mn = rf < gf ? (rf < bf ? rf : bf) : (gf < bf ? gf : bf);
  final l = (mx + mn) / 2.0;
  double h = 0.0, s = 0.0;
  if ((mx - mn).abs() > 1e-9) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
    double hh;
    if ((mx - rf).abs() < 1e-9) {
      hh = (gf - bf) / d + (gf < bf ? 6.0 : 0.0);
    } else if ((mx - gf).abs() < 1e-9) {
      hh = (bf - rf) / d + 2.0;
    } else {
      hh = (rf - gf) / d + 4.0;
    }
    h = hh / 6.0;
  }
  h *= 360.0;
  return 'hsl(${h.round()}, ${(s * 100).round()}%, ${(l * 100).round()}%)';
}

/// CMYK 字符串，移植自桌面端 `cmyk`。
String toCmyk(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final mx = rf > gf ? (rf > bf ? rf : bf) : (gf > bf ? gf : bf);
  final k = 1.0 - mx;
  double c = 0, m = 0, y = 0;
  if (k < 0.9999) {
    c = (1.0 - rf - k) / (1.0 - k);
    m = (1.0 - gf - k) / (1.0 - k);
    y = (1.0 - bf - k) / (1.0 - k);
  }
  return 'cmyk(${(c * 100).round()}%, ${(m * 100).round()}%, '
      '${(y * 100).round()}%, ${(k * 100).round()}%)';
}
