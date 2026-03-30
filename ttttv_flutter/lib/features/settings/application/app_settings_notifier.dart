import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_app_settings_store.dart';
import '../domain/app_settings.dart';

class AppSettingsNotifier extends Notifier<AppSettings> {
  bool _loaded = false;

  @override
  AppSettings build() {
    if (!_loaded) {
      _loaded = true;
      Future<void>.microtask(_load);
    }
    return const AppSettings();
  }

  Future<void> _load() async {
    final settings = await ref.read(appSettingsStoreProvider).load();
    state = settings;
  }

  Future<void> _save(AppSettings settings) async {
    state = settings;
    await ref.read(appSettingsStoreProvider).save(settings);
  }

  Future<void> setAutoSavePlaybackProgress(bool enabled) {
    return _save(state.copyWith(autoSavePlaybackProgress: enabled));
  }

  Future<void> setDefaultVideoFit(VideoFitPreference preference) {
    return _save(state.copyWith(defaultVideoFit: preference));
  }

  Future<void> setKeepScreenAwakeDuringPlayback(bool enabled) {
    return _save(state.copyWith(keepScreenAwakeDuringPlayback: enabled));
  }

  Future<void> setLiveQualityPreference(LiveQualityPreference preference) {
    return _save(state.copyWith(liveQualityPreference: preference));
  }

  Future<void> setLiveDanmakuEnabled(bool enabled) {
    return _save(state.copyWith(liveDanmakuEnabled: enabled));
  }

  Future<void> setAutoCheckSourceHealthOnLaunch(bool enabled) {
    return _save(state.copyWith(autoCheckSourceHealthOnLaunch: enabled));
  }

  Future<void> setAutoSkipBadSources(bool enabled) {
    return _save(state.copyWith(autoSkipBadSources: enabled));
  }

  Future<void> setAutoClearCacheOnExit(bool enabled) {
    return _save(state.copyWith(autoClearCacheOnExit: enabled));
  }

  Future<void> setAutoClearCacheThreshold(CacheAutoClearThreshold threshold) {
    return _save(state.copyWith(autoClearCacheThreshold: threshold));
  }
}

final appSettingsStoreProvider = Provider<LocalAppSettingsStore>((ref) {
  return LocalAppSettingsStore();
});

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
