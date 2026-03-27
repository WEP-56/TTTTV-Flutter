import '../../../core/models/vod_models.dart';

abstract interface class LiveRepository {
  // 平台列表
  Future<List<LivePlatformInfo>> fetchPlatforms();

  // 推荐 / 搜索
  Future<List<LiveRoomItem>> recommend(String platform, {int page = 1});
  Future<List<LiveRoomItem>> search(String platform, String kw, {int page = 1});

  // 房间详情 / 清晰度 / 播放地址
  Future<LiveRoomDetail> getRoomDetail(String platform, String roomId);
  Future<List<LivePlayQuality>> getQualities(String platform, String roomId);
  Future<LivePlayUrl> getPlayUrl(String platform, String roomId, String qualityId);

  // 代理 URL 构造（封面 / 头像 / 流）
  String proxyUrl(String platform, String url);

  // 弹幕 WebSocket URL
  String danmakuWsUrl(String platform, String roomId);

  // 收藏
  Future<List<LiveFavoriteItem>> fetchFavorites();
  Future<void> addFavorite({
    required String platform,
    required String roomId,
    required String title,
    String? cover,
    String? userName,
    String? userAvatar,
  });
  Future<void> deleteFavorite(String platform, String roomId);
  Future<bool> checkFavorite(String platform, String roomId);
  Future<void> clearFavorites();

  // 历史
  Future<List<LiveHistoryItem>> fetchHistory();
  Future<void> addHistory({
    required String platform,
    required String roomId,
    required String title,
    String? cover,
    String? userName,
    String? userAvatar,
  });
  Future<void> deleteHistory(String platform, String roomId);
  Future<void> clearHistory();

  // 认证 — Bilibili
  Future<BilibiliAuthStatus> bilibiliAuthStatus();
  Future<BilibiliQrCode> bilibiliQrCode();
  Future<BilibiliQrPollResult> bilibiliQrPoll(String qrcodeKey);
  Future<void> bilibiliLogout();

  // 认证 — 其他平台（斗鱼 / 虎牙 / 抖音）
  Future<BilibiliAuthStatus> liveAuthStatus(String platform);
  Future<void> saveLiveCookie(String platform, String cookie);
  Future<void> liveAuthLogout(String platform);
}
