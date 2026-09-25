import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/picked_color.dart';

/// 全局状态：取色历史、主题、显示格式（单选）。
/// 历史与设置通过 SharedPreferences 持久化。
class AppState extends ChangeNotifier {
  static const _kHistory = 'duck.history.v1';
  static const _kTheme = 'duck.theme.v1';
  static const _kDisplayFormat = 'duck.displayFormat.v1';
  static const _kStripHashOnCopy = 'duck.stripHashOnCopy.v1';
  static const int maxHistory = 50;

  List<PickedColor> _history = [];
  ThemeMode _themeMode = ThemeMode.system;
  ColorFormat _displayFormat = ColorFormat.hex;
  bool _stripHashOnCopy = false;
  bool _loaded = false;

  List<PickedColor> get history => List.unmodifiable(_history);
  ThemeMode get themeMode => _themeMode;
  ColorFormat get displayFormat => _displayFormat;

  /// 复制 HEX 时去掉 #（只影响复制，不影响显示）。
  bool get stripHashOnCopy => _stripHashOnCopy;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getStringList(_kHistory);
    if (rawHistory != null) {
      _history = rawHistory
          .map((s) => PickedColor.fromJson(
              Map<String, dynamic>.from(jsonDecode(s) as Map)))
          .toList();
    }
    _themeMode = ThemeMode.values[prefs.getInt(_kTheme) ?? 0];
    _displayFormat = _migrateDisplayFormat(prefs.getInt(_kDisplayFormat));
    _stripHashOnCopy = prefs.getBool(_kStripHashOnCopy) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// 旧版索引迁移：0=HEX不含#，1=HEX含#，2=RGB，3=HSL，4=CMYK
  /// → 新版：0=HEX，1=RGB，2=HSL，3=CMYK。
  static ColorFormat _migrateDisplayFormat(int? raw) {
    switch (raw) {
      case 0:
      case 1:
        return ColorFormat.hex;
      case 2:
        return ColorFormat.rgb;
      case 3:
        return ColorFormat.hsl;
      case 4:
        return ColorFormat.cmyk;
      default:
        return ColorFormat.hex;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kHistory, _history.map((c) => jsonEncode(c.toJson())).toList());
    await prefs.setInt(_kTheme, _themeMode.index);
    await prefs.setInt(_kDisplayFormat, _displayFormat.index);
    await prefs.setBool(_kStripHashOnCopy, _stripHashOnCopy);
  }

  void addColor(PickedColor color) {
    _history.insert(0, color);
    if (_history.length > maxHistory) {
      _history = _history.sublist(0, maxHistory);
    }
    _persist();
    notifyListeners();
  }

  void removeColor(String id) {
    _history.removeWhere((c) => c.id == id);
    _persist();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _persist();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _persist();
    notifyListeners();
  }

  void setDisplayFormat(ColorFormat format) {
    _displayFormat = format;
    _persist();
    notifyListeners();
  }

  void setStripHashOnCopy(bool value) {
    _stripHashOnCopy = value;
    _persist();
    notifyListeners();
  }
}
