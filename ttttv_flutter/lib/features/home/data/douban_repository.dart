import 'dart:convert';

import 'package:dio/dio.dart';

import '../../settings/domain/app_settings.dart';

class DoubanItem {
  const DoubanItem({
    required this.id,
    required this.title,
    required this.poster,
    this.rate,
    this.year,
  });

  final String id;
  final String title;
  final String poster;
  final String? rate;
  final String? year;
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

  /// 获取热门推荐分类数据
  Future<DoubanCategoryResult> fetchCategory({
    required DoubanDataSource source,
    required String kind, // 'movie' or 'tv'
    required String category,
    required String type,
    int limit = 20,
  }) async {
    final base = _baseUrl(source);
    final url =
        '$base/rexxar/api/v2/subject/recent_hot/$kind?start=0&limit=$limit&category=$category&type=$type';

    final response = await _dio.getUri<Object>(
      Uri.parse(url),
      options: Options(
        headers: _apiHeaders,
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      ),
    );

    final data = _toJson(response.data);
    final items = (data['items'] as List?)
            ?.map((item) {
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
                  final match =
                      RegExp(r'\d{4}').firstMatch(subtitle);
                  return match?.group(0);
                }(),
              );
            })
            .toList(growable: false) ??
        [];

    return DoubanCategoryResult(items: items);
  }

  /// 获取新番放送（Bangumi 日历）
  Future<DoubanCategoryResult> fetchBangumiCalendar({
    required DoubanDataSource source,
  }) async {
    final base = _baseUrl(source);
    final today = DateTime.now();
    final weekdays = [
      'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
    ];
    final currentWeekday = weekdays[today.weekday % 7];

    final url = '$base/rexxar/api/v2/subject/recent_hot/tv'
        '?start=0&limit=20&category=anime&type=$currentWeekday';

    try {
      final response = await _dio.getUri<Object>(
        Uri.parse(url),
        options: Options(
          headers: _apiHeaders,
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      final data = _toJson(response.data);
      final items = (data['items'] as List?)
              ?.map((item) {
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
              })
              .toList(growable: false) ??
          [];

      return DoubanCategoryResult(items: items);
    } catch (_) {
      return DoubanCategoryResult(items: []);
    }
  }
}

  /// 获取 Bangumi 新番日历
  Future<List<DoubanItem>> fetchBangumiCalendar() async {
    try {
      final response = await _dio.getUri<Object>(
        Uri.parse('https://api.bgm.tv/calendar'),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      final data = response.data;
      final list = (data as List?) ?? [];

      final today = DateTime.now();
      final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final currentWeekday = weekdays[today.weekday % 7];

      final todayItems = list
          .whereType<Map>()
          .firstWhere(
            (day) => () {
              final wd = day['weekday'];
              if (wd is Map) return wd['en'] == currentWeekday;
              return false;
            }(),
            orElse: () => const {},
          );

      final items = (todayItems['items'] as List?) ?? [];

      return items.whereType<Map>().map((item) {
        final images = (item['images'] as Map?) ?? {};
        return DoubanItem(
          id: (item['id'] ?? '').toString(),
          title: (item['name_cn'] ?? item['name'] ?? '').toString(),
          poster: (images['large'] ?? images['common'] ?? images['medium'] ?? '').toString(),
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
    } catch (_) {
      return [];
    }
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
