import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeedKey = 'theme_seed_color';
const _kThemeModeKey = 'theme_mode';
const _kDefaultSeed = Color(0xFF6750A4);

final _prefsProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

class ThemeState {
  const ThemeState({
    this.seedColor = _kDefaultSeed,
    this.themeMode = ThemeMode.system,
  });
  final Color seedColor;
  final ThemeMode themeMode;

  ThemeData get light => _buildTheme(Brightness.light, seedColor);
  ThemeData get dark => _buildTheme(Brightness.dark, seedColor);

  static ThemeData _buildTheme(Brightness brightness, Color seed) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
    );
  }

  ThemeState copyWith({
    Color? seedColor,
    ThemeMode? themeMode,
  }) =>
      ThemeState(
        seedColor: seedColor ?? this.seedColor,
        themeMode: themeMode ?? this.themeMode,
      );
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    ref.listen(_prefsProvider, (_, next) {
      next.whenData((prefs) {
        final seedValue = prefs.getInt(_kSeedKey);
        final themeModeValue = prefs.getString(_kThemeModeKey);
        state = state.copyWith(
          seedColor: seedValue != null ? Color(seedValue) : state.seedColor,
          themeMode: _themeModeFromStorage(themeModeValue),
        );
      });
    });
    return const ThemeState();
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedKey, color.toARGB32());
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    state = state.copyWith(themeMode: themeMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, themeMode.name);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeState>(
  ThemeNotifier.new,
);

// Preset accent colors
const List<({String label, Color color})> kAccentPresets = [
  (label: '默认紫', color: Color(0xFF6750A4)),
  (label: '深海蓝', color: Color(0xFF0061A4)),
  (label: '松绿', color: Color(0xFF006B54)),
  (label: '暖红', color: Color(0xFFB3261E)),
  (label: '橙金', color: Color(0xFFE65100)),
  (label: '石墨', color: Color(0xFF49454F)),
];

ThemeMode _themeModeFromStorage(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}
