import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../../../../core/models/vod_models.dart';

class DouyuDanmakuClient {
  Stream<LiveMessage> connect(String roomId) {
    final controller = StreamController<LiveMessage>();
    IOWebSocketChannel? channel;
    Timer? heartbeatTimer;

    Future<void> close() async {
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      try {
        await channel?.sink.close();
      } catch (_) {}
      await controller.close();
    }

    controller.onListen = () {
      channel = IOWebSocketChannel.connect(
        Uri.parse('wss://danmuproxy.douyu.com:8506'),
      );

      channel!.stream.listen(
        (event) {
          final data = event is List<int> ? event : <int>[];
          _decodeMessage(data, controller);
        },
        onDone: close,
        onError: (_) => close(),
        cancelOnError: true,
      );

      channel!.sink.add(_serializeDouyu('type@=loginreq/roomid@=$roomId/'));
      channel!.sink.add(
        _serializeDouyu('type@=joingroup/rid@=$roomId/gid@=-9999/'),
      );

      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => channel?.sink.add(_serializeDouyu('type@=mrkl/')),
      );
    };

    controller.onCancel = close;
    return controller.stream;
  }

  List<int> _serializeDouyu(String body) {
    const clientSendToServer = 689;
    const encrypted = 0;
    const reserved = 0;

    final payload = utf8.encode(body);
    final totalLength = 4 + 4 + body.length + 1;
    final writer = BytesBuilder();

    writer.add(_intBytes(totalLength, 4));
    writer.add(_intBytes(totalLength, 4));
    writer.add(_intBytes(clientSendToServer, 2));
    writer.add(_intBytes(encrypted, 1));
    writer.add(_intBytes(reserved, 1));
    writer.add(payload);
    writer.add(_intBytes(0, 1));
    return writer.toBytes();
  }

  List<int> _intBytes(int value, int byteLength) {
    final data = ByteData(byteLength);
    switch (byteLength) {
      case 1:
        data.setUint8(0, value);
      case 2:
        data.setInt16(0, value, Endian.little);
      case 4:
        data.setInt32(0, value, Endian.little);
      default:
        throw ArgumentError('Unsupported byte length: $byteLength');
    }
    return data.buffer.asUint8List();
  }

  void _decodeMessage(List<int> data, StreamController<LiveMessage> output) {
    final decoded = _deserializeDouyu(data);
    if (decoded == null) return;

    final json = _sttToObject(decoded);
    final type = json['type']?.toString() ?? '';
    if (type != 'chatmsg') return;
    if (json['dms'] == null) return;

    output.add(
      LiveMessage(
        type: 'chat',
        userName: json['nn']?.toString() ?? '',
        message: json['txt']?.toString() ?? '',
        color: _getColor(int.tryParse(json['col']?.toString() ?? '') ?? 0),
      ),
    );
  }

  String? _deserializeDouyu(List<int> buffer) {
    try {
      final reader = ByteData.sublistView(Uint8List.fromList(buffer));
      final fullLength = reader.getInt32(0, Endian.little);
      final bodyLength = fullLength - 9;
      final body = buffer.sublist(12, 12 + bodyLength);
      return utf8.decode(body);
    } catch (_) {
      return null;
    }
  }

  dynamic _sttToObject(String value) {
    if (value.contains('//')) {
      return value
          .split('//')
          .where((item) => item.isNotEmpty)
          .map(_sttToObject)
          .toList();
    }
    if (value.contains('@=')) {
      final map = <String, dynamic>{};
      for (final field in value.split('/')) {
        if (field.isEmpty) continue;
        final tokens = field.split('@=');
        if (tokens.length < 2) continue;
        map[tokens[0]] = _sttToObject(_unescapeSlashAt(tokens[1]));
      }
      return map;
    }
    if (value.contains('@A=')) {
      return _sttToObject(_unescapeSlashAt(value));
    }
    return _unescapeSlashAt(value);
  }

  String _unescapeSlashAt(String value) {
    return value.replaceAll('@S', '/').replaceAll('@A', '@');
  }

  LiveMessageColor _getColor(int type) {
    switch (type) {
      case 1:
        return LiveMessageColor(r: 255, g: 0, b: 0);
      case 2:
        return LiveMessageColor(r: 30, g: 135, b: 240);
      case 3:
        return LiveMessageColor(r: 122, g: 200, b: 75);
      case 4:
        return LiveMessageColor(r: 255, g: 127, b: 0);
      case 5:
        return LiveMessageColor(r: 155, g: 57, b: 244);
      case 6:
        return LiveMessageColor(r: 255, g: 105, b: 180);
      default:
        return LiveMessageColor(r: 255, g: 255, b: 255);
    }
  }
}
