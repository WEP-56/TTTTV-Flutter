import 'dart:convert';

import 'package:dio/dio.dart';

import '../../settings/domain/app_settings.dart';

enum DoubanTargetSource {
  douban,
  bangumi,
}

class DoubanItem {
  const DoubanItem({
    required this.id,
    required this.title,
    required this.poster,
    this.rate,
    this.year,
    this.subtitle,
    this.summary,
    this.episodeCount,
    this.source = DoubanTargetSource.douban,
  });

  final String id;
  final String title;
  final String poster;
  final String? rate;
  final String? year;
  final String? subtitle;
  final String? summary;
  final int? episodeCount;
  final DoubanTargetSource source;
}

class DoubanCategoryResult {
  const DoubanCategoryResult({required this.items});
  final List<DoubanItem> items;
}

class DoubanRepository {
  DoubanRepository({required Dio dio, this.customProxyUrl}) : _dio = dio;

  final Dio _dio;
  final String? customProxyUrl;

  static const _apiHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://movie.douban.com/',
  };

  String _baseUrl(DoubanDataSource source) {
    switch (source) {
      case DoubanDataSource.tencentCDN:
        return 'https://m.douban.cmliussss.net';
      case DoubanDataSource.aliCDN:
        return 'https://m.douban.cmliussss.com';
      case DoubanDataSource.custom:
        return customProxyUrl ?? 'https://m.douban.com';
      case DoubanDataSource.direct:
        return 'https://m.douban.com';
    }
  }

  String _movieBaseUrl(DoubanDataSource source) {
    switch (source) {
      case DoubanDataSource.tencentCDN:
        return 'https://movie.douban.cmliussss.net';
      case DoubanDataSource.aliCDN:
        return 'https://movie.douban.cmliussss.com';
      case DoubanDataSource.custom:
        final url = customProxyUrl;
        if (url == null || url.trim().isEmpty) {
          return 'https://movie.douban.com';
        }
        return url
            .replaceFirst('https://m.douban.', 'https://movie.douban.')
            .replaceFirst('http://m.douban.', 'http://movie.douban.');
      case DoubanDataSource.direct:
        return 'https://movie.douban.com';
    }
  }

  Future<List<DoubanItem>> searchTargets({
    required DoubanDataSource source,
    required String keyword,
    int limit = 20,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    final results = await Future.wait<List<DoubanItem>>([
      _searchDoubanSuggest(source: source, keyword: query, limit: limit),
      _searchBangumiSubjects(keyword: query, limit: limit ~/ 2),
    ]);

    final seen = <String>{};
    final items = <DoubanItem>[];
    for (final item in results.expand((items) => items)) {
      final key = [
        _normalizeTargetTitle(item.title),
        item.year ?? '',
        item.id,
      ].join('|');
      if (item.title.trim().isEmpty || !seen.add(key)) {
        continue;
      }
      items.add(item);
      if (items.length >= limit) {
        break;
      }
    }
    return items;
  }

  Future<List<DoubanItem>> _searchDoubanSuggest({
    required DoubanDataSource source,
    required String keyword,
    required int limit,
  }) async {
    try {
      final base = _movieBaseUrl(source);
      final uri = Uri.parse('$base/j/subject_suggest').replace(
        queryParameters: {'q': keyword},
      );
      final response = await _dio.getUri<Object>(
        uri,
        options: Options(
          headers: _apiHeaders,
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      final list = response.data is List ? response.data as List : const [];
      return list
          .take(limit)
          .map((entry) {
            final item = _toJson(entry);
            final episodeText = item['episode']?.toString();
            final year = item['year']?.toString();
            final subtitle = item['sub_title']?.toString();
            final remarks = [
              '豆瓣',
              if (year != null && year.isNotEmpty) year,
              if (episodeText != null &&
                  episodeText.isNotEmpty &&
                  episodeText != 'unknow')
                '$episodeText集',
            ].join(' · ');
            return DoubanItem(
              id: 'douban:${item['id'] ?? ''}',
              title: item['title']?.toString() ?? '',
              poster: item['img']?.toString() ?? '',
              rate: remarks,
              year: year,
              subtitle: subtitle,
              source: DoubanTargetSource.douban,
              episodeCount: int.tryParse(episodeText ?? ''),
            );
          })
          .where((item) => item.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<DoubanItem>> _searchBangumiSubjects({
    required String keyword,
    required int limit,
  }) async {
    if (limit <= 0) {
      return const [];
    }
    try {
      final response = await _dio.postUri<Object>(
        Uri.parse('https://api.bgm.tv/v0/search/subjects').replace(
          queryParameters: {'limit': limit.toString()},
        ),
        data: {
          'keyword': keyword,
          'filter': {
            'type': [2],
          },
        },
        options: Options(
          headers: const {
            'User-Agent': 'TTTTV-Flutter/1.0 (local media search)',
          },
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      final data = _toJson(response.data);
      final list = (data['data'] as List?) ?? const [];
      return list.take(limit).map((entry) {
        final item = _toJson(entry);
        final images = _toJson(item['images'] ?? const {});
        final title = (item['name_cn'] ?? item['name'] ?? '').toString();
        final date = item['date']?.toString() ?? '';
        final year = RegExp(r'\d{4}').firstMatch(date)?.group(0);
        final score = _toJson(item['rating'] ?? const {})['score'];
        final rate = double.tryParse(score?.toString() ?? '');
        final remarks = [
          'Bangumi',
          if (year != null && year.isNotEmpty) year,
          if (rate != null && rate > 0) rate.toStringAsFixed(1),
        ].join(' · ');
        return DoubanItem(
          id: 'bangumi:${item['id'] ?? ''}',
          title: title,
          poster: (images['large'] ??
                  images['common'] ??
                  images['medium'] ??
                  item['image'] ??
                  '')
              .toString(),
          rate: remarks,
          year: year,
          subtitle: item['name']?.toString(),
          source: DoubanTargetSource.bangumi,
          summary: item['summary']?.toString(),
        );
      }).where((item) {
        if (item.title.isEmpty) return false;
        final normalizedKeyword = _normalizeTargetTitle(keyword);
        final normalizedTitle = _normalizeTargetTitle(item.title);
        final normalizedSubtitle = _normalizeTargetTitle(item.subtitle ?? '');
        return normalizedTitle.contains(normalizedKeyword) ||
            normalizedKeyword.contains(normalizedTitle) ||
            normalizedSubtitle.contains(normalizedKeyword);
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 获取热门推荐分类数据
  Future<DoubanCategoryResult> fetchCategory({
    required DoubanDataSource source,
    required String kind, // 'movie' or 'tv'
    required String category,
    required String type,
    int limit = 20,
    int start = 0,
  }) async {
    final base = _baseUrl(source);
    final url =
        '$base/rexxar/api/v2/subject/recent_hot/$kind?start=$start&limit=$limit&category=$category&type=$type';

    final response = await _dio.getUri<Object>(
      Uri.parse(url),
      options: Options(
        headers: _apiHeaders,
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      ),
    );

    final data = _toJson(response.data);
    final items = (data['items'] as List?)?.map((item) {
          final m = _toJson(item);
          final pic = _toJson(m['pic'] ?? const {});
          final rating = _toJson(m['rating'] ?? const {});
          return DoubanItem(
            id: m['id']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            poster: (pic['normal'] ?? pic['large'])?.toString() ?? '',
            rate: () {
              final v = rating['value'];
              if (v == null) return null;
              return double.tryParse(v.toString())?.toStringAsFixed(1);
            }(),
            year: () {
              final subtitle = m['card_subtitle']?.toString() ?? '';
              final match = RegExp(r'\d{4}').firstMatch(subtitle);
              return match?.group(0);
            }(),
          );
        }).toList(growable: false) ??
        [];

    return DoubanCategoryResult(items: items);
  }

  /// 获取 Bangumi 新番日历（当天）
  Future<List<DoubanItem>> fetchBangumiCalendar() async {
    try {
      final all = await fetchBangumiCalendarFull();
      final today = DateTime.now();
      final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final currentWeekday = weekdays[today.weekday % 7];
      return all[currentWeekday] ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 获取 Bangumi 新番日历（全部 7 天），按 weekday key 分组。
  Future<Map<String, List<DoubanItem>>> fetchBangumiCalendarFull() async {
    final response = await _dio.getUri<Object>(
      Uri.parse('https://api.bgm.tv/calendar'),
      options: Options(
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      ),
    );

    final data = response.data;
    final list = (data as List?) ?? [];
    final result = <String, List<DoubanItem>>{};

    for (final day in list.whereType<Map>()) {
      final wd = day['weekday'];
      if (wd is! Map) continue;
      final key = wd['en']?.toString() ?? '';
      if (key.isEmpty) continue;

      final items = (day['items'] as List?) ?? [];
      result[key] = items.whereType<Map>().map((item) {
        final images = (item['images'] as Map?) ?? {};
        return DoubanItem(
          id: (item['id'] ?? '').toString(),
          title: (item['name_cn'] ?? item['name'] ?? '').toString(),
          poster:
              (images['large'] ?? images['common'] ?? images['medium'] ?? '')
                  .toString(),
          rate: () {
            final rating = item['rating'] as Map?;
            final score = rating?['score'];
            if (score == null) return null;
            return double.tryParse(score.toString())?.toStringAsFixed(1);
          }(),
          year: () {
            final airDate = (item['air_date'] ?? '').toString();
            final match = RegExp(r'\d{4}').firstMatch(airDate);
            return match?.group(0);
          }(),
        );
      }).toList();
    }

    return result;
  }
}

Map<String, dynamic> _toJson(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return data.cast<String, dynamic>();
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  }
  return const {};
}

String _normalizeTargetTitle(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[·・:：,，.。!！?？()（）【】\[\]《》<>「」『』-]'), '')
      .toLowerCase();
}
