import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import 'douyin_auth_service.dart';
import 'douyin_danmaku_client.dart';
import 'douyin_models.dart';
import 'douyin_signer.dart';

class DouyinLiveProvider extends LiveProvider {
  DouyinLiveProvider({
    required Dio dio,
    required DouyinSigner signer,
    required DouyinAuthService authService,
    DouyinDanmakuClient? danmakuClient,
  })  : _dio = dio,
        _signer = signer,
        _authService = authService,
        _danmakuClient = danmakuClient ?? const DouyinDanmakuClient();

  final Dio _dio;
  final DouyinSigner _signer;
  final DouyinAuthService _authService;
  final DouyinDanmakuClient _danmakuClient;

  @override
  String get id => 'douyin';

  @override
  String get name => '抖音';

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
    final hasTtwid = normalized.contains('ttwid=');
    final hasNonce = normalized.contains('__ac_nonce=');
    final hasMsToken = normalized.contains('mstoken=');
    final matchedCount =
        [hasTtwid, hasNonce, hasMsToken].where((item) => item).length;

    if (matchedCount >= 2) {
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.warning,
        message: '基础检查通过，已包含抖音请求关键字段；当前未接入强校验接口。',
      );
    }

    return const LiveAuthCheckResult(
      status: LiveAuthCheckStatus.failure,
      message: 'Cookie 缺少关键字段，可能无法正常请求。',
    );
  }

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    return _fetchPartitionRooms(
      page: page,
      partition: '720',
      partitionType: '1',
    );
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final response = await _dio.get<Object?>(
      'https://www.douyin.com/aweme/v1/web/live/search/',
      queryParameters: {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'search_channel': 'aweme_live',
        'keyword': trimmed,
        'search_source': 'switch_tab',
        'query_correct_type': '1',
        'is_filter_search': '0',
        'from_group_id': '',
        'offset': (page - 1) * 10,
        'count': 10,
        'pc_client_type': '1',
        'version_code': '170400',
        'version_name': '17.4.0',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
        'browser_online': 'true',
        'engine_name': 'Blink',
        'engine_version': '125.0.0.0',
        'os_name': 'Windows',
        'os_version': '10',
        'cpu_core_num': '12',
        'device_memory': '8',
        'platform': 'PC',
        'downlink': '10',
        'effective_type': '4g',
        'round_trip_time': '100',
      },
      options: Options(
        headers: await _signer.searchHeaders(trimmed),
      ),
    );

    final json = _decodeJsonMap(response.data);
    final list = json['data'] as List<dynamic>? ?? const [];
    final rooms = <LiveRoomItem>[];

    for (final raw in list) {
      final item = _asMap(raw);
      final lives = _asMap(item['lives']);
      final rawData = lives['rawdata']?.toString() ?? '';
      if (rawData.trim().isEmpty) continue;

      final decoded = jsonDecode(rawData);
      final root = _asMap(decoded);
      final room =
          _asMap(root['room']).isNotEmpty ? _asMap(root['room']) : root;
      final owner = _asMap(room['owner']).isNotEmpty
          ? _asMap(room['owner'])
          : _asMap(root['owner']);

      final webRid = owner['web_rid']?.toString().trim() ?? '';
      if (webRid.isEmpty) continue;

      final cover = _firstUrl(room['cover']) ?? _firstUrl(root['cover']) ?? '';
      final stats = _asMap(room['room_view_stats']).isNotEmpty
          ? _asMap(room['room_view_stats'])
          : _asMap(root['stats']);

      rooms.add(
        LiveRoomItem(
          platform: id,
          roomId: webRid,
          title: _nonEmpty(
            room['title']?.toString(),
            root['title']?.toString(),
          ),
          cover: cover,
          userName: owner['nickname']?.toString() ?? '',
          online: _parseOnlineCount(
            stats['display_value'] ?? stats['total_user_str'],
          ),
        ),
      );
    }

    return rooms;
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    final profile = await _loadRoomProfile(roomId);
    return profile.toDetail(id);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail) async {
    final profile = await _loadRoomProfile(detail.roomId);
    if (!profile.status) {
      throw StateError('抖音直播间未开播');
    }
    return profile.qualities.map((item) => item.toPlayQuality()).toList();
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
    LiveRoomDetail detail,
    String qualityId,
  ) async {
    final profile = await _loadRoomProfile(detail.roomId);
    if (!profile.status) {
      throw StateError('抖音直播间未开播');
    }

    DouyinQualityOption? quality;
    for (final item in profile.qualities) {
      if (item.id == qualityId) {
        quality = item;
        break;
      }
    }
    quality ??= profile.qualities.isNotEmpty ? profile.qualities.first : null;
    if (quality == null || quality.urls.isEmpty) {
      throw StateError('抖音未获取到播放地址');
    }

    return LivePlayUrl(
      urls: quality.urls,
      headers: await _signer.playHeaders(referer: detail.url),
      urlType: 'auto',
    );
  }

  @override
  Stream<LiveMessage> createDanmakuStream(LiveRoomDetail detail) {
    return Stream.fromFuture(
      _buildDanmakuArgs(detail.roomId),
    ).asyncExpand(_danmakuClient.connect);
  }

  @override
  String resolveImageUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return url;
  }

  Future<List<LiveRoomItem>> _fetchPartitionRooms({
    required int page,
    required String partition,
    required String partitionType,
  }) async {
    final uri = _signer.signUrl(
      'https://live.douyin.com/webcast/web/partition/detail/room/v2/',
      queryParameters: {
        'aid': '6383',
        'app_name': 'douyin_web',
        'live_id': '1',
        'device_platform': 'web',
        'language': 'zh-CN',
        'enter_from': 'link_share',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
        'browser_online': 'true',
        'count': 15,
        'offset': (page - 1) * 15,
        'partition': partition,
        'partition_type': partitionType,
        'req_from': '2',
      },
    );

    final response = await _dio.get<Object?>(
      uri.toString(),
      options: Options(headers: await _signer.headers()),
    );

    final json = _decodeJsonMap(response.data);
    final data = _asMap(json['data']);
    final list = data['data'] as List<dynamic>? ?? const [];

    return list
        .map((raw) {
          final item = _asMap(raw);
          final room = _asMap(item['room']);
          final owner = _asMap(room['owner']);
          return LiveRoomItem(
            platform: id,
            roomId: item['web_rid']?.toString() ?? '',
            title: room['title']?.toString() ?? '',
            cover: _firstUrl(room['cover']) ?? '',
            userName: owner['nickname']?.toString() ?? '',
            online: _parseOnlineCount(
              _asMap(room['room_view_stats'])['display_value'],
            ),
          );
        })
        .where((room) => room.roomId.trim().isNotEmpty)
        .toList();
  }

  Future<DouyinRoomProfile> _loadRoomProfile(String input) async {
    final roomId = input.trim();
    if (roomId.isEmpty) {
      throw StateError('抖音房间号不能为空');
    }

    try {
      return await _loadRoomProfileByWebRid(roomId);
    } catch (_) {
      return _loadRoomProfileByRoomId(roomId);
    }
  }

  Future<DouyinRoomProfile> _loadRoomProfileByWebRid(String webRid) async {
    try {
      final data = await _fetchRoomDataByWebRid(webRid);
      final roomList = data['data'] as List<dynamic>? ?? const [];
      if (roomList.isEmpty) {
        throw StateError('抖音房间信息为空');
      }
      return _profileFromEnterResponse(
        requestedWebRid: webRid,
        roomData: _asMap(roomList.first),
        userData: _asMap(data['user']),
      );
    } catch (_) {
      return _loadRoomProfileByHtml(webRid);
    }
  }

  Future<DouyinRoomProfile> _loadRoomProfileByRoomId(String roomId) async {
    final response = await _dio.get<Object?>(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        'type_id': 0,
        'live_id': 1,
        'room_id': roomId,
        'sec_user_id': '',
        'version_code': '99.99.99',
        'app_id': 6383,
      },
      options: Options(
        headers: await _signer.headers(
          referer: '${DouyinSigner.defaultReferer}/$roomId',
        ),
      ),
    );

    final json = _decodeJsonMap(response.data);
    final data = _asMap(json['data']);
    final room = _asMap(data['room']);
    if (room.isEmpty) {
      throw StateError('抖音房间信息为空');
    }

    final owner = _asMap(room['owner']);
    final webRid = owner['web_rid']?.toString().trim() ?? '';
    final status = _toInt(room['status']) == 2;
    if (!status && webRid.isNotEmpty && webRid != roomId) {
      return _loadRoomProfileByWebRid(webRid);
    }

    return _profileFromRoomData(
      webRid: webRid.isNotEmpty ? webRid : roomId,
      roomData: room,
      fallbackUser: owner,
      introduction: owner['signature']?.toString(),
    );
  }

  Future<DouyinRoomProfile> _loadRoomProfileByHtml(String webRid) async {
    final cookie = await _signer.getRequestCookie(
      refreshWebCookie: true,
      webRid: webRid,
    );
    final response = await _dio.get<String>(
      '${DouyinSigner.defaultReferer}/$webRid',
      options: Options(
        responseType: ResponseType.plain,
        headers: await _signer.headers(
          referer: DouyinSigner.defaultReferer,
          cookie: cookie,
        ),
      ),
    );

    final html = response.data ?? '';
    final match =
        RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n').firstMatch(html);
    final encoded = match?.group(0) ?? '';
    if (encoded.isEmpty) {
      throw StateError('抖音房间网页解析失败');
    }

    final normalized = encoded
        .trim()
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', '\\')
        .replaceAll(']\\n', '');
    final state = _asMap(_asMap(jsonDecode(normalized))['state']);
    final roomStore = _asMap(state['roomStore']);
    final roomInfo = _asMap(_asMap(roomStore['roomInfo'])['room']);
    if (roomInfo.isEmpty) {
      throw StateError('抖音房间网页解析失败');
    }

    final owner = _asMap(roomInfo['owner']);
    final anchor = _asMap(_asMap(roomStore['roomInfo'])['anchor']);
    final status = _toInt(roomInfo['status']) == 2;
    final fallbackUser = status ? owner : anchor;

    return _profileFromRoomData(
      webRid: webRid,
      roomData: roomInfo,
      fallbackUser: fallbackUser,
      introduction: _nonEmpty(
        owner['signature']?.toString(),
        roomInfo['title']?.toString(),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchRoomDataByWebRid(String webRid) async {
    final uri = _signer.signUrl(
      'https://live.douyin.com/webcast/room/web/enter/',
      queryParameters: {
        'aid': '6383',
        'app_name': 'douyin_web',
        'live_id': '1',
        'device_platform': 'web',
        'enter_from': 'web_live',
        'web_rid': webRid,
        'room_id_str': '',
        'enter_source': '',
        'Room-Enter-User-Login-Ab': '0',
        'is_need_double_stream': 'false',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
      },
    );

    final response = await _dio.get<Object?>(
      uri.toString(),
      options: Options(
        headers: await _signer.headers(
          referer: '${DouyinSigner.defaultReferer}/$webRid',
        ),
      ),
    );

    final json = _decodeJsonMap(response.data);
    return _asMap(json['data']);
  }

  Future<DouyinDanmakuArgs> _buildDanmakuArgs(String webRid) async {
    final normalizedWebRid = webRid.trim();
    if (normalizedWebRid.isEmpty) {
      throw StateError('抖音弹幕房间号不能为空');
    }

    var actualRoomId = '';
    try {
      final data = await _fetchRoomDataByWebRid(normalizedWebRid);
      final roomList = data['data'] as List<dynamic>? ?? const [];
      if (roomList.isNotEmpty) {
        actualRoomId = _asMap(roomList.first)['id_str']?.toString() ?? '';
      }
    } catch (_) {}

    if (actualRoomId.trim().isEmpty) {
      final cookie = await _signer.getRequestCookie(
        refreshWebCookie: true,
        webRid: normalizedWebRid,
      );
      final response = await _dio.get<String>(
        '${DouyinSigner.defaultReferer}/$normalizedWebRid',
        options: Options(
          responseType: ResponseType.plain,
          headers: await _signer.headers(
            referer: DouyinSigner.defaultReferer,
            cookie: cookie,
          ),
        ),
      );

      final html = response.data ?? '';
      final match =
          RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n').firstMatch(html);
      final encoded = match?.group(0) ?? '';
      if (encoded.isNotEmpty) {
        final normalized = encoded
            .trim()
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', '\\')
            .replaceAll(']\\n', '');
        final state = _asMap(_asMap(jsonDecode(normalized))['state']);
        final roomInfo = _asMap(
          _asMap(_asMap(_asMap(state['roomStore'])['roomInfo'])['room']),
        );
        actualRoomId = roomInfo['id_str']?.toString() ?? '';
        final htmlUserId =
            _asMap(_asMap(state['userStore'])['odin'])['user_unique_id']
                    ?.toString()
                    .trim() ??
                '';
        if (actualRoomId.trim().isNotEmpty && htmlUserId.isNotEmpty) {
          return DouyinDanmakuArgs(
            webRid: normalizedWebRid,
            roomId: actualRoomId,
            userId: htmlUserId,
            cookie: cookie,
            signature: _signer.getWebSocketSignature(actualRoomId, htmlUserId),
          );
        }
      }
    }

    if (actualRoomId.trim().isEmpty) {
      throw StateError('抖音弹幕房间ID解析失败');
    }

    final userId = _generateRandomNumber(12);
    final cookie = await _signer.getRequestCookie(
      refreshWebCookie: true,
      webRid: normalizedWebRid,
    );
    final signature = _signer.getWebSocketSignature(actualRoomId, userId);

    return DouyinDanmakuArgs(
      webRid: normalizedWebRid,
      roomId: actualRoomId,
      userId: userId,
      cookie: cookie,
      signature: signature,
    );
  }

  DouyinRoomProfile _profileFromEnterResponse({
    required String requestedWebRid,
    required Map<String, dynamic> roomData,
    required Map<String, dynamic> userData,
  }) {
    final status = _toInt(roomData['status']) == 2;
    final owner = _asMap(roomData['owner']);
    return _profileFromRoomData(
      webRid: requestedWebRid,
      roomData: roomData,
      fallbackUser: status ? owner : userData,
      introduction: owner['signature']?.toString(),
    );
  }

  DouyinRoomProfile _profileFromRoomData({
    required String webRid,
    required Map<String, dynamic> roomData,
    required Map<String, dynamic> fallbackUser,
    String? introduction,
  }) {
    final status = _toInt(roomData['status']) == 2;
    final owner = _asMap(roomData['owner']);
    final activeUser = status ? owner : fallbackUser;
    final resolvedIntroduction = (introduction ?? '').trim();

    return DouyinRoomProfile(
      roomId: webRid,
      title: roomData['title']?.toString() ?? '',
      cover: status ? (_firstUrl(roomData['cover']) ?? '') : '',
      userName: activeUser['nickname']?.toString() ?? '',
      userAvatar: _firstUrl(activeUser['avatar_thumb']) ?? '',
      online: status
          ? _parseOnlineCount(
              _asMap(roomData['room_view_stats'])['display_value'],
            )
          : 0,
      status: status,
      isRecord: false,
      url: '${DouyinSigner.defaultReferer}/$webRid',
      introduction: resolvedIntroduction.isEmpty ? null : resolvedIntroduction,
      notice: null,
      qualities:
          status ? _parseQualities(_asMap(roomData['stream_url'])) : const [],
    );
  }

  List<DouyinQualityOption> _parseQualities(Map<String, dynamic> streamUrl) {
    if (streamUrl.isEmpty) return const [];

    final pullData = _asMap(
      _asMap(_asMap(streamUrl['live_core_sdk_data'])['pull_data']),
    );
    final qualities = _asList(
      _asMap(pullData['options'])['qualities'],
    );
    final streamDataRaw = pullData['stream_data']?.toString() ?? '';

    final parsed = <DouyinQualityOption>[];
    if (streamDataRaw.trimLeft().startsWith('{')) {
      final streamData = _asMap(_asMap(jsonDecode(streamDataRaw))['data']);
      for (final raw in qualities) {
        final quality = _asMap(raw);
        final sdkKey = quality['sdk_key']?.toString().trim();
        final key = (sdkKey?.isNotEmpty ?? false)
            ? sdkKey!
            : _toInt(quality['level']).toString();
        final stream = _asMap(streamData[key]);
        final main = _asMap(stream['main']);
        final urls = <String>[
          if ((main['flv']?.toString().trim() ?? '').isNotEmpty)
            main['flv'].toString().trim(),
          if ((main['hls']?.toString().trim() ?? '').isNotEmpty)
            main['hls'].toString().trim(),
        ];
        if (urls.isEmpty) continue;
        parsed.add(
          DouyinQualityOption(
            id: key,
            name: quality['name']?.toString() ?? key,
            sort: _toInt(quality['level']),
            urls: urls,
          ),
        );
      }
    } else {
      final flvList = _asMap(streamUrl['flv_pull_url'])
          .values
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
      final hlsList = _asMap(streamUrl['hls_pull_url_map'])
          .values
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();

      for (final raw in qualities) {
        final quality = _asMap(raw);
        final level = _toInt(quality['level']);
        final urls = <String>[];
        final flvIndex = flvList.length - level;
        if (flvIndex >= 0 && flvIndex < flvList.length) {
          urls.add(flvList[flvIndex]);
        }
        final hlsIndex = hlsList.length - level;
        if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
          urls.add(hlsList[hlsIndex]);
        }
        if (urls.isEmpty) continue;
        parsed.add(
          DouyinQualityOption(
            id: quality['sdk_key']?.toString().trim().isNotEmpty == true
                ? quality['sdk_key'].toString().trim()
                : level.toString(),
            name: quality['name']?.toString() ?? level.toString(),
            sort: level,
            urls: urls,
          ),
        );
      }
    }

    parsed.sort((left, right) => right.sort.compareTo(left.sort));
    return parsed;
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
    throw StateError('Douyin response format is invalid.');
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

  List<dynamic> _asList(Object? value) {
    return value as List<dynamic>? ?? const [];
  }

  String? _firstUrl(Object? raw) {
    final map = _asMap(raw);
    final list = map['url_list'] as List<dynamic>? ?? const [];
    if (list.isEmpty) return null;
    return list.first?.toString();
  }

  int _parseOnlineCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    final text = value?.toString().trim().replaceAll(',', '') ?? '';
    if (text.isEmpty) return 0;

    if (text.contains('亿')) {
      final parsed = double.tryParse(text.replaceAll('亿', ''));
      if (parsed != null) return (parsed * 100000000).round();
    }
    if (text.contains('万')) {
      final parsed = double.tryParse(text.replaceAll('万', ''));
      if (parsed != null) return (parsed * 10000).round();
    }
    if (text.toLowerCase().endsWith('w')) {
      final parsed = double.tryParse(text.substring(0, text.length - 1));
      if (parsed != null) return (parsed * 10000).round();
    }

    return int.tryParse(text) ?? 0;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _nonEmpty(String? first, [String? second]) {
    for (final value in [first, second]) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  String _generateRandomNumber(int length) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index += 1) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}
