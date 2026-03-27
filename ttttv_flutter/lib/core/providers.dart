import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/favorites/domain/favorites_repository.dart';
import '../features/history/domain/history_repository.dart';
import '../features/live/application/live_controller.dart';
import '../features/live/application/live_room_controller.dart';
import '../features/live/data/http_live_backend.dart';
import '../features/live/domain/live_repository.dart';
import '../features/play/domain/play_repository.dart';
import '../features/search/application/search_controller.dart';
import '../features/search/domain/search_repository.dart';
import '../features/settings/domain/sources_repository.dart';
import '../features/shared/data/http_vod_backend.dart';
import 'config/backend_config.dart';
import 'models/vod_models.dart';
import 'network/http_backend_client.dart';

final backendConfigProvider = Provider<BackendConfig>((ref) {
  return const BackendConfig.localhost();
});

final httpBackendClientProvider = Provider<HttpBackendClient>((ref) {
  final config = ref.watch(backendConfigProvider);
  return HttpBackendClient(baseUrl: config.baseUrl);
});

final backendHealthProvider = FutureProvider<BackendHealth>((ref) async {
  final client = ref.watch(httpBackendClientProvider);
  return client.getRaw<BackendHealth>(
    '/health',
    decoder: BackendHealth.fromJson,
  );
});

final vodBackendProvider = Provider<HttpVodBackend>((ref) {
  final client = ref.watch(httpBackendClientProvider);
  return HttpVodBackend(client: client);
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return ref.watch(vodBackendProvider);
});

final playRepositoryProvider = Provider<PlayRepository>((ref) {
  return ref.watch(vodBackendProvider);
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return ref.watch(vodBackendProvider);
});

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return ref.watch(vodBackendProvider);
});

final sourcesRepositoryProvider = Provider<SourcesRepository>((ref) {
  return ref.watch(vodBackendProvider);
});

final doubanChartProvider = FutureProvider<List<DoubanSubject>>((ref) async {
  final client = ref.watch(httpBackendClientProvider);
  return client.getRaw<List<DoubanSubject>>(
    '/api/douban/chart',
    queryParameters: {'type': '11', 'limit': '8'},
    decoder: (json) {
      final map = json as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>?;
      final subjects = (data?['subjects'] as List?) ?? [];
      return subjects.map(DoubanSubject.fromJson).toList();
    },
  );
});

final doubanMoviesProvider = FutureProvider<List<DoubanSubject>>((ref) async {
  final client = ref.watch(httpBackendClientProvider);
  return client.getRaw<List<DoubanSubject>>(
    '/api/douban/search',
    queryParameters: {'type': 'movie', 'tag': '热门', 'page_limit': '16'},
    decoder: (json) {
      final map = json as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>?;
      final subjects = (data?['subjects'] as List?) ?? [];
      return subjects.map(DoubanSubject.fromJson).toList();
    },
  );
});

final doubanTvProvider = FutureProvider<List<DoubanSubject>>((ref) async {
  final client = ref.watch(httpBackendClientProvider);
  return client.getRaw<List<DoubanSubject>>(
    '/api/douban/search',
    queryParameters: {'type': 'tv', 'tag': '热门', 'page_limit': '16'},
    decoder: (json) {
      final map = json as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>?;
      final subjects = (data?['subjects'] as List?) ?? [];
      return subjects.map(DoubanSubject.fromJson).toList();
    },
  );
});

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) {
  final repository = ref.watch(searchRepositoryProvider);
  return SearchController(repository);
});

final historyItemsProvider = FutureProvider<List<WatchHistoryItem>>((ref) async {
  final repository = ref.watch(historyRepositoryProvider);
  return repository.fetchHistory();
});

final favoriteItemsProvider = FutureProvider<List<FavoriteItem>>((ref) async {
  final repository = ref.watch(favoritesRepositoryProvider);
  return repository.fetchFavorites();
});

final siteListProvider = FutureProvider<List<SiteWithStatus>>((ref) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.fetchSites();
});

// 跨页面搜索触发：首页点击豆瓣条目 → 写入标题 → AppShell 切换到搜索 Tab → SearchPage 自动搜索
final pendingSearchProvider = StateProvider<String?>((ref) => null);

// ─── Live providers ───────────────────────────────────────────────────────────

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  final client = ref.watch(httpBackendClientProvider);
  final config = ref.watch(backendConfigProvider);
  return HttpLiveBackend(client: client, baseUrl: config.baseUrl);
});

final liveControllerProvider =
    StateNotifierProvider<LiveController, LiveState>((ref) {
  final repo = ref.watch(liveRepositoryProvider);
  return LiveController(repo);
});

final liveRoomControllerProvider = StateNotifierProvider.family<
    LiveRoomController, LiveRoomState,
    ({String platform, String roomId})>((ref, key) {
  final repo = ref.watch(liveRepositoryProvider);
  return LiveRoomController(repo, key.platform, key.roomId);
});
