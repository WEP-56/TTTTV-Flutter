import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../core/providers/live_provider.dart';
import '../core/providers/live_provider_registry.dart';
import '../data/storage/live_library_store.dart';

const _danmakuSettingsKey = 'ttttv-live-danmaku-settings';

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
    this.supportsDanmaku = false,
    this.danmakuEnabled = true,
    this.danmakuOpacity = 0.85,
    this.danmakuFontSize = 22,
    this.danmakuSpeed = 120,
  });

  final LiveRoomDetail? detail;
  final List<LivePlayQuality> qualities;
  final String? selectedQualityId;
  final LivePlayUrl? playUrl;
  final int currentLineIndex;
  final bool loading;
  final String? error;
  final bool isFavorite;
  final bool supportsDanmaku;
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuSpeed;

  String? get currentStreamUrl {
    final urls = playUrl?.urls;
    if (urls == null || urls.isEmpty) return null;
    final idx = currentLineIndex.clamp(0, urls.length - 1);
    return urls[idx];
  }

  Map<String, String>? get currentStreamHeaders => playUrl?.headers;

  LiveRoomState copyWith({
    LiveRoomDetail? detail,
    List<LivePlayQuality>? qualities,
    Object? selectedQualityId = _sentinel,
    LivePlayUrl? playUrl,
    int? currentLineIndex,
    bool? loading,
    Object? error = _sentinel,
    bool? isFavorite,
    bool? supportsDanmaku,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontSize,
    double? danmakuSpeed,
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
      supportsDanmaku: supportsDanmaku ?? this.supportsDanmaku,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
      danmakuFontSize: danmakuFontSize ?? this.danmakuFontSize,
      danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
    );
  }
}

const _sentinel = Object();

class LiveRoomController extends StateNotifier<LiveRoomState> {
  LiveRoomController(
    this._registry,
    this._libraryStore,
    this._providerId,
    this._roomId,
  ) : super(LiveRoomState());

  final LiveProviderRegistry _registry;
  final LiveLibraryStore _libraryStore;
  final String _providerId;
  final String _roomId;
  final StreamController<LiveMessage> _danmakuController =
      StreamController<LiveMessage>.broadcast();

  SharedPreferences? _preferences;
  bool _settingsLoaded = false;
  StreamSubscription<LiveMessage>? _danmakuSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _allowReconnect = true;

  Stream<LiveMessage> get danmakuMessages => _danmakuController.stream;

