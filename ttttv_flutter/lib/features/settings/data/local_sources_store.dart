import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../domain/sources_repository.dart';

const _sourcesPrefsKey = 'ttttv_local_vod_sources_v1';
const _defaultSourcesAsset = 'assets/vod/sources.json';
const _healthDegradedThresholdMs = 2500;
const _defaultRemoteSourcesIndexUrls = <String>[
  'https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/sources.json',
  'https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/index.json',
  'https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/indexes/all.json',
];

class LocalSourcesStore implements SourcesRepository {
  LocalSourcesStore({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<LocalVodSource>> loadAllSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      final defaults = await _loadDefaultSources();
      await _saveSources(defaults);
      return defaults;
    }
    return _decodeStoredSources(raw);
  }

  Future<List<LocalVodSource>> loadEnabledSources() async {
    final sources = await loadAllSources();
    return sources.where((source) => source.enabled).toList();
  }

  Future<LocalVodSource?> getSource(String key) async {
    final sources = await loadAllSources();
    return sources.where((source) => source.key == key).firstOrNull;
  }

  @override
  Future<List<SiteWithStatus>> fetchSites() async {
    final sources = await loadAllSources();
    return sources.map((source) => source.toSiteWithStatus()).toList();
  }

  @override
  Future<List<SiteWithStatus>> checkSites({String? key}) async {
    final sources = await loadAllSources();
    final keys = <String>{};
    if (key != null && key.trim().isNotEmpty) {
      keys.add(key.trim());
    }
    final targets = keys.isEmpty
        ? sources
        : sources.where((source) => keys.contains(source.key)).toList();

    if (targets.isEmpty) {
      throw StateError('未找到可检查的片源');
    }

    final checked = await Future.wait(targets.map(_runHealthCheck));
    final checkedByKey = {for (final source in checked) source.key: source};
    final merged = sources
        .map((source) => checkedByKey[source.key] ?? source)
        .toList(growable: false);
    await _saveSources(merged);

    return merged
        .where((source) => keys.isEmpty || keys.contains(source.key))
        .map((source) => source.toSiteWithStatus())
        .toList();
  }

  @override
  Future<void> toggleSite({
    required String key,
    required bool enabled,
  }) async {
    final sources = await loadAllSources();
    var found = false;
    final updated = sources.map((source) {
      if (source.key != key) {
        return source;
      }
      found = true;
      return source.copyWith(enabled: enabled);
    }).toList(growable: false);

    if (!found) {
      throw StateError('片源不存在: $key');
    }

    await _saveSources(updated);
  }

  @override
  Future<void> addSource(AddSourceRequest request) async {
    final key = request.key.trim();
    if (key.isEmpty) {
      throw StateError('片源标识不能为空');
    }

    final sources = await loadAllSources();
    if (sources.any((source) => source.key == key)) {
      throw StateError('片源已存在: $key');
    }

    final next = [...sources, LocalVodSource.fromRequest(request)];
    await _saveSources(next);
  }

  @override
  Future<void> deleteSource(String key) async {
    final normalized = key.trim();
    final sources = await loadAllSources();
    final next = sources
        .where((source) => source.key != normalized)
        .toList(growable: false);
    if (next.length == sources.length) {
      throw StateError('片源不存在: $normalized');
    }
    await _saveSources(next);
  }

  @override
  Future<RemoteSourcesResponse> fetchRemoteSources({String? url}) async {
    final requestedUrl = url?.trim();
    final candidates = requestedUrl != null && requestedUrl.isNotEmpty
        ? [requestedUrl]
        : _defaultRemoteSourcesIndexUrls;

    if (requestedUrl != null &&
        requestedUrl.isNotEmpty &&
        !requestedUrl.startsWith('https://')) {
      throw StateError('远程片源地址必须以 https:// 开头');
    }

    String? lastError;
    for (final candidate in candidates) {
      try {
        final response = await _dio.getUri<String>(
          Uri.parse(candidate),
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
          ),
        );
        final body = response.data ?? '';
        return RemoteSourcesResponse(
          url: candidate,
          sources: _parseRemoteSources(body),
        );
      } catch (error) {
        lastError = error.toString();
        if (requestedUrl != null && requestedUrl.isNotEmpty) {
          rethrow;
        }
      }
    }

