import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/models/vod_models.dart';
import '../../settings/data/local_sources_store.dart';

class NativeSourceCrawler {
  NativeSourceCrawler({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<VodItem>> search(
    LocalVodSource source,
    String keyword, {
    List<String> restrictedCategories = const [],
  }) async {
    final response = await _fetchVodList(
      source.apiUrl,
      queryParameters: {
        'ac': 'videolist',
        'pg': '1',
        'wd': keyword,
      },
    );
    return response.map((item) => _mapToVodItem(item, source)).where((item) {
      final typeName = item.typeName;
      if (typeName == null || restrictedCategories.isEmpty) {
        return true;
      }
      return !restrictedCategories.any(typeName.contains);
    }).toList(growable: false);
  }

  Future<VodItem> getDetail(LocalVodSource source, String vodId) async {
    final response = await _fetchVodList(
      source.apiUrl,
      queryParameters: {
        'ac': 'videolist',
        'ids': vodId,
      },
    );
    final detail = response.firstOrNull;
    if (detail == null) {
      throw StateError('未找到影视详情');
    }
    return _mapToVodItem(detail, source);
  }

  Future<List<Map<String, dynamic>>> _fetchVodList(
    String baseUrl, {
    required Map<String, String> queryParameters,
  }) async {
    final response = await _dio.getUri<Object>(
      _buildVodApiUri(baseUrl, queryParameters),
    );
    final json = _toJsonMap(response.data);
    final code = _readResponseCode(json['code']);
    if (code != null && !const [0, 1, 200].contains(code)) {
      final message = _readString(json['msg']) ?? '片源接口返回错误';
      throw StateError(message);
    }
    final list = json['list'];
    if (list is! List) {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  VodItem _mapToVodItem(Map<String, dynamic> item, LocalVodSource source) {
    return VodItem(
      sourceKey: source.key,
      vodId: _readString(item['vod_id']) ?? '',
      vodName: _readString(item['vod_name']) ?? '',
      vodPlayUrl: _readString(item['vod_play_url']) ?? '',
      vodPic: _readString(item['vod_pic']),
      vodRemarks: _readString(item['vod_remarks']),
      vodActor: _readString(item['vod_actor']),
      vodDirector: _readString(item['vod_director']),
      vodContent:
          _readString(item['vod_content']) ?? _readString(item['vod_blurb']),
      vodYear: _readString(item['vod_year']),
      vodArea: _readString(item['vod_area']),
      vodClass: _readString(item['vod_class']),
      vodTag: _readString(item['vod_tag']),
      vodDuration: _readString(item['vod_duration']),
      vodLang: _readString(item['vod_lang']),
      typeName: _readString(item['type_name']),
    );
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
    final nextTarget = upstream.replace(
      queryParameters: {
        ...upstream.queryParameters,
        ...queryParameters,
      },
    );
    existing['url'] = nextTarget.toString();
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
  throw const FormatException('资源站响应格式错误');
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _readResponseCode(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
