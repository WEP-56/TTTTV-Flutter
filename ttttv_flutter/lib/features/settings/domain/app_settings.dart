enum VideoFitPreference {
  original,
  cover,
  stretch,
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
    this.autoClearCacheOnExit = false,
    this.autoClearCacheThreshold = CacheAutoClearThreshold.disabled,
  });

  final bool autoSavePlaybackProgress;
  final VideoFitPreference defaultVideoFit;
  final bool keepScreenAwakeDuringPlayback;
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
    bool? autoClearCacheOnExit,
    CacheAutoClearThreshold? autoClearCacheThreshold,
  }) {
    return AppSettings(
      autoSavePlaybackProgress:
          autoSavePlaybackProgress ?? this.autoSavePlaybackProgress,
      defaultVideoFit: defaultVideoFit ?? this.defaultVideoFit,
      keepScreenAwakeDuringPlayback:
          keepScreenAwakeDuringPlayback ?? this.keepScreenAwakeDuringPlayback,
      autoClearCacheOnExit: autoClearCacheOnExit ?? this.autoClearCacheOnExit,
      autoClearCacheThreshold:
          autoClearCacheThreshold ?? this.autoClearCacheThreshold,
    );
  }
}
