import 'dart:convert';
import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import 'douyu_auth_service.dart';
import 'douyu_danmaku_client.dart';
import 'douyu_models.dart';
import 'douyu_signer.dart';

class DouyuLiveProvider extends LiveProvider {
  DouyuLiveProvider({
    required Dio dio,
    required DouyuSigner signer,
    required DouyuAuthService authService,
    DouyuDanmakuClient? danmakuClient,
  })  : _dio = dio,
        _signer = signer,
        _authService = authService,
        _danmakuClient = danmakuClient ?? DouyuDanmakuClient();

  final Dio _dio;
  final DouyuSigner _signer;
  final DouyuAuthService _authService;
  final DouyuDanmakuClient _danmakuClient;

  @override
  String get id => 'douyu';

  @override
  String get name => '斗鱼';

  @override
  bool get supportsSearch => true;

  @override
  bool get supportsCategories => true;

  @override
  bool get supportsDanmaku => true;

  @override
  bool get supportsAuth => true;

  @override
  Future<bool> isAuthenticated() {
    return _authService.hasCookie();
  }

  @override
  Future<String> getSavedCookie() {
    return _authService.getCookie();
  }

  @override
  Future<void> saveCookie(String cookie) {
    return _authService.saveCookie(cookie);
  }

  @override
  Future<void> clearAuth() {
    return _authService.clearCookie();
  }

  @override
  Future<LiveAuthCheckResult> checkAuth() async {
    final cookie = await _authService.getCookie();
    if (cookie.trim().isEmpty) {
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.failure,
        message: '未保存 Cookie',
      );
    }

    final normalized = cookie.toLowerCase();
    final hasUid = normalized.contains('acf_uid=');
    final hasUserName = normalized.contains('acf_username=');
    final hasLtkid = normalized.contains('acf_ltkid=');

