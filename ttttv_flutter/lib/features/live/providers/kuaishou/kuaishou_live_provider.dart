import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import 'kuaishou_models.dart';
import 'kuaishou_parser.dart';

class KuaishouLiveProvider extends LiveProvider {
  KuaishouLiveProvider({
    required Dio dio,
    KuaishouParser? parser,
  })  : _dio = dio,
        _parser = parser ?? const KuaishouParser();

  final Dio _dio;
  final KuaishouParser _parser;

  @override
  String get id => 'kuaishou';

  @override
  String get name => '快手';

  @override
  bool get supportsSearch => false;

  @override
  bool get supportsCategories => true;

  @override
  bool get supportsDanmaku => false;

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    final response = await _dio.get<Object?>(
      'https://live.kuaishou.com/live_api/home/list',
      options: _parser.options(referer: 'https://live.kuaishou.com/'),
    );

    final map = _parser.decodeJsonMap(response.data);
    final groups =
        (_parser.asMap(map['data']))['list'] as List<dynamic>? ?? const [];
    final items = <LiveRoomItem>[];

    for (final group in groups) {
      final groupMap = _parser.asMap(group);
      final gameLiveInfo =
          groupMap['gameLiveInfo'] as List<dynamic>? ?? const [];
      for (final game in gameLiveInfo) {
        final gameMap = _parser.asMap(game);
        final liveInfo = gameMap['liveInfo'] as List<dynamic>? ?? const [];
        for (final room in liveInfo) {
          items.add(_parser.roomItemFromRecommend(room));
        }
      }
    }

    return items;
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    return const [];
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
    if (profile.qualities.isEmpty) {
      throw StateError('快手未获取到播放清晰度');
    }
    return profile.qualities.map((item) => item.toPlayQuality()).toList();
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
    if (profile.qualities.isEmpty) {
      throw StateError('快手未获取到播放地址');
    }
    return _parser.buildPlayUrl(profile, qualityId);
  }

  Future<KuaishouRoomProfile> _fetchRoomProfile(String roomId) async {
    final response = await _dio.get<String>(
      'https://live.kuaishou.com/u/$roomId',
      options: Options(
        responseType: ResponseType.plain,
        headers: _parser.headers(
          referer: 'https://live.kuaishou.com/',
        ),
      ),
    );

    final html = response.data ?? '';
    final initialState = _parser.extractInitialState(html);
    return _parser.parseRoomProfile(roomId, initialState);
  }
}
