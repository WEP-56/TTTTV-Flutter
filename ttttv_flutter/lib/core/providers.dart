import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/favorites/domain/favorites_repository.dart';
import '../features/history/domain/history_repository.dart';
import '../features/live/application/live_controller.dart';
import '../features/live/application/live_room_controller.dart';
import '../features/live/core/providers/live_provider_registry.dart';
import '../features/live/data/m3u/m3u_source_store.dart';
import '../features/live/data/storage/live_cookie_store.dart';
import '../features/live/data/storage/live_library_store.dart';
import '../features/live/providers/bilibili/bilibili_auth_service.dart';
import '../features/live/providers/bilibili/bilibili_live_provider.dart';
import '../features/live/providers/bilibili/bilibili_signer.dart';
import '../features/live/providers/douyin/douyin_auth_service.dart';
import '../features/live/providers/douyin/douyin_live_provider.dart';
import '../features/live/providers/douyin/douyin_signer.dart';
import '../features/live/providers/douyu/douyu_auth_service.dart';
import '../features/live/providers/douyu/douyu_live_provider.dart';
import '../features/live/providers/douyu/douyu_signer.dart';
import '../features/live/providers/huya/huya_auth_service.dart';
import '../features/live/providers/huya/huya_live_provider.dart';
import '../features/live/providers/kuaishou/kuaishou_live_provider.dart';
import '../features/live/providers/custom/custom_m3u_provider.dart';
import '../features/play/domain/play_repository.dart';
import '../features/search/application/search_controller.dart';
import '../features/search/domain/search_repository.dart';
import '../features/settings/domain/storage_manager.dart';
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

final storageManagerProvider = Provider<StorageManager>((ref) {
  return StorageManager();
});

final cacheUsageProvider = FutureProvider<CacheUsage>((ref) async {
  final manager = ref.watch(storageManagerProvider);
  return manager.getCacheUsage();
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

final historyItemsProvider =
    FutureProvider<List<WatchHistoryItem>>((ref) async {
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

final liveDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      },
    ),
  );
});

final liveM3uSourceStoreProvider = Provider<LiveM3uSourceStore>((ref) {
  return LiveM3uSourceStore();
});

final liveLibraryStoreProvider = Provider<LiveLibraryStore>((ref) {
  return LiveLibraryStore();
});

final liveCookieStoreProvider = Provider<LiveCookieStore>((ref) {
  return LiveCookieStore();
});

final liveProviderRegistryProvider = Provider<LiveProviderRegistry>((ref) {
  final dio = ref.watch(liveDioProvider);
  final sourceStore = ref.watch(liveM3uSourceStoreProvider);
  final cookieStore = ref.watch(liveCookieStoreProvider);
  final bilibiliAuthService = BilibiliAuthService(cookieStore: cookieStore);
  final bilibiliSigner = BilibiliSigner(
    dio: dio,
    authService: bilibiliAuthService,
  );
  final douyinAuthService = DouyinAuthService(cookieStore: cookieStore);
  final douyinSigner = DouyinSigner(
    dio: dio,
    authService: douyinAuthService,
  );
  final douyuAuthService = DouyuAuthService(cookieStore: cookieStore);
  final douyuSigner = DouyuSigner(
    dio: dio,
    authService: douyuAuthService,
  );
  final huyaAuthService = HuyaAuthService(cookieStore: cookieStore);
  return LiveProviderRegistry([
    BilibiliLiveProvider(
      dio: dio,
      signer: bilibiliSigner,
      authService: bilibiliAuthService,
    ),
    DouyinLiveProvider(
      dio: dio,
      signer: douyinSigner,
      authService: douyinAuthService,
    ),
    DouyuLiveProvider(
      dio: dio,
      signer: douyuSigner,
      authService: douyuAuthService,
    ),
    HuyaLiveProvider(
      dio: dio,
      authService: huyaAuthService,
    ),
    KuaishouLiveProvider(
      dio: dio,
    ),
    CustomM3uProvider(dio: dio, sourceStore: sourceStore),
  ]);
});

final liveControllerProvider =
    StateNotifierProvider<LiveController, LiveState>((ref) {
  final registry = ref.watch(liveProviderRegistryProvider);
  return LiveController(registry);
});

final liveRoomControllerProvider = StateNotifierProvider.family<
    LiveRoomController,
    LiveRoomState,
    ({String platform, String roomId})>((ref, key) {
  final registry = ref.watch(liveProviderRegistryProvider);
  final libraryStore = ref.watch(liveLibraryStoreProvider);
  return LiveRoomController(
    registry,
    libraryStore,
    key.platform,
    key.roomId,
  );
});
