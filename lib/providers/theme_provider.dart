import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);

/// App color personalities: a Material 3 seed color that tints the whole app
/// (buttons, switches, cards, nav bar) in both light and dark mode.
enum AppColorTheme {
  violet('Violet (default)', Color(0xFF6750A4)),
  ocean('Ocean', Color(0xFF0277BD)),
  forest('Forest', Color(0xFF2E7D32)),
  rose('Rose', Color(0xFFC2185B)),
  amber('Amber', Color(0xFFF57C00)),
  crimson('Crimson', Color(0xFF990000)), // AO3-ish red
  mono('Mono', Color(0xFF607D8B));

  final String label;
  final Color seed;
  const AppColorTheme(this.label, this.seed);
}

final appColorProvider = StateNotifierProvider<AppColorNotifier, AppColorTheme>(
  (ref) => AppColorNotifier(),
);

class AppColorNotifier extends StateNotifier<AppColorTheme> {
  AppColorNotifier() : super(AppColorTheme.violet) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString('app_color_theme');
    state = AppColorTheme.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AppColorTheme.violet,
    );
  }

  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('app_color_theme', theme.name);
  }
}

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    switch (sp.getString('theme_mode')) {
      case 'dark':
        state = ThemeMode.dark;
        break;
      case 'light':
        state = ThemeMode.light;
        break;
      default:
        // 'system' or unset — follow the device theme.
        state = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final sp = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await sp.setString('theme_mode', raw);
  }
}
