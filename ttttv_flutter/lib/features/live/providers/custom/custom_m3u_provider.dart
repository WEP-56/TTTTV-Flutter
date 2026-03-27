import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import '../../core/providers/live_provider.dart';
import '../../data/m3u/m3u_parser.dart';
import '../../data/m3u/m3u_source_store.dart';

class CustomM3uProvider extends LiveProvider {
  CustomM3uProvider({
    required Dio dio,
    required LiveM3uSourceStore sourceStore,
  })  : _dio = dio,
        _sourceStore = sourceStore;

  final Dio _dio;
  final LiveM3uSourceStore _sourceStore;
  final M3uParser _parser = M3uParser();

  List<_ResolvedM3uItem>? _cachedItems;

  @override
  String get id => 'custom_m3u';

  @override
  String get name => '直播源';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsCategories => false;

  @override
  Future<List<LiveRoomItem>> fetchRecommend({int page = 1}) async {
    final items = await _loadItems();
    return items.map(_toRoomItem).toList();
  }

  @override
  Future<List<LiveRoomItem>> search(String keyword, {int page = 1}) async {
    final normalized = keyword.trim().toLowerCase();
    final items = await _loadItems();

    if (normalized.isEmpty) {
      return items.map(_toRoomItem).toList();
    }

    return items
        .where((item) {
          final title = item.item.title.toLowerCase();
          final group =
              (item.item.attributes['group-title'] ?? '').toLowerCase();
          final source = item.source.name.toLowerCase();
          return title.contains(normalized) ||
              group.contains(normalized) ||
              source.contains(normalized);
        })
        .map(_toRoomItem)
        .toList();
  }

  @override
  Future<LiveRoomDetail> getRoomDetail(String roomId) async {
    final item = await _findItem(roomId);
    final groupTitle = item.item.attributes['group-title'];
    final logo = item.item.attributes['tvg-logo'] ?? '';

    return LiveRoomDetail(
      platform: id,
      roomId: roomId,
      title: item.item.title,
      cover: logo,
      userName: groupTitle?.isNotEmpty == true ? groupTitle! : item.source.name,
      userAvatar: logo,
      online: 0,
      status: true,
      isRecord: false,
      url: item.item.link,
      introduction: '来源：${item.source.name}',
      notice: item.item.link,
      showTime: null,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(LiveRoomDetail detail) async {
    return [
      LivePlayQuality(
        id: 'default',
        name: '默认',
        sort: 1,
      ),
    ];
  }

  @override
  Future<LivePlayUrl> getPlayUrl(
    LiveRoomDetail detail,
    String qualityId,
  ) async {
    final item = await _findItem(detail.roomId);
    return LivePlayUrl(
      urls: [item.item.link],
      urlType: _guessUrlType(item.item.link),
    );
  }

  @override
  Future<List<LiveImportedSource>> listSources() {
    return _sourceStore.loadSources();
  }

  @override
  Future<void> addNetworkSource(String url, {String? sourceName}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      throw const FormatException('请输入有效的 M3U 地址。');
    }

    final response = await _dio.get<String>(normalized);
    final playlist = _parser.parse(response.data ?? '');
    if (playlist.items.isEmpty) {
      throw const FormatException('该链接不是有效的 M3U 播放列表。');
    }

    final sources = await _sourceStore.loadSources();
    if (sources.any((item) => item.value == normalized)) {
      return;
    }

    final nextSources = <LiveImportedSource>[
      ...sources,
      LiveImportedSource(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: (sourceName?.trim().isNotEmpty == true)
            ? sourceName!.trim()
            : _guessSourceName(normalized),
        type: LiveImportedSourceType.network,
        value: normalized,
      ),
    ];

    await _sourceStore.saveSources(nextSources);
    _cachedItems = null;
  }

  @override
  Future<void> addLocalSource(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      throw FormatException('未选择 M3U 文件。');
    }

    final file = File(normalized);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在。', normalized);
    }

    final playlist = _parser.parse(await file.readAsString());
    if (playlist.items.isEmpty) {
      throw const FormatException('该文件不是有效的 M3U 播放列表。');
    }

    final sources = await _sourceStore.loadSources();
    if (sources.any((item) => item.value == normalized)) {
      return;
    }

    final nextSources = <LiveImportedSource>[
      ...sources,
      LiveImportedSource(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _guessSourceName(normalized),
        type: LiveImportedSourceType.local,
        value: normalized,
      ),
    ];

    await _sourceStore.saveSources(nextSources);
    _cachedItems = null;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _sourceStore.removeSource(sourceId);
    _cachedItems = null;
  }

  @override
  Future<void> refreshSources() async {
    _cachedItems = null;
    await _loadItems(forceReload: true);
  }

  Future<List<_ResolvedM3uItem>> _loadItems({bool forceReload = false}) async {
    if (!forceReload && _cachedItems != null) {
      return _cachedItems!;
    }

    final sources = await _sourceStore.loadSources();
    final resolved = <_ResolvedM3uItem>[];

    for (final source in sources) {
      try {
        final content = await _readSourceContent(source);
        final playlist = _parser.parse(content);
        for (final item in playlist.items) {
          resolved.add(_ResolvedM3uItem(source: source, item: item));
        }
      } catch (_) {
        // Skip invalid sources so the rest of the list remains usable.
      }
    }

    _cachedItems = resolved;
    return resolved;
  }

  Future<_ResolvedM3uItem> _findItem(String roomId) async {
    final items = await _loadItems();
    final item = items.where((entry) => _buildRoomId(entry) == roomId);
    if (item.isEmpty) {
      throw StateError('直播源不存在或已被移除。');
    }
    return item.first;
  }

  Future<String> _readSourceContent(LiveImportedSource source) async {
    if (source.type == LiveImportedSourceType.network) {
      final response = await _dio.get<String>(source.value);
      return response.data ?? '';
    }
    return File(source.value).readAsString();
  }

  LiveRoomItem _toRoomItem(_ResolvedM3uItem resolved) {
    return LiveRoomItem(
      platform: id,
      roomId: _buildRoomId(resolved),
      title: resolved.item.title,
      cover: resolved.item.attributes['tvg-logo'] ?? '',
      userName: resolved.item.attributes['group-title'] ?? resolved.source.name,
      online: 0,
    );
  }

  String _buildRoomId(_ResolvedM3uItem resolved) {
    return '${resolved.source.id}|${Uri.encodeComponent(resolved.item.link)}';
  }

  String _guessUrlType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'hls';
    if (lower.contains('.flv')) return 'flv';
    return 'unknown';
  }

  String _guessSourceName(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    final separator = Platform.pathSeparator;
    if (value.contains(separator)) {
      return value.split(separator).last;
    }
    return value;
  }
}

class _ResolvedM3uItem {
  const _ResolvedM3uItem({
    required this.source,
    required this.item,
  });

  final LiveImportedSource source;
  final M3uMediaItem item;
}
