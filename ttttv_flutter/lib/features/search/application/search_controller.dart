import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../../home/data/douban_repository.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/search_repository.dart';

const _searchHistoryKey = 'ttttv_search_history';
const _searchHistoryLimit = 20;
const _unset = Object();

enum SearchResultMode {
  target,
  source,
}

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.filteredCount = 0,
    this.isLoading = false,
    this.error,
    this.history = const [],
    this.resultMode = SearchResultMode.target,
    this.usedSourceFallback = false,
  });

  final String query;
  final List<VodItem> results;
  final int filteredCount;
  final bool isLoading;
  final String? error;
  final List<String> history;
  final SearchResultMode resultMode;
  final bool usedSourceFallback;

  SearchState copyWith({
    String? query,
    List<VodItem>? results,
    int? filteredCount,
    bool? isLoading,
    Object? error = _unset,
    List<String>? history,
    SearchResultMode? resultMode,
    bool? usedSourceFallback,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      filteredCount: filteredCount ?? this.filteredCount,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      history: history ?? this.history,
      resultMode: resultMode ?? this.resultMode,
      usedSourceFallback: usedSourceFallback ?? this.usedSourceFallback,
    );
  }
}

class SearchController extends StateNotifier<SearchState> {
  SearchController(
    this._repository,
    this._doubanRepository,
    this._doubanDataSource,
  ) : super(const SearchState()) {
    unawaited(_loadHistory());
  }

  final SearchRepository _repository;
  final DoubanRepository _doubanRepository;
  final DoubanDataSource Function() _doubanDataSource;

  Future<void> search(
    String query, {
    bool bypass = false,
    Set<String>? sourceKeys,
    SearchResultMode mode = SearchResultMode.target,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }

    state = state.copyWith(
      query: normalized,
      isLoading: true,
      results: const [],
      filteredCount: 0,
      error: null,
      resultMode: mode,
      usedSourceFallback: false,
    );

    try {
      SearchResult result;
      var resultMode = mode;
      var usedSourceFallback = false;
      if (mode == SearchResultMode.target) {
        final targets = await _searchTargets(normalized);
        if (targets.isNotEmpty) {
          result = SearchResult(items: targets, filteredCount: 0);
        } else {
          usedSourceFallback = true;
          resultMode = SearchResultMode.source;
          result = await _searchSources(
            normalized,
            bypass: bypass,
            sourceKeys: sourceKeys,
          );
        }
      } else {
        result = await _searchSources(
          normalized,
          bypass: bypass,
          sourceKeys: sourceKeys,
        );
      }

      final history = await _rememberQuery(normalized);
      state = state.copyWith(
        isLoading: false,
        results: result.items,
        filteredCount: result.filteredCount,
        history: history,
        resultMode: resultMode,
        usedSourceFallback: usedSourceFallback,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  void cancelSearch() {
    _repository.cancelSearch();
  }

  void clearResults() {
    state = state.copyWith(
      results: const [],
      filteredCount: 0,
      error: null,
      usedSourceFallback: false,
    );
  }

  Future<List<VodItem>> _searchTargets(String query) async {
    final targets = await _doubanRepository.searchTargets(
      source: _doubanDataSource(),
      keyword: query,
    );
    return targets.map(_targetToVodItem).toList(growable: false);
  }

  Future<SearchResult> _searchSources(
    String normalized, {
    required bool bypass,
    required Set<String>? sourceKeys,
  }) async {
    final accumulated = <VodItem>[];
    return _repository.search(
      normalized,
      bypass: bypass,
      sourceKeys: sourceKeys,
      onBatch: (batch) {
        accumulated.addAll(batch);
        state = state.copyWith(
          results: [...accumulated],
          resultMode: SearchResultMode.source,
        );
      },
    );
  }

  VodItem _targetToVodItem(DoubanItem item) {
    final isBangumi = item.source == DoubanTargetSource.bangumi;
    final sourceLabel = isBangumi ? 'Bangumi' : '豆瓣';
    final remarks =
        item.rate == null || item.rate!.isEmpty ? sourceLabel : item.rate;
    return VodItem(
      sourceKey: '',
      vodId: '',
      vodName: item.title,
      vodPlayUrl: '',
      vodPic: item.poster,
      vodRemarks: remarks,
      vodContent: item.summary ?? item.subtitle,
      vodYear: item.year,
      vodClass: isBangumi ? '动画' : null,
      vodTag: item.id,
      typeName: isBangumi
          ? 'anime'
          : (item.episodeCount != null && item.episodeCount! > 1)
              ? 'tv'
              : 'movie',
    );
  }

  Future<void> removeHistoryEntry(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final next = state.history.where((item) => item != query).toList();
    await prefs.setStringList(_searchHistoryKey, next);
    state = state.copyWith(history: next);
  }

  Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
    state = state.copyWith(history: const []);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_searchHistoryKey) ?? const [];
    state = state.copyWith(history: history);
  }

  Future<List<String>> _rememberQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [
      query,
      ...state.history.where((item) => item != query),
    ].take(_searchHistoryLimit).toList();
    await prefs.setStringList(_searchHistoryKey, next);
    return next;
  }
}
