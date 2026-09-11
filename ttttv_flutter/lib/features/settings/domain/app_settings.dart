enum VideoFitPreference {
  original,
  cover,
  stretch,
}

enum DoubanDataSource {
  direct('直连豆瓣'),
  tencentCDN('腾讯 CDN'),
  aliCDN('阿里 CDN'),
  custom('自定义');

  const DoubanDataSource(this.label);
  final String label;
}

enum CacheAutoClearThreshold {
  disabled,
  mb500,
  gb1,
  gb2,
}

class AppSettings {
  const AppSettings({
    this.autoCheckSources = false,
    this.autoSavePlaybackProgress = true,
    this.defaultVideoFit = VideoFitPreference.original,
    this.keepScreenAwakeDuringPlayback = false,
    this.doubanDataSource = DoubanDataSource.direct,
    this.autoClearCacheOnExit = false,
    this.autoClearCacheThreshold = CacheAutoClearThreshold.disabled,
  });

  final bool autoSavePlaybackProgress;
  final bool autoCheckSources;
  final VideoFitPreference defaultVideoFit;
  final bool keepScreenAwakeDuringPlayback;
  final DoubanDataSource doubanDataSource;
  final bool autoClearCacheOnExit;
  final CacheAutoClearThreshold autoClearCacheThreshold;

  int? get autoClearCacheThresholdBytes => switch (autoClearCacheThreshold) {
        CacheAutoClearThreshold.disabled => null,
        CacheAutoClearThreshold.mb500 => 500 * 1024 * 1024,
        CacheAutoClearThreshold.gb1 => 1024 * 1024 * 1024,
        CacheAutoClearThreshold.gb2 => 2 * 1024 * 1024 * 1024,
      };

  AppSettings copyWith({
    bool? autoCheckSources,
    bool? autoSavePlaybackProgress,
    VideoFitPreference? defaultVideoFit,
    bool? keepScreenAwakeDuringPlayback,
    DoubanDataSource? doubanDataSource,
    bool? autoClearCacheOnExit,
    CacheAutoClearThreshold? autoClearCacheThreshold,
  }) {
    return AppSettings(
      autoCheckSources: autoCheckSources ?? this.autoCheckSources,
      autoSavePlaybackProgress:
          autoSavePlaybackProgress ?? this.autoSavePlaybackProgress,
      defaultVideoFit: defaultVideoFit ?? this.defaultVideoFit,
      keepScreenAwakeDuringPlayback:
          keepScreenAwakeDuringPlayback ?? this.keepScreenAwakeDuringPlayback,
      doubanDataSource: doubanDataSource ?? this.doubanDataSource,
      autoClearCacheOnExit: autoClearCacheOnExit ?? this.autoClearCacheOnExit,
      autoClearCacheThreshold:
          autoClearCacheThreshold ?? this.autoClearCacheThreshold,
    );
  }
}
