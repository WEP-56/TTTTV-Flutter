import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/platform/platform_window.dart';
import '../../../core/platform/screen_brightness.dart';
import '../../../core/platform/android_media.dart';
import '../../../core/providers.dart';
import '../../history/domain/history_repository.dart';
import '../../player/application/playback_loader.dart';
import '../../player/application/dlna_controller.dart';
import '../../player/presentation/widgets/cast_device_dialog.dart';
import '../../player/presentation/widgets/player_controls_overlay.dart';
import '../../player/presentation/widgets/player_episode_panel.dart';
import '../../player/presentation/widgets/player_gesture_layer.dart';
import '../../player/presentation/widgets/player_video_surface.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({
    required this.initialItem,
    this.initialHistory,
    super.key,
  });

  final VodItem initialItem;
  final WatchHistoryItem? initialHistory;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage>
    with WidgetsBindingObserver {
  static const Duration _seekStep = Duration(seconds: 10);
  static const double _volumeStep = 5;
  static const int _speedProbeBytes = 256 * 1024;

  late VodItem _detail;
  late VodItem _infoDetail;
  final List<_PlayableLine> _playableLines = [];
  final List<VodItem> _candidateDetails = [];
  final Set<String> _candidateKeys = {};
  final Set<String> _lineKeys = {};
  final Set<String> _detailFetchKeys = {};
  final Set<Future<void>> _candidateTasks = {};
  final Map<int, _LineSpeedTest> _lineSpeedTests = {};
  final Set<int> _lineSpeedTesting = {};
  final FocusNode _keyboardFocusNode =
      FocusNode(debugLabel: 'detail-inline-player');
  bool _loading = true;
  bool _searchingSources = false;
  bool _favoriteLoading = false;
  bool _sourceToggleLoading = false;
  bool _isFavorited = false;
  bool _sourceEnabled = true;
  String? _error;
  int _resumeEpisodeIndex = 0;
  double _resumeProgress = 0;
  int _selectedLineIndex = 0;
  int _selectedEpisodeIndex = 0;
  late final Player _inlinePlayer;
  late final VideoController _inlineVideoController;
  late final PlatformFullscreenBinding _fullscreenBinding;
  late final Dio _speedTestDio;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<Duration> _bufferSubscription;
  late final HistoryRepository _historyRepository;
  late final bool _autoSavePlaybackProgress;
  bool _inlineInitialized = false;
  bool _inlineLoading = false;
  bool _isBuffering = false;
  bool _isSeeking = false;
  bool _showPlayerControls = true;
  bool _playerExpanded = false;
  bool _traditionalFullscreen = false;
  bool _wasExpandedBeforeTraditionalFullscreen = false;
  bool _episodeDrawerOpen = false;
  bool _mobileImmersiveApplied = false;
  bool _temporarySpeedActive = false;
  double _volume = 100;
  double _playbackSpeed = 1;
  double _temporarySpeedSaved = 1;
  double _brightness = 1;
  int _fitMode = 0;
  Duration _bufferPosition = Duration.zero;
  String? _inlineError;
  String? _inlineSignature;
  Timer? _controlsHideTimer;
  Timer? _progressSaveTimer;
  int _loadGeneration = 0;
  int _processedCandidateCount = 0;
  String? _lastPersistSignature;
  bool _initialHistoryApplied = false;
  bool _restoringInitialHistory = false;
  bool _disposing = false;
  int _episodeGeneration = 0;
  int _selectionGeneration = 0;
  Future<void> _episodeQueue = Future<void>.value();
  bool _startingFirstLine = false;
  bool _pipSupported = false;
  bool _inPip = false;
  bool _pipPreparing = false;
  DlnaController? _castController;
  DlnaDevice? _castDevice;
  bool _castBusy = false;
  bool _castPlaying = false;
  bool _castPolling = false;
  Duration _castPosition = Duration.zero;
  Duration _castDuration = Duration.zero;
  Timer? _castTimer;

  _PlayableLine? get _selectedLine =>
      _playableLines.isEmpty ? null : _playableLines[_selectedLineIndex];

  PlayResult? get _selectedPlayResult {
    final line = _selectedLine;
    if (line == null) return null;
    return PlayResult(sources: [line.source]);
  }

  PlaySource? get _currentSource => _selectedLine?.source;

  PlayEpisode? get _currentEpisode {
    final source = _currentSource;
    if (source == null || source.episodes.isEmpty) return null;
    final index = _selectedEpisodeIndex.clamp(0, source.episodes.length - 1);
    return source.episodes[index];
  }

  bool get _canPlayPrevious => _selectedEpisodeIndex > 0;

  bool get _canPlayNext {
    final source = _currentSource;
    if (source == null) return false;
    return _selectedEpisodeIndex < source.episodes.length - 1;
  }

  BoxFit get _videoFit => switch (_fitMode) {
        1 => BoxFit.cover,
        2 => BoxFit.fill,
        _ => BoxFit.contain,
      };

  String get _fitLabel => switch (_fitMode) {
        1 => '铺满',
        2 => '拉伸',
        _ => '原比例',
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      AndroidMedia.channel.setMethodCallHandler(_handleAndroidMedia);
      unawaited(_loadPipSupport());
    }
    _detail = widget.initialItem;
    _infoDetail = widget.initialItem;
    _inlinePlayer = Player();
    _inlineVideoController = VideoController(_inlinePlayer);
    _historyRepository = ref.read(historyRepositoryProvider);
    _autoSavePlaybackProgress =
        ref.read(appSettingsProvider).autoSavePlaybackProgress;
    _speedTestDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 4),
      ),
    );
    _fullscreenBinding = PlatformFullscreenBinding(
      onEnterFullscreen: _handlePlatformEnteredFullscreen,
      onLeaveFullscreen: _handlePlatformExitedFullscreen,
    );
    _fullscreenBinding.attach();
    _playingSubscription =
        _inlinePlayer.stream.playing.listen(_handleInlinePlayingChanged);
    _bufferingSubscription =
        _inlinePlayer.stream.buffering.listen(_handleInlineBufferingChanged);
    _bufferSubscription =
        _inlinePlayer.stream.buffer.listen(_handleInlineBufferChanged);
    _keyboardFocusNode.requestFocus();
    unawaited(_inlinePlayer.setVolume(_volume));
    unawaited(_loadScreenBrightness());
    _progressSaveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_persistProgress()),
    );
    _load();
  }

  @override
  void dispose() {
    _disposing = true;
    _episodeGeneration++;
    _castTimer?.cancel();
    final cast = _castController;
    final device = _castDevice;
    if (cast != null) {
      unawaited(() async {
        try {
          if (device != null) await cast.command(device, 'Stop');
        } catch (_) {
        } finally {
          await cast.dispose();
        }
      }());
    }
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) AndroidMedia.channel.setMethodCallHandler(null);
    _controlsHideTimer?.cancel();
    _progressSaveTimer?.cancel();
    unawaited(_persistProgress());
    _fullscreenBinding.detach();
    _playingSubscription.cancel();
    _bufferingSubscription.cancel();
    _bufferSubscription.cancel();
    _keyboardFocusNode.dispose();
    if (_mobileImmersiveApplied) {
      unawaited(_restoreMobileInlineMode());
    }
    unawaited(resetScreenBrightness());
    if (_traditionalFullscreen) {
      unawaited(setPlatformFullscreen(false));
    }
    _speedTestDio.close(force: true);
    unawaited(_inlinePlayer.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final seed = widget.initialItem;
    setState(() {
      _detail = seed;
      _infoDetail = seed;
      _loading = false;
      _searchingSources = true;
      _error = null;
      _playableLines.clear();
      _candidateDetails.clear();
      _candidateKeys.clear();
      _lineKeys.clear();
      _detailFetchKeys.clear();
      _lineSpeedTests.clear();
      _lineSpeedTesting.clear();
      _selectedLineIndex = 0;
      _selectedEpisodeIndex = 0;
      _resumeEpisodeIndex = 0;
      _resumeProgress = 0;
      _inlineInitialized = false;
      _inlineLoading = false;
      _inlineError = null;
      _inlineSignature = null;
      _processedCandidateCount = 0;
      _initialHistoryApplied = false;
      _restoringInitialHistory = false;
      _startingFirstLine = false;
    });

    try {
      final sites = await ref.read(sourcesRepositoryProvider).fetchSites();
      if (!mounted || generation != _loadGeneration) return;

      final sourceByKey = {for (final site in sites) site.key: site};
      final query = seed.vodName.trim();

      if (seed.sourceKey.isNotEmpty && seed.vodId.isNotEmpty) {
        await _loadSeedDetail(seed, sourceByKey, generation);
      }

      if (query.isNotEmpty) {
        final result = await ref.read(searchRepositoryProvider).search(
          query,
          onBatch: (batch) {
            _scheduleCandidate(
                _appendSearchItems(batch, sourceByKey, generation));
          },
        );
        if (!mounted || generation != _loadGeneration) return;
        await _appendSearchItems(result.items, sourceByKey, generation);
      }

      while (_candidateTasks.isNotEmpty &&
          mounted &&
          generation == _loadGeneration) {
        await Future.wait(_candidateTasks.toList());
      }

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _searchingSources = false;
        if (_playableLines.isEmpty) {
          _error = '未找到可播放源';
        }
      });
      if (widget.initialHistory != null &&
          !_initialHistoryApplied &&
          _playableLines.isNotEmpty) {
        await _applyInitialHistoryLineIfReady();
        if (!mounted) return;
        if (!_initialHistoryApplied && !_restoringInitialHistory) {
          _initialHistoryApplied = true;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('上次观看的片源已不可用，历史进度仍保留。请选择其他片源播放。')));
          await _loadInlineEpisode(episodeIndex: 0);
        }
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = e.toString();
        _searchingSources = false;
        _loading = false;
      });
    }
  }

  Future<void> _loadPipSupport() async {
    try {
      final supported = await AndroidMedia.supportsPip();
      if (mounted) setState(() => _pipSupported = supported);
    } catch (_) {
      // Some Android devices do not provide system picture-in-picture.
    }
  }

  void _scheduleCandidate(Future<void> work) {
    final task = work.catchError((Object _) {});
    _candidateTasks.add(task);
    unawaited(task.whenComplete(() => _candidateTasks.remove(task)));
  }

  Future<void> _handleAndroidMedia(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'pipChanged':
        setState(() {
          _inPip = call.arguments == true;
          _pipPreparing = false;
        });
      case 'togglePlayback':
        await _toggleInlinePlayPause();
      case 'pipClosed':
        await _inlinePlayer.pause();
        await _persistProgress();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_persistProgress());
    }
    if (state == AppLifecycleState.paused &&
        !_inPip &&
        !_pipPreparing &&
        _castDevice == null) {
      unawaited(_inlinePlayer.pause());
    }
  }

  Future<void> _enterPip() async {
    if (!_inlineInitialized || _pipPreparing) return;
    try {
      setState(() => _pipPreparing = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await AndroidMedia.setPlaying(_inlinePlayer.state.playing);
      final entered = await AndroidMedia.enterPip();
      if (!entered) throw StateError('系统未允许画中画，请在应用设置中开启画中画权限');
      if (mounted)
        setState(() {
          _inPip = true;
          _pipPreparing = false;
        });
    } catch (error) {
      if (!mounted) return;
      setState(() => _pipPreparing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('小窗播放失败：$error')));
    }
  }

  Future<void> _openCast() async {
    if (_castBusy || !_inlineInitialized) return;
    if (_castDevice != null) {
      await _showCastControls();
      return;
    }
    setState(() => _castBusy = true);
    final controller = _castController ??= DlnaController();
    try {
      final device = await showDialog<DlnaDevice>(
          context: context,
          builder: (_) => CastDeviceDialog(controller: controller));
      if (!mounted || device == null) return;
      final episode = _currentEpisode;
      if (episode == null) return;
      await _persistProgress();
      final position = _inlinePlayer.state.position;
      await controller.cast(
          device, episode, '${_infoDetail.vodName} · ${episode.name}');
      if (!mounted) return;
      setState(() {
        _castDevice = device;
        _castPosition = Duration.zero;
        _castDuration = _inlinePlayer.state.duration;
        _castPlaying = true;
      });
      await _inlinePlayer.pause();
      if (position > Duration.zero) {
        try {
          await controller.seek(device, position);
          _castPosition = position;
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已开始投屏，但电视未接受进度定位，请在投屏控制中重试。')));
        }
      }
      _castTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => unawaited(_pollCast()));
      if (mounted) await _showCastControls();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('投屏失败：$error')));
    } finally {
      if (mounted) setState(() => _castBusy = false);
    }
  }

  Future<void> _pollCast() async {
    final controller = _castController;
    final device = _castDevice;
    if (_castPolling || device == null || controller == null) return;
    _castPolling = true;
    try {
      final position = await controller.position(device);
      if (!mounted || _castDevice != device) return;
      setState(() {
        _castPosition = position.position;
        _castDuration = position.duration;
      });
    } catch (_) {
      // Keep the last known position across a transient TV/network timeout.
    } finally {
      _castPolling = false;
    }
  }

  Future<void> _stopCasting({required bool resumeLocally}) async {
    final device = _castDevice;
    final controller = _castController;
    if (device == null || controller == null) return;
    await _pollCast();
    await _persistProgress();
    final position = _castPosition;
    await controller.command(device, 'Stop');
    await controller.releaseMedia();
    _castTimer?.cancel();
    _castDevice = null;
    if (!mounted) return;
    setState(() {});
    if (resumeLocally) {
      await _loadInlineEpisode(
          episodeIndex: _selectedEpisodeIndex,
          play: true,
          startAtSeconds: position.inMilliseconds / 1000,
          restart: true);
    }
  }

  Future<void> _showCastControls() async {
    if (!mounted || _castDevice == null) return;
    var busy = false;
    String? error;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) =>
            StatefulBuilder(builder: (sheetContext, update) {
              Future<void> run(Future<void> Function() action) async {
                update(() {
                  busy = true;
                  error = null;
                });
                try {
                  await action();
                } catch (e) {
                  if (sheetContext.mounted) update(() => error = e.toString());
                } finally {
                  if (sheetContext.mounted) update(() => busy = false);
                }
              }

              return SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('正在投屏到 ${_castDevice?.name ?? '电视'}',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text('本机负责转发视频，投屏期间请保持应用运行。'),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(error!)),
                        if (busy) const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Wrap(spacing: 12, children: [
                          IconButton(
                              tooltip: '后退 30 秒',
                              icon: const Icon(Icons.replay_30_rounded),
                              onPressed: busy
                                  ? null
                                  : () => run(() => _seekInline(_castPosition -
                                      const Duration(seconds: 30)))),
                          IconButton(
                              tooltip: _castPlaying ? '暂停' : '播放',
                              icon: Icon(_castPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              onPressed: busy
                                  ? null
                                  : () => run(_toggleInlinePlayPause)),
                          IconButton(
                              tooltip: '前进 30 秒',
                              icon: const Icon(Icons.forward_30_rounded),
                              onPressed: busy
                                  ? null
                                  : () => run(() => _seekInline(_castPosition +
                                      const Duration(seconds: 30)))),
                        ]),
                        FilledButton.icon(
                            icon: const Icon(Icons.stop_screen_share_rounded),
                            label: const Text('结束投屏并在本机继续'),
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                      await _stopCasting(resumeLocally: true);
                                      if (sheetContext.mounted)
                                        Navigator.of(sheetContext).pop();
                                    })),
                      ])));
            }));
  }

  Future<void> _loadSeedDetail(
    VodItem seed,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    await _appendCandidate(seed, sourceByKey, generation);
    if (seed.vodPlayUrl.trim().isNotEmpty) {
      return;
    }
    try {
      final detail = await ref.read(searchRepositoryProvider).getDetail(
            sourceKey: seed.sourceKey,
            vodId: seed.vodId,
          );
      await _mergeCandidateDetail(detail, sourceByKey, generation);
    } catch (_) {}
  }

  Future<void> _appendSearchItems(
    List<VodItem> items,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    if (!mounted || generation != _loadGeneration || items.isEmpty) return;

    final seed = widget.initialItem;
    final normalizedQuery = _normalizeTitle(seed.vodName);
    final exactMatches = items.where((item) {
      return _normalizeTitle(item.vodName) == normalizedQuery;
    }).toList();
    final matches =
        exactMatches.isEmpty ? items.toList(growable: false) : exactMatches;
    if (widget.initialHistory != null && exactMatches.isEmpty) return;
    matches.sort((a, b) {
      return _candidateRank(b, seed, normalizedQuery)
          .compareTo(_candidateRank(a, seed, normalizedQuery));
    });

    for (final item in matches) {
      if (_processedCandidateCount >= 24) return;
      final key = '${item.sourceKey}/${item.vodId}';
      if (item.sourceKey.isEmpty ||
          item.vodId.isEmpty ||
          _candidateKeys.contains(key)) {
        continue;
      }
      _processedCandidateCount++;
      await _appendCandidate(item, sourceByKey, generation);
      _scheduleCandidate(_loadCandidateDetail(item, sourceByKey, generation));
      if (!mounted || generation != _loadGeneration) return;
    }
  }

  Future<void> _loadCandidateDetail(
    VodItem item,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    final key = '${item.sourceKey}/${item.vodId}';
    if (!_detailFetchKeys.add(key)) return;
    try {
      final detail = await ref.read(searchRepositoryProvider).getDetail(
            sourceKey: item.sourceKey,
            vodId: item.vodId,
          );
      await _mergeCandidateDetail(detail, sourceByKey, generation);
    } catch (_) {
    } finally {
      _detailFetchKeys.remove(key);
    }
  }

  Future<void> _mergeCandidateDetail(
    VodItem incoming,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    if (!mounted || generation != _loadGeneration) return;
    if (incoming.sourceKey.isEmpty || incoming.vodId.isEmpty) return;

    final candidateKey = '${incoming.sourceKey}/${incoming.vodId}';
    final index = _candidateDetails.indexWhere(
      (item) => '${item.sourceKey}/${item.vodId}' == candidateKey,
    );
    if (index < 0) {
      await _appendCandidate(incoming, sourceByKey, generation);
      return;
    }

    final merged = _mergeVodItem(_candidateDetails[index], incoming);
    _candidateDetails[index] = merged;
    for (var i = 0; i < _playableLines.length; i++) {
      final line = _playableLines[i];
      if (line.detail.sourceKey == merged.sourceKey &&
          line.detail.vodId == merged.vodId) {
        _playableLines[i] = _PlayableLine(
          detail: merged,
          source: line.source,
          rawName: line.rawName,
          site: line.site,
        );
      }
    }

    if (_selectedLine?.detail.sourceKey == merged.sourceKey &&
        _selectedLine?.detail.vodId == merged.vodId) {
      _detail = merged;
    }
    _refreshInfoDetail();
    await _appendPlayableLines(merged, sourceByKey, generation);
  }

  Future<void> _appendCandidate(
    VodItem candidate,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    if (!mounted || generation != _loadGeneration) return;
    if (candidate.sourceKey.isEmpty || candidate.vodId.isEmpty) return;

    final candidateKey = '${candidate.sourceKey}/${candidate.vodId}';
    if (!_candidateKeys.add(candidateKey)) return;
    _candidateDetails.add(candidate);
    _refreshInfoDetail();

    await _appendPlayableLines(candidate, sourceByKey, generation);
  }

  Future<void> _appendPlayableLines(
    VodItem candidate,
    Map<String, SiteWithStatus> sourceByKey,
    int generation,
  ) async {
    if (!mounted || generation != _loadGeneration) return;

    if (candidate.vodPlayUrl.trim().isEmpty) {
      _refreshInfoDetail();
      return;
    }

    final site = sourceByKey[candidate.sourceKey];
    final referer = site?.detailUrl ?? site?.baseUrl ?? '';
    final playResult = await ref
        .read(playRepositoryProvider)
        .parsePlayUrl(candidate.vodPlayUrl, referer: referer);
    if (!mounted || generation != _loadGeneration) return;

    final addedIndexes = <int>[];
    for (final source in playResult.sources) {
      if (source.episodes.isEmpty) continue;
      final firstUrl = source.episodes.first.effectiveUrl;
      final lineKey =
          '${candidate.sourceKey}/${candidate.vodId}/${source.name}/$firstUrl';
      if (!_lineKeys.add(lineKey)) {
        _updateExistingLine(lineKey, candidate, source, site);
        continue;
      }
      final line = _PlayableLine(
        detail: candidate,
        rawName: source.name,
        source: PlaySource(
          name: _sourceDisplayName(candidate, source, site),
          episodes: source.episodes,
        ),
        site: site,
      );
      _playableLines.add(line);
      addedIndexes.add(_playableLines.length - 1);
    }

    if (addedIndexes.isEmpty) {
      _refreshInfoDetail();
      unawaited(_applyInitialHistoryLineIfReady());
      return;
    }

    if (_playableLines.length == addedIndexes.length) {
      _startingFirstLine = true;
      final selection = _selectionGeneration;
      final selectedLineIndex = _findHistoryLineIndex() ?? 0;
      final selected = _playableLines[selectedLineIndex];
      final (ei, prog) =
          await _loadResumeForLine(selected, lineIndex: selectedLineIndex);
      final favorited =
          await ref.read(favoritesRepositoryProvider).checkFavorite(
                vodId: selected.detail.vodId,
                sourceKey: selected.detail.sourceKey,
              );
      if (!mounted ||
          generation != _loadGeneration ||
          selection != _selectionGeneration) {
        _startingFirstLine = false;
        return;
      }

      setState(() {
        _selectedLineIndex = selectedLineIndex;
        _detail = selected.detail;
        _infoDetail = _buildInfoDetail(
          seed: widget.initialItem,
          selected: selected.detail,
          candidates: _candidateDetails,
        );
        _isFavorited = favorited;
        _sourceEnabled = selected.site?.enabled ?? true;
        _resumeEpisodeIndex = ei;
        _resumeProgress = prog;
        _selectedEpisodeIndex = ei;
        _loading = false;
      });
      _startingFirstLine = false;
      _initialHistoryApplied = widget.initialHistory == null ||
          _historyMatchesLine(
            widget.initialHistory!,
            selected,
            selectedLineIndex,
            strict: true,
          );
      if (_shouldWaitForInitialHistoryLine(selectedLineIndex)) {
        unawaited(_applyInitialHistoryLineIfReady());
      } else {
        unawaited(_loadInlineEpisode(
          episodeIndex: ei,
          startAtSeconds: prog,
          play: widget.initialHistory != null,
        ));
      }
    } else {
      _refreshInfoDetail();
      unawaited(_applyInitialHistoryLineIfReady());
    }

    for (final index in addedIndexes) {
      unawaited(_testLineSpeed(index));
    }
  }

  void _updateExistingLine(
    String lineKey,
    VodItem detail,
    PlaySource source,
    SiteWithStatus? site,
  ) {
    final expectedPrefix = '${detail.sourceKey}/${detail.vodId}/';
    final index = _playableLines.indexWhere((line) {
      final firstUrl = line.source.episodes.first.effectiveUrl;
      return line.detail.sourceKey == detail.sourceKey &&
          line.detail.vodId == detail.vodId &&
          lineKey.startsWith(expectedPrefix) &&
          lineKey.endsWith('/$firstUrl');
    });
    if (index < 0) return;

    final existing = _playableLines[index];
    final episodes = source.episodes.length > existing.source.episodes.length
        ? source.episodes
        : existing.source.episodes;
    _playableLines[index] = _PlayableLine(
      detail: _mergeVodItem(existing.detail, detail),
      rawName: source.name,
      source: PlaySource(
        name: existing.source.name,
        episodes: episodes,
      ),
      site: existing.site ?? site,
    );
  }

  void _refreshInfoDetail() {
    if (!mounted) return;
    final selected = _selectedLine;
    setState(() {
      if (selected != null) {
        _infoDetail = _buildInfoDetail(
          seed: widget.initialItem,
          selected: selected.detail,
          candidates: _candidateDetails,
        );
      } else if (_candidateDetails.isNotEmpty) {
        _infoDetail = _buildInfoDetail(
          seed: widget.initialItem,
          selected: _candidateDetails.first,
          candidates: _candidateDetails,
        );
      } else {
        _infoDetail = widget.initialItem;
      }
    });
  }

  int _candidateRank(VodItem item, VodItem seed, String normalizedQuery) {
    var score = 0;
    if (_hasHlsHint(item.vodPlayUrl)) {
      score += 40;
    } else if (_hasPlayableHint(item.vodPlayUrl)) {
      score += 20;
    }
    if (_normalizeTitle(item.vodName) == normalizedQuery) {
      score += 30;
    }
    final seedYear = seed.vodYear?.trim();
    final itemYear = item.vodYear?.trim();
    if (seedYear != null &&
        seedYear.isNotEmpty &&
        itemYear != null &&
        itemYear == seedYear) {
      score += 12;
    }
    final seedType = _searchTypeKey(seed);
    final itemType = _searchTypeKey(item);
    if (seedType != null && itemType != null && seedType == itemType) {
      score += 6;
    }
    score += _metadataScore(item);
    return score;
  }

  bool _hasPlayableHint(String value) {
    return value.trim().isNotEmpty && value.contains(r'$');
  }

  bool _hasHlsHint(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('m3u8');
  }

  VodItem _buildInfoDetail({
    required VodItem seed,
    required VodItem selected,
    required List<VodItem> candidates,
  }) {
    final pool = [seed, ...candidates, selected];
    final best =
        pool.reduce((a, b) => _metadataScore(a) >= _metadataScore(b) ? a : b);
    final content = pool
        .where((item) => _hasText(item.vodContent))
        .fold<VodItem?>(null, (current, item) {
      if (current == null) return item;
      return item.vodContent!.length > current.vodContent!.length
          ? item
          : current;
    });

    return VodItem(
      sourceKey: selected.sourceKey,
      vodId: selected.vodId,
      vodName: _firstText([seed.vodName, best.vodName, selected.vodName]) ?? '',
      vodPlayUrl: selected.vodPlayUrl,
      vodPic: _firstText([seed.vodPic, best.vodPic, selected.vodPic]),
      vodRemarks:
          _firstText([seed.vodRemarks, best.vodRemarks, selected.vodRemarks]),
      vodActor:
          _firstText([best.vodActor, content?.vodActor, selected.vodActor]),
      vodDirector: _firstText([
        best.vodDirector,
        content?.vodDirector,
        selected.vodDirector,
      ]),
      vodContent: _firstText(
          [content?.vodContent, best.vodContent, selected.vodContent]),
      vodYear: _firstText([seed.vodYear, best.vodYear, selected.vodYear]),
      vodArea: _firstText([best.vodArea, selected.vodArea, seed.vodArea]),
      vodClass: _firstText([best.vodClass, selected.vodClass]),
      vodTag: _firstText([best.vodTag, selected.vodTag]),
      vodDuration: _firstText([best.vodDuration, selected.vodDuration]),
      vodLang: _firstText([best.vodLang, selected.vodLang]),
      typeName: _firstText([best.typeName, selected.typeName]),
    );
  }

  VodItem _mergeVodItem(VodItem current, VodItem incoming) {
    return VodItem(
      sourceKey:
          current.sourceKey.isNotEmpty ? current.sourceKey : incoming.sourceKey,
      vodId: current.vodId.isNotEmpty ? current.vodId : incoming.vodId,
      vodName: _firstText([incoming.vodName, current.vodName]) ?? '',
      vodPlayUrl: _firstText([incoming.vodPlayUrl, current.vodPlayUrl]) ?? '',
      vodPic: _firstText([incoming.vodPic, current.vodPic]),
      vodRemarks: _firstText([incoming.vodRemarks, current.vodRemarks]),
      vodActor: _firstText([incoming.vodActor, current.vodActor]),
      vodDirector: _firstText([incoming.vodDirector, current.vodDirector]),
      vodContent: _firstText([incoming.vodContent, current.vodContent]),
      vodYear: _firstText([incoming.vodYear, current.vodYear]),
      vodArea: _firstText([incoming.vodArea, current.vodArea]),
      vodClass: _firstText([incoming.vodClass, current.vodClass]),
      vodTag: _firstText([incoming.vodTag, current.vodTag]),
      vodDuration: _firstText([incoming.vodDuration, current.vodDuration]),
      vodLang: _firstText([incoming.vodLang, current.vodLang]),
      typeName: _firstText([incoming.typeName, current.typeName]),
      avgSpeedMs: incoming.avgSpeedMs ?? current.avgSpeedMs,
    );
  }

  Future<(int, double)> _loadResumeForLine(
    _PlayableLine line, {
    int? lineIndex,
  }) async {
    final index = lineIndex ?? _playableLines.indexOf(line);
    final initialHistory = widget.initialHistory;
    WatchHistoryItem? resumeItem;
    if (initialHistory != null &&
        !_initialHistoryApplied &&
        _historyMatchesLine(initialHistory, line, index, strict: false)) {
      resumeItem = initialHistory;
    } else {
      final history = await _historyRepository.fetchHistory();
      resumeItem = history.where((item) {
        return _historyMatchesLine(item, line, index, strict: true);
      }).firstOrNull;
      resumeItem ??= history.where((item) {
        return _historyMatchesLine(item, line, index, strict: false);
      }).firstOrNull;
    }
    if (resumeItem == null) {
      return (0, 0.0);
    }
    final result = PlayResult(sources: [line.source]);
    final (_, ei) = _locateEpisode(
      result,
      resumeItem.episode,
      sourceIndex: 0,
      episodeIndex: resumeItem.episodeIndex,
    );
    return (
      ei,
      resumeItem.progress.isFinite
          ? resumeItem.progress.clamp(0, double.infinity).toDouble()
          : 0.0
    );
  }

  int? _findHistoryLineIndex() {
    final history = widget.initialHistory;
    if (history == null) return null;

    for (var i = 0; i < _playableLines.length; i++) {
      if (_historyMatchesLine(history, _playableLines[i], i, strict: true)) {
        return i;
      }
    }
    for (var i = 0; i < _playableLines.length; i++) {
      if (_historyMatchesLine(history, _playableLines[i], i, strict: false)) {
        return i;
      }
    }
    return null;
  }

  Future<void> _applyInitialHistoryLineIfReady() async {
    if (_startingFirstLine ||
        _initialHistoryApplied ||
        widget.initialHistory == null) return;
    final index = _findHistoryLineIndex();
    if (index == null) return;
    if (_restoringInitialHistory) return;
    _restoringInitialHistory = true;
    try {
      await _restoreInitialHistoryAtLine(index);
    } finally {
      _restoringInitialHistory = false;
      _initialHistoryApplied = true;
    }
  }

  Future<void> _restoreInitialHistoryAtLine(int index) async {
    if (index < 0 || index >= _playableLines.length) return;
    final selection = ++_selectionGeneration;
    final line = _playableLines[index];
    final (ei, prog) = await _loadResumeForLine(line, lineIndex: index);
    final isFavorited = await ref
        .read(favoritesRepositoryProvider)
        .checkFavorite(
            vodId: line.detail.vodId, sourceKey: line.detail.sourceKey);
    if (!mounted || selection != _selectionGeneration) return;

    _restoringInitialHistory = true;
    try {
      setState(() {
        _selectedLineIndex = index;
        _detail = line.detail;
        _isFavorited = isFavorited;
        _sourceEnabled = line.site?.enabled ?? true;
        _resumeEpisodeIndex = ei;
        _resumeProgress = prog;
        _selectedEpisodeIndex = ei;
        _loading = false;
      });
      await _loadInlineEpisode(
        episodeIndex: ei,
        startAtSeconds: prog,
        play: true,
      );
    } finally {
      _restoringInitialHistory = false;
    }
  }

  bool _shouldWaitForInitialHistoryLine(int selectedLineIndex) {
    final history = widget.initialHistory;
    if (history == null || _initialHistoryApplied) return false;
    if (!_historyHasLineHint(history)) return false;
    return !_historyMatchesLine(
      history,
      _playableLines[selectedLineIndex],
      selectedLineIndex,
      strict: true,
    );
  }

  bool _historyMatchesLine(
    WatchHistoryItem item,
    _PlayableLine line,
    int lineIndex, {
    required bool strict,
  }) {
    if (item.vodId != line.detail.vodId ||
        item.sourceKey != line.detail.sourceKey) {
      return false;
    }
    if (!strict) return true;
    if (item.playbackLineName?.isNotEmpty == true) {
      return item.playbackLineName == line.rawName;
    }
    final sourceName = item.sourceName?.trim();
    if (sourceName != null && sourceName.isNotEmpty) {
      if (_normalizeLineName(sourceName) ==
              _normalizeLineName(line.source.name) ||
          _normalizeLineName(sourceName) == _normalizeLineName(line.rawName))
        return true;
      if (sourceName.split(' · ').last == line.rawName) return true;
    }
    // Legacy sourceIndex is a global search-result index, not a stable line ID.
    return !_historyHasLineHint(item);
  }

  bool _historyHasLineHint(WatchHistoryItem item) {
    return item.sourceIndex != null ||
        (item.sourceName != null && item.sourceName!.trim().isNotEmpty);
  }

  String _normalizeLineName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  String _sourceDisplayName(
    VodItem detail,
    PlaySource source,
    SiteWithStatus? site,
  ) {
    final siteName = site?.name.trim();
    final base =
        siteName == null || siteName.isEmpty ? detail.sourceKey : siteName;
    if (source.name.isEmpty || source.name == '播放源 1') {
      return base;
    }
    return '$base · ${source.name}';
  }

  Future<void> _selectLine(int index) async {
    if (index == _selectedLineIndex ||
        index < 0 ||
        index >= _playableLines.length) {
      return;
    }
    final selection = ++_selectionGeneration;
    _episodeGeneration++;
    await _persistProgress();
    if (!mounted || selection != _selectionGeneration) return;
    _initialHistoryApplied = true;
    if (_castDevice != null) await _stopCasting(resumeLocally: false);
    final line = _playableLines[index];
    final (ei, prog) = await _loadResumeForLine(line, lineIndex: index);
    final isFavorited = await ref
        .read(favoritesRepositoryProvider)
        .checkFavorite(
            vodId: line.detail.vodId, sourceKey: line.detail.sourceKey);
    if (!mounted || selection != _selectionGeneration) {
      return;
    }
    setState(() {
      _selectedLineIndex = index;
      _detail = line.detail;
      _isFavorited = isFavorited;
      _sourceEnabled = line.site?.enabled ?? true;
      _resumeEpisodeIndex = ei;
      _resumeProgress = prog;
      _selectedEpisodeIndex = ei;
    });
    await _loadInlineEpisode(
      episodeIndex: ei,
      startAtSeconds: prog,
    );
  }

  Future<void> _selectBestLine() async {
    if (_playableLines.length <= 1) {
      return;
    }
    var bestIndex = _selectedLineIndex;
    double? bestScore;
    for (var i = 0; i < _playableLines.length; i++) {
      final score = _sourceScore(i);
      if (score == null) {
        continue;
      }
      if (bestScore == null || score > bestScore) {
        bestIndex = i;
        bestScore = score;
      }
    }
    await _selectLine(bestIndex);
  }

  double? _sourceScore(int index) {
    final speedTest = _lineSpeedTests[index];
    if (speedTest != null && speedTest.isSuccess) {
      final speedScore =
          (speedTest.speedKBps! / 1024).clamp(0.0, 1.0).toDouble() * 60;
      final latencyScore =
          (1 - (speedTest.pingMs! / 1200).clamp(0.0, 1.0).toDouble()) * 40;
      return speedScore + latencyScore;
    }
    final siteLatency = _playableLines[index].site?.responseTimeMs;
    if (siteLatency == null || siteLatency <= 0) {
      return null;
    }
    return (1 - (siteLatency / 1500).clamp(0.0, 1.0).toDouble()) * 40;
  }

  Future<void> _testLineSpeed(int index) async {
    if (index < 0 ||
        index >= _playableLines.length ||
        _lineSpeedTesting.contains(index)) {
      return;
    }
    final line = _playableLines[index];
    if (line.source.episodes.isEmpty) {
      return;
    }
    final episode = line.source.episodes.length > 1
        ? line.source.episodes[1]
        : line.source.episodes.first;
    setState(() {
      _lineSpeedTesting.add(index);
      _lineSpeedTests[index] = const _LineSpeedTest.testing();
    });
    try {
      final result = await _measureEpisodeSpeed(episode);
      if (!mounted) return;
      setState(() {
        _lineSpeedTesting.remove(index);
        _lineSpeedTests[index] = result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lineSpeedTesting.remove(index);
        _lineSpeedTests[index] = const _LineSpeedTest.failed();
      });
    }
  }

  Future<_LineSpeedTest> _measureEpisodeSpeed(PlayEpisode episode) async {
    final url = episode.effectiveUrl;
    final headers = episode.httpHeaders ?? const <String, String>{};
    final pingMs = await _measurePing(url, headers);
    final targetUrl = url.toLowerCase().contains('.m3u8')
        ? await _resolveFirstM3u8Segment(url, headers)
        : url;
    final speed = await _measureDownloadSpeed(targetUrl, headers);
    return _LineSpeedTest.success(
      pingMs: pingMs ?? speed.pingMs,
      speedKBps: speed.speedKBps,
      bytesRead: speed.bytesRead,
    );
  }

  Future<int?> _measurePing(String url, Map<String, String> headers) async {
    final sw = Stopwatch()..start();
    try {
      await _speedTestDio.head<void>(
        url,
        options: Options(headers: headers, validateStatus: (_) => true),
      );
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolveFirstM3u8Segment(
    String url,
    Map<String, String> headers,
  ) async {
    final response = await _speedTestDio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final text = response.data ?? '';
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      return Uri.parse(url).resolve(line).toString();
    }
    return url;
  }

  Future<_DownloadProbe> _measureDownloadSpeed(
    String url,
    Map<String, String> headers,
  ) async {
    final probeHeaders = <String, String>{
      ...headers,
      'Range': 'bytes=0-${_speedProbeBytes - 1}',
    };
    final sw = Stopwatch()..start();
    final response = await _speedTestDio.get<List<int>>(
      url,
      options: Options(
        headers: probeHeaders,
        responseType: ResponseType.bytes,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final elapsedMs = sw.elapsedMilliseconds.clamp(1, 1 << 31);
    final bytes = response.data?.length ?? 0;
    if (bytes <= 0) {
      throw StateError('empty speed probe');
    }
    final speedKBps = bytes / 1024 / (elapsedMs / 1000);
    return _DownloadProbe(
      pingMs: elapsedMs,
      speedKBps: speedKBps,
      bytesRead: bytes,
    );
  }

  void _handleInlinePlayingChanged(bool playing) {
    if (!mounted) return;
    if (Platform.isAndroid)
      unawaited(AndroidMedia.setPlaying(playing).catchError((Object _) {}));
    if (playing) {
      _startControlsHideTimer();
      return;
    }
    _controlsHideTimer?.cancel();
    setState(() => _showPlayerControls = true);
  }

  void _handleInlineBufferingChanged(bool buffering) {
    if (!mounted) return;
    setState(() => _isBuffering = buffering);
  }

  void _handleInlineBufferChanged(Duration buffer) {
    if (!mounted) return;
    setState(() => _bufferPosition = buffer);
  }

  void _handlePlatformEnteredFullscreen() {
    if (!mounted) return;
    setState(() {
      _traditionalFullscreen = true;
      _showPlayerControls = true;
    });
    _startControlsHideTimer();
  }

  void _handlePlatformExitedFullscreen() {
    if (!mounted) return;
    setState(() {
      _traditionalFullscreen = false;
      if (!_wasExpandedBeforeTraditionalFullscreen) {
        _playerExpanded = false;
        _episodeDrawerOpen = false;
      }
      _showPlayerControls = true;
    });
    _startControlsHideTimer();
  }

  void _startControlsHideTimer() {
    _controlsHideTimer?.cancel();
    if (!_inlinePlayer.state.playing || _episodeDrawerOpen) return;
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _episodeDrawerOpen) return;
      setState(() => _showPlayerControls = false);
    });
  }

  void _cancelControlsHideTimer() {
    _controlsHideTimer?.cancel();
  }

  void _showControlsNow() {
    if (!mounted) return;
    if (!_showPlayerControls) {
      setState(() => _showPlayerControls = true);
    }
    _startControlsHideTimer();
  }

  void _toggleControls() {
    if (!mounted) return;
    _keyboardFocusNode.requestFocus();
    setState(() => _showPlayerControls = !_showPlayerControls);
    if (_showPlayerControls) {
      _startControlsHideTimer();
    } else {
      _cancelControlsHideTimer();
    }
  }

  void _desktopShowControls() {
    if (!mounted) return;
    if (!_showPlayerControls) {
      setState(() => _showPlayerControls = true);
    }
  }

  void _desktopHideControls() {
    if (!mounted || _episodeDrawerOpen || !_inlinePlayer.state.playing) return;
    if (_showPlayerControls) {
      setState(() => _showPlayerControls = false);
    }
  }

  void _forceHideControls() {
    if (!mounted) return;
    _cancelControlsHideTimer();
    setState(() => _showPlayerControls = false);
  }

  Future<void> _toggleInlinePlayPause() async {
    final device = _castDevice;
    if (device != null) {
      await _castController!.command(device, _castPlaying ? 'Pause' : 'Play',
          _castPlaying ? const {} : const {'Speed': '1'});
      if (mounted) setState(() => _castPlaying = !_castPlaying);
      return;
    }
    if (_inlinePlayer.state.playing) {
      await _inlinePlayer.pause();
      return;
    }
    await _inlinePlayer.play();
    _showControlsNow();
  }

  Future<void> _seekInline(Duration position) async {
    final device = _castDevice;
    if (device != null) {
      final target = Duration(
          milliseconds: position.inMilliseconds.clamp(
              0,
              _castDuration > Duration.zero
                  ? _castDuration.inMilliseconds
                  : 1 << 53));
      await _castController!.seek(device, target);
      if (mounted) setState(() => _castPosition = target);
      return;
    }
    final duration = _inlinePlayer.state.duration;
    final target = duration == Duration.zero
        ? position
        : Duration(
            milliseconds:
                position.inMilliseconds.clamp(0, duration.inMilliseconds),
          );
    setState(() => _isSeeking = true);
    try {
      await _inlinePlayer.seek(target);
    } finally {
      if (mounted) {
        setState(() => _isSeeking = false);
      }
    }
    _showControlsNow();
  }

  Future<void> _seekRelative(Duration delta) async {
    await _seekInline(_inlinePlayer.state.position + delta);
  }

  Future<void> _setInlineVolume(double value) async {
    final next = value.clamp(0, 100).toDouble();
    setState(() => _volume = next);
    await _inlinePlayer.setVolume(next);
  }

  Future<void> _adjustInlineVolume(double delta) async {
    await _setInlineVolume(_volume + delta);
    _showControlsNow();
  }

  Future<void> _setInlineSpeed(double value) async {
    _temporarySpeedSaved = value;
    setState(() => _playbackSpeed = value);
    await _inlinePlayer.setRate(value);
    _showControlsNow();
  }

  Future<void> _setTemporarySpeed(bool active) async {
    if (active == _temporarySpeedActive) return;
    if (active) {
      _temporarySpeedSaved = _playbackSpeed;
      _temporarySpeedActive = true;
      await _inlinePlayer.setRate(2);
    } else {
      _temporarySpeedActive = false;
      await _inlinePlayer.setRate(_temporarySpeedSaved);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadScreenBrightness() async {
    final brightness = await readScreenBrightness();
    if (!mounted) return;
    setState(() => _brightness = brightness);
  }

  Future<void> _setBrightness(double value) async {
    final next = value.clamp(0.0, 1.0).toDouble();
    setState(() => _brightness = next);
    await setScreenBrightness(next);
  }

  void _setInlineFit(int value) {
    setState(() => _fitMode = value);
    _showControlsNow();
  }

  Future<void> _handleKeyEvent(KeyEvent event) async {
    final key = event.logicalKey;

    if (event is KeyRepeatEvent && key == LogicalKeyboardKey.arrowRight) {
      if (!_temporarySpeedActive) {
        await _setTemporarySpeed(true);
      }
      return;
    }

    if (event is KeyUpEvent && key == LogicalKeyboardKey.arrowRight) {
      if (_temporarySpeedActive) {
        await _setTemporarySpeed(false);
      }
      return;
    }

    if (event is! KeyDownEvent) return;

    if (key == LogicalKeyboardKey.escape) {
      if (_episodeDrawerOpen) {
        _closeEpisodeDrawer();
        return;
      }
      if (_traditionalFullscreen) {
        await _exitTraditionalFullscreen();
        return;
      }
      if (_playerExpanded) {
        await _exitExpandedPlayer();
        return;
      }
    }
    if (key == LogicalKeyboardKey.space) {
      await _toggleInlinePlayPause();
      return;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      await _toggleTraditionalFullscreen();
      return;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleEpisodeDrawer();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      await _seekRelative(-_seekStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      await _seekRelative(_seekStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      await _adjustInlineVolume(_volumeStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      await _adjustInlineVolume(-_volumeStep);
      return;
    }
    if (key == LogicalKeyboardKey.pageUp && _canPlayPrevious) {
      await _selectPreviousEpisode();
      return;
    }
    if (key == LogicalKeyboardKey.pageDown && _canPlayNext) {
      await _selectNextEpisode();
    }
  }

  Future<void> _selectPreviousEpisode() async {
    if (!_canPlayPrevious) return;
    await _selectInlineEpisode(_selectedEpisodeIndex - 1);
  }

  Future<void> _selectNextEpisode() async {
    if (!_canPlayNext) return;
    await _selectInlineEpisode(_selectedEpisodeIndex + 1);
  }

  void _toggleEpisodeDrawer() {
    setState(() {
      _episodeDrawerOpen = !_episodeDrawerOpen;
      _showPlayerControls = true;
    });
    if (_episodeDrawerOpen) {
      _controlsHideTimer?.cancel();
    } else {
      _startControlsHideTimer();
    }
  }

  void _closeEpisodeDrawer() {
    if (!_episodeDrawerOpen) return;
    setState(() => _episodeDrawerOpen = false);
    _startControlsHideTimer();
  }

  Future<void> _toggleExpandedPlayer() async {
    if (_playerExpanded) {
      await _exitExpandedPlayer();
    } else {
      await _enterExpandedPlayer();
    }
  }

  Future<void> _toggleTraditionalFullscreen() async {
    if (!isDesktopPlatform) {
      await _toggleExpandedPlayer();
      return;
    }
    if (_traditionalFullscreen) {
      await _exitTraditionalFullscreen();
    } else {
      await _enterTraditionalFullscreen();
    }
  }

  Future<void> _enterTraditionalFullscreen() async {
    if (_traditionalFullscreen) return;
    _wasExpandedBeforeTraditionalFullscreen = _playerExpanded;
    if (!_playerExpanded) {
      setState(() {
        _playerExpanded = true;
        _showPlayerControls = true;
      });
    }
    await setPlatformFullscreen(true);
    if (!mounted) return;
    setState(() {
      _traditionalFullscreen = true;
      _showPlayerControls = true;
    });
    await _inlinePlayer.play();
    _startControlsHideTimer();
  }

  Future<void> _exitTraditionalFullscreen() async {
    if (!_traditionalFullscreen) return;
    await setPlatformFullscreen(false);
    if (!mounted) return;
    setState(() {
      _traditionalFullscreen = false;
      if (!_wasExpandedBeforeTraditionalFullscreen) {
        _playerExpanded = false;
        _episodeDrawerOpen = false;
      }
      _showPlayerControls = true;
    });
    _startControlsHideTimer();
  }

  Future<void> _enterExpandedPlayer() async {
    if (_playerExpanded) return;
    setState(() {
      _playerExpanded = true;
      _showPlayerControls = true;
    });
    if (isMobilePlatform) {
      _mobileImmersiveApplied = true;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    await _inlinePlayer.play();
    _startControlsHideTimer();
  }

  Future<void> _exitExpandedPlayer() async {
    if (!_playerExpanded) return;
    if (_traditionalFullscreen) {
      await _exitTraditionalFullscreen();
      return;
    }
    setState(() {
      _playerExpanded = false;
      _episodeDrawerOpen = false;
      _showPlayerControls = true;
    });
    if (_mobileImmersiveApplied) {
      await _restoreMobileInlineMode();
    }
  }

  Future<void> _restoreMobileInlineMode() async {
    _mobileImmersiveApplied = false;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _selectInlineEpisode(int index) async {
    final selection = ++_selectionGeneration;
    _episodeGeneration++;
    await _persistProgress();
    if (!mounted || selection != _selectionGeneration) return;
    _initialHistoryApplied = true;
    await _loadInlineEpisode(episodeIndex: index, play: true);
  }

  Future<void> _loadInlineEpisode({
    required int episodeIndex,
    bool play = false,
    double startAtSeconds = 0,
    bool restart = false,
  }) {
    final generation = ++_episodeGeneration;
    final task = _episodeQueue.then((_) async {
      if (!mounted || _disposing || generation != _episodeGeneration) return;
      if (_castDevice != null) await _stopCasting(resumeLocally: false);
      if (!mounted || generation != _episodeGeneration) return;
      await _performLoadInlineEpisode(
          generation: generation,
          episodeIndex: episodeIndex,
          play: play,
          startAtSeconds: startAtSeconds,
          restart: restart);
    });
    _episodeQueue = task.catchError((Object _) {});
    return task;
  }

  Future<void> _performLoadInlineEpisode({
    required int generation,
    bool restart = false,
    required int episodeIndex,
    bool play = false,
    double startAtSeconds = 0,
  }) async {
    final line = _selectedLine;
    if (line == null || line.source.episodes.isEmpty) {
      return;
    }
    final clampedIndex = episodeIndex.clamp(0, line.source.episodes.length - 1);
    final episode = line.source.episodes[clampedIndex];
    final signature =
        '${line.detail.sourceKey}/${line.detail.vodId}/$clampedIndex/${episode.effectiveUrl}';
    if (!restart &&
        _inlineSignature == signature &&
        _inlineInitialized &&
        (startAtSeconds <= 0 ||
            (_inlinePlayer.state.position.inMilliseconds / 1000 -
                        startAtSeconds)
                    .abs() <
                2)) {
      if (play) {
        await _inlinePlayer.play();
      }
      return;
    }

    setState(() {
      _selectedEpisodeIndex = clampedIndex;
      _inlineLoading = true;
      _inlineInitialized = false;
      _isBuffering = false;
      _isSeeking = false;
      _bufferPosition = Duration.zero;
      _inlineError = null;
      _showPlayerControls = true;
    });

    try {
      await openPlayback(
        player: _inlinePlayer,
        media: Media(episode.effectiveUrl, httpHeaders: episode.httpHeaders),
        play: play,
        start: Duration(milliseconds: (startAtSeconds * 1000).round()),
        isCurrent: () =>
            mounted && !_disposing && generation == _episodeGeneration,
      );
      if (!mounted || _disposing || generation != _episodeGeneration) return;
      await _inlinePlayer.setRate(_playbackSpeed);
      await _inlinePlayer.setVolume(_volume);
      if (!mounted || generation != _episodeGeneration) return;
      setState(() {
        _inlineInitialized = true;
        _inlineLoading = false;
        _inlineSignature = signature;
      });
      _startControlsHideTimer();
    } catch (error) {
      if (!mounted || generation != _episodeGeneration) {
        return;
      }
      setState(() {
        _inlineInitialized = false;
        _inlineLoading = false;
        _inlineError = error.toString();
      });
    }
  }

  Future<void> _persistProgress({bool force = false}) async {
    if (_restoringInitialHistory || _inlineLoading || _isSeeking) {
      return;
    }
    final line = _selectedLine;
    final episode = _currentEpisode;
    if (line == null || episode == null || !_inlineInitialized) {
      return;
    }
    if (_inlineSignature !=
        '${line.detail.sourceKey}/${line.detail.vodId}/$_selectedEpisodeIndex/${episode.effectiveUrl}')
      return;
    if (!_autoSavePlaybackProgress) {
      return;
    }
    final positionSeconds =
        (_castDevice == null ? _inlinePlayer.state.position : _castPosition)
            .inSeconds
            .toDouble();
    final durationSeconds =
        (_castDevice == null ? _inlinePlayer.state.duration : _castDuration)
            .inSeconds
            .toDouble();
    if (!force && positionSeconds < 1) {
      return;
    }
    if (positionSeconds <= 0) {
      return;
    }
    final signature =
        '${line.detail.sourceKey}|${line.detail.vodId}|$_selectedEpisodeIndex|'
        '${positionSeconds.round()}';
    if (!force && _lastPersistSignature == signature) {
      return;
    }
    await _historyRepository.addHistory(
      WatchHistoryUpsert(
        vodId: line.detail.vodId,
        sourceKey: line.detail.sourceKey,
        vodName: _infoDetail.vodName,
        vodPic: _infoDetail.vodPic ?? line.detail.vodPic,
        sourceName: line.source.name,
        playbackLineName: line.rawName,
        year: _infoDetail.vodYear ?? line.detail.vodYear,
        totalEpisodes: line.source.episodes.length,
        totalTime: durationSeconds > 0 ? durationSeconds : null,
        searchTitle: widget.initialItem.vodName,
        progress: positionSeconds,
        episode: episode.name,
        sourceIndex: _selectedLineIndex,
        episodeIndex: _selectedEpisodeIndex,
      ),
    );
    if (!_disposing && mounted) {
      ref.invalidate(historyItemsProvider);
    }
    _lastPersistSignature = signature;
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) {
      return;
    }
    final line = _selectedLine;
    if (line == null) {
      return;
    }
    setState(() => _favoriteLoading = true);
    final repo = ref.read(favoritesRepositoryProvider);
    final favoriteDetail = _favoriteDetailForLine(line);
    try {
      if (_isFavorited) {
        await repo.deleteFavorite(
          vodId: line.detail.vodId,
          sourceKey: line.detail.sourceKey,
        );
      } else {
        await repo.addFavorite(
          favoriteDetail,
          sourceName: line.source.name,
          year: favoriteDetail.vodYear,
          totalEpisodes: line.source.episodes.length,
          searchTitle: widget.initialItem.vodName,
        );
      }
      final favorited = await repo.checkFavorite(
        vodId: line.detail.vodId,
        sourceKey: line.detail.sourceKey,
      );
      if (!mounted) return;
      ref.invalidate(favoriteItemsProvider);
      setState(() => _isFavorited = favorited);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(favorited ? '已收藏' : '已取消收藏')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏操作失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _favoriteLoading = false);
      }
    }
  }

  VodItem _favoriteDetailForLine(_PlayableLine line) {
    return VodItem(
      sourceKey: line.detail.sourceKey,
      vodId: line.detail.vodId,
      vodName: _firstText([
            _infoDetail.vodName,
            line.detail.vodName,
            widget.initialItem.vodName,
          ]) ??
          '',
      vodPlayUrl: line.detail.vodPlayUrl,
      vodPic: _firstText([
        _infoDetail.vodPic,
        line.detail.vodPic,
        widget.initialItem.vodPic,
      ]),
      vodRemarks: _firstText([
        _infoDetail.vodRemarks,
        line.detail.vodRemarks,
        widget.initialItem.vodRemarks,
      ]),
      vodActor: _firstText([_infoDetail.vodActor, line.detail.vodActor]),
      vodDirector:
          _firstText([_infoDetail.vodDirector, line.detail.vodDirector]),
      vodContent: _firstText([_infoDetail.vodContent, line.detail.vodContent]),
      vodYear: _firstText([
        _infoDetail.vodYear,
        line.detail.vodYear,
        widget.initialItem.vodYear,
      ]),
      vodArea: _firstText([_infoDetail.vodArea, line.detail.vodArea]),
      vodClass: _firstText([_infoDetail.vodClass, line.detail.vodClass]),
      vodTag: _firstText([_infoDetail.vodTag, line.detail.vodTag]),
      vodDuration:
          _firstText([_infoDetail.vodDuration, line.detail.vodDuration]),
      vodLang: _firstText([_infoDetail.vodLang, line.detail.vodLang]),
      typeName: _firstText([_infoDetail.typeName, line.detail.typeName]),
      avgSpeedMs: line.detail.avgSpeedMs ?? _infoDetail.avgSpeedMs,
    );
  }

  Future<void> _disableCurrentSource() async {
    if (_sourceToggleLoading || !_sourceEnabled) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('禁用此源'),
          content: Text(
            '禁用片源 ${_detail.sourceKey} 后，后续搜索和详情将不再默认使用它。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('禁用'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _sourceToggleLoading = true);
    try {
      await ref.read(sourcesRepositoryProvider).toggleSite(
            key: _detail.sourceKey,
            enabled: false,
          );
      ref.invalidate(siteListProvider);
      if (!mounted) {
        return;
      }
      setState(() => _sourceEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已禁用片源 ${_detail.sourceKey}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('禁用失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _sourceToggleLoading = false);
      }
    }
  }

  Future<void> _openPlayer(int si, int ei, double prog) async {
    if (_castDevice != null) {
      await _showCastControls();
      return;
    }
    final source = _currentSource;
    if (source == null || source.episodes.isEmpty) return;
    final targetEpisode = ei.clamp(0, source.episodes.length - 1);
    await _loadInlineEpisode(
        episodeIndex: targetEpisode,
        play: true,
        startAtSeconds: prog,
        restart: prog == 0);
    if (!mounted || !_inlineInitialized) return;
    await _enterExpandedPlayer();
  }

  (int, int) _locateEpisode(
    PlayResult result,
    String? name, {
    int? sourceIndex,
    int? episodeIndex,
  }) {
    if (name != null && name.isNotEmpty) {
      for (var si = 0; si < result.sources.length; si++) {
        final eps = result.sources[si].episodes;
        for (var ei = 0; ei < eps.length; ei++) {
          if (eps[ei].name.trim() == name.trim()) return (si, ei);
        }
      }
    }
    if (sourceIndex != null &&
        episodeIndex != null &&
        sourceIndex >= 0 &&
        sourceIndex < result.sources.length &&
        episodeIndex >= 0 &&
        episodeIndex < result.sources[sourceIndex].episodes.length) {
      return (sourceIndex, episodeIndex);
    }
    return (0, 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_inPip || _pipPreparing) {
      return Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
              child: Video(
                  controller: _inlineVideoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  pauseUponEnteringBackgroundMode: false)));
    }
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(scrolledUnderElevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _playableLines.isEmpty && !_searchingSources) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final content = isDesktopPlatform
        ? _buildDesktopLayout(context, cs)
        : _buildMobileLayout(context, cs);

    if (_playerExpanded) {
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (_, __) => unawaited(_exitExpandedPlayer()),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: KeyboardListener(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: _buildExpandedPlayer(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: isDesktopPlatform
            ? PlatformDragToMoveArea(
                child: SizedBox(
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_infoDetail.vodName),
                  ),
                ),
              )
            : Text(
                _infoDetail.vodName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        scrolledUnderElevation: 0,
        actions: [
          _favoriteLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _isFavorited ? cs.error : null,
                  ),
                ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: content,
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, ColorScheme cs) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildPlayerFrame(context, fill: false),
          ),
        ),
        SliverToBoxAdapter(child: _buildInfoBlock(context, cs, compact: false)),
        SliverToBoxAdapter(child: _buildActionBlock(context)),
        SliverToBoxAdapter(child: _buildSourceSwitcher(context, cs)),
        _buildEpisodeGrid(context, cs),
        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
            child: _buildPlayerFrame(context, fill: true),
          ),
        ),
        SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                children: [
                  _RightPanelCover(detail: _infoDetail),
                  const SizedBox(height: 14),
                  _buildInfoBlock(context, cs, compact: true),
                  const SizedBox(height: 14),
                  _buildActionBlock(context),
                  const SizedBox(height: 14),
                  _buildSourceSwitcher(context, cs, padded: false),
                  const SizedBox(height: 10),
                  _EpisodeGridBox(
                    source: _selectedLine?.source,
                    speedTest: _lineSpeedTests[_selectedLineIndex],
                    selectedEpisodeIndex: _selectedEpisodeIndex,
                    resumeEpisodeIndex: _resumeEpisodeIndex,
                    resumeProgress: _resumeProgress,
                    onEpisode: (index, _) => _selectInlineEpisode(index),
                  ),
                  if (_infoDetail.vodContent != null &&
                      _infoDetail.vodContent!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '简介',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _ExpandableText(text: _infoDetail.vodContent!),
                  ],
                  if (_infoDetail.vodActor != null ||
                      _infoDetail.vodDirector != null) ...[
                    const SizedBox(height: 12),
                    _MetaChips(detail: _infoDetail),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerFrame(BuildContext context, {required bool fill}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(fill ? 8 : 0),
      child: SizedBox(
        width: double.infinity,
        height:
            fill ? double.infinity : MediaQuery.of(context).size.width * 9 / 16,
        child: _buildPlayerStage(compact: !fill, expanded: false),
      ),
    );
  }

  Widget _buildExpandedPlayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPlayerStage(compact: false, expanded: true),
        _buildEpisodeDrawerLayer(),
      ],
    );
  }

  Widget _buildPlayerStage({
    required bool compact,
    required bool expanded,
  }) {
    if (_castDevice != null) {
      return ColoredBox(
          color: Colors.black,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cast_connected_rounded,
                color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text('正在投屏到 ${_castDevice!.name}',
                style: const TextStyle(color: Colors.white)),
            Text(
                '${formatDuration(_castPosition)} / ${formatDuration(_castDuration)}',
                style: const TextStyle(color: Colors.white70)),
            TextButton(onPressed: _showCastControls, child: const Text('投屏控制')),
          ])));
    }
    final episode = _currentEpisode;
    final source = _currentSource;
    final showLoading = _inlineError == null &&
        (!_inlineInitialized || _inlineLoading || _isSeeking || _isBuffering);
    final loadingLabel = _isSeeking
        ? '正在定位...'
        : _isBuffering
            ? '缓冲中...'
            : '加载中...';
    final showDesktopFullWindowAction =
        isDesktopPlatform && !_traditionalFullscreen;
    final topActionIcon = showDesktopFullWindowAction
        ? expanded
            ? Icons.close_fullscreen_rounded
            : Icons.open_in_full_rounded
        : null;
    final topActionTooltip = showDesktopFullWindowAction
        ? expanded
            ? '退出全窗口'
            : '全窗口播放'
        : null;
    final VoidCallback? onTopAction = showDesktopFullWindowAction
        ? () => unawaited(
              expanded ? _exitExpandedPlayer() : _enterExpandedPlayer(),
            )
        : null;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_inlineInitialized && !_inlineLoading && _inlineError == null)
            _PosterBackdrop(detail: _infoDetail),
          if (_inlineInitialized || _inlineLoading || _inlineError != null)
            PlayerVideoSurface(
              controller: _inlineVideoController,
              initialized: _inlineInitialized,
              fit: _videoFit,
              showLoadingIndicator: showLoading,
              loadingLabel: loadingLabel,
              errorText: _inlineError,
              pauseOnBackground: false,
              onRetry: () => _loadInlineEpisode(
                episodeIndex: _selectedEpisodeIndex,
                play: true,
                startAtSeconds: _selectedEpisodeIndex == _resumeEpisodeIndex
                    ? _resumeProgress
                    : 0,
              ),
            ),
          _buildCenterPauseIndicator(),
          if (isMobilePlatform)
            MobileGestureLayer(
              player: _inlinePlayer,
              volume: _volume,
              brightness: _brightness,
              onTapToggleControls: _toggleControls,
              onSeek: _seekInline,
              onTogglePlayPause: _toggleInlinePlayPause,
              onVolumeChanged: (value) => unawaited(_setInlineVolume(value)),
              onBrightnessChanged: (value) => unawaited(_setBrightness(value)),
              onTemporarySpeed: (active) =>
                  unawaited(_setTemporarySpeed(active)),
              onHideControls: _forceHideControls,
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _keyboardFocusNode.requestFocus();
                if (isDesktopPlatform) {
                  unawaited(_toggleInlinePlayPause());
                } else {
                  _toggleControls();
                }
              },
              onDoubleTap: isDesktopPlatform
                  ? () => unawaited(_toggleExpandedPlayer())
                  : null,
              child: const SizedBox.expand(),
            ),
          AnimatedOpacity(
            opacity: _showPlayerControls ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_showPlayerControls,
              child: PlayerControlsOverlay(
                title: _infoDetail.vodName,
                subtitle: '${source?.name ?? '播放源'} · ${episode?.name ?? ''}',
                player: _inlinePlayer,
                bufferPosition: _bufferPosition,
                fullscreen:
                    isDesktopPlatform ? _traditionalFullscreen : expanded,
                canPlayPrevious: _canPlayPrevious,
                canPlayNext: _canPlayNext,
                volume: _volume,
                playbackSpeed: _playbackSpeed,
                fitMode: _fitMode,
                fitLabel: _fitLabel,
                speedOptions: const [0.5, 0.75, 1, 1.25, 1.5, 2],
                episodesActive: _episodeDrawerOpen,
                compact: compact,
                fullscreenTooltip: '全屏播放',
                fullscreenExitTooltip: '退出全屏',
                topActionIcon: topActionIcon,
                topActionTooltip: topActionTooltip,
                onTopAction: onTopAction,
                onPictureInPicture: _pipSupported && _inlineInitialized
                    ? () => unawaited(_enterPip())
                    : null,
                onCast: _inlineInitialized && !_castBusy
                    ? () => unawaited(_openCast())
                    : null,
                onBackPressed: () {
                  if (_traditionalFullscreen) {
                    unawaited(_exitTraditionalFullscreen());
                  } else if (_playerExpanded) {
                    unawaited(_exitExpandedPlayer());
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                onDragWindow: isDesktopPlatform && !_traditionalFullscreen
                    ? () => Future<void>.microtask(startPlatformWindowDrag)
                    : null,
                onPlayPause: _toggleInlinePlayPause,
                onSeek: _seekInline,
                onSpeedSelected: _setInlineSpeed,
                onFitSelected: _setInlineFit,
                onVolumeChanged: _setInlineVolume,
                onToggleFullscreen: isDesktopPlatform
                    ? _toggleTraditionalFullscreen
                    : _toggleExpandedPlayer,
                onToggleEpisodes: _toggleEpisodeDrawer,
                onPreviousEpisode:
                    _canPlayPrevious ? _selectPreviousEpisode : null,
                onNextEpisode: _canPlayNext ? _selectNextEpisode : null,
                onInteractionStart: _cancelControlsHideTimer,
                onInteractionEnd: _startControlsHideTimer,
              ),
            ),
          ),
          if (isDesktopPlatform)
            DesktopHoverDetector(
              onShowControls: _desktopShowControls,
              onHideControls: _desktopHideControls,
            ),
        ],
      ),
    );
  }

  Widget _buildCenterPauseIndicator() {
    return StreamBuilder<bool>(
      stream: _inlinePlayer.stream.playing,
      initialData: _inlinePlayer.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        if (playing || !_inlineInitialized || _inlineError != null) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeDrawerLayer() {
    final result = _selectedPlayResult;
    if (result == null) return const SizedBox.shrink();
    final mediaWidth = MediaQuery.of(context).size.width;
    final width = 340.0.clamp(280.0, mediaWidth * 0.85);

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !_episodeDrawerOpen,
          child: GestureDetector(
            onTap: _closeEpisodeDrawer,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color:
                  Colors.black.withValues(alpha: _episodeDrawerOpen ? 0.4 : 0),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          right: _episodeDrawerOpen ? 0 : -width - 16,
          top: 0,
          bottom: 0,
          width: width,
          child: Material(
            color: Colors.transparent,
            elevation: 12,
            child: PlayerEpisodePanel(
              detail: _detail,
              playResult: result,
              currentSourceIndex: 0,
              currentEpisodeIndex: _selectedEpisodeIndex,
              onSourceSelected: (_) {},
              onEpisodeSelected: (index) {
                _closeEpisodeDrawer();
                unawaited(_selectInlineEpisode(index));
              },
              onClose: _closeEpisodeDrawer,
              glassMode: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBlock(
    BuildContext context,
    ColorScheme cs, {
    required bool compact,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 4, compact ? 0 : 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _infoDetail.vodName,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Tag(
                _selectedLine?.source.name ??
                    (_searchingSources ? '正在匹配片源' : '暂无片源'),
                color: cs.primaryContainer,
                textColor: cs.onPrimaryContainer,
              ),
              if (_infoDetail.vodYear != null &&
                  _infoDetail.vodYear!.isNotEmpty)
                _Tag(_infoDetail.vodYear!),
              if (_infoDetail.vodArea != null &&
                  _infoDetail.vodArea!.isNotEmpty)
                _Tag(_infoDetail.vodArea!),
              if (_infoDetail.typeName != null &&
                  _infoDetail.typeName!.isNotEmpty)
                _Tag(_infoDetail.typeName!),
              if (_infoDetail.vodRemarks != null &&
                  _infoDetail.vodRemarks!.isNotEmpty)
                _Tag(_infoDetail.vodRemarks!),
            ],
          ),
          if (!compact &&
              _infoDetail.vodContent != null &&
              _infoDetail.vodContent!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ExpandableText(text: _infoDetail.vodContent!),
          ],
          if (!compact &&
              (_infoDetail.vodActor != null ||
                  _infoDetail.vodDirector != null)) ...[
            const SizedBox(height: 12),
            _MetaChips(detail: _infoDetail),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBlock(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktopPlatform ? 0 : 16),
      child: _DetailActionRow(
        hasPlay: _selectedPlayResult != null,
        hasResume: _resumeProgress > 0,
        sourceEnabled: _selectedLine != null && _sourceEnabled,
        sourceToggleLoading: _sourceToggleLoading,
        onPlay: () => _openPlayer(
            0,
            _selectedEpisodeIndex,
            _inlineInitialized
                ? _inlinePlayer.state.position.inMilliseconds / 1000
                : _resumeProgress),
        onPlayFromStart: () => _openPlayer(0, 0, 0),
        onDisableSource: _disableCurrentSource,
      ),
    );
  }

  Widget _buildSourceSwitcher(
    BuildContext context,
    ColorScheme cs, {
    bool padded = true,
  }) {
    if (_playableLines.isEmpty) {
      if (!_searchingSources) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: padded ? 16 : 0),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              '正在匹配可播放源...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padded ? 16 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '播放源',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  _keyboardFocusNode.requestFocus();
                  unawaited(_selectBestLine());
                },
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text('自动优选'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < _playableLines.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        descendantsAreFocusable: false,
                        child: ChoiceChip(
                          selected: index == _selectedLineIndex,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_playableLines[index].source.name),
                              const SizedBox(width: 6),
                              _LatencyBadge(
                                speedTest: _lineSpeedTests[index],
                                fallbackLatencyMs:
                                    _playableLines[index].site?.responseTimeMs,
                              ),
                            ],
                          ),
                          onSelected: (_) {
                            _keyboardFocusNode.requestFocus();
                            unawaited(_selectLine(index));
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeGrid(BuildContext context, ColorScheme cs) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _EpisodeGridBox(
          source: _selectedLine?.source,
          speedTest: _lineSpeedTests[_selectedLineIndex],
          selectedEpisodeIndex: _selectedEpisodeIndex,
          resumeEpisodeIndex: _resumeEpisodeIndex,
          resumeProgress: _resumeProgress,
          onEpisode: (index, _) => _selectInlineEpisode(index),
        ),
      ),
    );
  }
}

class _PlayableLine {
  const _PlayableLine({
    required this.detail,
    required this.source,
    required this.site,
    required this.rawName,
  });

  final String rawName;
  final VodItem detail;
  final PlaySource source;
  final SiteWithStatus? site;
}

enum _LineSpeedTestStatus { testing, success, failed }

class _LineSpeedTest {
  const _LineSpeedTest._({
    required this.status,
    this.pingMs,
    this.speedKBps,
    this.bytesRead,
  });

  const _LineSpeedTest.testing() : this._(status: _LineSpeedTestStatus.testing);

  const _LineSpeedTest.failed() : this._(status: _LineSpeedTestStatus.failed);

  const _LineSpeedTest.success({
    required int pingMs,
    required double speedKBps,
    required int bytesRead,
  }) : this._(
          status: _LineSpeedTestStatus.success,
          pingMs: pingMs,
          speedKBps: speedKBps,
          bytesRead: bytesRead,
        );

  final _LineSpeedTestStatus status;
  final int? pingMs;
  final double? speedKBps;
  final int? bytesRead;

  bool get isSuccess =>
      status == _LineSpeedTestStatus.success &&
      pingMs != null &&
      speedKBps != null;

  String get speedLabel {
    final speed = speedKBps;
    if (speed == null || speed <= 0) {
      return '未知';
    }
    if (speed >= 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${speed.toStringAsFixed(1)} KB/s';
  }
}

class _DownloadProbe {
  const _DownloadProbe({
    required this.pingMs,
    required this.speedKBps,
    required this.bytesRead,
  });

  final int pingMs;
  final double speedKBps;
  final int bytesRead;
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({
    required this.speedTest,
    required this.fallbackLatencyMs,
  });

  final _LineSpeedTest? speedTest;
  final int? fallbackLatencyMs;

  @override
  Widget build(BuildContext context) {
    final test = speedTest;
    if (test == null) {
      final fallback = fallbackLatencyMs;
      if (fallback == null || fallback <= 0) {
        return const SizedBox.shrink();
      }
      return _LatencyPill(
        label: '${fallback}ms',
        color: _latencyColor(fallback),
      );
    }
    return switch (test.status) {
      _LineSpeedTestStatus.testing => const _LatencyPill(
          label: '测...',
          color: Colors.teal,
        ),
      _LineSpeedTestStatus.failed => const _LatencyPill(
          label: '失败',
          color: Colors.redAccent,
        ),
      _LineSpeedTestStatus.success => _LatencyPill(
          label: '${test.pingMs}ms',
          color: _latencyColor(test.pingMs ?? 0),
        ),
    };
  }
}

class _LatencyPill extends StatelessWidget {
  const _LatencyPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _SpeedTestDetails extends StatelessWidget {
  const _SpeedTestDetails({required this.speedTest});

  final _LineSpeedTest? speedTest;

  @override
  Widget build(BuildContext context) {
    final test = speedTest;
    if (test == null) {
      return const SizedBox.shrink();
    }
    if (test.status == _LineSpeedTestStatus.testing) {
      return Text(
        '测速中...',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.tealAccent.shade400,
              fontWeight: FontWeight.w700,
            ),
      );
    }
    if (!test.isSuccess) {
      return Text(
        '无测速数据',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          test.speedLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.greenAccent.shade400,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${test.pingMs}ms',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

Color _latencyColor(int latencyMs) {
  if (latencyMs <= 0) return Colors.grey;
  if (latencyMs <= 250) return Colors.greenAccent.shade400;
  if (latencyMs <= 800) return Colors.orangeAccent;
  return Colors.redAccent;
}

class _RightPanelCover extends StatelessWidget {
  const _RightPanelCover({required this.detail});

  final VodItem detail;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 150,
          height: 220,
          child: detail.vodPic != null && detail.vodPic!.isNotEmpty
              ? Image.network(
                  detail.vodPic!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _CoverFallback(detail: detail),
                )
              : _CoverFallback(detail: detail),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.detail});

  final VodItem detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        detail.vodName,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PosterBackdrop extends StatelessWidget {
  const _PosterBackdrop({required this.detail});

  final VodItem detail;

  @override
  Widget build(BuildContext context) {
    final pic = detail.vodPic;
    if (pic == null || pic.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Image.network(
            pic,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0.78),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeGridBox extends StatelessWidget {
  const _EpisodeGridBox({
    required this.source,
    required this.speedTest,
    required this.selectedEpisodeIndex,
    required this.resumeEpisodeIndex,
    required this.resumeProgress,
    required this.onEpisode,
  });

  final PlaySource? source;
  final _LineSpeedTest? speedTest;
  final int selectedEpisodeIndex;
  final int resumeEpisodeIndex;
  final double resumeProgress;
  final void Function(int index, double progress) onEpisode;

  @override
  Widget build(BuildContext context) {
    final episodes = source?.episodes ?? const <PlayEpisode>[];
    if (episodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Text(
                '剧集',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              _SpeedTestDetails(speedTest: speedTest),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 100,
            childAspectRatio: 2.4,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            final isResume = index == resumeEpisodeIndex && resumeProgress > 0;
            final isSelected = index == selectedEpisodeIndex;
            return FilledButton.tonal(
              style: isSelected
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    )
                  : isResume
                      ? FilledButton.styleFrom(
                          backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                        )
                      : null,
              onPressed: () => onEpisode(index, isResume ? resumeProgress : 0),
              child: Text(
                ep.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({
    required this.hasPlay,
    required this.hasResume,
    required this.sourceEnabled,
    required this.sourceToggleLoading,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onDisableSource,
  });

  final bool hasPlay;
  final bool hasResume;
  final bool sourceEnabled;
  final bool sourceToggleLoading;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromStart;
  final VoidCallback onDisableSource;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (hasPlay) {
      if (hasResume) {
        children.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 180,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('继续观看'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPlayFromStart,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('从头播放'),
              ),
            ],
          ),
        );
      } else {
        children.add(
          SizedBox(
            width: 180,
            child: FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('立即播放'),
            ),
          ),
        );
      }
    }

    if (sourceEnabled) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sourceToggleLoading ? null : onDisableSource,
            icon: sourceToggleLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.block_rounded, size: 18),
            label: Text(sourceToggleLoading ? '禁用中...' : '禁用此源'),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

// ─── SliverAppBar ────────────────────────────────────────────────────────────

// ignore: unused_element
class _DetailSliverAppBar extends StatelessWidget {
  const _DetailSliverAppBar({
    required this.detail,
    required this.isFavorited,
    required this.favoriteLoading,
    required this.onFavorite,
  });

  final VodItem detail;
  final bool isFavorited;
  final bool favoriteLoading;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      scrolledUnderElevation: 0,
      title: isDesktopPlatform
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) =>
                  Future<void>.microtask(startPlatformWindowDrag),
              child: const SizedBox(
                  width: double.infinity, height: kToolbarHeight),
            )
          : Text(
              detail.vodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      actions: [
        favoriteLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                onPressed: onFavorite,
                icon: Icon(
                  isFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorited ? cs.error : null,
                ),
              ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // blurred cover background
            if (detail.vodPic != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Image.network(
                  detail.vodPic!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                  ),
                ),
              )
            else
              Container(color: cs.surfaceContainerHighest),
            // dark gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    cs.surface.withValues(alpha: 0.85),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            // poster + meta
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // poster thumbnail
                  if (detail.vodPic != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        detail.vodPic!,
                        width: 90,
                        height: 130,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 90,
                          height: 130,
                          color: cs.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  // title + tags
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          detail.vodName,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _Tag(
                              '片源 ${detail.sourceKey}',
                              color:
                                  cs.tertiaryContainer.withValues(alpha: 0.9),
                              textColor: cs.onTertiaryContainer,
                            ),
                            if (detail.vodYear != null &&
                                detail.vodYear!.isNotEmpty)
                              _Tag(detail.vodYear!),
                            if (detail.vodArea != null &&
                                detail.vodArea!.isNotEmpty)
                              _Tag(detail.vodArea!),
                            if (detail.typeName != null &&
                                detail.typeName!.isNotEmpty)
                              _Tag(detail.typeName!),
                            if (detail.vodRemarks != null &&
                                detail.vodRemarks!.isNotEmpty)
                              _Tag(detail.vodRemarks!,
                                  color: cs.primaryContainer,
                                  textColor: cs.onPrimaryContainer),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small tag chip ───────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color, this.textColor});

  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor ?? cs.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ─── Action row ───────────────────────────────────────────────────────────────

// ignore: unused_element
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.hasPlay,
    required this.hasResume,
    required this.onPlay,
    required this.onPlayFromStart,
  });

  final bool hasPlay;
  final bool hasResume;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromStart;

  @override
  Widget build(BuildContext context) {
    if (!hasPlay) {
      return const SizedBox.shrink();
    }
    if (hasResume) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('继续观看'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPlayFromStart,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('从头播放'),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('立即播放'),
      ),
    );
  }
}

// ─── Expandable synopsis ──────────────────────────────────────────────────────

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = _cleanText(widget.text);
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            secondChild: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _expanded ? '收起' : '展开',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.primary),
          ),
        ],
      ),
    );
  }
}

