import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../features/settings/application/app_settings_notifier.dart';
export '../features/settings/domain/app_settings.dart';

import '../features/favorites/data/local_favorites_repository.dart';
import '../features/favorites/domain/favorites_repository.dart';
import '../features/history/data/local_history_repository.dart';
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
import '../features/live/providers/custom/custom_m3u_provider.dart';
import '../features/live/providers/douyin/douyin_auth_service.dart';
import '../features/live/providers/douyin/douyin_live_provider.dart';
import '../features/live/providers/douyin/douyin_signer.dart';
import '../features/live/providers/douyu/douyu_auth_service.dart';
import '../features/live/providers/douyu/douyu_live_provider.dart';
import '../features/live/providers/douyu/douyu_signer.dart';
import '../features/live/providers/huya/huya_auth_service.dart';
import '../features/live/providers/huya/huya_live_provider.dart';
import '../features/live/providers/kuaishou/kuaishou_live_provider.dart';
import '../features/play/data/native_play_repository.dart';
import '../features/play/domain/play_repository.dart';
import '../features/search/application/search_controller.dart';
import '../features/search/data/native_search_repository.dart';
import '../features/search/data/native_source_crawler.dart';
import '../features/search/domain/search_repository.dart';
import '../features/settings/data/local_sources_store.dart';
import '../features/settings/application/app_settings_notifier.dart';
import '../features/settings/domain/sources_repository.dart';
import '../features/settings/domain/storage_manager.dart';
import 'models/vod_models.dart';

final nativeVodDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      },
    ),
  );
});

final localSourcesStoreProvider = Provider<LocalSourcesStore>((ref) {
  final dio = ref.watch(nativeVodDioProvider);
  return LocalSourcesStore(dio: dio);
});

final nativeSourceCrawlerProvider = Provider<NativeSourceCrawler>((ref) {
  final dio = ref.watch(nativeVodDioProvider);
  return NativeSourceCrawler(dio: dio);
});

final nativeSearchRepositoryProvider = Provider<SearchRepository>((ref) {
  final sourcesStore = ref.watch(localSourcesStoreProvider);
  final appSettingsStore = ref.watch(appSettingsStoreProvider);
  final crawler = ref.watch(nativeSourceCrawlerProvider);
  return NativeSearchRepository(
    sourcesStore: sourcesStore,
    appSettingsStore: appSettingsStore,
    crawler: crawler,
  );
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return ref.watch(nativeSearchRepositoryProvider);
});

final playRepositoryProvider = Provider<PlayRepository>((ref) {
  return const NativePlayRepository();
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return LocalHistoryRepository();
});

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return LocalFavoritesRepository();
});

final sourcesRepositoryProvider = Provider<SourcesRepository>((ref) {
  return ref.watch(localSourcesStoreProvider);
});

final storageManagerProvider = Provider<StorageManager>((ref) {
  return StorageManager();
});

final cacheUsageProvider = FutureProvider<CacheUsage>((ref) async {
  final manager = ref.watch(storageManagerProvider);
  return manager.getCacheUsage();
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

final liveFavoritesProvider =
    FutureProvider<List<LiveFavoriteItem>>((ref) async {
  final store = ref.watch(liveLibraryStoreProvider);
  return store.fetchFavorites();
});

final siteListProvider = FutureProvider<List<SiteWithStatus>>((ref) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.fetchSites();
});

final pendingSearchProvider = StateProvider<String?>((ref) => null);

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
  final settings = ref.read(appSettingsProvider);
  return LiveRoomController(
    registry,
    libraryStore,
    key.platform,
    key.roomId,
    settings.liveQualityPreference,
    settings.liveDanmakuEnabled,
  );
});
