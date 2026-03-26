class SearchResult {
  SearchResult({
    required this.items,
    required this.filteredCount,
  });

  final List<VodItem> items;
  final int filteredCount;

  factory SearchResult.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return SearchResult(
      items: ((map['items'] as List?) ?? const [])
          .map(VodItem.fromJson)
          .toList(),
      filteredCount: _readInt(map['filtered_count']) ?? 0,
    );
  }
}

class BackendHealth {
  BackendHealth({
    required this.status,
    required this.version,
  });

  final String status;
  final String version;

  bool get isOk => status.toLowerCase() == 'ok';

  factory BackendHealth.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return BackendHealth(
      status: _readString(map['status']) ?? 'unknown',
      version: _readString(map['version']) ?? 'unknown',
    );
  }
}

class VodItem {
  VodItem({
    required this.sourceKey,
    required this.vodId,
    required this.vodName,
    required this.vodPlayUrl,
    this.vodPic,
    this.vodRemarks,
    this.vodActor,
    this.vodDirector,
    this.vodContent,
    this.vodYear,
    this.vodArea,
    this.vodClass,
    this.vodTag,
    this.vodDuration,
    this.vodLang,
    this.typeName,
    this.avgSpeedMs,
  });

  final String sourceKey;
  final String vodId;
  final String vodName;
  final String vodPlayUrl;
  final String? vodPic;
  final String? vodRemarks;
  final String? vodActor;
  final String? vodDirector;
  final String? vodContent;
  final String? vodYear;
  final String? vodArea;
  final String? vodClass;
  final String? vodTag;
  final String? vodDuration;
  final String? vodLang;
  final String? typeName;
  final int? avgSpeedMs;

  factory VodItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return VodItem(
      sourceKey: _readString(map['source_key']) ?? '',
      vodId: _readString(map['vod_id']) ?? '',
      vodName: _readString(map['vod_name']) ?? '',
      vodPlayUrl: _readString(map['vod_play_url']) ?? '',
      vodPic: _readString(map['vod_pic']),
      vodRemarks: _readString(map['vod_remarks']),
      vodActor: _readString(map['vod_actor']),
      vodDirector: _readString(map['vod_director']),
      vodContent: _readString(map['vod_content']),
      vodYear: _readString(map['vod_year']),
      vodArea: _readString(map['vod_area']),
      vodClass: _readString(map['vod_class']),
      vodTag: _readString(map['vod_tag']),
      vodDuration: _readString(map['vod_duration']),
      vodLang: _readString(map['vod_lang']),
      typeName: _readString(map['type_name']),
      avgSpeedMs: _readInt(map['avg_speed_ms']),
    );
  }

  factory VodItem.fromHistory(WatchHistoryItem item) {
    return VodItem(
      sourceKey: item.sourceKey,
      vodId: item.vodId,
      vodName: item.vodName,
      vodPlayUrl: '',
      vodPic: item.vodPic,
    );
  }

  factory VodItem.fromFavorite(FavoriteItem item) {
    return VodItem(
      sourceKey: item.sourceKey,
      vodId: item.vodId,
      vodName: item.vodName,
      vodPlayUrl: '',
      vodPic: item.vodPic,
      vodRemarks: item.vodRemarks,
      vodActor: item.vodActor,
      vodDirector: item.vodDirector,
      vodContent: item.vodContent,
    );
  }
}

class PlayEpisode {
  PlayEpisode({
    required this.name,
    required this.url,
  });

  final String name;
  final String url;

  factory PlayEpisode.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return PlayEpisode(
      name: _readString(map['name']) ?? '',
      url: _readString(map['url']) ?? '',
    );
  }
}

class PlaySource {
  PlaySource({
    required this.name,
    required this.episodes,
  });

  final String name;
  final List<PlayEpisode> episodes;

  factory PlaySource.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return PlaySource(
      name: _readString(map['name']) ?? '',
      episodes: ((map['episodes'] as List?) ?? const [])
          .map(PlayEpisode.fromJson)
          .toList(),
    );
  }
}

class PlayResult {
  PlayResult({
    required this.sources,
  });

  final List<PlaySource> sources;

  factory PlayResult.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return PlayResult(
      sources: ((map['sources'] as List?) ?? const [])
          .map(PlaySource.fromJson)
          .toList(),
    );
  }
}

class WatchHistoryItem {
  WatchHistoryItem({
    required this.vodId,
    required this.sourceKey,
    required this.vodName,
    required this.lastPlayTime,
    required this.progress,
    this.vodPic,
    this.episode,
  });

  final String vodId;
  final String sourceKey;
  final String vodName;
  final String? vodPic;
  final int lastPlayTime;
  final double progress;
  final String? episode;

  factory WatchHistoryItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return WatchHistoryItem(
      vodId: _readString(map['vod_id']) ?? '',
      sourceKey: _readString(map['source_key']) ?? '',
      vodName: _readString(map['vod_name']) ?? '',
      vodPic: _readString(map['vod_pic']),
      lastPlayTime: _readInt(map['last_play_time']) ?? 0,
      progress: _readDouble(map['progress']) ?? 0,
      episode: _readString(map['episode']),
    );
  }
}

class WatchHistoryUpsert {
  WatchHistoryUpsert({
    required this.vodId,
    required this.sourceKey,
    required this.vodName,
    required this.progress,
    this.vodPic,
    this.episode,
  });

  final String vodId;
  final String sourceKey;
  final String vodName;
  final double progress;
  final String? vodPic;
  final String? episode;

