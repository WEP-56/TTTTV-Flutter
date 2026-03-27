import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/models/vod_models.dart';
import 'kuaishou_models.dart';

class KuaishouParser {
  const KuaishouParser();

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

  static const imageExtensions = <String>{
    'svgz',
    'pjp',
    'png',
    'ico',
    'avif',
    'tiff',
    'tif',
    'jfif',
    'svg',
    'xbm',
    'pjpeg',
    'webp',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
  };

  Map<String, dynamic> decodeJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    throw StateError('Kuaishou response format is invalid.');
  }

  Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  Map<String, dynamic> extractInitialState(String html) {
    final match = RegExp(
      r'window\.__INITIAL_STATE__=(.*?);',
      multiLine: false,
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      throw StateError('Kuaishou room page initial state not found.');
    }
    final payload = match.group(1)?.replaceAll('undefined', 'null') ?? '';
    if (payload.isEmpty) {
      throw StateError('Kuaishou room page initial state is empty.');
    }
    return decodeJsonMap(payload);
  }

  KuaishouRoomProfile parseRoomProfile(
    String authorId,
    Map<String, dynamic> initialState,
  ) {
    final liveroom = asMap(initialState['liveroom']);
    final playlist = liveroom['playList'] as List<dynamic>? ?? const [];
    if (playlist.isEmpty) {
      throw StateError('Kuaishou room playlist is empty.');
    }

    final item = asMap(playlist.first);
    final liveStream = asMap(item['liveStream']);
    final author = asMap(item['author']);
    final gameInfo = asMap(item['gameInfo']);

    final roomId = author['id']?.toString() ?? authorId;
    final cover = ensureImageUrl(liveStream['poster']?.toString() ?? '');
    final description = _emptyToNull(author['description']?.toString());
    final title = _firstNonEmpty(
      item['caption']?.toString(),
      description,
      author['name']?.toString(),
    );

    final rawPlayUrls = asMap(liveStream['playUrls']);
    final qualities = parseQualities(rawPlayUrls);
    final isLiving =
        item['isLiving'] as bool? ?? item['living'] as bool? ?? false;

    return KuaishouRoomProfile(
      roomId: roomId,
      title: title,
      cover: cover,
      userName: author['name']?.toString() ?? '',
      userAvatar: author['avatar']?.toString() ?? '',
      online: parseCount(gameInfo['watchingCount'] ?? item['watchingCount']),
      status: isLiving,
      isRecord: false,
      url: 'https://live.kuaishou.com/u/$roomId',
      introduction: description,
      notice: description,
      qualities: qualities,
    );
  }

  List<KuaishouQuality> parseQualities(Map<String, dynamic> rawPlayUrls) {
    final preferred = asMap(rawPlayUrls['h264']);
    final fallback = preferred.isNotEmpty
        ? preferred
        : rawPlayUrls.values
            .map(asMap)
            .firstWhere((item) => item.isNotEmpty, orElse: () => const {});
    final adaptationSet = asMap(fallback['adaptationSet']);
    final representations =
        adaptationSet['representation'] as List<dynamic>? ?? const [];

    final results = <KuaishouQuality>[];
    for (final raw in representations) {
      final map = asMap(raw);
      final url = map['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      results.add(
        KuaishouQuality(
          id: (map['id'] ?? map['level'] ?? results.length).toString(),
          name: map['name']?.toString() ?? '',
          shortName: map['shortName']?.toString() ?? '',
          level: toInt(map['level']),
          bitrate: toInt(map['bitrate']),
          url: url,
        ),
      );
    }

    results.sort((left, right) => right.level.compareTo(left.level));
    return results;
  }

  LivePlayUrl buildPlayUrl(
    KuaishouRoomProfile profile,
    String qualityId,
  ) {
    final selected = profile.qualities.firstWhere(
      (quality) => quality.id == qualityId,
      orElse: () => profile.qualities.first,
    );
    return LivePlayUrl(
      urls: [selected.url],
      headers: {
        'user-agent': userAgent,
        'referer': profile.url,
        'origin': 'https://live.kuaishou.com',
      },
      urlType: 'flv',
    );
  }

  LiveRoomItem roomItemFromRecommend(dynamic raw) {
    final map = asMap(raw);
    final author = asMap(map['author']);
    return LiveRoomItem(
      platform: 'kuaishou',
      roomId: author['id']?.toString() ?? '',
      title: _firstNonEmpty(
        map['caption']?.toString(),
        author['description']?.toString(),
        author['name']?.toString(),
      ),
      cover: ensureImageUrl(map['poster']?.toString() ?? ''),
      userName: author['name']?.toString() ?? '',
      online: parseCount(map['watchingCount']),
    );
  }

  String ensureImageUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (_isImage(trimmed)) {
      return trimmed;
    }
    return '$trimmed.jpg';
  }

  int parseCount(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;
    final normalized = text.replaceAll('+', '');
    if (normalized.contains('万')) {
      final parsed = double.tryParse(normalized.replaceAll('万', ''));
      if (parsed != null) {
        return (parsed * 10000).round();
      }
    }
    if (normalized.contains('亿')) {
      final parsed = double.tryParse(normalized.replaceAll('亿', ''));
      if (parsed != null) {
        return (parsed * 100000000).round();
      }
    }
    return int.tryParse(normalized) ?? 0;
  }

  int toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, String> headers({
    String? referer,
  }) {
    return {
      'user-agent': userAgent,
      'accept': 'application/json, text/plain, */*',
      if (referer != null) 'referer': referer,
      'origin': 'https://live.kuaishou.com',
    };
  }

  Options options({
    String? referer,
  }) {
    return Options(headers: headers(referer: referer));
  }

  bool _isImage(String url) {
    final normalized = url.split('?').first;
    final dotIndex = normalized.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == normalized.length - 1) {
      return false;
    }
    final ext = normalized.substring(dotIndex + 1).toLowerCase();
    return imageExtensions.contains(ext);
  }

  String _firstNonEmpty(
    String? first, [
    String? second,
    String? third,
  ]) {
    for (final value in [first, second, third]) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
