import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

class LocalAppSettingsStore {
  static const _autoSavePlaybackProgressKey =
      'app_settings_auto_save_playback_progress';
  static const _defaultVideoFitKey = 'app_settings_default_video_fit';
  static const _keepScreenAwakeDuringPlaybackKey =
      'app_settings_keep_screen_awake_during_playback';
  static const _liveQualityPreferenceKey =
      'app_settings_live_quality_preference';
  static const _liveDanmakuEnabledKey = 'app_settings_live_danmaku_enabled';
  static const _autoCheckSourceHealthOnLaunchKey =
      'app_settings_auto_check_source_health_on_launch';
  static const _autoSkipBadSourcesKey = 'app_settings_auto_skip_bad_sources';
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
      liveQualityPreference: _liveQualityPreferenceFromStorage(
        preferences.getString(_liveQualityPreferenceKey),
      ),
      liveDanmakuEnabled: preferences.getBool(_liveDanmakuEnabledKey) ?? true,
      autoCheckSourceHealthOnLaunch:
          preferences.getBool(_autoCheckSourceHealthOnLaunchKey) ?? false,
      autoSkipBadSources: preferences.getBool(_autoSkipBadSourcesKey) ?? false,
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
    await preferences.setString(
      _liveQualityPreferenceKey,
      settings.liveQualityPreference.name,
    );
    await preferences.setBool(
      _liveDanmakuEnabledKey,
      settings.liveDanmakuEnabled,
    );
    await preferences.setBool(
      _autoCheckSourceHealthOnLaunchKey,
      settings.autoCheckSourceHealthOnLaunch,
    );
    await preferences.setBool(
      _autoSkipBadSourcesKey,
      settings.autoSkipBadSources,
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

LiveQualityPreference _liveQualityPreferenceFromStorage(String? value) {
  switch (value) {
    case 'lowest':
      return LiveQualityPreference.lowest;
    case 'autoDegrade':
      return LiveQualityPreference.autoDegrade;
    case 'highest':
    default:
      return LiveQualityPreference.highest;
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
