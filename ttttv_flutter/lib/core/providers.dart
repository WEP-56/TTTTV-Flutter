import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../features/settings/application/app_settings_notifier.dart';
export '../features/settings/domain/app_settings.dart';

import '../features/home/data/douban_repository.dart';
import '../features/favorites/data/local_favorites_repository.dart';
import '../features/favorites/domain/favorites_repository.dart';
import '../features/history/data/local_history_repository.dart';
import '../features/history/domain/history_repository.dart';
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
  final crawler = ref.watch(nativeSourceCrawlerProvider);
  return NativeSearchRepository(
    sourcesStore: sourcesStore,
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

final siteListProvider = FutureProvider<List<SiteWithStatus>>((ref) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.fetchSites();
});

final doubanRepositoryProvider = Provider<DoubanRepository>((ref) {
  final dio = ref.watch(nativeVodDioProvider);
  return DoubanRepository(dio: dio);
});

final doubanDataSourceProvider = Provider<DoubanDataSource>((ref) {
  return ref.watch(appSettingsProvider.select((s) => s.doubanDataSource));
});

final pendingSearchProvider = StateProvider<String?>((ref) => null);
