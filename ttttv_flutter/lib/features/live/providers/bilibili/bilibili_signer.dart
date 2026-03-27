import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'bilibili_auth_service.dart';

class BilibiliSigner {
  BilibiliSigner({
    required Dio dio,
    required BilibiliAuthService authService,
  })  : _dio = dio,
        _authService = authService;

  final Dio _dio;
  final BilibiliAuthService _authService;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
  static const String defaultReferer = 'https://live.bilibili.com/';

  static const List<int> _mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  String _buvid3 = '';
  String _buvid4 = '';
  String _imgKey = '';
  String _subKey = '';
  String _accessId = '';

  Future<Map<String, String>> headers() async {
    await getBuvid();
    final cookie = await _authService.getCookie();
    return {
      'user-agent': defaultUserAgent,
      'referer': defaultReferer,
      'cookie': _mergeCookie(cookie),
    };
  }

  Future<String> getMergedCookie() async {
    await getBuvid();
    return _mergeCookie(await _authService.getCookie());
  }

  Future<String> getBuvid() async {
    if (_buvid3.isNotEmpty) {
      return _buvid3;
    }

    final cookie = await _authService.getCookie();
    final buvid3Match = RegExp(r'buvid3=([^;]+)').firstMatch(cookie);
    final buvid4Match = RegExp(r'buvid4=([^;]+)').firstMatch(cookie);
    if (buvid3Match != null && buvid4Match != null) {
      _buvid3 = buvid3Match.group(1) ?? '';
      _buvid4 = buvid4Match.group(1) ?? '';
      if (_buvid3.isNotEmpty) return _buvid3;
    }

    final response = await _dio.get<Object?>(
      'https://api.bilibili.com/x/frontend/finger/spi',
      options: Options(
        headers: {
          'user-agent': defaultUserAgent,
          'referer': defaultReferer,
          if (cookie.isNotEmpty) 'cookie': cookie,
        },
      ),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    _buvid3 = data['b_3']?.toString() ?? '';
    _buvid4 = data['b_4']?.toString() ?? '';
    return _buvid3;
  }

  Future<String> getAccessId() async {
    if (_accessId.isNotEmpty) {
      return _accessId;
    }

    final response = await _dio.get<String>(
      'https://live.bilibili.com/lol',
      options: Options(headers: await headers()),
    );

    _accessId = RegExp(r'"access_id":"(.*?)"')
            .firstMatch(response.data ?? '')
            ?.group(1)
            ?.replaceAll(r'\', '') ??
        '';
    return _accessId;
  }

  Future<Map<String, dynamic>> getWbiSign(
    String baseUrl, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final (imgKey, subKey) = await _getWbiKeys();
    final mixinKey = _getMixinKey('$imgKey$subKey');

    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        ...Uri.parse(baseUrl).queryParameters,
        if (queryParameters != null)
          for (final entry in queryParameters.entries)
            if (entry.value != null) entry.key: entry.value.toString(),
      },
    );

    final params = Map<String, String>.from(uri.queryParameters)
      ..['wts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final sortedKeys = params.keys.toList()..sort();
    final filtered = <String, String>{};
    for (final key in sortedKeys) {
      filtered[key] = (params[key] ?? '')
          .split('')
          .where((char) => !"!'()*".contains(char))
          .join();
    }

    final queryText = sortedKeys
        .map(
          (key) => '$key=${Uri.encodeQueryComponent(filtered[key] ?? '')}',
        )
        .join('&');

    params['w_rid'] =
        md5.convert(utf8.encode('$queryText$mixinKey')).toString();
    return params;
  }

  Future<(String, String)> _getWbiKeys() async {
    if (_imgKey.isNotEmpty && _subKey.isNotEmpty) {
      return (_imgKey, _subKey);
    }

    final response = await _dio.get<Object?>(
      'https://api.bilibili.com/x/web-interface/nav',
      options: Options(headers: await headers()),
    );

    final map = response.data as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final wbiImage = data['wbi_img'] as Map<String, dynamic>? ?? const {};
    final imageUrl = wbiImage['img_url']?.toString() ?? '';
    final subUrl = wbiImage['sub_url']?.toString() ?? '';

    _imgKey = imageUrl.split('/').last.split('.').first;
    _subKey = subUrl.split('/').last.split('.').first;
    return (_imgKey, _subKey);
  }

  String _getMixinKey(String origin) {
    return _mixinKeyEncTab
        .fold<String>(
          '',
          (value, index) => value + origin[index],
        )
        .substring(0, 32);
  }

  String _mergeCookie(String cookie) {
    final tokens = <String>[
      if (cookie.trim().isNotEmpty) cookie.trim(),
      if (_buvid3.isNotEmpty && !cookie.contains('buvid3=')) 'buvid3=$_buvid3',
      if (_buvid4.isNotEmpty && !cookie.contains('buvid4=')) 'buvid4=$_buvid4',
    ];
    return tokens.join(';');
  }
}
