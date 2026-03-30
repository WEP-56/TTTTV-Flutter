import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import 'bilibili_auth_service.dart';
import 'bilibili_danmaku_client.dart';
import 'bilibili_models.dart';
import 'bilibili_signer.dart';

class BilibiliLiveProvider extends LiveProvider {
  BilibiliLiveProvider({
    required Dio dio,
    required BilibiliSigner signer,
    required BilibiliAuthService authService,
    BilibiliDanmakuClient? danmakuClient,
  })  : _dio = dio,
        _signer = signer,
        _authService = authService,
        _danmakuClient = danmakuClient ?? BilibiliDanmakuClient();

  final Dio _dio;
  final BilibiliSigner _signer;
  final BilibiliAuthService _authService;
  final BilibiliDanmakuClient _danmakuClient;

  @override
  String get id => 'bilibili';

  @override
  String get name => 'Bilibili';

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

    try {
      final response = await _dio.get<Object?>(
        'https://api.bilibili.com/x/web-interface/nav',
        options: Options(headers: await _signer.headers()),
      );
      final json = response.data as Map<String, dynamic>? ?? const {};
      final data = json['data'] as Map<String, dynamic>? ?? const {};
      final isLogin = data['isLogin'] == true;
      final uname = data['uname']?.toString().trim() ?? '';
      if (isLogin) {
        return LiveAuthCheckResult(
          status: LiveAuthCheckStatus.success,
          message: uname.isEmpty ? 'Cookie 校验成功' : 'Cookie 校验成功，当前用户：$uname',
        );
      }
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.failure,
        message: 'Cookie 已失效或未登录',
      );
    } catch (error) {
      return LiveAuthCheckResult(
        status: LiveAuthCheckStatus.warning,
        message: 'Cookie 检查失败：$error',
      );
    }
  }

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    const baseUrl =
        'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea';
    final response = await _dio.get<Object?>(
      baseUrl,
      queryParameters: await _signer.getWbiSign(
        baseUrl,
        queryParameters: {
          'platform': 'web',
          'sort': 'online',
          'page_size': 30,
          'page': page,
        },
      ),
      options: Options(headers: await _signer.headers()),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final list = data['list'] as List<dynamic>? ?? const [];
    return list.map(_roomItemFromRecommend).toList();
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    final response = await _dio.get<Object?>(
      'https://api.bilibili.com/x/web-interface/search/type',
      queryParameters: {
        'context': '',
        'search_type': 'live',
        'cover_type': 'user_cover',
        'order': '',
        'keyword': keyword,
        'category_id': '',
        '__refresh__': '',
        '_extra': '',
        'highlight': 0,
        'single_column': 0,
        'page': page,
      },
      options: Options(headers: await _signer.headers()),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    final list = result['live_room'] as List<dynamic>? ?? const [];
    return list.map(_roomItemFromSearch).toList();
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    const baseUrl =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom';
    final response = await _dio.get<Object?>(
      baseUrl,
      queryParameters: await _signer.getWbiSign(
        baseUrl,
        queryParameters: {'room_id': roomId},
      ),
      options: Options(headers: await _signer.headers()),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final roomInfo = data['room_info'] as Map<String, dynamic>? ?? const {};
    final anchorInfo = data['anchor_info'] as Map<String, dynamic>? ?? const {};
    final baseInfo =
        anchorInfo['base_info'] as Map<String, dynamic>? ?? const {};

    return LiveRoomDetail(
      platform: id,
      roomId: roomId,
      title: roomInfo['title']?.toString() ?? '',
      cover: _normalizeImageUrl(roomInfo['cover']?.toString() ?? ''),
      userName: baseInfo['uname']?.toString() ?? '',
      userAvatar: _normalizeImageUrl(baseInfo['face']?.toString() ?? ''),
      online: _toInt(roomInfo['online']),
      introduction: roomInfo['description']?.toString(),
      notice: '',
      status: _toInt(roomInfo['live_status']) == 1,
      isRecord: false,
      url: 'https://live.bilibili.com/$roomId',
      showTime: null,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail) async {
    final response = await _getRoomPlayInfo(detail.roomId);
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final playInfo = data['playurl_info'] as Map<String, dynamic>? ?? const {};
    final playUrl = playInfo['playurl'] as Map<String, dynamic>? ?? const {};

    final descriptions = <String, String>{};
    final qnDesc = playUrl['g_qn_desc'] as List<dynamic>? ?? const [];
    for (final item in qnDesc) {
      final map = item as Map<String, dynamic>;
      descriptions[map['qn']?.toString() ?? ''] = map['desc']?.toString() ?? '';
    }

    final streamList = playUrl['stream'] as List<dynamic>? ?? const [];
    if (streamList.isEmpty) return const [];
    final firstStream = streamList.first as Map<String, dynamic>;
    final formats = firstStream['format'] as List<dynamic>? ?? const [];
    if (formats.isEmpty) return const [];
    final codecs =
        (formats.first as Map<String, dynamic>)['codec'] as List<dynamic>? ??
            const [];
    if (codecs.isEmpty) return const [];

    final qualities = <LivePlayQuality>[];
    final acceptQn =
        (codecs.first as Map<String, dynamic>)['accept_qn'] as List<dynamic>? ??
            const [];

    for (final item in acceptQn) {
      final id = item.toString();
      qualities.add(
        LivePlayQuality(
          id: id,
          name: descriptions[id] ?? id,
          sort: int.tryParse(id) ?? 0,
        ),
      );
    }

    qualities.sort((left, right) => right.sort.compareTo(left.sort));
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
    LiveRoomDetail detail,
    String qualityId,
  ) async {
    final response = await _getRoomPlayInfo(detail.roomId, qn: qualityId);
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final playInfo = data['playurl_info'] as Map<String, dynamic>? ?? const {};
    final playUrl = playInfo['playurl'] as Map<String, dynamic>? ?? const {};
    final streamList = playUrl['stream'] as List<dynamic>? ?? const [];

    final urls = <String>[];
    for (final stream in streamList) {
      final formats =
          (stream as Map<String, dynamic>)['format'] as List<dynamic>? ??
              const [];
      for (final format in formats) {
        final formatMap = format as Map<String, dynamic>;
        final formatName = formatMap['format_name']?.toString() ?? '';
        if (formatName == 'flv') continue;

        final codecs = formatMap['codec'] as List<dynamic>? ?? const [];
        for (final codec in codecs) {
          final codecMap = codec as Map<String, dynamic>;
          final baseUrl = codecMap['base_url']?.toString() ?? '';
          final urlInfo = codecMap['url_info'] as List<dynamic>? ?? const [];
          for (final item in urlInfo) {
            final map = item as Map<String, dynamic>;
            final host = map['host']?.toString() ?? '';
            final extra = map['extra']?.toString() ?? '';
            final url = '$host$baseUrl$extra';
            if (url.isNotEmpty) {
              urls.add(url);
            }
          }
        }
      }
    }

    urls.sort((left, right) {
      if (left.contains('mcdn') == right.contains('mcdn')) return 0;
      return left.contains('mcdn') ? 1 : -1;
    });

    return LivePlayUrl(
      urls: urls,
      headers: {
        'user-agent': BilibiliSigner.defaultUserAgent,
        'referer': BilibiliSigner.defaultReferer,
        if (await _authService.hasCookie())
          'cookie': await _signer.getMergedCookie(),
      },
      urlType: 'hls',
    );
  }

  @override
  Stream<LiveMessage> createDanmakuStream(LiveRoomDetail detail) {
    return Stream.fromFuture(_buildDanmakuArgs(detail.roomId)).asyncExpand(
      (args) => _danmakuClient.connect(args),
    );
  }

  @override
  String resolveImageUrl(String url) => _normalizeImageUrl(url);

  Future<Map<String, dynamic>> _getRoomPlayInfo(
    String roomId, {
    String? qn,
  }) async {
    final response = await _dio.get<Object?>(
      'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
      queryParameters: {
        'room_id': roomId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0',
        'platform': 'html5',
        'dolby': '5',
        if (qn != null) 'qn': qn,
      },
      options: Options(headers: await _signer.headers()),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<BilibiliDanmakuArgs> _buildDanmakuArgs(String roomId) async {
    const infoBaseUrl =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo';
    final response = await _dio.get<Object?>(
      infoBaseUrl,
      queryParameters: await _signer.getWbiSign(
        infoBaseUrl,
        queryParameters: {'id': roomId},
      ),
      options: Options(headers: await _signer.headers()),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final hostList = data['host_list'] as List<dynamic>? ?? const [];
    final serverHost = hostList.isNotEmpty
        ? (hostList.first as Map<String, dynamic>)['host']?.toString() ?? ''
        : 'broadcastlv.chat.bilibili.com';

    return BilibiliDanmakuArgs(
      roomId: int.tryParse(roomId) ?? 0,
      token: data['token']?.toString() ?? '',
      buvid: await _signer.getBuvid(),
      serverHost: serverHost,
      uid: await _authService.getUserId(),
      cookie: await _signer.getMergedCookie(),
    );
  }

  LiveRoomItem _roomItemFromRecommend(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    return LiveRoomItem(
      platform: id,
      roomId: map['roomid']?.toString() ?? '',
      title: _stripHtml(map['title']?.toString() ?? ''),
      cover: _normalizeImageUrl(map['cover']?.toString() ?? ''),
      userName: map['uname']?.toString() ?? '',
      online: _toInt(map['online']),
    );
  }

  LiveRoomItem _roomItemFromSearch(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    return LiveRoomItem(
      platform: id,
      roomId: map['roomid']?.toString() ?? '',
      title: _stripHtml(map['title']?.toString() ?? ''),
      cover: _normalizeImageUrl(map['cover']?.toString() ?? ''),
      userName: _stripHtml(map['uname']?.toString() ?? ''),
      online: _toInt(map['online']),
    );
  }

  String _stripHtml(String value) {
    return value.replaceAll(RegExp(r'<.*?>'), '');
  }

  String _normalizeImageUrl(String value) {
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    return value;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
