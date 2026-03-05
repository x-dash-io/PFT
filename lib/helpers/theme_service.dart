import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage theme preferences (Light, Dark, System)
class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  
  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  /// Initialize the theme service by loading saved preference
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedTheme = _prefs.getString(_themeKey);
    
    if (savedTheme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == savedTheme,
        orElse: () => ThemeMode.system,
      );
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }
  
  /// Set theme mode and save preference
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_themeKey, mode.toString());
    notifyListeners();
  }
  
  /// Get current theme mode as string
  String getThemeModeString() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System Default';
    }
  }
  
  /// Check if dark mode is currently active
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }
}
