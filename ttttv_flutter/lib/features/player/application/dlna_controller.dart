import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/platform/android_media.dart';
import '../../play/data/local_media_proxy.dart';

class DlnaDevice {
  const DlnaDevice(
      this.name, this.controlUrl, this.serviceType, this.localAddress);
  final String name;
  final Uri controlUrl;
  final String serviceType;
  final String localAddress;
}

class DlnaPosition {
  const DlnaPosition(this.position, this.duration);
  final Duration position;
  final Duration duration;
}

/// SSDP discovery and the AVTransport service shared by Android & Windows.
class DlnaController {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 6),
    sendTimeout: const Duration(seconds: 6),
    responseType: ResponseType.plain,
  ));
  final List<RawDatagramSocket> _sockets = [];
  LocalMediaProxy? _proxy;
  bool _disposed = false;
  Future<List<DlnaDevice>>? _discovery;
  final Completer<void> _closed = Completer<void>();

  Future<List<DlnaDevice>> discover() {
    if (_disposed) return Future.value(const []);
    return _discovery ??= _discover().whenComplete(() => _discovery = null);
  }

  Future<List<DlnaDevice>> _discover() async {
    final found = <String, DlnaDevice>{};
    final locations = <String>{};
    final pending = <Future<void>>[];
    try {
      await AndroidMedia.multicast(true);
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final network in interfaces) {
        for (final address in network.addresses) {
          if (_disposed || address.isLoopback) continue;
          try {
            final socket = await RawDatagramSocket.bind(address, 0);
            if (_disposed) {
              socket.close();
              continue;
            }
            _sockets.add(socket);
            socket.listen((event) {
              if (event != RawSocketEvent.read || _disposed) return;
              Datagram? packet;
              while ((packet = socket.receive()) != null) {
                final reply = utf8.decode(packet!.data, allowMalformed: true);
                final match = RegExp(r'^location:\s*(.+)$',
                        caseSensitive: false, multiLine: true)
                    .firstMatch(reply);
                final location = match?.group(1)?.trim();
                if (location == null ||
                    locations.length >= 32 ||
                    !locations.add(location)) continue;
                pending.add(_describe(location, address.address).then((device) {
                  if (device != null)
                    found[device.controlUrl.toString()] = device;
                }).catchError((Object _) {}));
              }
            }, onError: (Object _) {});
            for (final target in [
              'urn:schemas-upnp-org:device:MediaRenderer:1',
              'urn:schemas-upnp-org:service:AVTransport:1'
            ]) {
              final request =
                  'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
                  'MAN: "ssdp:discover"\r\nMX: 3\r\nST: $target\r\n\r\n';
              socket.send(utf8.encode(request),
                  InternetAddress('239.255.255.250'), 1900);
            }
          } on SocketException catch (_) {/* Try the next network interface. */}
        }
      }
      await Future.any(
          [Future<void>.delayed(const Duration(seconds: 5)), _closed.future]);
      for (final socket in _sockets) {
        socket.close();
      }
      _sockets.clear();
      await Future.wait(pending);
      return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    } finally {
      for (final socket in _sockets) {
        socket.close();
      }
      _sockets.clear();
      await AndroidMedia.multicast(false);
    }
  }

  Future<DlnaDevice?> _describe(String location, String localAddress) async {
    final uri = Uri.tryParse(location);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https'))
      return null;
    final response = await _dio.get<String>(uri.toString());
    if (_disposed) return null;
    final document = XmlDocument.parse(response.data ?? '');
    final base = _value(document, 'URLBase');
    final baseUri = base.isEmpty ? uri : uri.resolve(base);
    for (final service in document.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'service')) {
      final type = _value(service, 'serviceType');
      final control = _value(service, 'controlURL');
      if (type.contains(':service:AVTransport:') && control.isNotEmpty) {
        return DlnaDevice(_value(document, 'friendlyName'),
            baseUri.resolve(control), type, localAddress);
      }
    }
    return null;
  }

  Future<void> cast(
      DlnaDevice device, PlayEpisode episode, String title) async {
    await _proxy?.close();
    final proxy = LocalMediaProxy.forCasting(device.localAddress);
    _proxy = proxy;
    // HLS URLs used by the local player point at loopback. Recreate the upstream
    // headers and publish rewritten playlists, keys and segments on the LAN.
    final local = Uri.tryParse(episode.effectiveUrl);
    var headers = episode.httpHeaders ?? const <String, String>{};
    if (local?.host == '127.0.0.1' &&
        local?.queryParameters['headers'] != null) {
      final decoded = jsonDecode(utf8.decode(base64Url
          .decode(base64Url.normalize(local!.queryParameters['headers']!))));
      headers = Map<String, String>.from(decoded as Map);
    }
    final url = await proxy.createCastUrl(episode.url, headers);
    if (_disposed) {
      await proxy.close();
      return;
    }
    final mime = episode.url.toLowerCase().contains('m3u8')
        ? 'application/vnd.apple.mpegurl'
        : 'video/mp4';
    final metadata =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1"><dc:title>${_escape(title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:*">${_escape(url)}</res></item></DIDL-Lite>';
    try {
      await command(device, 'SetAVTransportURI',
          {'CurrentURI': url, 'CurrentURIMetaData': metadata});
      await command(device, 'Play', {'Speed': '1'});
    } catch (_) {
      try {
        await command(device, 'Stop');
      } catch (_) {}
      await releaseMedia();
      rethrow;
    }
  }

  Future<XmlDocument> command(DlnaDevice device, String action,
      [Map<String, String> arguments = const {}]) async {
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="${device.serviceType}"><InstanceID>0</InstanceID>'
        '${arguments.entries.map((e) => '<${e.key}>${_escape(e.value)}</${e.key}>').join()}'
        '</u:$action></s:Body></s:Envelope>';
    final response = await _dio.post<String>(device.controlUrl.toString(),
        data: body,
        options: Options(headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPACTION': '"${device.serviceType}#$action"'
        }, validateStatus: (_) => true));
    final xml = XmlDocument.parse(response.data ?? '');
    final error = _value(xml, 'errorDescription');
    if ((response.statusCode ?? 500) >= 400 ||
        _value(xml, 'errorCode').isNotEmpty) {
      throw StateError(error.isEmpty ? '设备不支持此操作 ($action)' : error);
    }
    return xml;
  }

  Future<void> seek(DlnaDevice device, Duration position) async {
    final time = '${position.inHours.toString().padLeft(2, '0')}:'
        '${position.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${position.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    await command(device, 'Seek', {'Unit': 'REL_TIME', 'Target': time});
  }

  Future<DlnaPosition> position(DlnaDevice device) async {
    final xml = await command(device, 'GetPositionInfo');
    if (!_value(xml, 'RelTime').contains(':')) {
      throw StateError('电视未提供播放进度');
    }
    return DlnaPosition(_duration(_value(xml, 'RelTime')),
        _duration(_value(xml, 'TrackDuration')));
  }

  Future<void> dispose() async {
    _disposed = true;
    if (!_closed.isCompleted) _closed.complete();
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    _dio.close(force: true);
    await releaseMedia();
  }

  Future<void> releaseMedia() async {
    final proxy = _proxy;
    _proxy = null;
    await proxy?.close();
  }

  static String _value(XmlNode node, String name) =>
      node.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText
          .trim() ??
      '';
  static String _escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);
  static Duration _duration(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(
        seconds: (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (double.tryParse(parts[2]) ?? 0).round());
  }
}
