import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeedKey = 'theme_seed_color';
const _kDefaultSeed = Color(0xFF6750A4);

final _prefsProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

class ThemeState {
  const ThemeState({this.seedColor = _kDefaultSeed});
  final Color seedColor;

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

  ThemeState copyWith({Color? seedColor}) =>
      ThemeState(seedColor: seedColor ?? this.seedColor);
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    ref.listen(_prefsProvider, (_, next) {
      next.whenData((prefs) {
        final value = prefs.getInt(_kSeedKey);
        if (value != null) {
          state = state.copyWith(seedColor: Color(value));
        }
      });
    });
    return const ThemeState();
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedKey, color.toARGB32());
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
