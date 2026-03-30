import '../../../../core/models/vod_models.dart';

enum LiveImportedSourceType {
  network,
  local,
}

class LiveImportedSource {
  const LiveImportedSource({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
  });

  final String id;
  final String name;
  final LiveImportedSourceType type;
  final String value;

  String get label => type == LiveImportedSourceType.network ? '网络' : '本地';

  factory LiveImportedSource.fromJson(Map<String, dynamic> json) {
    return LiveImportedSource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type'] == 'local'
          ? LiveImportedSourceType.local
          : LiveImportedSourceType.network,
      value: json['value']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type == LiveImportedSourceType.local ? 'local' : 'network',
      'value': value,
    };
  }
}

class LiveProviderDescriptor {
  const LiveProviderDescriptor({
    required this.id,
    required this.name,
    required this.supportsSearch,
    required this.supportsCategories,
    required this.supportsDanmaku,
    required this.supportsImport,
    required this.supportsAuth,
  });

  final String id;
  final String name;
  final bool supportsSearch;
  final bool supportsCategories;
  final bool supportsDanmaku;
  final bool supportsImport;
  final bool supportsAuth;
}

enum LiveAuthCheckStatus {
  success,
  warning,
  failure,
}

class LiveAuthCheckResult {
  const LiveAuthCheckResult({
    required this.status,
    required this.message,
  });

  final LiveAuthCheckStatus status;
  final String message;
}

abstract class LiveProvider {
  String get id;
  String get name;

  bool get supportsSearch => true;
  bool get supportsCategories => false;
  bool get supportsDanmaku => false;
  bool get supportsImport => false;
  bool get supportsAuth => false;

  LiveProviderDescriptor get descriptor {
    return LiveProviderDescriptor(
      id: id,
      name: name,
      supportsSearch: supportsSearch,
      supportsCategories: supportsCategories,
      supportsDanmaku: supportsDanmaku,
      supportsImport: supportsImport,
      supportsAuth: supportsAuth,
    );
  }

  Future<List<LiveRoomItem>> fetchRecommend({int page = 1});

  Future<List<LiveRoomItem>> search(String keyword, {int page = 1});

  Future<LiveRoomDetail> getRoomDetail(String roomId);

  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail);

  Future<LivePlayUrl> getPlayUrl(LiveRoomDetail detail, String qualityId);

  Stream<LiveMessage> createDanmakuStream(LiveRoomDetail detail) {
    return const Stream<LiveMessage>.empty();
  }

  String resolveImageUrl(String url) => url;

  Future<List<LiveImportedSource>> listSources() async => const [];

  Future<void> addNetworkSource(String url, {String? sourceName}) {
    throw UnsupportedError(
      '$name does not support network source import.',
    );
  }

  Future<void> addLocalSource(String path) {
    throw UnsupportedError('$name does not support local file import.');
  }

  Future<void> removeSource(String sourceId) {
    throw UnsupportedError('$name does not support source removal.');
  }

  Future<bool> isAuthenticated() async => false;

  Future<String> getSavedCookie() {
    throw UnsupportedError('$name does not support cookie auth.');
  }

  Future<void> saveCookie(String cookie) {
    throw UnsupportedError('$name does not support cookie auth.');
  }

  Future<void> clearAuth() {
    throw UnsupportedError('$name does not support auth clearing.');
  }

  Future<LiveAuthCheckResult> checkAuth() async {
    if (!(await isAuthenticated())) {
      return const LiveAuthCheckResult(
        status: LiveAuthCheckStatus.failure,
        message: '未保存 Cookie',
      );
    }
    return const LiveAuthCheckResult(
      status: LiveAuthCheckStatus.warning,
      message: '已保存 Cookie，但当前平台未实现校验接口。',
    );
  }

  Future<void> refreshSources() async {}
}
