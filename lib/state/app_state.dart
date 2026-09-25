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
  static const int maxHistory = 50;

  List<PickedColor> _history = [];
  ThemeMode _themeMode = ThemeMode.system;
  ColorFormat _displayFormat = ColorFormat.hexWithHash;
  bool _loaded = false;

  List<PickedColor> get history => List.unmodifiable(_history);
  ThemeMode get themeMode => _themeMode;
  ColorFormat get displayFormat => _displayFormat;
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
    _displayFormat = ColorFormat
        .values[prefs.getInt(_kDisplayFormat) ?? ColorFormat.hexWithHash.index];
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kHistory, _history.map((c) => jsonEncode(c.toJson())).toList());
    await prefs.setInt(_kTheme, _themeMode.index);
    await prefs.setInt(_kDisplayFormat, _displayFormat.index);
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
}
