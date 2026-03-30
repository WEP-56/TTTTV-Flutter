enum VideoFitPreference {
  original,
  cover,
  stretch,
}

enum LiveQualityPreference {
  highest,
  lowest,
  autoDegrade,
}

enum CacheAutoClearThreshold {
  disabled,
  mb500,
  gb1,
  gb2,
}

class AppSettings {
  const AppSettings({
    this.autoSavePlaybackProgress = true,
    this.defaultVideoFit = VideoFitPreference.original,
    this.keepScreenAwakeDuringPlayback = false,
    this.liveQualityPreference = LiveQualityPreference.highest,
    this.liveDanmakuEnabled = true,
    this.autoCheckSourceHealthOnLaunch = false,
    this.autoSkipBadSources = false,
    this.autoClearCacheOnExit = false,
    this.autoClearCacheThreshold = CacheAutoClearThreshold.disabled,
  });

  final bool autoSavePlaybackProgress;
  final VideoFitPreference defaultVideoFit;
  final bool keepScreenAwakeDuringPlayback;
  final LiveQualityPreference liveQualityPreference;
  final bool liveDanmakuEnabled;
  final bool autoCheckSourceHealthOnLaunch;
  final bool autoSkipBadSources;
  final bool autoClearCacheOnExit;
  final CacheAutoClearThreshold autoClearCacheThreshold;

  int? get autoClearCacheThresholdBytes => switch (autoClearCacheThreshold) {
        CacheAutoClearThreshold.disabled => null,
        CacheAutoClearThreshold.mb500 => 500 * 1024 * 1024,
        CacheAutoClearThreshold.gb1 => 1024 * 1024 * 1024,
        CacheAutoClearThreshold.gb2 => 2 * 1024 * 1024 * 1024,
      };

  AppSettings copyWith({
    bool? autoSavePlaybackProgress,
    VideoFitPreference? defaultVideoFit,
    bool? keepScreenAwakeDuringPlayback,
    LiveQualityPreference? liveQualityPreference,
    bool? liveDanmakuEnabled,
    bool? autoCheckSourceHealthOnLaunch,
    bool? autoSkipBadSources,
    bool? autoClearCacheOnExit,
    CacheAutoClearThreshold? autoClearCacheThreshold,
  }) {
    return AppSettings(
      autoSavePlaybackProgress:
          autoSavePlaybackProgress ?? this.autoSavePlaybackProgress,
      defaultVideoFit: defaultVideoFit ?? this.defaultVideoFit,
      keepScreenAwakeDuringPlayback:
          keepScreenAwakeDuringPlayback ?? this.keepScreenAwakeDuringPlayback,
      liveQualityPreference:
          liveQualityPreference ?? this.liveQualityPreference,
      liveDanmakuEnabled: liveDanmakuEnabled ?? this.liveDanmakuEnabled,
      autoCheckSourceHealthOnLaunch:
          autoCheckSourceHealthOnLaunch ?? this.autoCheckSourceHealthOnLaunch,
      autoSkipBadSources: autoSkipBadSources ?? this.autoSkipBadSources,
      autoClearCacheOnExit: autoClearCacheOnExit ?? this.autoClearCacheOnExit,
      autoClearCacheThreshold:
          autoClearCacheThreshold ?? this.autoClearCacheThreshold,
    );
  }
}
