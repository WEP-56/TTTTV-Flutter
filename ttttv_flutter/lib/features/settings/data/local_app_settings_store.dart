import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

class LocalAppSettingsStore {
  static const _autoSavePlaybackProgressKey =
      'app_settings_auto_save_playback_progress';
  static const _defaultVideoFitKey = 'app_settings_default_video_fit';
  static const _keepScreenAwakeDuringPlaybackKey =
      'app_settings_keep_screen_awake_during_playback';
  static const _autoClearCacheOnExitKey =
      'app_settings_auto_clear_cache_on_exit';
  static const _autoClearCacheThresholdKey =
      'app_settings_auto_clear_cache_threshold';

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      autoSavePlaybackProgress:
          preferences.getBool(_autoSavePlaybackProgressKey) ?? true,
      defaultVideoFit: _videoFitPreferenceFromStorage(
        preferences.getString(_defaultVideoFitKey),
      ),
      keepScreenAwakeDuringPlayback:
          preferences.getBool(_keepScreenAwakeDuringPlaybackKey) ?? false,
      autoClearCacheOnExit:
          preferences.getBool(_autoClearCacheOnExitKey) ?? false,
      autoClearCacheThreshold: _cacheAutoClearThresholdFromStorage(
        preferences.getString(_autoClearCacheThresholdKey),
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _autoSavePlaybackProgressKey,
      settings.autoSavePlaybackProgress,
    );
    await preferences.setString(
      _defaultVideoFitKey,
      settings.defaultVideoFit.name,
    );
    await preferences.setBool(
      _keepScreenAwakeDuringPlaybackKey,
      settings.keepScreenAwakeDuringPlayback,
    );
    await preferences.setBool(
      _autoClearCacheOnExitKey,
      settings.autoClearCacheOnExit,
    );
    await preferences.setString(
      _autoClearCacheThresholdKey,
      settings.autoClearCacheThreshold.name,
    );
  }
}

VideoFitPreference _videoFitPreferenceFromStorage(String? value) {
  switch (value) {
    case 'cover':
      return VideoFitPreference.cover;
    case 'stretch':
      return VideoFitPreference.stretch;
    case 'original':
    default:
      return VideoFitPreference.original;
  }
}


CacheAutoClearThreshold _cacheAutoClearThresholdFromStorage(String? value) {
  switch (value) {
    case 'mb500':
      return CacheAutoClearThreshold.mb500;
    case 'gb1':
      return CacheAutoClearThreshold.gb1;
    case 'gb2':
      return CacheAutoClearThreshold.gb2;
    case 'disabled':
    default:
      return CacheAutoClearThreshold.disabled;
  }
}
