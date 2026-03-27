import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../core/providers/live_provider.dart';
import '../core/providers/live_provider_registry.dart';

class LiveState {
  LiveState({
    this.providers = const [],
    this.rooms = const [],
    this.activeProviderId = '',
    this.loading = false,
    this.error,
  });

  final List<LiveProviderDescriptor> providers;
  final List<LiveRoomItem> rooms;
  final String activeProviderId;
  final bool loading;
  final String? error;

  LiveProviderDescriptor? get activeProvider {
    for (final provider in providers) {
      if (provider.id == activeProviderId) return provider;
    }
    return providers.isEmpty ? null : providers.first;
  }

  LiveState copyWith({
    List<LiveProviderDescriptor>? providers,
    List<LiveRoomItem>? rooms,
    String? activeProviderId,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return LiveState(
      providers: providers ?? this.providers,
      rooms: rooms ?? this.rooms,
      activeProviderId: activeProviderId ?? this.activeProviderId,
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class LiveController extends StateNotifier<LiveState> {
  LiveController(this._registry) : super(LiveState());

  final LiveProviderRegistry _registry;

  Future<void> initialize() async {
    final descriptors = _registry.descriptors;
    final activeProviderId = state.activeProviderId.isNotEmpty
        ? state.activeProviderId
        : (descriptors.isNotEmpty ? descriptors.first.id : '');

    state = state.copyWith(
      providers: descriptors,
      activeProviderId: activeProviderId,
    );

    if (activeProviderId.isNotEmpty) {
      await loadRecommend();
    }
  }

  Future<void> loadRecommend() async {
    final provider = _activeProvider;
    if (provider == null) return;

    state = state.copyWith(loading: true, error: null);
    try {
      final rooms = await provider.fetchRecommend();
      state = state.copyWith(rooms: rooms, loading: false, error: null);
    } catch (error) {
      state = state.copyWith(
        rooms: const [],
        loading: false,
        error: error.toString(),
      );
    }
  }

  Future<void> search(String keyword) async {
    final provider = _activeProvider;
    if (provider == null) return;

    if (keyword.trim().isEmpty) {
      await loadRecommend();
      return;
    }

    state = state.copyWith(loading: true, error: null);
    try {
      final rooms = await provider.search(keyword.trim());
      state = state.copyWith(rooms: rooms, loading: false, error: null);
    } catch (error) {
      state = state.copyWith(
        rooms: const [],
        loading: false,
        error: error.toString(),
      );
    }
  }

  Future<void> switchProvider(String providerId) async {
    if (providerId == state.activeProviderId) return;
    state = state.copyWith(
      activeProviderId: providerId,
      rooms: const [],
      error: null,
    );
    await loadRecommend();
  }

  LiveProvider? get _activeProvider {
    if (state.activeProviderId.isEmpty) return null;
    return _registry.of(state.activeProviderId);
  }
}
