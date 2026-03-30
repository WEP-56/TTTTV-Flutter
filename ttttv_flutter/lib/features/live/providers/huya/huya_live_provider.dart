import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import 'huya_auth_service.dart';
import 'huya_danmaku_client.dart';
import 'huya_models.dart';
import 'huya_parser.dart';

class HuyaLiveProvider extends LiveProvider {
  HuyaLiveProvider({
    required Dio dio,
    required HuyaAuthService authService,
    HuyaParser? parser,
    HuyaDanmakuClient? danmakuClient,
  })  : _dio = dio,
        _authService = authService,
        _parser = parser ?? const HuyaParser(),
        _danmakuClient = danmakuClient ?? HuyaDanmakuClient();

  final Dio _dio;
  final HuyaAuthService _authService;
  final HuyaParser _parser;
  final HuyaDanmakuClient _danmakuClient;

  @override
  String get id => 'huya';

  @override
  String get name => '虎牙';

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
    final hasYyuid = normalized.contains('yyuid=');
    final hasUdbUid = normalized.contains('udb_uid=');
    final hasHuyaWebUid = normalized.contains('huya_web_uid=');

    if ((hasYyuid || hasUdbUid) && hasHuyaWebUid) {
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.warning,
        message: '基础检查通过，已包含虎牙登录关键字段；当前未接入强校验接口。',
      );
    }

    return const LiveAuthCheckResult(
      status: LiveAuthCheckStatus.failure,
      message: 'Cookie 缺少关键字段，可能不是完整的虎牙登录 Cookie。',
    );
  }

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    final response = await _dio.get<Object?>(
      'https://www.huya.com/cache.php',
      queryParameters: {
        'm': 'LiveList',
        'do': 'getLiveListByPage',
        'tagAll': 0,
        'page': page,
      },
      options: Options(
        headers: await _headers(
          referer: 'https://www.huya.com/',
          origin: 'https://www.huya.com',
        ),
      ),
    );

    final map = _decodeJsonMap(response.data);
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final list = data['datas'] as List<dynamic>? ?? const [];
    return list.map(_roomItemFromRecommend).toList();
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    final response = await _dio.get<Object?>(
      'https://search.cdn.huya.com/',
      queryParameters: {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': keyword,
        'uid': 0,
        'v': 4,
        'typ': -5,
        'livestate': 0,
        'rows': 20,
        'start': (page - 1) * 20,
      },
      options: Options(
        headers: await _headers(referer: 'https://www.huya.com/'),
      ),
    );

    final map = _decodeJsonMap(response.data);
    final responseMap = map['response'] as Map<String, dynamic>? ?? const {};
    final queryList = (responseMap['3'] as Map<String, dynamic>? ??
            const {})['docs'] as List<dynamic>? ??
        const [];
    final responseList = (responseMap['1'] as Map<String, dynamic>? ??
            const {})['docs'] as List<dynamic>? ??
        const [];

    return queryList
        .map((item) => _roomItemFromSearch(item, responseList))
        .toList();
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    final profile = await _fetchRoomProfile(roomId);
    return profile.toDetail(id);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail) async {
    if (!detail.status) {
      throw StateError('直播间未开播');
    }

    final profile = await _fetchRoomProfile(detail.roomId);
    final qualities = profile.bitRates.map((item) => item.toQuality()).toList();
    if (qualities.isEmpty) {
      return [
        LivePlayQuality(id: '0', name: '原画', sort: 1 << 30),
        LivePlayQuality(id: '2000', name: '高清', sort: 2000),
      ];
    }

    qualities.sort((left, right) => right.sort.compareTo(left.sort));
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
    LiveRoomDetail detail,
    String qualityId,
  ) async {
    if (!detail.status) {
      throw StateError('直播间未开播');
    }

    final profile = await _fetchRoomProfile(detail.roomId);
    if (profile.streamLines.isEmpty) {
      throw StateError('虎牙未获取到播放地址');
    }
    return _parser.buildPlayUrl(profile.streamLines, qualityId);
  }

  @override
  Stream<LiveMessage> createDanmakuStream(LiveRoomDetail detail) {
    return Stream.fromFuture(_buildDanmakuArgs(detail.roomId)).asyncExpand(
      _danmakuClient.connect,
    );
  }

  @override
  String resolveImageUrl(String url) => _parser.normalizeImageUrl(url);

  Future<HuyaDanmakuArgs> _buildDanmakuArgs(String roomId) async {
    final profile = await _fetchRoomProfile(roomId);
    return HuyaDanmakuArgs(
      ayyuid: profile.ayyuid,
      topSid: profile.topSid,
      subSid: profile.subSid,
    );
  }

  Future<HuyaRoomProfile> _fetchRoomProfile(String roomId) async {
    final response = await _dio.get<Object?>(
      'https://mp.huya.com/cache.php',
      queryParameters: {
        'm': 'Live',
        'do': 'profileRoom',
        'roomid': roomId,
        'showSecret': 1,
      },
      options: Options(
        headers: await _headers(
          referer: 'https://www.huya.com/$roomId',
          origin: 'https://www.huya.com',
        ),
      ),
    );

    final map = _decodeJsonMap(response.data);
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return _parseRoomProfile(roomId, data);
  }

  Future<Map<String, String>> _headers({
    String? referer,
    String? origin,
  }) async {
    final headers = <String, String>{
      'user-agent': HuyaParser.roomUserAgent,
      if (referer != null) 'referer': referer,
      if (origin != null) 'origin': origin,
    };

    final cookie = await _authService.getCookie();
    if (cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
    return headers;
  }

  HuyaRoomProfile _parseRoomProfile(
    String requestedRoomId,
    Map<String, dynamic> data,
  ) {
    final liveData = _asMap(data['liveData']);
    final profileInfo = _asMap(data['profileInfo']);
    final stream = _asMap(data['stream']);
    final roomId = liveData['profileRoom']?.toString() ?? requestedRoomId;
    final liveStatus = liveData['liveStatus']?.toString() ??
        data['liveStatus']?.toString() ??
        '';
    final isRecord = liveStatus == 'REPLAY';
    final status = liveStatus == 'ON' || isRecord;

    var topSid = 0;
    var subSid = 0;
    final streamLines = <HuyaStreamLine>[];
    final baseStreamInfoList =
        stream['baseSteamInfoList'] as List<dynamic>? ?? const [];

    final flv = _asMap(stream['flv']);
    final hls = _asMap(stream['hls']);
    _collectStreamLines(
      items: flv['multiLine'] as List<dynamic>? ?? const [],
      baseStreamInfoList: baseStreamInfoList,
      type: HuyaLineType.flv,
      sink: streamLines,
      updateTopSid: (value) => topSid = value,
      updateSubSid: (value) => subSid = value,
    );
    _collectStreamLines(
      items: hls['multiLine'] as List<dynamic>? ?? const [],
      baseStreamInfoList: baseStreamInfoList,
      type: HuyaLineType.hls,
      sink: streamLines,
      updateTopSid: (value) => topSid = value,
      updateSubSid: (value) => subSid = value,
    );

    final bitRates = _parseBitRates(liveData, flv);
    final title = _firstNonEmpty(
      liveData['introduction']?.toString(),
      liveData['roomName']?.toString(),
    );

    return HuyaRoomProfile(
      roomId: roomId,
      title: title,
      cover:
          _parser.normalizeImageUrl(liveData['screenshot']?.toString() ?? ''),
      userName: profileInfo['nick']?.toString() ?? '',
      userAvatar:
          _parser.normalizeImageUrl(profileInfo['avatar180']?.toString() ?? ''),
      online: _toInt(liveData['userCount']),
      introduction: _emptyToNull(liveData['introduction']?.toString()),
      notice: _emptyToNull(data['welcomeText']?.toString()),
      status: status,
      isRecord: isRecord,
      url: 'https://www.huya.com/$roomId',
      streamLines: streamLines,
      bitRates: bitRates,
      ayyuid: _toInt(profileInfo['yyid']),
      topSid: topSid,
      subSid: subSid,
    );
  }

  void _collectStreamLines({
    required List<dynamic> items,
    required List<dynamic> baseStreamInfoList,
    required HuyaLineType type,
    required List<HuyaStreamLine> sink,
    required void Function(int value) updateTopSid,
    required void Function(int value) updateSubSid,
  }) {
    for (final raw in items) {
      final item = _asMap(raw);
      final currentStream = _findStreamInfo(baseStreamInfoList, item);
      if (currentStream.isEmpty) continue;

      final lineUrl = type == HuyaLineType.flv
          ? currentStream['sFlvUrl']?.toString() ?? ''
          : currentStream['sHlsUrl']?.toString() ?? '';
      final antiCode = type == HuyaLineType.flv
          ? currentStream['sFlvAntiCode']?.toString() ?? ''
          : currentStream['sHlsAntiCode']?.toString() ?? '';
      final streamName = currentStream['sStreamName']?.toString() ?? '';
      if (lineUrl.isEmpty || antiCode.isEmpty || streamName.isEmpty) {
        continue;
      }

      final currentTopSid = _toInt(currentStream['lChannelId']);
      final currentSubSid = _toInt(currentStream['lSubChannelId']);
      if (currentTopSid > 0) {
        updateTopSid(currentTopSid);
      }
      if (currentSubSid > 0) {
        updateSubSid(currentSubSid);
      }

      sink.add(
        HuyaStreamLine(
          baseUrl: lineUrl,
          streamName: streamName,
          antiCode: antiCode,
          cdnType: _firstNonEmpty(
            item['sCdnType']?.toString(),
            item['cdnType']?.toString(),
            currentStream['sCdnType']?.toString(),
          ),
          type: type,
          presenterUid: currentTopSid > 0
              ? currentTopSid
              : _parsePresenterUid(streamName),
        ),
      );
    }
  }

  Map<String, dynamic> _findStreamInfo(
    List<dynamic> baseStreamInfoList,
    Map<String, dynamic> item,
  ) {
    final cdnType = _firstNonEmpty(
      item['cdnType']?.toString(),
      item['sCdnType']?.toString(),
    );
    for (final raw in baseStreamInfoList) {
      final map = _asMap(raw);
      if (map['sCdnType']?.toString() == cdnType) {
        return map;
      }
    }
    return const {};
  }

  List<HuyaBitRate> _parseBitRates(
    Map<String, dynamic> liveData,
    Map<String, dynamic> flv,
  ) {
    dynamic rawList;
    final bitRateInfo = liveData['bitRateInfo'];
    if (bitRateInfo is String && bitRateInfo.trim().isNotEmpty) {
      rawList = jsonDecode(bitRateInfo);
    } else {
      rawList = flv['rateArray'];
    }

    final list = rawList as List<dynamic>? ?? const [];
    final result = <HuyaBitRate>[];
    final seen = <String>{};
    for (final raw in list) {
      final map = _asMap(raw);
      final name = _firstNonEmpty(
        map['sDisplayName']?.toString(),
        map['name']?.toString(),
        '原画',
      );
      if (name.contains('HDR') || !seen.add(name)) {
        continue;
      }
      result.add(
        HuyaBitRate(
          name: name,
          bitRate: _toInt(map['iBitRate'] ?? map['bitRate']),
        ),
      );
    }
    return result;
  }

  LiveRoomItem _roomItemFromRecommend(dynamic raw) {
    final map = _asMap(raw);
    return LiveRoomItem(
      platform: id,
      roomId: _firstNonEmpty(
        map['profileRoom']?.toString(),
        map['privateHost']?.toString(),
      ),
      title: _firstNonEmpty(
        map['introduction']?.toString(),
        map['roomName']?.toString(),
      ),
      cover: _coverUrl(map['screenshot']?.toString() ?? ''),
      userName: map['nick']?.toString() ?? '',
      online: _toInt(map['totalCount']),
    );
  }

  LiveRoomItem _roomItemFromSearch(
    dynamic raw,
    List<dynamic> responseList,
  ) {
    final map = _asMap(raw);
    return LiveRoomItem(
      platform: id,
      roomId: _findRoomId(
            responseList,
            _toInt(map['uid']),
            _toInt(map['yyid']),
          ) ??
          (map['room_id']?.toString() ?? ''),
      title: _firstNonEmpty(
        map['game_introduction']?.toString(),
        map['game_roomName']?.toString(),
      ),
      cover: _coverUrl(map['game_screenshot']?.toString() ?? ''),
      userName: map['game_nick']?.toString() ?? '',
      online: _toInt(map['game_total_count']),
    );
  }

  String? _findRoomId(
    List<dynamic> items,
    int targetUid,
    int targetYyid,
  ) {
    for (final raw in items) {
      final map = _asMap(raw);
      if (_toInt(map['uid']) == targetUid &&
          _toInt(map['yyid']) == targetYyid) {
        final roomId = map['room_id']?.toString();
        if (roomId != null && roomId.isNotEmpty) {
          return roomId;
        }
      }
    }
    return null;
  }

  String _coverUrl(String value) {
    final normalized = _parser.normalizeImageUrl(value);
    return normalized.contains('?')
        ? normalized
        : '$normalized?x-oss-process=style/w338_h190&';
  }

  int _parsePresenterUid(String streamName) {
    final dashIndex = streamName.indexOf('-');
    final prefix =
        dashIndex >= 0 ? streamName.substring(0, dashIndex) : streamName;
    return int.tryParse(prefix) ?? 0;
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
    throw StateError('Huya response format is invalid.');
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _firstNonEmpty(
    String? first, [
    String? second,
    String? third,
  ]) {
    for (final value in [first, second, third]) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
