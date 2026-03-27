import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:web_socket_channel/io.dart';

import '../../../../core/models/vod_models.dart';
import 'bilibili_models.dart';

class BilibiliDanmakuClient {
  Stream<LiveMessage> connect(BilibiliDanmakuArgs args) {
    final controller = StreamController<LiveMessage>();
    IOWebSocketChannel? channel;
    Timer? heartbeatTimer;

    Future<void> close([Object? error]) async {
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      try {
        await channel?.sink.close();
      } catch (_) {}
      if (!controller.isClosed) {
        if (error != null) {
          await controller.close();
        } else {
          await controller.close();
        }
      }
    }

    controller.onListen = () {
      channel = IOWebSocketChannel.connect(
        Uri.parse('wss://${args.serverHost}/sub'),
        headers: {
          if (args.cookie.isNotEmpty) 'cookie': args.cookie,
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
          'referer': 'https://live.bilibili.com/',
        },
      );

      channel!.stream.listen(
        (event) {
          final bytes = event is List<int> ? event : <int>[];
          _decodePackets(bytes, controller);
        },
        onDone: () => close(),
        onError: (_) => close(),
        cancelOnError: true,
      );

      channel!.sink.add(_encodeData(
          jsonEncode({
            'uid': args.uid,
            'roomid': args.roomId,
            'protover': 3,
            'buvid': args.buvid,
            'platform': 'web',
            'type': 2,
            'key': args.token,
          }),
          7));

      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => channel?.sink.add(_encodeData('', 2)),
      );
    };

    controller.onCancel = () => close();
    return controller.stream;
  }

  List<int> _encodeData(String message, int action) {
    final data = utf8.encode(message);
    final length = data.length + 16;
    final buffer = BytesBuilder();

    buffer.add(_intBytes(length, 4));
    buffer.add(_intBytes(16, 2));
    buffer.add(_intBytes(0, 2));
    buffer.add(_intBytes(action, 4));
    buffer.add(_intBytes(1, 4));
    buffer.add(data);

    return buffer.toBytes();
  }

  List<int> _intBytes(int value, int byteLength) {
    final data = ByteData(byteLength);
    switch (byteLength) {
      case 2:
        data.setInt16(0, value, Endian.big);
      case 4:
        data.setInt32(0, value, Endian.big);
      default:
        throw ArgumentError('Unsupported byte length: $byteLength');
    }
    return data.buffer.asUint8List();
  }

  void _decodePackets(List<int> bytes, StreamController<LiveMessage> output) {
    var offset = 0;
    while (offset + 16 <= bytes.length) {
      final packetLength = _readInt(bytes, offset, 4);
      if (packetLength <= 0 || offset + packetLength > bytes.length) {
        break;
      }

      final headerLength = _readInt(bytes, offset + 4, 2);
      final protocolVersion = _readInt(bytes, offset + 6, 2);
      final operation = _readInt(bytes, offset + 8, 4);
      final body = bytes.sublist(offset + headerLength, offset + packetLength);

      if (operation == 5) {
        if (protocolVersion == 2) {
          _decodePackets(zlib.decode(body), output);
        } else if (protocolVersion == 3) {
          _decodePackets(brotli.decode(body), output);
        } else {
          _parseMessageBody(body, output);
        }
      }

      offset += packetLength;
    }
  }

  void _parseMessageBody(List<int> body, StreamController<LiveMessage> output) {
    final text = utf8.decode(body, allowMalformed: true);
    final chunks = text.split(RegExp(r'[\x00-\x1f]+', multiLine: true));
    for (final chunk in chunks) {
      if (chunk.length < 2 || !chunk.startsWith('{')) continue;
      try {
        final payload = jsonDecode(chunk) as Map<String, dynamic>;
        final cmd = payload['cmd']?.toString() ?? '';
        if (cmd.contains('DANMU_MSG')) {
          final info = payload['info'] as List<dynamic>? ?? const [];
          if (info.length < 3) continue;
          final message = info[1]?.toString() ?? '';
          final user =
              (info[2] as List<dynamic>? ?? const []).elementAtOrNull(1);
          final colorCode = ((info[0] as List<dynamic>? ?? const [])
                      .elementAtOrNull(3) as num?)
                  ?.toInt() ??
              0xffffff;

          if (message.trim().isEmpty) continue;
          output.add(
            LiveMessage(
              type: 'chat',
              userName: user?.toString() ?? '',
              message: message,
              color: _intToColor(colorCode),
            ),
          );
        }
      } catch (_) {
        // Ignore malformed chunks.
      }
    }
  }

  int _readInt(List<int> data, int offset, int length) {
    final bytes = Uint8List.fromList(data.sublist(offset, offset + length));
    final view = ByteData.view(bytes.buffer);
    switch (length) {
      case 2:
        return view.getInt16(0, Endian.big);
      case 4:
        return view.getInt32(0, Endian.big);
      default:
        throw ArgumentError('Unsupported int length: $length');
    }
  }

  LiveMessageColor _intToColor(int color) {
    final safe = color & 0xFFFFFF;
    return LiveMessageColor(
      r: (safe >> 16) & 0xFF,
      g: (safe >> 8) & 0xFF,
      b: safe & 0xFF,
    );
  }
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }
}
