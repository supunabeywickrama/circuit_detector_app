import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}


class SettingsProvider with ChangeNotifier {
  bool _enableBlurWarning = true;
  int _maxAngles = 3;
  String _aspectRatio = '4:3';

  bool get enableBlurWarning => _enableBlurWarning;
  int get maxAngles => _maxAngles;
  String get aspectRatio => _aspectRatio;

  void setEnableBlurWarning(bool value) {
    _enableBlurWarning = value;
    notifyListeners();
  }

  void setMaxAngles(int value) {
    if (value >= 1 && value <= 5) {
      _maxAngles = value;
      notifyListeners();
    }
  }

  void setAspectRatio(String value) {
    _aspectRatio = value;
    notifyListeners();
  }

  void clearSettings() {
    _enableBlurWarning = true;
    _maxAngles = 3;
    _aspectRatio = '4:3';
    notifyListeners();
  }
}
