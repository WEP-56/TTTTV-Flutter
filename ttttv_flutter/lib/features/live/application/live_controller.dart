import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../domain/live_repository.dart';

class LiveState {
  LiveState({
    this.platforms = const [],
    this.rooms = const [],
    this.activePlatform = 'bilibili',
    this.loading = false,
    this.error,
  });

  final List<LivePlatformInfo> platforms;
  final List<LiveRoomItem> rooms;
  final String activePlatform;
  final bool loading;
  final String? error;

  LiveState copyWith({
    List<LivePlatformInfo>? platforms,
    List<LiveRoomItem>? rooms,
    String? activePlatform,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return LiveState(
      platforms: platforms ?? this.platforms,
      rooms: rooms ?? this.rooms,
      activePlatform: activePlatform ?? this.activePlatform,
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class LiveController extends StateNotifier<LiveState> {
  LiveController(this._repo) : super(LiveState());

  final LiveRepository _repo;

  Future<void> loadPlatforms() async {
    try {
      final platforms = await _repo.fetchPlatforms();
      if (platforms.isNotEmpty) {
        state = state.copyWith(platforms: platforms);
      }
    } catch (_) {
      // non-critical: fall back to hardcoded list in UI
    }
  }

  Future<void> loadRecommend() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final rooms = await _repo.recommend(state.activePlatform);
      state = state.copyWith(rooms: rooms, loading: false);
    } catch (e) {
      state = state.copyWith(
        rooms: [],
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> search(String kw) async {
    if (kw.trim().isEmpty) {
      await loadRecommend();
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final rooms = await _repo.search(state.activePlatform, kw.trim());
      state = state.copyWith(rooms: rooms, loading: false);
    } catch (e) {
      state = state.copyWith(
        rooms: [],
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> switchPlatform(String platform) async {
    state = state.copyWith(activePlatform: platform, rooms: []);
    await loadRecommend();
  }
}
