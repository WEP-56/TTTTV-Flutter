import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../domain/live_repository.dart';

class LiveRoomState {
  LiveRoomState({
    this.detail,
    this.qualities = const [],
    this.selectedQualityId,
    this.playUrl,
    this.currentLineIndex = 0,
    this.loading = false,
    this.error,
    this.isFavorite = false,
  });

  final LiveRoomDetail? detail;
  final List<LivePlayQuality> qualities;
  final String? selectedQualityId;
  final LivePlayUrl? playUrl;
  final int currentLineIndex;
  final bool loading;
  final String? error;
  final bool isFavorite;

  String? get currentStreamUrl {
    final urls = playUrl?.urls;
    if (urls == null || urls.isEmpty) return null;
    final idx = currentLineIndex.clamp(0, urls.length - 1);
    return urls[idx];
  }

  LiveRoomState copyWith({
    LiveRoomDetail? detail,
    List<LivePlayQuality>? qualities,
    Object? selectedQualityId = _sentinel,
    LivePlayUrl? playUrl,
    int? currentLineIndex,
    bool? loading,
    Object? error = _sentinel,
    bool? isFavorite,
  }) {
    return LiveRoomState(
      detail: detail ?? this.detail,
      qualities: qualities ?? this.qualities,
      selectedQualityId: selectedQualityId == _sentinel
          ? this.selectedQualityId
          : selectedQualityId as String?,
      playUrl: playUrl ?? this.playUrl,
      currentLineIndex: currentLineIndex ?? this.currentLineIndex,
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

const _sentinel = Object();

class LiveRoomController extends StateNotifier<LiveRoomState> {
  LiveRoomController(this._repo, this._platform, this._roomId)
      : super(LiveRoomState());

  final LiveRepository _repo;
  final String _platform;
  final String _roomId;

  Future<void> init() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final results = await Future.wait([
        _repo.getRoomDetail(_platform, _roomId),
        _repo.getQualities(_platform, _roomId),
        _repo.checkFavorite(_platform, _roomId),
      ]);
      final detail = results[0] as LiveRoomDetail;
      final qualities = results[1] as List<LivePlayQuality>;
      final isFav = results[2] as bool;

      qualities.sort((a, b) => a.sort.compareTo(b.sort));

      state = state.copyWith(
        detail: detail,
        qualities: qualities,
        isFavorite: isFav,
        loading: false,
      );

      if (qualities.isNotEmpty) {
        await selectQuality(qualities.first.id);
      } else {
        state = state.copyWith(loading: false);
      }

      unawaited(_writeHistory(detail));
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> selectQuality(String qualityId) async {
    state = state.copyWith(
        selectedQualityId: qualityId, currentLineIndex: 0, loading: true);
    try {
      final playUrl = await _repo.getPlayUrl(_platform, _roomId, qualityId);
      state = state.copyWith(playUrl: playUrl, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void selectLine(int index) {
    final urls = state.playUrl?.urls ?? [];
    if (index < 0 || index >= urls.length) return;
    state = state.copyWith(currentLineIndex: index);
  }

  Future<void> refresh() async {
    final qualityId = state.selectedQualityId;
    if (qualityId == null) {
      await init();
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final playUrl = await _repo.getPlayUrl(_platform, _roomId, qualityId);
      state = state.copyWith(playUrl: playUrl, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> toggleFavorite() async {
    final detail = state.detail;
    if (detail == null) return;
    try {
      if (state.isFavorite) {
        await _repo.deleteFavorite(_platform, _roomId);
        state = state.copyWith(isFavorite: false);
      } else {
        await _repo.addFavorite(
          platform: _platform,
          roomId: _roomId,
          title: detail.title,
          cover: detail.cover.isNotEmpty ? detail.cover : null,
          userName: detail.userName.isNotEmpty ? detail.userName : null,
          userAvatar: detail.userAvatar.isNotEmpty ? detail.userAvatar : null,
        );
        state = state.copyWith(isFavorite: true);
      }
    } catch (_) {
      // non-critical: keep current state
    }
  }

  Future<void> _writeHistory(LiveRoomDetail detail) async {
    try {
      await _repo.addHistory(
        platform: _platform,
        roomId: _roomId,
        title: detail.title,
        cover: detail.cover.isNotEmpty ? detail.cover : null,
        userName: detail.userName.isNotEmpty ? detail.userName : null,
        userAvatar: detail.userAvatar.isNotEmpty ? detail.userAvatar : null,
      );
    } catch (_) {}
  }
}
