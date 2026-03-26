import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../domain/search_repository.dart';

const _searchHistoryKey = 'ttttv_search_history';
const _searchHistoryLimit = 20;
const _unset = Object();

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.filteredCount = 0,
    this.isLoading = false,
    this.error,
    this.history = const [],
  });

  final String query;
  final List<VodItem> results;
  final int filteredCount;
  final bool isLoading;
  final String? error;
  final List<String> history;

  SearchState copyWith({
    String? query,
    List<VodItem>? results,
    int? filteredCount,
    bool? isLoading,
    Object? error = _unset,
    List<String>? history,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      filteredCount: filteredCount ?? this.filteredCount,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      history: history ?? this.history,
    );
  }
}

class SearchController extends StateNotifier<SearchState> {
  SearchController(this._repository) : super(const SearchState()) {
    unawaited(_loadHistory());
  }

  final SearchRepository _repository;

  Future<void> search(String query, {bool bypass = false}) async {
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
    );

    try {
      final result = await _repository.search(normalized, bypass: bypass);
      final history = await _rememberQuery(normalized);
      state = state.copyWith(
        isLoading: false,
        results: result.items,
        filteredCount: result.filteredCount,
        history: history,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  void clearResults() {
    state = state.copyWith(
      results: const [],
      filteredCount: 0,
      error: null,
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
