import '../../../core/models/vod_models.dart';
import '../../../core/network/http_backend_client.dart';
import '../domain/live_repository.dart';

class HttpLiveBackend implements LiveRepository {
  HttpLiveBackend({required HttpBackendClient client, required String baseUrl})
      : _client = client,
        _baseUrl = baseUrl;

  final HttpBackendClient _client;
  final String _baseUrl;

  @override
  Future<List<LivePlatformInfo>> fetchPlatforms() {
    return _client.getData<List<LivePlatformInfo>>(
      '/api/live/platforms',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LivePlatformInfo.fromJson).toList();
      },
    );
  }

  @override
  Future<List<LiveRoomItem>> recommend(String platform, {int page = 1}) {
    return _client.getData<List<LiveRoomItem>>(
      '/api/live/$platform/recommend',
      queryParameters: {'page': page},
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LiveRoomItem.fromJson).toList();
      },
    );
  }

  @override
  Future<List<LiveRoomItem>> search(String platform, String kw,
      {int page = 1}) {
    return _client.getData<List<LiveRoomItem>>(
      '/api/live/$platform/search',
      queryParameters: {'kw': kw, 'page': page},
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LiveRoomItem.fromJson).toList();
      },
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String platform, String roomId) {
    return _client.getData<LiveRoomDetail>(
      '/api/live/$platform/room/detail',
      queryParameters: {'room_id': roomId},
      decoder: LiveRoomDetail.fromJson,
    );
  }

  @override
  Future<List<LivePlayQuality>> getQualities(String platform, String roomId) {
    return _client.getData<List<LivePlayQuality>>(
      '/api/live/$platform/room/qualities',
      queryParameters: {'room_id': roomId},
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LivePlayQuality.fromJson).toList();
      },
    );
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
      String platform, String roomId, String qualityId) {
    return _client.getData<LivePlayUrl>(
      '/api/live/$platform/room/play',
      queryParameters: {'room_id': roomId, 'quality_id': qualityId},
      decoder: LivePlayUrl.fromJson,
    );
  }

  @override
  String proxyUrl(String platform, String url) {
    final encoded = Uri.encodeComponent(url);
    final encodedPlatform = Uri.encodeComponent(platform);
    return '$_baseUrl/api/live/proxy?platform=$encodedPlatform&url=$encoded';
  }

  @override
  String danmakuWsUrl(String platform, String roomId) {
    final wsBase = _baseUrl.replaceFirst('http://', 'ws://');
    final encodedPlatform = Uri.encodeComponent(platform);
    return '$wsBase/api/live/$encodedPlatform/room/danmaku?room_id=${Uri.encodeComponent(roomId)}';
  }

  // ─── 收藏 ────────────────────────────────────────────────────────────────────

  @override
  Future<List<LiveFavoriteItem>> fetchFavorites() {
    return _client.getData<List<LiveFavoriteItem>>(
      '/api/live/favorites',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LiveFavoriteItem.fromJson).toList();
      },
    );
  }

  @override
  Future<void> addFavorite({
    required String platform,
    required String roomId,
    required String title,
    String? cover,
    String? userName,
    String? userAvatar,
  }) {
    return _client.postVoid(
      '/api/live/favorites',
      body: {
        'platform': platform,
        'room_id': roomId,
        'title': title,
        if (cover != null) 'cover': cover,
        if (userName != null) 'user_name': userName,
        if (userAvatar != null) 'user_avatar': userAvatar,
      },
    );
  }

  @override
  Future<void> deleteFavorite(String platform, String roomId) {
    return _client.deleteVoid(
      '/api/live/favorites',
      queryParameters: {'platform': platform, 'room_id': roomId},
    );
  }

  @override
  Future<bool> checkFavorite(String platform, String roomId) {
    return _client.getData<bool>(
      '/api/live/favorites/check',
      queryParameters: {'platform': platform, 'room_id': roomId},
      decoder: (json) {
        final map = json as Map<String, dynamic>;
        return map['is_favorited'] as bool? ?? false;
      },
    );
  }

  @override
  Future<void> clearFavorites() {
    return _client.deleteVoid('/api/live/favorites/clear');
  }

  // ─── 历史 ────────────────────────────────────────────────────────────────────

  @override
  Future<List<LiveHistoryItem>> fetchHistory() {
    return _client.getData<List<LiveHistoryItem>>(
      '/api/live/history',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(LiveHistoryItem.fromJson).toList();
      },
    );
  }

  @override
  Future<void> addHistory({
    required String platform,
    required String roomId,
    required String title,
    String? cover,
    String? userName,
    String? userAvatar,
  }) {
    return _client.postVoid(
      '/api/live/history',
      body: {
        'platform': platform,
        'room_id': roomId,
        'title': title,
        if (cover != null) 'cover': cover,
        if (userName != null) 'user_name': userName,
        if (userAvatar != null) 'user_avatar': userAvatar,
      },
    );
  }

  @override
  Future<void> deleteHistory(String platform, String roomId) {
    return _client.deleteVoid(
      '/api/live/history',
      queryParameters: {'platform': platform, 'room_id': roomId},
    );
  }

  @override
  Future<void> clearHistory() {
    return _client.deleteVoid('/api/live/history/clear');
  }

  // ─── 认证 — Bilibili ─────────────────────────────────────────────────────────

  @override
  Future<BilibiliAuthStatus> bilibiliAuthStatus() {
    return _client.getData<BilibiliAuthStatus>(
      '/api/live/auth/bilibili/status',
      decoder: BilibiliAuthStatus.fromJson,
    );
  }

  @override
  Future<BilibiliQrCode> bilibiliQrCode() {
    return _client.getData<BilibiliQrCode>(
      '/api/live/auth/bilibili/qrcode',
      decoder: BilibiliQrCode.fromJson,
    );
  }

  @override
  Future<BilibiliQrPollResult> bilibiliQrPoll(String qrcodeKey) {
    return _client.getData<BilibiliQrPollResult>(
      '/api/live/auth/bilibili/qrcode/poll',
      queryParameters: {'qrcode_key': qrcodeKey},
      decoder: BilibiliQrPollResult.fromJson,
    );
  }

  @override
  Future<void> bilibiliLogout() {
    return _client.postVoid('/api/live/auth/bilibili/logout');
  }

  // ─── 认证 — 其他平台 ──────────────────────────────────────────────────────────

  @override
  Future<BilibiliAuthStatus> liveAuthStatus(String platform) {
    return _client.getData<BilibiliAuthStatus>(
      '/api/live/auth/$platform/status',
      decoder: BilibiliAuthStatus.fromJson,
    );
  }

  @override
  Future<void> saveLiveCookie(String platform, String cookie) {
    return _client.postVoid(
      '/api/live/auth/$platform/cookie',
      body: {'cookie': cookie},
    );
  }

  @override
  Future<void> liveAuthLogout(String platform) {
    return _client.postVoid('/api/live/auth/$platform/logout');
  }
}
