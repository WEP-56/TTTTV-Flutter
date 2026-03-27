import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../../../core/models/vod_models.dart';
import 'huya_models.dart';

class HuyaParser {
  const HuyaParser();

  static const roomUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
  static const playUserAgent =
      'HYSDK(Windows,30000002)_APP(pc_exe&7070000&official)'
      '_SDK(trans&2.33.0.5678)';

  LivePlayUrl buildPlayUrl(
    List<HuyaStreamLine> lines,
    String qualityId,
  ) {
    final bitRate = int.tryParse(qualityId) ?? 0;
    final urls = lines
        .map((line) => buildLineUrl(line, bitRate: bitRate))
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();

    urls.sort((left, right) {
      final leftIsFlv = left.contains('.flv?');
      final rightIsFlv = right.contains('.flv?');
      if (leftIsFlv == rightIsFlv) return left.compareTo(right);
      return leftIsFlv ? -1 : 1;
    });

    return LivePlayUrl(
      urls: urls,
      headers: const {
        'user-agent': playUserAgent,
        'referer': 'https://www.huya.com/',
        'origin': 'https://www.huya.com',
      },
      urlType: 'auto',
    );
  }

  String buildLineUrl(
    HuyaStreamLine line, {
    required int bitRate,
  }) {
    final antiCode = buildAntiCode(
      line.streamName,
      line.presenterUid,
      line.antiCode,
    );
    final buffer = StringBuffer(
      '${_normalizeBaseUrl(line.baseUrl)}/${line.streamName}.${line.extension}?',
    )..write(antiCode);

    if (line.type == HuyaLineType.flv) {
      buffer.write('&codec=264');
    }
    if (bitRate > 0) {
      buffer.write('&ratio=$bitRate');
    }
    return buffer.toString();
  }

  String buildAntiCode(
    String streamName,
    int presenterUid,
    String antiCode,
  ) {
    final sanitized = antiCode
        .trim()
        .replaceAll('&amp;', '&')
        .replaceFirst(RegExp(r'^[?&]+'), '');
    final mapAnti = Uri(query: sanitized).queryParametersAll;
    if (!mapAnti.containsKey('fm')) {
      return sanitized;
    }

    final ctype = mapAnti['ctype']?.first ?? 'huya_pc_exe';
    final platformId = int.tryParse(mapAnti['t']?.first ?? '0') ?? 0;
    final isWap = platformId == 103;
    final calcStartTime = DateTime.now().millisecondsSinceEpoch;
    final seqId = presenterUid + calcStartTime;
    final secretHash =
        md5.convert(utf8.encode('$seqId|$ctype|$platformId')).toString();

    final calcUid = isWap ? presenterUid : _rotl64(presenterUid);
    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    final wsTime = mapAnti['wsTime']?.first ?? '';
    if (secretPrefix.isEmpty || wsTime.isEmpty) {
      return sanitized;
    }

    final secret = md5
        .convert(
          utf8.encode(
            '${secretPrefix}_${calcUid}_${streamName}_${secretHash}_$wsTime',
          ),
        )
        .toString();

    final random = math.Random();
    final ct =
        ((int.parse(wsTime, radix: 16) + random.nextDouble()) * 1000).toInt();
    final uuid =
        ((((ct % 1e10) + random.nextDouble()) * 1e3) % 0xffffffff).toInt();

    final params = <String, String>{
      'wsSecret': secret,
      'wsTime': wsTime,
      'seqid': seqId.toString(),
      'ctype': ctype,
      'ver': '1',
      'fs': mapAnti['fs']?.first ?? '',
      'fm': Uri.encodeComponent(mapAnti['fm']!.first),
      't': platformId.toString(),
    };

    if (isWap) {
      params['uid'] = presenterUid.toString();
      params['uuid'] = uuid.toString();
    } else {
      params['u'] = calcUid.toString();
    }

    return params.entries
        .map(
          (entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  String normalizeImageUrl(String value) {
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    return value;
  }

  String _normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
  }

  int _rotl64(int value) {
    final low = value & 0xFFFFFFFF;
    final rotatedLow = ((low << 8) | (low >> 24)) & 0xFFFFFFFF;
    final high = value & ~0xFFFFFFFF;
    return high | rotatedLow;
  }
}