  Future<void> init() async {
    await _ensureDanmakuSettingsLoaded();

    state = state.copyWith(loading: true, error: null);
    try {
      final provider = _provider;
      final detail = await provider.getRoomDetail(_roomId);
      final results = await Future.wait([
        provider.getPlayQualities(detail),
        _libraryStore.isFavorite(_providerId, _roomId),
      ]);

      final qualities = results[0] as List<LivePlayQuality>;
      final isFavorite = results[1] as bool;
      qualities.sort((left, right) => left.sort.compareTo(right.sort));

      if (!mounted) return;

      state = state.copyWith(
        detail: detail,
        qualities: qualities,
        isFavorite: isFavorite,
        supportsDanmaku: provider.supportsDanmaku,
        loading: false,
        error: null,
      );

      if (qualities.isNotEmpty) {
        await selectQuality(qualities.first.id);
      }

      _syncDanmakuConnection();
      unawaited(_writeHistory(detail));
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: error.toString());
      _stopDanmaku();
    }
  }

  Future<void> selectQuality(String qualityId) async {
    final detail = state.detail;
    if (detail == null) return;

    state = state.copyWith(
      selectedQualityId: qualityId,
      currentLineIndex: 0,
      loading: true,
      error: null,
    );

    try {
      final playUrl = await _provider.getPlayUrl(detail, qualityId);
      if (!mounted) return;
      state = state.copyWith(playUrl: playUrl, loading: false, error: null);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: error.toString());
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
    await selectQuality(qualityId);
  }

  Future<void> toggleFavorite() async {
    final detail = state.detail;
    if (detail == null) return;

    try {
      if (state.isFavorite) {
        await _libraryStore.deleteFavorite(_providerId, _roomId);
        if (!mounted) return;
        state = state.copyWith(isFavorite: false);
      } else {
        await _libraryStore.addFavorite(
          platform: _providerId,
          roomId: _roomId,
          title: detail.title,
          cover: detail.cover.isNotEmpty ? detail.cover : null,
          userName: detail.userName.isNotEmpty ? detail.userName : null,
          userAvatar: detail.userAvatar.isNotEmpty ? detail.userAvatar : null,
        );
        if (!mounted) return;
        state = state.copyWith(isFavorite: true);
      }
    } catch (_) {
      // Local library persistence is best-effort.
    }
  }

  Future<void> setDanmakuEnabled(bool enabled) async {
    if (!state.supportsDanmaku) return;
    if (enabled == state.danmakuEnabled) return;

    state = state.copyWith(danmakuEnabled: enabled);
    await _saveDanmakuSettings();

    if (enabled) {
      _allowReconnect = true;
      _reconnectAttempts = 0;
      _syncDanmakuConnection();
    } else {
      _stopDanmaku();
    }
  }

  Future<void> updateDanmakuSettings({
    required double opacity,
    required double fontSize,
    required double speed,
  }) async {
    state = state.copyWith(
      danmakuOpacity: opacity,
      danmakuFontSize: fontSize,
      danmakuSpeed: speed,
    );
    await _saveDanmakuSettings();
  }

  Future<void> _writeHistory(LiveRoomDetail detail) async {
    try {
      await _libraryStore.addHistory(
        platform: _providerId,
        roomId: _roomId,
        title: detail.title,
        cover: detail.cover.isNotEmpty ? detail.cover : null,
        userName: detail.userName.isNotEmpty ? detail.userName : null,
        userAvatar: detail.userAvatar.isNotEmpty ? detail.userAvatar : null,
      );
    } catch (_) {}
  }

  Future<void> _ensureDanmakuSettingsLoaded() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;

    try {
      _preferences ??= await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_danmakuSettingsKey);
      if (raw == null || raw.isEmpty) return;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;

      state = state.copyWith(
        danmakuEnabled: json['enabled'] as bool? ?? true,
        danmakuOpacity:
            (json['opacity'] as num?)?.toDouble().clamp(0.1, 1.0) ?? 0.85,
        danmakuFontSize:
            (json['fontSize'] as num?)?.toDouble().clamp(14.0, 40.0) ?? 22,
        danmakuSpeed:
            (json['speed'] as num?)?.toDouble().clamp(60.0, 240.0) ?? 120,
      );
    } catch (_) {
      // Keep defaults when local settings are missing or malformed.
    }
  }

  Future<void> _saveDanmakuSettings() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setString(
        _danmakuSettingsKey,
        jsonEncode({
          'enabled': state.danmakuEnabled,
          'opacity': state.danmakuOpacity,
          'fontSize': state.danmakuFontSize,
          'speed': state.danmakuSpeed,
        }),
      );
    } catch (_) {
      // Ignore persistence failures for local UI settings.
    }
  }

  void _syncDanmakuConnection() {
    if (!state.supportsDanmaku || !state.danmakuEnabled) {
      _stopDanmaku();
      return;
    }

    final detail = state.detail;
    if (detail == null) return;

    _connectDanmaku(detail);
  }

  void _connectDanmaku(LiveRoomDetail detail) {
    _closeDanmakuSubscription();
    _allowReconnect = true;

    try {
      final stream = _provider.createDanmakuStream(detail);
      _danmakuSubscription = stream.listen(
        (message) {
          _danmakuController.add(message);
          _reconnectAttempts = 0;
        },
        onDone: _handleDanmakuDisconnect,
        onError: (_, __) => _handleDanmakuDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleDanmakuDisconnect() {
    _closeDanmakuSubscription();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_allowReconnect || !state.supportsDanmaku || !state.danmakuEnabled) {
      return;
    }
    if (_reconnectAttempts >= 10) return;
    if (_reconnectTimer != null) return;

    final delayMs = math.min(
      30000,
      (1000 * math.pow(1.8, _reconnectAttempts)).round(),
    );

    _reconnectAttempts += 1;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      if (!mounted || !state.supportsDanmaku || !state.danmakuEnabled) return;
      final detail = state.detail;
      if (detail == null) return;
      _connectDanmaku(detail);
    });
  }

  void _closeDanmakuSubscription() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_danmakuSubscription?.cancel());
    _danmakuSubscription = null;
  }

  void _stopDanmaku() {
    _allowReconnect = false;
    _reconnectAttempts = 0;
    _closeDanmakuSubscription();
  }

  LiveProvider get _provider => _registry.of(_providerId);

  @override
  void dispose() {
    _stopDanmaku();
    _danmakuController.close();
    super.dispose();
  }
}