    if (hasUid && (hasUserName || hasLtkid)) {
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.warning,
        message: '基础检查通过，已包含斗鱼登录关键字段；当前未接入强校验接口。',
      );
    }

    return const LiveAuthCheckResult(
      status: LiveAuthCheckStatus.failure,
      message: 'Cookie 缺少关键字段，可能不是完整的斗鱼登录 Cookie。',
    );
  }

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    final response = await _dio.get<Object?>(
      'https://www.douyu.com/japi/weblist/apinc/allpage/6/$page',
      options: Options(
        headers: await _signer.headers(referer: 'https://www.douyu.com/'),
      ),
    );

    final map = _decodeJsonMap(response.data);
    _ensureSuccess(map, fallbackMessage: '斗鱼推荐获取失败');

    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final list = data['rl'] as List<dynamic>? ?? const [];
    return list.where(_isLiveCard).map(_roomItemFromDirectory).toList();
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    final did = await _signer.getDid();
    final response = await _dio.get<Object?>(
      'https://www.douyu.com/japi/search/api/searchShow',
      queryParameters: {
        'kw': keyword,
        'page': page,
        'pageSize': 20,
      },
      options: Options(
        headers: await _signer.headers(
          referer: 'https://www.douyu.com/search/',
          did: did,
        ),
      ),
    );

    final map = _decodeJsonMap(response.data);
    _ensureSuccess(map, fallbackMessage: '斗鱼搜索失败');

    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final list = data['relateShow'] as List<dynamic>? ?? const [];
    return list.map(_roomItemFromSearch).toList();
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    final roomResponse = await _dio.get<Object?>(
      'https://www.douyu.com/betard/$roomId',
      options: Options(
        headers: await _signer.headers(
          referer: 'https://www.douyu.com/$roomId',
        ),
      ),
    );

    final roomMap = _parseBetardRoom(roomResponse.data);
    final h5Response = await _dio.get<Object?>(
      'https://www.douyu.com/swf_api/h5room/$roomId',
      options: Options(
        headers: await _signer.headers(
          referer: 'https://www.douyu.com/$roomId',
        ),
      ),
    );

    final h5Map = _decodeJsonMap(h5Response.data);
    final h5Data = h5Map['data'] as Map<String, dynamic>? ?? const {};
    final online = _toInt(
      ((roomMap['room_biz_all'] as Map<String, dynamic>? ?? const {})['hot']),
    );
    final status = _toInt(roomMap['show_status']) == 1;
    final isRecord = _toInt(roomMap['videoLoop']) == 1;
    final realRoomId = roomMap['room_id']?.toString() ?? roomId;

    return LiveRoomDetail(
      platform: id,
      roomId: realRoomId,
      title: roomMap['room_name']?.toString() ?? '',
      cover: roomMap['room_pic']?.toString() ?? '',
      userName: roomMap['owner_name']?.toString() ?? '',
      userAvatar: roomMap['owner_avatar']?.toString() ?? '',
      online: online,
      introduction: roomMap['show_details']?.toString(),
      notice: null,
      status: status && !isRecord,
      isRecord: isRecord,
      url: 'https://www.douyu.com/$realRoomId',
      showTime: h5Data['show_time']?.toString(),
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail) async {
    if (!detail.status) {
      throw StateError('直播间未开播');
    }

    final metadata = await _fetchPlayMetadata(detail.roomId);
    return metadata.qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
    LiveRoomDetail detail,
    String qualityId,
  ) async {
    if (!detail.status) {
      throw StateError('直播间未开播');
    }

    final metadata = await _fetchPlayMetadata(detail.roomId);
    final urls = <String>[];
    for (final cdn in metadata.cdns) {
      final json = await _postH5Play(
        detail.roomId,
        await _playArgs(detail.roomId, cdn: cdn, rate: qualityId),
      );
      urls.addAll(_collectPlayUrls(json));
    }

    urls.sort();
    final deduped = urls.toSet().toList();
    if (deduped.isEmpty) {
      throw StateError('斗鱼未获取到播放地址');
    }

    return LivePlayUrl(
      urls: deduped,
      headers: null,
      urlType: 'auto',
    );
  }

  @override
  Stream<LiveMessage> createDanmakuStream(LiveRoomDetail detail) {
    return _danmakuClient.connect(detail.roomId);
  }

  Future<DouyuPlayMetadata> _fetchPlayMetadata(String roomId) async {
    final response = await _postH5Play(
      roomId,
      await _playArgs(roomId),
    );
    final data = response['data'] as Map<String, dynamic>? ?? const {};

    final cdns = _parseCdns(data);
    for (final cdn in ['ws-h5', 'tct-h5', 'ali-h5', 'hs-h5']) {
      if (!cdns.contains(cdn)) {
        cdns.add(cdn);
      }
    }

    final qualities = <LivePlayQuality>[];
    final rates = data['multirates'] as List<dynamic>? ?? const [];
    for (final raw in rates) {
      final map = raw as Map<String, dynamic>;
      final rate = _toInt(map['rate'] ?? map['type']);
      if (rate < 0) continue;
      qualities.add(
        LivePlayQuality(
          id: rate.toString(),
          name: map['name']?.toString() ?? '未知清晰度',
          sort: rate == 0 ? 1 << 30 : rate,
        ),
      );
    }
    qualities.sort((left, right) => right.sort.compareTo(left.sort));

    return DouyuPlayMetadata(cdns: cdns, qualities: qualities);
  }

  Future<String> _playArgs(
    String roomId, {
    String? cdn,
    String? rate,
  }) async {
    final sign = await _signer.getPlayArgs(roomId);
    return '$sign&cdn=${cdn ?? ''}&rate=${rate ?? '-1'}'
        '&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0';
  }

  Future<Map<String, dynamic>> _postH5Play(String roomId, String body) async {
    final response = await _dio.post<Object?>(
      'https://www.douyu.com/lapi/live/getH5Play/$roomId',
      data: body,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: await _signer.headers(
          referer: 'https://www.douyu.com/$roomId',
        ),
      ),
    );

    final map = _decodeJsonMap(response.data);
    _ensureSuccess(map, fallbackMessage: '斗鱼播放地址获取失败');
    return map;
  }

  Map<String, dynamic> _parseBetardRoom(Object? raw) {
    final map = _decodeJsonMap(raw);
    final room = map['room'];
    if (room is Map<String, dynamic>) {
      return room;
    }
    if (room is Map) {
      return Map<String, dynamic>.from(room);
    }
    return const {};
  }

  List<String> _parseCdns(Map<String, dynamic> data) {
    final result = <String>[];
    final list = data['cdnsWithName'] as List<dynamic>? ?? const [];
    for (final raw in list) {
      final map = raw as Map<String, dynamic>;
      final cdn = map['cdn']?.toString().trim() ?? '';
      if (cdn.isNotEmpty) {
        result.add(cdn);
      }
    }

    result.sort((left, right) {
      final leftScdn = left.startsWith('scdn');
      final rightScdn = right.startsWith('scdn');
      if (leftScdn == rightScdn) return 0;
      return leftScdn ? 1 : -1;
    });

    return result.toSet().toList();
  }

  List<String> _collectPlayUrls(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final urls = <String>[];

    final hlsUrl = data['hls_url']?.toString().trim() ?? '';
    final hlsLive = data['hls_live']?.toString().trim() ?? '';
    if (hlsUrl.isNotEmpty && hlsLive.isNotEmpty) {
      urls.add(_joinUrl(hlsUrl, _htmlUnescape(hlsLive)));
    }

    final rtmpUrl = data['rtmp_url']?.toString().trim() ?? '';
    final rtmpLive = data['rtmp_live']?.toString().trim() ?? '';
    if (rtmpUrl.isNotEmpty && rtmpLive.isNotEmpty) {
      urls.add(_joinUrl(rtmpUrl, _htmlUnescape(rtmpLive)));
    }

    return urls;
  }

  String _joinUrl(String base, String path) {
    return base.endsWith('/') ? '$base$path' : '$base/$path';
  }

  String _htmlUnescape(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  LiveRoomItem _roomItemFromDirectory(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    return LiveRoomItem(
      platform: id,
      roomId: map['rid']?.toString() ?? '',
      title: map['rn']?.toString() ?? '',
      cover: map['rs16']?.toString() ?? '',
      userName: map['nn']?.toString() ?? '',
      online: _toInt(map['ol']),
    );
  }

  LiveRoomItem _roomItemFromSearch(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    return LiveRoomItem(
      platform: id,
      roomId: map['rid']?.toString() ?? '',
      title: map['roomName']?.toString() ?? '',
      cover: map['roomSrc']?.toString() ?? '',
      userName: map['nickName']?.toString() ?? '',
      online: _parseHotNum(map['hot']?.toString() ?? '0'),
    );
  }

  bool _isLiveCard(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    return _toInt(map['type']) == 1;
  }

  int _parseHotNum(String value) {
    final text = value.trim();
    if (text.isEmpty) return 0;
    final isWan = text.contains('万');
    final parsed = double.tryParse(text.replaceAll('万', ''));
    if (parsed == null) return int.tryParse(text) ?? 0;
    return isWan ? (parsed * 10000).round() : parsed.round();
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _decodeJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    throw StateError('Douyu response format is invalid.');
  }

  void _ensureSuccess(
    Map<String, dynamic> json, {
    required String fallbackMessage,
  }) {
    if (_toInt(json['error']) == 0) return;
    throw StateError(json['msg']?.toString() ?? fallbackMessage);
  }
}
