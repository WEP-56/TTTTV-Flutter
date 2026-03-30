import '../../../core/models/vod_models.dart';
import '../../settings/data/local_sources_store.dart';
import '../domain/search_repository.dart';
import 'native_source_crawler.dart';

class NativeSearchRepository implements SearchRepository {
  NativeSearchRepository({
    required LocalSourcesStore sourcesStore,
    required NativeSourceCrawler crawler,
  })  : _sourcesStore = sourcesStore,
        _crawler = crawler;

  final LocalSourcesStore _sourcesStore;
  final NativeSourceCrawler _crawler;

  @override
  Future<SearchResult> search(String keyword, {bool bypass = false}) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    final sources = await _sourcesStore.loadEnabledSources();
    if (sources.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    Object? lastError;
    var successCount = 0;
    final allItems = <VodItem>[];

    final results = await Future.wait(
      sources.map((source) async {
        try {
          final items = await _crawler.search(source, query);
          successCount += 1;
          return items;
        } catch (error) {
          lastError = error;
          return const <VodItem>[];
        }
      }),
    );

    for (final items in results) {
      allItems.addAll(items);
    }

    if (successCount == 0 && lastError != null) {
      throw StateError('所有片源搜索失败: $lastError');
    }

    return SearchResult(
      items: allItems,
      filteredCount: 0,
    );
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