    throw StateError(
      lastError == null ? '远程片源获取失败' : '远程片源获取失败: $lastError',
    );
  }

  @override
  Future<AddSourcesBatchResult> addSourcesBatch(
      List<RemoteSource> sources) async {
    final installed = await loadAllSources();
    final installedKeys = installed.map((source) => source.key).toSet();
    final next = [...installed];
    final added = <String>[];
    final skippedExisting = <String>[];
    final failed = <AddSourcesBatchFailure>[];

    for (final source in sources) {
      final key = source.key.trim();
      if (key.isEmpty) {
        failed.add(
          AddSourcesBatchFailure(key: key, error: 'key 不能为空'),
        );
        continue;
      }
      if (installedKeys.contains(key)) {
        skippedExisting.add(key);
        continue;
      }
      installedKeys.add(key);
      next.add(LocalVodSource.fromRemote(source));
      added.add(key);
    }

    await _saveSources(next);
    return AddSourcesBatchResult(
      added: added,
      skippedExisting: skippedExisting,
      failed: failed,
    );
  }

  @override
  Future<DisableBadSitesResult> disableBadSites() async {
    final sources = await loadAllSources();
    final disabled = <String>[];
    final alreadyDisabled = <String>[];
    final skipped = <String>[];

    final next = sources.map((source) {
      if (!source.isBadHealth) {
        skipped.add(source.key);
        return source;
      }
      if (!source.enabled) {
        alreadyDisabled.add(source.key);
        return source;
      }
      disabled.add(source.key);
      return source.copyWith(enabled: false);
    }).toList(growable: false);

    await _saveSources(next);
    return DisableBadSitesResult(
      disabled: disabled,
      alreadyDisabled: alreadyDisabled,
      skipped: skipped,
    );
  }

  Future<List<LocalVodSource>> _loadDefaultSources() async {
    final raw = await rootBundle.loadString(_defaultSourcesAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('默认片源格式错误');
    }

    final apiSite = decoded['api_site'];
    if (apiSite is! Map) {
      throw const FormatException('默认片源缺少 api_site');
    }

    return apiSite.entries
        .map((entry) {
          final value = entry.value;
          if (value is! Map) {
            return null;
          }
          return LocalVodSource.fromJsonMap(
            entry.key.toString(),
            value.cast<String, dynamic>(),
          );
        })
        .whereType<LocalVodSource>()
        .toList(growable: false);
  }

  Future<void> _saveSources(List<LocalVodSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      sources.map((source) => source.toJson()).toList(growable: false),
    );
    await prefs.setString(_sourcesPrefsKey, json);
  }

  List<LocalVodSource> _decodeStoredSources(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('本地片源数据格式错误');
    }
    return decoded
        .whereType<Map>()
        .map((item) => LocalVodSource.fromStorage(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<LocalVodSource> _runHealthCheck(LocalVodSource source) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.getUri<Object>(
        _buildVodApiUri(source.apiUrl, const {
          'ac': 'videolist',
          'pg': '1',
          'wd': '',
        }),
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      stopwatch.stop();

      final payload = _toJsonMap(response.data);
      final code = _readResponseCode(payload['code']) ?? 1;
      if (![0, 1, 200].contains(code)) {
        return source.withHealth(
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'unhealthy',
          message: _readString(payload['msg']) ?? '接口返回错误码: $code',
        );
      }
      if (payload['list'] is! List) {
        return source.withHealth(
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'unhealthy',
          message: '响应缺少 list 字段',
        );
      }

      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs > _healthDegradedThresholdMs) {
        return source.withHealth(
          elapsedMs: elapsedMs,
          status: 'degraded',
          message: '接口可用，但响应较慢: ${elapsedMs}ms',
        );
      }

      return source.withHealth(
        elapsedMs: elapsedMs,
        status: 'healthy',
        message: null,
      );
    } catch (error) {
      stopwatch.stop();
      return source.withHealth(
        elapsedMs: stopwatch.elapsedMilliseconds,
        status: 'unhealthy',
        message: error.toString(),
      );
    }
  }

  List<RemoteSource> _parseRemoteSources(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return _normalizeRemoteSources(
        decoded
            .whereType<Map>()
            .map((item) => _remoteSourceFromMap(item.cast<String, dynamic>()))
            .whereType<RemoteSource>()
            .toList(growable: false),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('远程片源格式不受支持');
    }
    final sources = decoded['sources'];
    if (sources is List) {
      return _normalizeRemoteSources(
        sources
            .whereType<Map>()
            .map((item) => _remoteSourceFromMap(item.cast<String, dynamic>()))
            .whereType<RemoteSource>()
            .toList(growable: false),
      );
    }
    final apiSite = decoded['api_site'];
    if (apiSite is Map) {
      final list = <RemoteSource>[];
      for (final entry in apiSite.entries) {
        final value = entry.value;
        if (value is! Map) {
          continue;
        }
        final map = value.cast<String, dynamic>();
        list.add(
          RemoteSource(
            key: entry.key.toString(),
            name: _readString(map['name']) ?? '',
            api: _readString(map['api']) ?? '',
            detail: _readString(map['detail']) ?? _readString(map['api']) ?? '',
            group: _readString(map['group']),
            r18: map['r18'] as bool?,
            comment:
                _readString(map['_comment']) ?? _readString(map['comment']),
          ),
        );
      }
      return _normalizeRemoteSources(list);
    }

    throw const FormatException('远程片源格式不受支持');
  }

  List<RemoteSource> _normalizeRemoteSources(List<RemoteSource> input) {
    return input
        .where(
      (source) =>
          source.key.trim().isNotEmpty &&
          source.name.trim().isNotEmpty &&
          source.api.trim().isNotEmpty,
    )
        .map((source) {
      final inferredR18 = source.r18 ??
          source.group == 'R18' ||
              source.name.contains('R18') ||
              source.name.contains('🔒');
      return RemoteSource(
        key: source.key.trim(),
        name: source.name.trim(),
        api: source.api.trim(),
        detail: source.detail.trim().isEmpty
            ? source.api.trim()
            : source.detail.trim(),
        group: source.group ?? (inferredR18 ? 'R18' : null),
        r18: inferredR18,
        comment: source.comment,
      );
    }).toList(growable: false);
  }

  RemoteSource? _remoteSourceFromMap(Map<String, dynamic> map) {
    final key = _readString(map['key']) ?? '';
    final name = _readString(map['name']) ?? '';
    final api = _readString(map['api']) ?? '';
    final detail = _readString(map['detail']) ?? api;
    if (key.isEmpty || name.isEmpty || api.isEmpty) {
      return null;
    }
    return RemoteSource(
      key: key,
      name: name,
      api: api,
      detail: detail,
      group: _readString(map['group']),
      r18: map['r18'] as bool?,
      comment: _readString(map['_comment']) ?? _readString(map['comment']),
    );
  }
}

