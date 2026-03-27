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

// ─── Live models ────────────────────────────────────────────────────────────

class LivePlatformInfo {
  LivePlatformInfo({required this.id, required this.name});

  final String id;
  final String name;

  factory LivePlatformInfo.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LivePlatformInfo(
      id: _readString(map['id']) ?? '',
      name: _readString(map['name']) ?? '',
    );
  }
}

class LiveRoomItem {
  LiveRoomItem({
    required this.platform,
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    required this.online,
  });

  final String platform;
  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final int online;

  factory LiveRoomItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveRoomItem(
      platform: _readString(map['platform']) ?? '',
      roomId: _readString(map['room_id']) ?? '',
      title: _readString(map['title']) ?? '',
      cover: _readString(map['cover']) ?? '',
      userName: _readString(map['user_name']) ?? '',
      online: _readInt(map['online']) ?? 0,
    );
  }
}

class LiveRoomDetail {
  LiveRoomDetail({
    required this.platform,
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    required this.userAvatar,
    required this.online,
    required this.status,
    required this.isRecord,
    required this.url,
    this.introduction,
    this.notice,
    this.showTime,
  });

  final String platform;
  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final String userAvatar;
  final int online;
  final bool status;
  final bool isRecord;
  final String url;
  final String? introduction;
  final String? notice;
  final String? showTime;

  factory LiveRoomDetail.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveRoomDetail(
      platform: _readString(map['platform']) ?? '',
      roomId: _readString(map['room_id']) ?? '',
      title: _readString(map['title']) ?? '',
      cover: _readString(map['cover']) ?? '',
      userName: _readString(map['user_name']) ?? '',
      userAvatar: _readString(map['user_avatar']) ?? '',
      online: _readInt(map['online']) ?? 0,
      status: map['status'] as bool? ?? false,
      isRecord: map['is_record'] as bool? ?? false,
      url: _readString(map['url']) ?? '',
      introduction: _readString(map['introduction']),
      notice: _readString(map['notice']),
      showTime: _readString(map['show_time']),
    );
  }
}

class LivePlayQuality {
  LivePlayQuality({
    required this.id,
    required this.name,
    required this.sort,
  });

  final String id;
  final String name;
  final int sort;

  factory LivePlayQuality.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LivePlayQuality(
      id: _readString(map['id']) ?? '',
      name: _readString(map['name']) ?? '',
      sort: _readInt(map['sort']) ?? 0,
    );
  }
}

class LivePlayUrl {
  LivePlayUrl({
    required this.urls,
    this.headers,
    this.urlType,
    this.expiresAt,
  });

  final List<String> urls;
  final Map<String, String>? headers;
  final String? urlType;
  final int? expiresAt;

  factory LivePlayUrl.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    final rawHeaders = map['headers'] as Map<String, dynamic>?;
    return LivePlayUrl(
      urls: ((map['urls'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      headers: rawHeaders?.map((k, v) => MapEntry(k, v.toString())),
      urlType: _readString(map['url_type']),
      expiresAt: _readInt(map['expires_at']),
    );
  }
}

class LiveMessageColor {
  LiveMessageColor({required this.r, required this.g, required this.b});

  final int r;
  final int g;
  final int b;

  factory LiveMessageColor.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveMessageColor(
      r: _readInt(map['r']) ?? 255,
      g: _readInt(map['g']) ?? 255,
      b: _readInt(map['b']) ?? 255,
    );
  }
}

class LiveMessage {
  LiveMessage({
    required this.type,
    required this.userName,
    required this.message,
    required this.color,
  });

  final String type;
  final String userName;
  final String message;
  final LiveMessageColor color;

  factory LiveMessage.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveMessage(
      type: _readString(map['type']) ?? '',
      userName: _readString(map['user_name']) ?? '',
      message: _readString(map['message']) ?? '',
      color: map['color'] != null
          ? LiveMessageColor.fromJson(map['color'])
          : LiveMessageColor(r: 255, g: 255, b: 255),
    );
  }
}

class LiveFavoriteItem {
  LiveFavoriteItem({
    required this.platform,
    required this.roomId,
    required this.title,
    required this.createdTime,
    this.cover,
    this.userName,
    this.userAvatar,
  });

  final String platform;
  final String roomId;
  final String title;
  final int createdTime;
  final String? cover;
  final String? userName;
  final String? userAvatar;

  factory LiveFavoriteItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveFavoriteItem(
      platform: _readString(map['platform']) ?? '',
      roomId: _readString(map['room_id']) ?? '',
      title: _readString(map['title']) ?? '',
      createdTime: _readInt(map['created_time']) ?? 0,
      cover: _readString(map['cover']),
      userName: _readString(map['user_name']),
      userAvatar: _readString(map['user_avatar']),
    );
  }
}

class LiveHistoryItem {
  LiveHistoryItem({
    required this.platform,
    required this.roomId,
    required this.title,
    required this.lastWatchTime,
    this.cover,
    this.userName,
    this.userAvatar,
  });

  final String platform;
  final String roomId;
  final String title;
  final int lastWatchTime;
  final String? cover;
  final String? userName;
  final String? userAvatar;

  factory LiveHistoryItem.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return LiveHistoryItem(
      platform: _readString(map['platform']) ?? '',
      roomId: _readString(map['room_id']) ?? '',
      title: _readString(map['title']) ?? '',
      lastWatchTime: _readInt(map['last_watch_time']) ?? 0,
      cover: _readString(map['cover']),
      userName: _readString(map['user_name']),
      userAvatar: _readString(map['user_avatar']),
    );
  }
}

class BilibiliAuthStatus {
  BilibiliAuthStatus({required this.loggedIn});

  final bool loggedIn;

  factory BilibiliAuthStatus.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return BilibiliAuthStatus(loggedIn: map['logged_in'] as bool? ?? false);
  }
}

class BilibiliQrCode {
  BilibiliQrCode({
    required this.qrcodeKey,
    required this.url,
    required this.svg,
  });

  final String qrcodeKey;
  final String url;
  final String svg;

  factory BilibiliQrCode.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return BilibiliQrCode(
      qrcodeKey: _readString(map['qrcode_key']) ?? '',
      url: _readString(map['url']) ?? '',
      svg: _readString(map['svg']) ?? '',
    );
  }
}

class BilibiliQrPollResult {
  BilibiliQrPollResult({
    required this.code,
    required this.status,
    required this.message,
  });

  final int code;
  final String status;
  final String message;

  factory BilibiliQrPollResult.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return BilibiliQrPollResult(
      code: _readInt(map['code']) ?? 0,
      status: _readString(map['status']) ?? '',
      message: _readString(map['message']) ?? '',
    );
  }
}

// ─── End live models ─────────────────────────────────────────────────────────

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
