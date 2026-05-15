import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/models/vod_models.dart';
import '../../settings/data/local_sources_store.dart';
import '../domain/search_repository.dart';
import 'native_source_crawler.dart';
import 'search_cache.dart';

/// 本地搜索仓库（重写版）。
///
/// 主要改动：
/// 1. **遵守服务端的 `pagecount`**：第 1 页拿到 `pagecount` 后才决定是否分页，
///    彻底取消"每个站盲扫 4 页"。
/// 2. **完整的负缓存**：超时、4xx/5xx、JSON 解析错误都写短 TTL 负缓存，
///    避免反复重打慢站 / 失效站。
/// 3. **流式输出**：每个站完成后立刻通过 [OnSourceBatch] 推回 UI，
///    慢站不会阻塞快站结果展示。
/// 4. **真正的取消**：用 [CancelToken] 取消正在进行的 dio 请求，
///    用户改关键词时立即释放连接，不再堆积请求。
class NativeSearchRepository implements SearchRepository {
  NativeSearchRepository({
    required LocalSourcesStore sourcesStore,
    required NativeSourceCrawler crawler,
  })  : _sourcesStore = sourcesStore,
        _crawler = crawler;

  final LocalSourcesStore _sourcesStore;
  final NativeSourceCrawler _crawler;
  final _cache = SearchCache();

  /// 当前搜索使用的取消令牌；调用 [cancelSearch] 时会真正中止 HTTP。
  CancelToken? _activeCancelToken;

  /// 上次搜索的会话标识。即使没用到 [CancelToken]（缓存命中），
  /// 也能据此忽略迟到结果。
  Object? _activeSession;

  static const _perRequestTimeout = Duration(seconds: 8);
  static const _maxPagesPerSource = 5;

  @override
  void cancelSearch() {
    _activeSession = null;
    final token = _activeCancelToken;
    _activeCancelToken = null;
    if (token != null && !token.isCancelled) {
      token.cancel('user-cancelled');
    }
  }

  @override
  Future<SearchResult> search(
    String keyword, {
    bool bypass = false,
    OnSourceBatch? onBatch,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    // 启动新会话前，先取消旧的请求
    cancelSearch();

    final sources = (await _sourcesStore.loadAllSources())
        .where((source) => source.enabled)
        .toList(growable: false);
    if (sources.isEmpty) {
      return SearchResult(items: const [], filteredCount: 0);
    }

    final session = Object();
    final cancelToken = CancelToken();
    _activeSession = session;
    _activeCancelToken = cancelToken;

    final allItems = <VodItem>[];
    var successCount = 0;
    Object? lastError;

    // 把每个站当作一个独立的 Future，完成一个就 emit 一次
    final pending = <Future<void>>[];
    for (final source in sources) {
      pending.add(() async {
        try {
          final items = await _searchSource(
            source,
            query,
            cancelToken: cancelToken,
          );
          if (_activeSession != session) return; // 已被取消
          if (items.isEmpty) return;
          successCount++;
          allItems.addAll(items);
          onBatch?.call(items);
        } catch (error) {
          if (error is DioException && CancelToken.isCancel(error)) {
            return;
          }
          lastError = error;
        }
      }());
    }

    await Future.wait(pending);

    if (_activeSession == session) {
      _activeSession = null;
      _activeCancelToken = null;
    }

    if (successCount == 0 && lastError != null && allItems.isEmpty) {
      throw StateError('所有片源搜索失败: $lastError');
    }

    return SearchResult(items: allItems, filteredCount: 0);
  }

  /// 搜索单个站点：
  /// 1. 优先吃命中的缓存（包括负缓存）
  /// 2. 拿第 1 页 + 服务端 pagecount
  /// 3. 仅在 pagecount > 1 时分页（最多 [_maxPagesPerSource] 页，并行）
  Future<List<VodItem>> _searchSource(
    LocalVodSource source,
    String query, {
    required CancelToken cancelToken,
  }) async {
    // page=1 缓存
    final cached1 = _cache.get(source.key, query, 1);
    List<VodItem> page1Items;
    int? pageCount;

    if (cached1 != null) {
      if (cached1.status != CachedPageStatus.ok) {
        return const <VodItem>[];
      }
      page1Items = cached1.data;
      pageCount = cached1.pageCount;
    } else {
      try {
        final result = await _crawler
            .search(source, query, page: 1, cancelToken: cancelToken)
            .timeout(_perRequestTimeout);
        _cache.set(
          source.key,
          query,
          1,
          CachedPageStatus.ok,
          result.items,
          pageCount: result.pageCount,
        );
        page1Items = result.items;
        pageCount = result.pageCount;
      } catch (error) {
        _writeNegativeCache(source.key, query, 1, error);
        rethrow;
      }
    }

    if (page1Items.isEmpty) {
      return const <VodItem>[];
    }

    if (pageCount == null || pageCount <= 1) {
      return page1Items;
    }

    final maxPage = pageCount.clamp(1, _maxPagesPerSource);
    if (maxPage <= 1) {
      return page1Items;
    }

    // 并发拿剩余页（每页失败独立处理）
    final extraResults = await Future.wait(
      [for (var page = 2; page <= maxPage; page++) page]
          .map((page) => _fetchPage(source, query, page, cancelToken)),
    );

    return [
      ...page1Items,
      for (final pageItems in extraResults) ...pageItems,
    ];
  }

  Future<List<VodItem>> _fetchPage(
    LocalVodSource source,
    String query,
    int page,
    CancelToken cancelToken,
  ) async {
    final cached = _cache.get(source.key, query, page);
    if (cached != null) {
      return cached.status == CachedPageStatus.ok ? cached.data : const [];
    }

    try {
      final result = await _crawler
          .search(source, query, page: page, cancelToken: cancelToken)
          .timeout(_perRequestTimeout);
      _cache.set(
        source.key,
        query,
        page,
        CachedPageStatus.ok,
        result.items,
      );
      return result.items;
    } catch (error) {
      // 取消的请求不写负缓存
      if (error is DioException && CancelToken.isCancel(error)) {
        return const [];
      }
      _writeNegativeCache(source.key, query, page, error);
      return const [];
    }
  }

  void _writeNegativeCache(
    String sourceKey,
    String query,
    int page,
    Object error,
  ) {
    final status = _classifyError(error);
    _cache.set(sourceKey, query, page, status, const []);
  }

  CachedPageStatus _classifyError(Object error) {
    if (error is TimeoutException) {
      return CachedPageStatus.timeout;
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return CachedPageStatus.timeout;
        case DioExceptionType.badResponse:
        case DioExceptionType.badCertificate:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
        case DioExceptionType.cancel:
          return CachedPageStatus.forbidden;
      }
    }
    // FormatException、StateError 等都按 forbidden 短 TTL 处理
    return CachedPageStatus.forbidden;
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
