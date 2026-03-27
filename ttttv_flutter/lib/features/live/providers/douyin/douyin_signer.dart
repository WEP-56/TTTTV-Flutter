import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'douyin_auth_service.dart';
import 'douyin_signature_script.dart';

class DouyinSigner {
  DouyinSigner({
    required Dio dio,
    required DouyinAuthService authService,
  })  : _dio = dio,
        _authService = authService;

  final Dio _dio;
  final DouyinAuthService _authService;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 '
      'Core/1.116.567.400 QQBrowser/19.7.6764.400';
  static const String searchUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';
  static const String defaultCookie =
      'ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049'
      '%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511';
  static const String defaultReferer = 'https://live.douyin.com';
  static const String defaultAuthority = 'live.douyin.com';
  static const String _windowEnv =
      '1920|1080|1920|1040|0|30|0|0|1872|92|1920|1040|1857|92|1|24|Win32';

  Future<Map<String, String>> headers({
    String? referer,
    String? authority,
    String? userAgent,
    String? cookie,
    Map<String, String>? extra,
  }) async {
    return {
      'authority': authority ?? defaultAuthority,
      'referer': referer ?? defaultReferer,
      'user-agent': userAgent ?? defaultUserAgent,
      'cookie': cookie ?? await getRequestCookie(),
      if (extra != null) ...extra,
    };
  }

  Future<Map<String, String>> playHeaders({
    required String referer,
  }) async {
    return {
      'referer': referer,
      'user-agent': defaultUserAgent,
      'cookie': await getRequestCookie(),
    };
  }

  Future<String> getRequestCookie({
    bool refreshWebCookie = false,
    String? webRid,
  }) async {
    final savedCookie = (await _authService.getCookie()).trim();
    final baseCookie = savedCookie.isNotEmpty ? savedCookie : defaultCookie;
    if (!refreshWebCookie) {
      return baseCookie;
    }

    final transientCookie = await _fetchTransientCookie(webRid: webRid);
    return _mergeCookies(baseCookie, transientCookie);
  }

  Future<Map<String, String>> searchHeaders(String keyword) async {
    final cookie = await getRequestCookie(refreshWebCookie: true);
    return {
      'authority': 'www.douyin.com',
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'cookie': cookie,
      'priority': 'u=1, i',
      'referer':
          'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
      'sec-ch-ua':
          '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      'user-agent': searchUserAgent,
    };
  }

  String getWebSocketSignature(String roomId, String userId) {
    return DouyinSignatureScript.getSignature(roomId, userId);
  }

