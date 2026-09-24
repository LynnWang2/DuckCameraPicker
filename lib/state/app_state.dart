import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/picked_color.dart';

/// 全局状态：取色历史、主题、格式开关、复制格式。
/// 历史与设置通过 SharedPreferences 持久化。
class AppState extends ChangeNotifier {
  static const _kHistory = 'duck.history.v1';
  static const _kTheme = 'duck.theme.v1';
  static const _kFormats = 'duck.formats.v1';
  static const _kCopyFormat = 'duck.copyFormat.v1';
  static const int maxHistory = 50;

  List<PickedColor> _history = [];
  ThemeMode _themeMode = ThemeMode.system;
  Set<ColorFormat> _formats = {...ColorFormat.values};
  ColorFormat _copyFormat = ColorFormat.hex;
  bool _loaded = false;

  List<PickedColor> get history => List.unmodifiable(_history);
  ThemeMode get themeMode => _themeMode;
  Set<ColorFormat> get formats => Set.unmodifiable(_formats);
  ColorFormat get copyFormat => _copyFormat;
  bool get loaded => _loaded;

  bool get allFormatsOff => _formats.isEmpty;

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
    final rawFormats = prefs.getStringList(_kFormats);
    if (rawFormats != null) {
      _formats = rawFormats
          .map((s) => ColorFormat.values
              .firstWhere((f) => f.name == s, orElse: () => ColorFormat.hex))
          .toSet();
    }
    _copyFormat = ColorFormat.values[prefs.getInt(_kCopyFormat) ?? 0];
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kHistory, _history.map((c) => jsonEncode(c.toJson())).toList());
    await prefs.setInt(_kTheme, _themeMode.index);
    await prefs.setStringList(_kFormats, _formats.map((f) => f.name).toList());
    await prefs.setInt(_kCopyFormat, _copyFormat.index);
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

  void toggleFormat(ColorFormat format) {
    if (_formats.contains(format)) {
      _formats.remove(format);
    } else {
      _formats.add(format);
    }
    _persist();
    notifyListeners();
  }

  void setCopyFormat(ColorFormat format) {
    _copyFormat = format;
    _persist();
    notifyListeners();
  }
}