class LocalVodSource {
  LocalVodSource({
    required this.key,
    required this.name,
    required this.apiUrl,
    required this.detailUrl,
    required this.enabled,
    this.lastCheck,
    this.isHealthy,
    this.healthStatus,
    this.responseTimeMs,
    this.statusMessage,
    this.comment,
    this.r18,
    this.group,
  });

  final String key;
  final String name;
  final String apiUrl;
  final String detailUrl;
  final bool enabled;
  final int? lastCheck;
  final bool? isHealthy;
  final String? healthStatus;
  final int? responseTimeMs;
  final String? statusMessage;
  final String? comment;
  final bool? r18;
  final String? group;

  bool get isBadHealth =>
      healthStatus == 'degraded' || healthStatus == 'unhealthy';

  factory LocalVodSource.fromJsonMap(String key, Map<String, dynamic> json) {
    return LocalVodSource(
      key: key,
      name: _readString(json['name']) ?? key,
      apiUrl: _readString(json['api']) ?? '',
      detailUrl: _readString(json['detail']) ?? _readString(json['api']) ?? '',
      enabled: json['enabled'] as bool? ?? true,
      comment: _readString(json['_comment']) ?? _readString(json['comment']),
      r18: json['r18'] as bool?,
      group: _readString(json['group']),
    );
  }

  factory LocalVodSource.fromStorage(Map<String, dynamic> json) {
    return LocalVodSource(
      key: _readString(json['key']) ?? '',
      name: _readString(json['name']) ?? '',
      apiUrl: _readString(json['api_url']) ?? '',
      detailUrl: _readString(json['detail_url']) ?? '',
      enabled: json['enabled'] as bool? ?? true,
      lastCheck: _readInt(json['last_check']),
      isHealthy: json['is_healthy'] as bool?,
      healthStatus: _readString(json['health_status']),
      responseTimeMs: _readInt(json['response_time_ms']),
      statusMessage: _readString(json['status_message']),
      comment: _readString(json['comment']),
      r18: json['r18'] as bool?,
      group: _readString(json['group']),
    );
  }