  Uri signUrl(
    String baseUrl, {
    required Map<String, Object?> queryParameters,
    String userAgent = defaultUserAgent,
  }) {
    final orderedQuery = <String, String>{};
    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value == null) continue;
      orderedQuery[entry.key] = value.toString();
    }
    orderedQuery['msToken'] = _generateMsToken(107);

    final uri = Uri.parse(baseUrl).replace(queryParameters: orderedQuery);
    final aBogus = _generateABogus(uri.query, userAgent);
    return uri.replace(
      queryParameters: {
        ...orderedQuery,
        'a_bogus': aBogus,
      },
    );
  }

  Future<String> _fetchTransientCookie({String? webRid}) async {
    final path = (webRid ?? '').trim();
    final response = await _dio.head<Object?>(
      path.isEmpty ? defaultReferer : '$defaultReferer/$path',
      options: Options(
        headers: {
          'referer': defaultReferer,
          'user-agent': defaultUserAgent,
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final segments = <String>[];
    for (final value in response.headers['set-cookie'] ?? const []) {
      final segment = value.split(';').first.trim();
      if (segment.startsWith('ttwid=') ||
          segment.startsWith('__ac_nonce=') ||
          segment.startsWith('msToken=')) {
        segments.add(segment);
      }
    }
    return segments.join(';');
  }

  String _mergeCookies(String baseCookie, String extraCookie) {
    final ordered = <String>[];
    final seen = <String>{};

    void addCookieParts(String source) {
      for (final rawPart in source.split(';')) {
        final part = rawPart.trim();
        if (part.isEmpty || !part.contains('=')) continue;
        final key = part.split('=').first.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) continue;
        ordered.add(part);
      }
    }

    addCookieParts(baseCookie);
    addCookieParts(extraCookie);
    return ordered.join(';');
  }

  String _generateABogus(String query, String userAgent) {
    final randomPrefix = _generateRandomPrefix();
    final bb = _generateRc4BbString(
      query,
      userAgent,
      _windowEnv,
      'cus',
      const [0, 1, 14],
    );
    return '${_resultEncrypt('$randomPrefix$bb', 's4')}=';
  }

  String _generateRandomPrefix() {
    final bytes = <int>[];
    bytes.addAll(_generRandom((0.123456789 * 10000).floor(), const [3, 45]));
    bytes.addAll(_generRandom((0.987654321 * 10000).floor(), const [1, 0]));
    bytes.addAll(_generRandom((0.555555555 * 10000).floor(), const [1, 5]));
    return String.fromCharCodes(bytes);
  }

  List<int> _generRandom(int randomValue, List<int> option) {
    final byte1 = randomValue & 255;
    final byte2 = (randomValue >> 8) & 255;
    return [
      (byte1 & 170) | (option[0] & 85),
      (byte1 & 85) | (option[0] & 170),
      (byte2 & 170) | (option[1] & 85),
      (byte2 & 85) | (option[1] & 170),
    ];
  }

  String _generateRc4BbString(
    String query,
    String userAgent,
    String windowEnv,
    String suffix,
    List<int> arguments,
  ) {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final urlDigest = _sm3Sum(
      _sm3Sum(utf8.encode('$query$suffix')),
    );
    final suffixDigest = _sm3Sum(_sm3Sum(utf8.encode(suffix)));
    final uaDigest = _sm3Sum(
      utf8.encode(
        _resultEncrypt(
          _rc4Encrypt(userAgent, String.fromCharCodes(const [0, 1, 14])),
          's3',
        ),
      ),
    );

    final endTime = startTime + 100;
    final buffer = List<int>.filled(80, 0);

    buffer[8] = 3;
    buffer[10] = endTime;
    buffer[16] = startTime;
    buffer[18] = 44;

    void writeBytes(int index, int value) {
      buffer[index] = (value >> 24) & 255;
      buffer[index + 1] = (value >> 16) & 255;
      buffer[index + 2] = (value >> 8) & 255;
      buffer[index + 3] = value & 255;
    }

    writeBytes(20, buffer[16]);
    buffer[24] = (buffer[16] ~/ 256 ~/ 256 ~/ 256 ~/ 256) & 255;
    buffer[25] = (buffer[16] ~/ 256 ~/ 256 ~/ 256 ~/ 256 ~/ 256) & 255;

    writeBytes(26, arguments[0]);
    buffer[30] = (arguments[1] ~/ 256) & 255;
    buffer[31] = arguments[1] % 256;
    buffer[32] = (arguments[1] >> 24) & 255;
    buffer[33] = (arguments[1] >> 16) & 255;
    writeBytes(34, arguments[2]);

    buffer[38] = urlDigest[21];
    buffer[39] = urlDigest[22];
    buffer[40] = suffixDigest[21];
    buffer[41] = suffixDigest[22];
    buffer[42] = uaDigest[23];
    buffer[43] = uaDigest[24];

    writeBytes(44, buffer[10]);
    buffer[48] = buffer[8];
    buffer[49] = (buffer[10] ~/ 256 ~/ 256 ~/ 256 ~/ 256) & 255;
    buffer[50] = (buffer[10] ~/ 256 ~/ 256 ~/ 256 ~/ 256 ~/ 256) & 255;

    const pageId = 110624;
    buffer[51] = pageId;
    writeBytes(52, pageId);

    const aid = 6383;
    buffer[56] = aid;
    buffer[57] = aid & 255;
    buffer[58] = (aid >> 8) & 255;
    buffer[59] = (aid >> 16) & 255;
    buffer[60] = (aid >> 24) & 255;

    final windowBytes = windowEnv.codeUnits;
    buffer[64] = windowBytes.length;
    buffer[65] = windowBytes.length & 255;
    buffer[66] = (windowBytes.length >> 8) & 255;

    final checksum = buffer[18] ^
        buffer[20] ^
        buffer[26] ^
        buffer[30] ^
        buffer[38] ^
        buffer[40] ^
        buffer[42] ^
        buffer[21] ^
        buffer[27] ^
        buffer[31] ^
        buffer[35] ^
        buffer[39] ^
        buffer[41] ^
        buffer[43] ^
        buffer[22] ^
        buffer[28] ^
        buffer[32] ^
        buffer[36] ^
        buffer[23] ^
        buffer[29] ^
        buffer[33] ^
        buffer[37] ^
        buffer[44] ^
        buffer[45] ^
        buffer[46] ^
        buffer[47] ^
        buffer[48] ^
        buffer[49] ^
        buffer[50] ^
        buffer[24] ^
        buffer[25] ^
        buffer[52] ^
        buffer[53] ^
        buffer[54] ^
        buffer[55] ^
        buffer[57] ^
        buffer[58] ^
        buffer[59] ^
        buffer[60] ^
        buffer[65] ^
        buffer[66] ^
        buffer[70] ^
        buffer[71];
    buffer[72] = checksum;

    final bb = <int>[
      buffer[18],
      buffer[20],
      buffer[52],
      buffer[26],
      buffer[30],
      buffer[34],
      buffer[58],
      buffer[38],
      buffer[40],
      buffer[53],
      buffer[42],
      buffer[21],
      buffer[27],
      buffer[54],
      buffer[55],
      buffer[31],
      buffer[35],
      buffer[57],
      buffer[39],
      buffer[41],
      buffer[43],
      buffer[22],
      buffer[28],
      buffer[32],
      buffer[60],
      buffer[36],
      buffer[23],
      buffer[29],
      buffer[33],
      buffer[37],
      buffer[44],
      buffer[45],
      buffer[59],
      buffer[46],
      buffer[47],
      buffer[48],
      buffer[49],
      buffer[50],
      buffer[24],
      buffer[25],
      buffer[65],
      buffer[66],
      buffer[70],
      buffer[71],
      ...windowBytes,
      checksum,
    ];

    return _rc4Encrypt(String.fromCharCodes(bb), String.fromCharCode(121));
  }

  String _rc4Encrypt(String plaintext, String key) {
    final state = List<int>.generate(256, (index) => index);
    var j = 0;
    final keyBytes = key.codeUnits;
    for (var i = 0; i < 256; i += 1) {
      j = (j + state[i] + keyBytes[i % keyBytes.length]) % 256;
      final temp = state[i];
      state[i] = state[j];
      state[j] = temp;
    }

    final output = <int>[];
    var i = 0;
    j = 0;
    for (final byte in plaintext.codeUnits) {
      i = (i + 1) % 256;
      j = (j + state[i]) % 256;
      final temp = state[i];
      state[i] = state[j];
      state[j] = temp;
      final t = (state[i] + state[j]) % 256;
      output.add(byte ^ state[t]);
    }
    return String.fromCharCodes(output);
  }

  String _resultEncrypt(String value, String tableKey) {
    const tables = {
      's0': 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',
      's1': 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
      's2': 'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
      's3': 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',
      's4': 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe',
    };
    final table = tables[tableKey]!.codeUnits;
    const masks = [16515072, 258048, 4032, 63];
    const shifts = [18, 12, 6, 0];

    int getLongInt(int round) {
      final offset = round * 3;
      final units = value.codeUnits;
      final first = offset < units.length ? units[offset] : 0;
      final second = offset + 1 < units.length ? units[offset + 1] : 0;
      final third = offset + 2 < units.length ? units[offset + 2] : 0;
      return (first << 16) | (second << 8) | third;
    }

    final output = StringBuffer();
    final totalChars = ((value.length / 3) * 4).ceil();
    var round = 0;
    var longInt = getLongInt(round);
    for (var index = 0; index < totalChars; index += 1) {
      if (index ~/ 4 != round) {
        round += 1;
        longInt = getLongInt(round);
      }
      final key = index % 4;
      output.writeCharCode(
        table[(longInt & masks[key]) >> shifts[key]],
      );
    }
    return output.toString();
  }

  List<int> _sm3Sum(List<int> data) {
    final sm3 = _Sm3();
    return sm3.sumBytes(data);
  }

  String _generateMsToken(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }
}

class _Sm3 {
  final List<int> _reg = List<int>.filled(8, 0);
  final List<int> _chunk = <int>[];
  int _size = 0;

  _Sm3() {
    reset();
  }

  void reset() {
    _reg
      ..[0] = 1937774191
      ..[1] = 1226093241
      ..[2] = 388252375
      ..[3] = 3666478592
      ..[4] = 2842636476
      ..[5] = 372324522
      ..[6] = 3817729613
      ..[7] = 2969243214;
    _chunk.clear();
    _size = 0;
  }

  List<int> sumBytes(List<int> data) {
    reset();
    write(data);
    _fill();

    final blocks = List<int>.from(_chunk);
    for (var offset = 0; offset < blocks.length; offset += 64) {
      _compress(blocks.sublist(offset, offset + 64));
    }

    final out = <int>[];
    for (final value in _reg) {
      out.addAll([
        (value >> 24) & 255,
        (value >> 16) & 255,
        (value >> 8) & 255,
        value & 255,
      ]);
    }
    reset();
    return out;
  }

  void write(List<int> data) {
    _size += data.length;
    var offset = 0;
    while (offset < data.length) {
      final needed = 64 - _chunk.length;
      final take = min(needed, data.length - offset);
      _chunk.addAll(data.sublist(offset, offset + take));
      offset += take;
      if (_chunk.length == 64) {
        _compress(List<int>.from(_chunk));
        _chunk.clear();
      }
    }
  }

  void _fill() {
    final bitLength = _size * 8;
    _chunk.add(0x80);
    while ((_chunk.length % 64) != 56) {
      _chunk.add(0);
    }

    final high = bitLength ~/ 0x100000000;
    final low = bitLength & 0xffffffff;
    _chunk.addAll([
      (high >> 24) & 255,
      (high >> 16) & 255,
      (high >> 8) & 255,
      high & 255,
      (low >> 24) & 255,
      (low >> 16) & 255,
      (low >> 8) & 255,
      low & 255,
    ]);
  }

  void _compress(List<int> block) {
    final w = List<int>.filled(132, 0);
    for (var index = 0; index < 16; index += 1) {
      final offset = index * 4;
      w[index] = ((block[offset] << 24) |
              (block[offset + 1] << 16) |
              (block[offset + 2] << 8) |
              block[offset + 3]) &
          0xffffffff;
    }

    for (var index = 16; index < 68; index += 1) {
      final a = w[index - 16] ^ w[index - 9] ^ _leftRotate(w[index - 3], 15);
      final p1 = a ^ _leftRotate(a, 15) ^ _leftRotate(a, 23);
      w[index] =
          (p1 ^ _leftRotate(w[index - 13], 7) ^ w[index - 6]) & 0xffffffff;
    }
    for (var index = 0; index < 64; index += 1) {
      w[index + 68] = (w[index] ^ w[index + 4]) & 0xffffffff;
    }

    var a = _reg[0];
    var b = _reg[1];
    var c = _reg[2];
    var d = _reg[3];
    var e = _reg[4];
    var f = _reg[5];
    var g = _reg[6];
    var h = _reg[7];

    for (var index = 0; index < 64; index += 1) {
      final ss1 = _leftRotate(
        (_leftRotate(a, 12) + e + _leftRotate(_t(index), index)) & 0xffffffff,
        7,
      );
      final ss2 = ss1 ^ _leftRotate(a, 12);
      final tt1 = (_ff(index, a, b, c) + d + ss2 + w[index + 68]) & 0xffffffff;
      final tt2 = (_gg(index, e, f, g) + h + ss1 + w[index]) & 0xffffffff;

      d = c;
      c = _leftRotate(b, 9);
      b = a;
      a = tt1;
      h = g;
      g = _leftRotate(f, 19);
      f = e;
      e = (tt2 ^ _leftRotate(tt2, 9) ^ _leftRotate(tt2, 17)) & 0xffffffff;
    }

    _reg[0] = (_reg[0] ^ a) & 0xffffffff;
    _reg[1] = (_reg[1] ^ b) & 0xffffffff;
    _reg[2] = (_reg[2] ^ c) & 0xffffffff;
    _reg[3] = (_reg[3] ^ d) & 0xffffffff;
    _reg[4] = (_reg[4] ^ e) & 0xffffffff;
    _reg[5] = (_reg[5] ^ f) & 0xffffffff;
    _reg[6] = (_reg[6] ^ g) & 0xffffffff;
    _reg[7] = (_reg[7] ^ h) & 0xffffffff;
  }

  int _t(int index) {
    return index < 16 ? 0x79cc4519 : 0x7a879d8a;
  }

  int _ff(int index, int x, int y, int z) {
    if (index < 16) {
      return x ^ y ^ z;
    }
    return (x & y) | (x & z) | (y & z);
  }

  int _gg(int index, int x, int y, int z) {
    if (index < 16) {
      return x ^ y ^ z;
    }
    return (x & y) | (~x & z);
  }

  int _leftRotate(int value, int shift) {
    final normalized = shift % 32;
    if (normalized == 0) {
      return value & 0xffffffff;
    }
    return ((value << normalized) |
            ((value & 0xffffffff) >> (32 - normalized))) &
        0xffffffff;
  }
}
