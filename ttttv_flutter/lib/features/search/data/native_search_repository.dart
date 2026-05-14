import 'dart:async';

import '../../../core/models/vod_models.dart';
import '../../settings/data/local_app_settings_store.dart';
import '../../settings/data/local_sources_store.dart';
import '../domain/search_repository.dart';
import 'native_source_crawler.dart';
import 'search_cache.dart';

class NativeSearchRepository implements SearchRepository {
  NativeSearchRepository({
    required LocalSourcesStore sourcesStore,
    required LocalAppSettingsStore appSettingsStore,
    required NativeSourceCrawler crawler,
  })  : _sourcesStore = sourcesStore,
        _appSettingsStore = appSettingsStore,
        _crawler = crawler;

  final LocalSourcesStore _sourcesStore;
  final LocalAppSettingsStore _appSettingsStore;
  final NativeSourceCrawler _crawler;
  final _cache = SearchCache();

  static const _perSourceTimeout = Duration(seconds: 8);
  static const _maxPages = 5;

  @override
  Future<SearchResult> search(String keyword, {bool bypass = false}) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    final settings = await _appSettingsStore.load();
    final sources = (await _sourcesStore.loadAllSources()).where((source) {
      if (!source.enabled) return false;
      if (settings.autoSkipBadSources && source.isBadHealth) return false;
      return true;
    }).toList(growable: false);

    if (sources.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    Object? lastError;
    var successCount = 0;
    final allItems = <VodItem>[];

    final sourceFutures = sources.map((source) async {
      try {
        final entry = _cache.get(source.key, query, 1);
        if (entry != null) {
          if (entry.status == CachedPageStatus.ok) {
            successCount++;
            final results = <VodItem>[...entry.data];
            if (entry.pageCount != null && entry.pageCount! > 1) {
              final extraPages =
                  (entry.pageCount!).clamp(2, _maxPages);
              final extraResults = await Future.wait(
                List.generate(extraPages - 1, (i) => i + 2)
                    .map((page) => _fetchPage(source, query, page)),
              );
              for (final pageItems in extraResults) {
                results.addAll(pageItems);
              }
            }
            return results;
          }
          return const <VodItem>[];
        }

        final page1Items = await _fetchPage(source, query, 1);
        if (page1Items.isEmpty) return const <VodItem>[];

        successCount++;
        final results = <VodItem>[...page1Items];

        final extraResults = await Future.wait(
          List.generate(_maxPages - 1, (i) => i + 2)
              .map((page) => _fetchPage(source, query, page)),
        );
        for (final pageItems in extraResults) {
          results.addAll(pageItems);
        }

        return results;
      } catch (error) {
        if (error is TimeoutException) {
          _cache.set(source.key, query, 1, CachedPageStatus.timeout, const []);
        } else {
          lastError = error;
        }
        return const <VodItem>[];
      }
    });

    final results = await Future.wait(sourceFutures);
    for (final items in results) {
      allItems.addAll(items);
    }

    if (successCount == 0 && lastError != null) {
      throw StateError('所有片源搜索失败: $lastError');
    }

    return SearchResult(items: allItems, filteredCount: 0);
  }

  Future<List<VodItem>> _fetchPage(
    LocalVodSource source,
    String query,
    int page,
  ) async {
    final cached = _cache.get(source.key, query, page);
    if (cached != null) {
      if (cached.status == CachedPageStatus.ok) return cached.data;
      return const [];
    }

    try {
      final items = await _crawler
          .search(source, query, page: page)
          .timeout(_perSourceTimeout);
      _cache.set(source.key, query, page, CachedPageStatus.ok, items);
      return items;
    } catch (error) {
      if (error is TimeoutException) {
        _cache.set(source.key, query, page, CachedPageStatus.timeout, const []);
      }
      return const [];
    }
  }

  @override
  Future<VodItem> getDetail({
    required String sourceKey,
    required String vodId,
  }) async {
    final source = await _sourcesStore.getSource(sourceKey);
    if (source == null) {
      throw StateError('片源不存在: $sourceKey');
    }
    return _crawler.getDetail(source, vodId);
  }
}