  factory LocalVodSource.fromRemote(RemoteSource source) {
    return LocalVodSource(
      key: source.key.trim(),
      name: source.name.trim(),
      apiUrl: source.api.trim(),
      detailUrl: source.detail.trim().isEmpty
          ? source.api.trim()
          : source.detail.trim(),
      enabled: true,
      comment: source.comment,
      r18: source.r18,
      group: source.group,
    );
  }

  factory LocalVodSource.fromRequest(AddSourceRequest request) {
    final group = request.group?.trim();
    final isR18 = request.r18 ?? false;
    return LocalVodSource(
      key: request.key.trim(),
      name: request.name.trim(),
      apiUrl: request.api.trim(),
      detailUrl: request.detail.trim(),
      enabled: true,
      comment: request.comment?.trim().isEmpty ?? true
          ? '自定义添加'
          : request.comment?.trim(),
      r18: isR18,
      group: group == null || group.isEmpty ? (isR18 ? 'R18' : '自定义') : group,
    );
  }

  LocalVodSource copyWith({
    String? key,
    String? name,
    String? apiUrl,
    String? detailUrl,
    bool? enabled,
    int? lastCheck,
    bool? isHealthy,
    String? healthStatus,
    int? responseTimeMs,
    String? statusMessage,
    String? comment,
    bool? r18,
    String? group,
  }) {
    return LocalVodSource(
      key: key ?? this.key,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      detailUrl: detailUrl ?? this.detailUrl,
      enabled: enabled ?? this.enabled,
      lastCheck: lastCheck ?? this.lastCheck,
      isHealthy: isHealthy ?? this.isHealthy,
      healthStatus: healthStatus ?? this.healthStatus,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      statusMessage: statusMessage ?? this.statusMessage,
      comment: comment ?? this.comment,
      r18: r18 ?? this.r18,
      group: group ?? this.group,
    );
  }

  LocalVodSource withHealth({
    required int elapsedMs,
    required String status,
    required String? message,
  }) {
    return LocalVodSource(
      key: key,
      name: name,
      apiUrl: apiUrl,
      detailUrl: detailUrl,
      enabled: enabled,
      lastCheck: DateTime.now().millisecondsSinceEpoch,
      isHealthy: status == 'healthy',
      healthStatus: status,
      responseTimeMs: elapsedMs,
      statusMessage: message,
      comment: comment,
      r18: r18,
      group: group,
    );
  }

  SiteWithStatus toSiteWithStatus() {
    return SiteWithStatus(
      key: key,
      name: name,
      baseUrl: apiUrl,
      detailUrl: detailUrl,
      enabled: enabled,
      lastCheck: lastCheck,
      isHealthy: isHealthy,
      healthStatus: healthStatus,
      responseTimeMs: responseTimeMs,
      statusMessage: statusMessage,
      comment: comment,
      r18: r18,
      group: group,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'api_url': apiUrl,
      'detail_url': detailUrl,
      'enabled': enabled,
      'last_check': lastCheck,
      'is_healthy': isHealthy,
      'health_status': healthStatus,
      'response_time_ms': responseTimeMs,
      'status_message': statusMessage,
      'comment': comment,
      'r18': r18,
      'group': group,
    };
  }
}

Uri _buildVodApiUri(
  String baseUrl,
  Map<String, String> queryParameters,
) {
  final uri = Uri.parse(baseUrl);
  final existing = Map<String, String>.from(uri.queryParameters);
  final proxiedTarget = existing['url'];
  if (proxiedTarget != null && proxiedTarget.trim().isNotEmpty) {
    final upstream = Uri.parse(proxiedTarget);
    final upstreamQuery = <String, String>{
      ...upstream.queryParameters,
      ...queryParameters,
    };
    existing['url'] =
        upstream.replace(queryParameters: upstreamQuery).toString();
    return uri.replace(queryParameters: existing);
  }
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      ...queryParameters,
    },
  );
}

Map<String, dynamic> _toJsonMap(Object? data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return data.cast<String, dynamic>();
  }
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  }
  throw const FormatException('响应格式错误');
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

int? _readResponseCode(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
