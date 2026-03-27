import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:web_socket_channel/io.dart';

import '../../../../core/models/vod_models.dart';
import 'douyin_models.dart';
import 'proto/douyin.pb.dart';

class DouyinDanmakuClient {
  const DouyinDanmakuClient();

  Stream<LiveMessage> connect(DouyinDanmakuArgs args) {
    final controller = StreamController<LiveMessage>();
    IOWebSocketChannel? channel;
    Timer? heartbeatTimer;

    Future<void> close() async {
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      try {
        await channel?.sink.close();
      } catch (_) {}
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    controller.onListen = () {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse(
        'wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/',
      ).replace(
        queryParameters: {
          'app_name': 'douyin_web',
          'version_code': '180800',
          'webcast_sdk_version': '1.3.0',
          'update_version_code': '1.3.0',
          'compress': 'gzip',
          'cursor': 'h-1_t-${timestamp}_r-1_d-1_u-1',
          'host': 'https://live.douyin.com',
          'aid': '6383',
          'live_id': '1',
          'did_rule': '3',
          'debug': 'false',
          'maxCacheMessageNumber': '20',
          'endpoint': 'live_pc',
          'support_wrds': '1',
          'im_path': '/webcast/im/fetch/',
          'user_unique_id': args.userId,
          'device_platform': 'web',
          'cookie_enabled': 'true',
          'screen_width': '1920',
          'screen_height': '1080',
          'browser_language': 'zh-CN',
          'browser_platform': 'Win32',
          'browser_name': 'Mozilla',
          'browser_version':
              '5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400'
                  .replaceFirst('Mozilla/', ''),
          'browser_online': 'true',
          'tz_name': 'Asia/Shanghai',
          'identity': 'audience',
          'room_id': args.roomId,
          'heartbeatDuration': '0',
          'signature': args.signature,
        },
      );

      channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 '
                  'Core/1.116.567.400 QQBrowser/19.7.6764.400',
          'cookie': args.cookie,
          'origin': 'https://live.douyin.com',
        },
      );

      channel!.stream.listen(
        (event) {
          final bytes = switch (event) {
            final Uint8List value => value,
            final List<int> value => Uint8List.fromList(value),
            _ => Uint8List(0),
          };
          _decodePacket(bytes, controller, channel);
        },
        onDone: close,
        onError: (_) => close(),
        cancelOnError: true,
      );

      channel!.sink.add(heartbeatFrame());
      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => channel?.sink.add(heartbeatFrame()),
      );
    };

    controller.onCancel = close;
    return controller.stream;
  }

  List<int> heartbeatFrame() {
    final frame = PushFrame()..payloadType = 'hb';
    return frame.writeToBuffer();
  }

  List<int> ackFrame({
    required $fixnum.Int64 logId,
    required String internalExt,
  }) {
    final frame = PushFrame()
      ..payloadType = 'ack'
      ..logId = logId
      ..payload = utf8.encode(internalExt);
    return frame.writeToBuffer();
  }

  LiveMessageColor parseColor(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return LiveMessageColor(r: 255, g: 255, b: 255);
    }

    var normalized = text;
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length == 8) {
      normalized = normalized.substring(2);
    }

    final parsed = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
    return LiveMessageColor(
      r: (parsed >> 16) & 0xFF,
      g: (parsed >> 8) & 0xFF,
      b: parsed & 0xFF,
    );
  }

  void _decodePacket(
    Uint8List bytes,
    StreamController<LiveMessage> output,
    IOWebSocketChannel? channel,
  ) {
    if (bytes.isEmpty) return;

    final frame = PushFrame.fromBuffer(bytes);
    final payload = _decodePayload(frame.payload);
    if (payload == null) return;

    if (payload.needAck) {
      channel?.sink.add(
        ackFrame(logId: frame.logId, internalExt: payload.internalExt),
      );
    }

    for (final message in payload.messagesList) {
      switch (message.method) {
        case 'WebcastChatMessage':
          final chat = ChatMessage.fromBuffer(message.payload);
          final content = chat.content.trim();
          if (content.isEmpty) continue;
          output.add(
            LiveMessage(
              type: 'chat',
              userName: chat.user.nickName,
              message: content,
              color: parseColor(chat.fullScreenTextColor),
            ),
          );
        case 'WebcastRoomUserSeqMessage':
          final online = RoomUserSeqMessage.fromBuffer(message.payload);
          output.add(
            LiveMessage(
              type: 'online',
              userName: '',
              message: online.totalUserStr.isNotEmpty
                  ? online.totalUserStr
                  : online.totalUser.toString(),
              color: LiveMessageColor(r: 255, g: 255, b: 255),
            ),
          );
      }
    }
  }

  Response? _decodePayload(List<int> payload) {
    try {
      return Response.fromBuffer(gzip.decode(payload));
    } catch (_) {
      try {
        return Response.fromBuffer(payload);
      } catch (_) {
        return null;
      }
    }
  }
}
