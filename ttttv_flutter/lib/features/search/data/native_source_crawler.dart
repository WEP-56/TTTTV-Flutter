import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/models/vod_models.dart';
import '../../settings/data/local_sources_store.dart';

/// 一次站点搜索的结果，附带服务端返回的总页数（如果有）。
class CrawlerSearchResult {
  const CrawlerSearchResult({
    required this.items,
    this.pageCount,
  });

  final List<VodItem> items;

  /// 服务端 (apple cms) 返回的总页数，无值时表示未知，
  /// 调用方在分页前应回退到 1（不再盲扫）。
  final int? pageCount;
}

class NativeSourceCrawler {
  NativeSourceCrawler({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static final _m3u8GeneralPattern = RegExp(
    r'\$(https?://[^\s]+?\.m3u8)',
  );
  static final _m3u8ContentPattern = RegExp(
    r'(https?://[^\s]+?\.m3u8[^\s]*)',
  );

  Future<CrawlerSearchResult> search(
    LocalVodSource source,
    String keyword, {
    int page = 1,
    List<String> restrictedCategories = const [],
    CancelToken? cancelToken,
  }) async {
    final response = await _fetchVodList(
      source.apiUrl,
      queryParameters: {
        'ac': 'videolist',
        'pg': page.toString(),
        'wd': keyword,
      },
      cancelToken: cancelToken,
    );

    final pageCount = _readPageCount(response.raw);
    final items = response.list
        .map((item) => _mapToVodItem(item, source))
        .where((item) {
      final typeName = item.typeName;
      if (typeName == null || restrictedCategories.isEmpty) {
        return true;
      }
      return !restrictedCategories.any(typeName.contains);
    }).toList(growable: false);

    return CrawlerSearchResult(items: items, pageCount: pageCount);
  }

  Future<VodItem> getDetail(
    LocalVodSource source,
    String vodId, {
    CancelToken? cancelToken,
  }) async {
    if (source.hasCustomDetail) {
      return _handleHtmlDetail(source, vodId, cancelToken: cancelToken);
    }

    final response = await _fetchVodList(
      source.apiUrl,
      queryParameters: {
        'ac': 'videolist',
        'ids': vodId,
      },
      cancelToken: cancelToken,
    );
    final detail = response.list.firstOrNull;
    if (detail == null) {
      throw StateError('未找到影视详情');
    }
    return _mapToVodItem(detail, source);
  }

  Future<VodItem> _handleHtmlDetail(
    LocalVodSource source,
    String vodId, {
    CancelToken? cancelToken,
  }) async {
    final detailUrl = source.detailUrl;
    final url = '$detailUrl/index.php/vod/detail/id/$vodId.html';

    final response = await _dio.getUri<String>(
      Uri.parse(url),
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final html = response.data ?? '';

    var matches = <String>[];
    final lowerKey = source.key.toLowerCase();

    if (lowerKey == 'ffzy') {
      final ffzyPattern = RegExp(
        r'\$(https?://[^\s]+?/\d{8}/\d+_[a-f0-9]+/index\.m3u8)',
      );
      matches = ffzyPattern.allMatches(html).map((m) => m.group(1)!).toList();
    }

    if (matches.isEmpty) {
      matches = _m3u8GeneralPattern
          .allMatches(html)
          .map((m) => m.group(1)!)
          .toList();
    }

    matches = matches.toSet().map((link) {
      final parenIndex = link.indexOf('(');
      return parenIndex > 0 ? link.substring(0, parenIndex) : link;
    }).toList();

    final title =
        _extractHtmlText(html, RegExp(r'<h1[^>]*>([^<]+)<\/h1>')) ?? '';
    final desc = _extractHtmlText(
          html,
          RegExp(r"""<div[^>]*class=["']sketch["'][^>]*>([\s\S]*?)<\/div>"""),
        ) ??
        '';
    final coverMatch =
        RegExp(r'(https?://[^\s]+?\.jpg)').firstMatch(html);
    final coverUrl = coverMatch?.group(1) ?? '';
    final yearMatch = RegExp(r'>(\d{4})<').firstMatch(html);
    final yearText = yearMatch?.group(1) ?? 'unknown';

    final vodPlayUrl = List.generate(
      matches.length,
      (i) => '${i + 1}\$${matches[i]}',
    ).join('#');

    return VodItem(
      sourceKey: source.key,
      vodId: vodId,
      vodName: title,
      vodPlayUrl: vodPlayUrl,
      vodPic: coverUrl,
      vodContent: desc,
      vodYear: yearText,
    );
  }

  String? _extractHtmlText(String html, RegExp pattern) {
    final match = pattern.firstMatch(html);
    if (match == null) return null;
    final text = match.group(1)?.trim();
    if (text == null || text.isEmpty) return null;
    return _stripHtmlTags(text);
  }

  String _stripHtmlTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '\n')
        .replaceAll(RegExp(r'\n+'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  Future<_VodListResponse> _fetchVodList(
    String baseUrl, {
    required Map<String, String> queryParameters,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.getUri<Object>(
      _buildVodApiUri(baseUrl, queryParameters),
      cancelToken: cancelToken,
    );
    final json = _toJsonMap(response.data);
    final code = _readResponseCode(json['code']);
    if (code != null && !const [0, 1, 200].contains(code)) {
      final message = _readString(json['msg']) ?? '片源接口返回错误';
      throw StateError(message);
    }
    final list = json['list'];
    final items = list is List
        ? list
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return _VodListResponse(raw: json, list: items);
  }

  int? _readPageCount(Map<String, dynamic> json) {
    final raw = json['pagecount'] ?? json['pageCount'] ?? json['page_count'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  VodItem _mapToVodItem(Map<String, dynamic> item, LocalVodSource source) {
    var vodPlayUrl = _readString(item['vod_play_url']) ?? '';
    final vodContent =
        _readString(item['vod_content']) ?? _readString(item['vod_blurb']) ?? '';

    if (!_hasM3u8(vodPlayUrl) && vodContent.isNotEmpty) {
      final extracted =
          _m3u8ContentPattern.allMatches(vodContent).map((m) => m.group(0)!).toList();
      if (extracted.isNotEmpty) {
        vodPlayUrl = List.generate(
          extracted.length,
          (i) => '${i + 1}\$${extracted[i]}',
        ).join('#');
      }
    }

    return VodItem(
      sourceKey: source.key,
      vodId: _readString(item['vod_id']) ?? '',
      vodName: _readString(item['vod_name']) ?? '',
      vodPlayUrl: vodPlayUrl,
      vodPic: _readString(item['vod_pic']),
      vodRemarks: _readString(item['vod_remarks']),
      vodActor: _readString(item['vod_actor']),
      vodDirector: _readString(item['vod_director']),
      vodContent: vodContent,
      vodYear: _readString(item['vod_year']),
      vodArea: _readString(item['vod_area']),
      vodClass: _readString(item['vod_class']),
      vodTag: _readString(item['vod_tag']),
      vodDuration: _readString(item['vod_duration']),
      vodLang: _readString(item['vod_lang']),
      typeName: _readString(item['type_name']),
    );
  }

  bool _hasM3u8(String text) {
    return text.toLowerCase().contains('.m3u8');
  }
}

class _VodListResponse {
  const _VodListResponse({required this.raw, required this.list});
  final Map<String, dynamic> raw;
  final List<Map<String, dynamic>> list;
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