  Map<String, dynamic> toJson() {
    return {
      'vod_id': vodId,
      'source_key': sourceKey,
      'vod_name': vodName,
      'vod_pic': vodPic,
      'progress': progress,
      'episode': episode,
    };
  }
}

class FavoriteItem {
  FavoriteItem({
    required this.vodId,
    required this.sourceKey,
    required this.vodName,
    required this.createdTime,
    this.vodPic,
    this.vodRemarks,
    this.vodActor,
    this.vodDirector,
    this.vodContent,
  });

  final String vodId;
  final String sourceKey;
  final String vodName;
  final int createdTime;
  final String? vodPic;
  final String? vodRemarks;
  final String? vodActor;
  final String? vodDirector;
  final String? vodContent;

  factory FavoriteItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return FavoriteItem(
      vodId: _readString(map['vod_id']) ?? '',
      sourceKey: _readString(map['source_key']) ?? '',
      vodName: _readString(map['vod_name']) ?? '',
      createdTime: _readInt(map['created_time']) ?? 0,
      vodPic: _readString(map['vod_pic']),
      vodRemarks: _readString(map['vod_remarks']),
      vodActor: _readString(map['vod_actor']),
      vodDirector: _readString(map['vod_director']),
      vodContent: _readString(map['vod_content']),
    );
  }
}

class SiteWithStatus {
  SiteWithStatus({
    required this.key,
    required this.name,
    required this.baseUrl,
    required this.enabled,
    this.lastCheck,
    this.isHealthy,
    this.comment,
    this.r18,
    this.group,
  });

  final String key;
  final String name;
  final String baseUrl;
  final bool enabled;
  final int? lastCheck;
  final bool? isHealthy;
  final String? comment;
  final bool? r18;
  final String? group;

  factory SiteWithStatus.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return SiteWithStatus(
      key: _readString(map['key']) ?? '',
      name: _readString(map['name']) ?? '',
      baseUrl: _readString(map['base_url']) ?? '',
      enabled: map['enabled'] as bool? ?? false,
      lastCheck: _readInt(map['last_check']),
      isHealthy: map['is_healthy'] as bool?,
      comment: _readString(map['comment']),
      r18: map['r18'] as bool?,
      group: _readString(map['group']),
    );
  }
}

class RemoteSource {
  RemoteSource({
    required this.key,
    required this.name,
    required this.api,
    required this.detail,
    this.group,
    this.r18,
    this.comment,
  });

  final String key;
  final String name;
  final String api;
  final String detail;
  final String? group;
  final bool? r18;
  final String? comment;

  factory RemoteSource.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return RemoteSource(
      key: _readString(map['key']) ?? '',
      name: _readString(map['name']) ?? '',
      api: _readString(map['api']) ?? '',
      detail: _readString(map['detail']) ?? '',
      group: _readString(map['group']),
      r18: map['r18'] as bool?,
      comment: _readString(map['comment']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'api': api,
      'detail': detail,
      'group': group,
      'r18': r18,
      'comment': comment,
    };
  }
}

class RemoteSourcesResponse {
  RemoteSourcesResponse({
    required this.url,
    required this.sources,
  });

  final String url;
  final List<RemoteSource> sources;

  factory RemoteSourcesResponse.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return RemoteSourcesResponse(
      url: _readString(map['url']) ?? '',
      sources: ((map['sources'] as List?) ?? const [])
          .map(RemoteSource.fromJson)
          .toList(),
    );
  }
}

class AddSourcesBatchFailure {
  AddSourcesBatchFailure({
    required this.key,
    required this.error,
  });

  final String key;
  final String error;

  factory AddSourcesBatchFailure.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return AddSourcesBatchFailure(
      key: _readString(map['key']) ?? '',
      error: _readString(map['error']) ?? 'Unknown error',
    );
  }
}

class AddSourcesBatchResult {
  AddSourcesBatchResult({
    required this.added,
    required this.skippedExisting,
    required this.failed,
  });

  final List<String> added;
  final List<String> skippedExisting;
  final List<AddSourcesBatchFailure> failed;

  factory AddSourcesBatchResult.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return AddSourcesBatchResult(
      added: ((map['added'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      skippedExisting: ((map['skipped_existing'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      failed: ((map['failed'] as List?) ?? const [])
          .map(AddSourcesBatchFailure.fromJson)
          .toList(),
    );
  }
}

class DoubanSubject {
  DoubanSubject({
    required this.title,
    this.id,
    this.cover,
    this.rate,
    this.year,
  });

  final String? id;
  final String title;
  final String? cover;
  final String? rate;
  final String? year;

  factory DoubanSubject.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return DoubanSubject(
      id: _readString(map['id']),
      title: _readString(map['title']) ?? '',
      cover: _readString(map['cover']) ?? _readString(map['cover_url']),
      rate: _readString(map['rate']),
      year: _readString(map['year']),
    );
  }
}

class DoubanSearchResponse {
  DoubanSearchResponse({required this.subjects});

  final List<DoubanSubject> subjects;

  factory DoubanSearchResponse.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return DoubanSearchResponse(
      subjects: ((map['subjects'] as List?) ?? const [])
          .map(DoubanSubject.fromJson)
          .toList(),
    );
  }
}

class AddSourceRequest {
  AddSourceRequest({
    required this.key,
    required this.name,
    required this.api,
    required this.detail,
    this.group,
    this.r18,
    this.comment,
  });

  final String key;
  final String name;
  final String api;
  final String detail;
  final String? group;
  final bool? r18;
  final String? comment;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'api': api,
      'detail': detail,
      'group': group,
      'r18': r18,
      'comment': comment,
    };
  }
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _readDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}