// ─── Meta chips (actor / director) ───────────────────────────────────────────

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.detail});

  final VodItem detail;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[];
    if (detail.vodDirector != null && detail.vodDirector!.isNotEmpty) {
      items.add(('导演', detail.vodDirector!));
    }
    if (detail.vodActor != null && detail.vodActor!.isNotEmpty) {
      items.add(('演员', detail.vodActor!));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: value
                        .split(RegExp(r'[,，、]'))
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .map((s) => Chip(
                              label: Text(s),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              labelStyle:
                                  Theme.of(context).textTheme.labelSmall,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _normalizeTitle(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[：:·・\-—_（）()【】\[\]]'), '')
      .toLowerCase();
}

String? _searchTypeKey(VodItem item) {
  final type = item.typeName?.toLowerCase();
  if (type != null && type.isNotEmpty) {
    if (type.contains('movie') || type.contains('电影')) return 'movie';
    if (type.contains('anime') || type.contains('动画') || type.contains('动漫')) {
      return 'anime';
    }
    if (type.contains('tv') ||
        type.contains('剧') ||
        type.contains('综艺') ||
        type.contains('show')) {
      return 'tv';
    }
  }
  final playUrl = item.vodPlayUrl;
  if (playUrl.isEmpty) {
    return null;
  }
  if (!playUrl.contains('#') && !playUrl.contains(r'$$$')) {
    return 'movie';
  }
  return 'tv';
}

int _metadataScore(VodItem item) {
  var score = 0;
  if (_hasText(item.vodPic)) score += 4;
  if (_hasText(item.vodContent)) score += 4;
  if (_hasText(item.vodActor)) score += 2;
  if (_hasText(item.vodDirector)) score += 2;
  if (_hasText(item.vodYear)) score += 1;
  if (_hasText(item.vodArea)) score += 1;
  if (_hasText(item.typeName)) score += 1;
  return score;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String? _firstText(Iterable<String?> values) {
  for (final value in values) {
    if (_hasText(value)) {
      return value!.trim();
    }
  }
  return null;
}

String _cleanText(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n')
      .trim();
}
