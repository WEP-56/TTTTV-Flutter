import '../../../core/models/vod_models.dart';
import '../../../core/network/http_backend_client.dart';
import '../../favorites/domain/favorites_repository.dart';
import '../../history/domain/history_repository.dart';
import '../../play/domain/play_repository.dart';
import '../../search/domain/search_repository.dart';
import '../../settings/domain/sources_repository.dart';

class HttpVodBackend
    implements
        SearchRepository,
        PlayRepository,
        HistoryRepository,
        FavoritesRepository,
        SourcesRepository {
  HttpVodBackend({required HttpBackendClient client}) : _client = client;

  final HttpBackendClient _client;

  @override
  Future<SearchResult> search(String keyword, {bool bypass = false}) {
    return _client.getData<SearchResult>(
      '/api/search',
      queryParameters: {
        'kw': keyword,
        'bypass': bypass,
      },
      decoder: SearchResult.fromJson,
    );
  }

  @override
  Future<VodItem> getDetail({
    required String sourceKey,
    required String vodId,
  }) {
    return _client.getData<VodItem>(
      '/api/detail',
      queryParameters: {
        'source_key': sourceKey,
        'vod_id': vodId,
      },
      decoder: VodItem.fromJson,
    );
  }

  @override
  Future<PlayResult> parsePlayUrl(String playUrl) {
    return _client.getData<PlayResult>(
      '/api/play/parse',
      queryParameters: {
        'play_url': playUrl,
      },
      decoder: PlayResult.fromJson,
    );
  }

  @override
  Future<List<WatchHistoryItem>> fetchHistory() {
    return _client.getData<List<WatchHistoryItem>>(
      '/api/history',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(WatchHistoryItem.fromJson).toList();
      },
    );
  }

  @override
  Future<void> addHistory(WatchHistoryUpsert request) {
    return _client.postVoid(
      '/api/history',
      body: request.toJson(),
    );
  }

  @override
  Future<void> deleteHistory({
    required String vodId,
    required String sourceKey,
  }) {
    return _client.deleteVoid(
      '/api/history',
      queryParameters: {
        'vod_id': vodId,
        'source_key': sourceKey,
      },
    );
  }

  @override
  Future<void> clearHistory() {
    return _client.deleteVoid('/api/history/clear');
  }

  @override
  Future<List<FavoriteItem>> fetchFavorites() {
    return _client.getData<List<FavoriteItem>>(
      '/api/favorites',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(FavoriteItem.fromJson).toList();
      },
    );
  }

  @override
  Future<void> addFavorite(VodItem item) {
    return _client.postVoid(
      '/api/favorites',
      body: {
        'vod_id': item.vodId,
        'source_key': item.sourceKey,
        'vod_name': item.vodName,
        'vod_pic': item.vodPic,
        'vod_remarks': item.vodRemarks,
        'vod_actor': item.vodActor,
        'vod_director': item.vodDirector,
        'vod_content': item.vodContent,
      },
    );
  }

  @override
  Future<void> deleteFavorite({
    required String vodId,
    required String sourceKey,
  }) {
    return _client.deleteVoid(
      '/api/favorites',
      queryParameters: {
        'vod_id': vodId,
        'source_key': sourceKey,
      },
    );
  }

  @override
  Future<bool> checkFavorite({
    required String vodId,
    required String sourceKey,
  }) {
    return _client.getData<bool>(
      '/api/favorites/check',
      queryParameters: {
        'vod_id': vodId,
        'source_key': sourceKey,
      },
      decoder: (json) {
        final map = json as Map<String, dynamic>;
        return map['is_favorited'] as bool? ?? false;
      },
    );
  }

  @override
  Future<void> clearFavorites() {
    return _client.deleteVoid('/api/favorites/clear');
  }

  @override
  Future<List<SiteWithStatus>> fetchSites() {
    return _client.getData<List<SiteWithStatus>>(
      '/api/sources',
      decoder: (json) {
        final list = (json as List?) ?? const [];
        return list.map(SiteWithStatus.fromJson).toList();
      },
    );
  }

  @override
  Future<void> toggleSite({
    required String key,
    required bool enabled,
  }) {
    return _client.postVoid(
      '/api/sources/toggle',
      queryParameters: {
        'key': key,
        'enabled': enabled,
      },
    );
  }

  @override
  Future<void> addSource(AddSourceRequest request) {
    return _client.postVoid(
      '/api/sources/add',
      body: request.toJson(),
    );
  }

  @override
  Future<void> deleteSource(String key) {
    return _client.deleteVoid(
      '/api/sources/delete',
      queryParameters: {
        'key': key,
      },
    );
  }

  @override
  Future<RemoteSourcesResponse> fetchRemoteSources({String? url}) {
    return _client.getData<RemoteSourcesResponse>(
      '/api/sources/remote',
      queryParameters: {
        if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
      },
      decoder: RemoteSourcesResponse.fromJson,
    );
  }

  @override
  Future<AddSourcesBatchResult> addSourcesBatch(List<RemoteSource> sources) {
    return _client.postData<AddSourcesBatchResult>(
      '/api/sources/add_batch',
      body: sources.map((source) => source.toJson()).toList(),
      decoder: AddSourcesBatchResult.fromJson,
    );
  }
}
