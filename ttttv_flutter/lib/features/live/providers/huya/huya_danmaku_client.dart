import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../../../../core/models/vod_models.dart';
import 'huya_models.dart';

class HuyaDanmakuClient {
  static final Uint8List _heartbeatData =
      Uint8List.fromList(base64.decode('ABQdAAwsNgBM'));

  Stream<LiveMessage> connect(HuyaDanmakuArgs args) {
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
      channel = IOWebSocketChannel.connect(
        Uri.parse('wss://cdnws.api.huya.com'),
      );

      channel!.stream.listen(
        (event) {
          final bytes = switch (event) {
            final Uint8List value => value,
            final List<int> value => Uint8List.fromList(value),
            _ => Uint8List(0),
          };
          _decodePacket(bytes, controller);
        },
        onDone: close,
        onError: (_) => close(),
        cancelOnError: true,
      );

      channel!.sink.add(_buildJoinPayload(args));
      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => channel?.sink.add(_heartbeatData),
      );
    };

    controller.onCancel = close;
    return controller.stream;
  }

  Uint8List _buildJoinPayload(HuyaDanmakuArgs args) {
    final inner = _TarsWriter()
      ..writeInt(args.ayyuid, 0)
      ..writeBool(true, 1)
      ..writeString('', 2)
      ..writeString('', 3)
      ..writeInt(args.topSid, 4)
      ..writeInt(args.subSid, 5)
      ..writeInt(0, 6)
      ..writeInt(0, 7);

    final outer = _TarsWriter()
      ..writeInt(1, 0)
      ..writeBytes(inner.toBytes(), 1);

    return outer.toBytes();
  }

  void _decodePacket(
    Uint8List bytes,
    StreamController<LiveMessage> output,
  ) {
    if (bytes.isEmpty) return;

    final outer = _TarsReader(bytes);
    final type = outer.readInt(0);
    if (type != 7) return;

    final payload = outer.readBytes(1);
    if (payload.isEmpty) return;

    final push = _HuyaPushMessage.fromBytes(payload);
    if (push == null) return;

    switch (push.uri) {
      case 1400:
        final chat = _HuyaChatMessage.fromBytes(push.message);
        if (chat == null || chat.content.trim().isEmpty) return;
        output.add(
          LiveMessage(
            type: 'chat',
            userName: chat.userName,
            message: chat.content,
            color: _intToColor(chat.fontColor),
          ),
        );
      case 8006:
        final online = _TarsReader(push.message).readInt(0);
        output.add(
          LiveMessage(
            type: 'online',
            userName: '',
            message: online.toString(),
            color: LiveMessageColor(r: 255, g: 255, b: 255),
          ),
        );
    }
  }

  LiveMessageColor _intToColor(int color) {
    final safe = color <= 0 ? 0xFFFFFF : color & 0xFFFFFF;
    return LiveMessageColor(
      r: (safe >> 16) & 0xFF,
      g: (safe >> 8) & 0xFF,
      b: safe & 0xFF,
    );
  }
}

class _HuyaPushMessage {
  const _HuyaPushMessage({
    required this.uri,
    required this.message,
  });

  final int uri;
  final Uint8List message;

  static _HuyaPushMessage? fromBytes(Uint8List bytes) {
    final reader = _TarsReader(bytes);
    return _HuyaPushMessage(
      uri: reader.readInt(1),
      message: reader.readBytes(2),
    );
  }
}

class _HuyaChatMessage {
  const _HuyaChatMessage({
    required this.userName,
    required this.content,
    required this.fontColor,
  });

  final String userName;
  final String content;
  final int fontColor;

  static _HuyaChatMessage? fromBytes(Uint8List bytes) {
    final reader = _TarsReader(bytes);
    final user = reader.readStruct(0, _HuyaUserInfo.fromReader);
    final content = reader.readString(3);
    final bullet = reader.readStruct(6, _HuyaBulletFormat.fromReader);
    return _HuyaChatMessage(
      userName: user?.nickName ?? '',
      content: content,
      fontColor: bullet?.fontColor ?? 0,
    );
  }
}

class _HuyaUserInfo {
  const _HuyaUserInfo({
    required this.nickName,
  });

  final String nickName;

  static _HuyaUserInfo fromReader(_TarsReader reader) {
    return _HuyaUserInfo(
      nickName: reader.readString(2),
    );
  }
}

class _HuyaBulletFormat {
  const _HuyaBulletFormat({
    required this.fontColor,
  });

  final int fontColor;

  static _HuyaBulletFormat fromReader(_TarsReader reader) {
    return _HuyaBulletFormat(
      fontColor: reader.readInt(0),
    );
  }
}

class _TarsWriter {
  final BytesBuilder _buffer = BytesBuilder();

  void writeBool(bool value, int tag) {
    writeInt(value ? 1 : 0, tag);
  }

  void writeInt(int value, int tag) {
    if (value == 0) {
      _writeHead(tag, 12);
      return;
    }
    if (value >= -128 && value <= 127) {
      _writeHead(tag, 0);
      _buffer.addByte(value & 0xFF);
      return;
    }
    if (value >= -32768 && value <= 32767) {
      _writeHead(tag, 1);
      _writeInt16(value);
      return;
    }
    if (value >= -2147483648 && value <= 2147483647) {
      _writeHead(tag, 2);
      _writeInt32(value);
      return;
    }
    _writeHead(tag, 3);
    _writeInt64(value);
  }

  void writeString(String value, int tag) {
    final bytes = utf8.encode(value);
    if (bytes.length < 256) {
      _writeHead(tag, 6);
      _buffer.addByte(bytes.length);
    } else {
      _writeHead(tag, 7);
      _writeInt32(bytes.length);
    }
    _buffer.add(bytes);
  }

  void writeBytes(Uint8List value, int tag) {
    _writeHead(tag, 13);
    _writeHead(0, 0);
    writeInt(value.length, 0);
    _buffer.add(value);
  }

  Uint8List toBytes() {
    return _buffer.toBytes();
  }

  void _writeHead(int tag, int type) {
    if (tag < 15) {
      _buffer.addByte((tag << 4) | type);
    } else {
      _buffer.addByte((15 << 4) | type);
      _buffer.addByte(tag);
    }
  }

  void _writeInt16(int value) {
    final data = ByteData(2)..setInt16(0, value, Endian.big);
    _buffer.add(data.buffer.asUint8List());
  }

  void _writeInt32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    _buffer.add(data.buffer.asUint8List());
  }

  void _writeInt64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    _buffer.add(data.buffer.asUint8List());
  }
}

class _TarsReader {
  _TarsReader(Uint8List data)
      : _data = data,
        _view = ByteData.sublistView(data);

  final Uint8List _data;
  final ByteData _view;
  int _offset = 0;

  int readInt(int tag) {
    final head = _seekToTag(tag);
    if (head == null) return 0;
    final value = _readNumeric(head.type, _offset);
    _offset = value.nextOffset;
    return value.value;
  }

  String readString(int tag) {
    final head = _seekToTag(tag);
    if (head == null) return '';

    late final int length;
    switch (head.type) {
      case 6:
        length = _data[_offset];
        _offset += 1;
      case 7:
        length = _view.getInt32(_offset, Endian.big);
        _offset += 4;
      default:
        return '';
    }

    final end = _offset + length;
    final value =
        utf8.decode(_data.sublist(_offset, end), allowMalformed: true);
    _offset = end;
    return value;
  }

  Uint8List readBytes(int tag) {
    final head = _seekToTag(tag);
    if (head == null || head.type != 13) {
      return Uint8List(0);
    }

    final subtype = _readHead(_offset);
    if (subtype.type != 0) {
      return Uint8List(0);
    }

    _offset = subtype.dataOffset;
    final sizeHead = _readHead(_offset);
    _offset = sizeHead.dataOffset;
    final size = _readNumeric(sizeHead.type, _offset);
    _offset = size.nextOffset;

    final length = size.value;
    final end = _offset + length;
    final value = Uint8List.sublistView(_data, _offset, end);
    _offset = end;
    return value;
  }

  T? readStruct<T>(int tag, T Function(_TarsReader reader) parser) {
    final head = _seekToTag(tag);
    if (head == null || head.type != 10) {
      return null;
    }

    final value = parser(this);
    _skipToStructEnd();
    return value;
  }

  _TarsHead? _seekToTag(int targetTag) {
    var cursor = _offset;
    while (cursor < _data.length) {
      final head = _readHead(cursor);
      if (head.type == 11) {
        _offset = head.startOffset;
        return null;
      }
      if (head.tag == targetTag) {
        _offset = head.dataOffset;
        return head;
      }
      if (head.tag > targetTag) {
        _offset = head.startOffset;
        return null;
      }
      cursor = _skipValue(head.dataOffset, head.type);
    }
    _offset = cursor;
    return null;
  }

  void _skipToStructEnd() {
    var cursor = _offset;
    while (cursor < _data.length) {
      final head = _readHead(cursor);
      if (head.type == 11) {
        _offset = head.dataOffset;
        return;
      }
      cursor = _skipValue(head.dataOffset, head.type);
    }
    _offset = cursor;
  }

  _TarsHead _readHead(int offset) {
    final first = _data[offset];
    final type = first & 0x0F;
    var tag = (first & 0xF0) >> 4;
    var dataOffset = offset + 1;
    if (tag == 15) {
      tag = _data[dataOffset];
      dataOffset += 1;
    }
    return _TarsHead(
      startOffset: offset,
      dataOffset: dataOffset,
      tag: tag,
      type: type,
    );
  }

  int _skipValue(int offset, int type) {
    switch (type) {
      case 0:
        return offset + 1;
      case 1:
        return offset + 2;
      case 2:
        return offset + 4;
      case 3:
        return offset + 8;
      case 6:
        return offset + 1 + _data[offset];
      case 7:
        return offset + 4 + _view.getInt32(offset, Endian.big);
      case 8:
        final mapSizeHead = _readHead(offset);
        final mapSize = _readNumeric(mapSizeHead.type, mapSizeHead.dataOffset);
        var mapCursor = mapSize.nextOffset;
        for (var index = 0; index < mapSize.value * 2; index += 1) {
          final entryHead = _readHead(mapCursor);
          mapCursor = _skipValue(entryHead.dataOffset, entryHead.type);
        }
        return mapCursor;
      case 9:
        final listSizeHead = _readHead(offset);
        final listSize =
            _readNumeric(listSizeHead.type, listSizeHead.dataOffset);
        var listCursor = listSize.nextOffset;
        for (var index = 0; index < listSize.value; index += 1) {
          final entryHead = _readHead(listCursor);
          listCursor = _skipValue(entryHead.dataOffset, entryHead.type);
        }
        return listCursor;
      case 10:
        var cursor = offset;
        while (cursor < _data.length) {
          final head = _readHead(cursor);
          if (head.type == 11) {
            return head.dataOffset;
          }
          cursor = _skipValue(head.dataOffset, head.type);
        }
        return cursor;
      case 12:
        return offset;
      case 11:
        return offset;
      case 13:
        final subtype = _readHead(offset);
        final sizeHead = _readHead(subtype.dataOffset);
        final size = _readNumeric(sizeHead.type, sizeHead.dataOffset);
        return size.nextOffset + size.value;
      default:
        throw UnsupportedError('Unsupported Huya Tars field type: $type');
    }
  }

  _NumericRead _readNumeric(int type, int offset) {
    switch (type) {
      case 12:
        return _NumericRead(0, offset);
      case 0:
        return _NumericRead(_view.getInt8(offset), offset + 1);
      case 1:
        return _NumericRead(_view.getInt16(offset, Endian.big), offset + 2);
      case 2:
        return _NumericRead(_view.getInt32(offset, Endian.big), offset + 4);
      case 3:
        return _NumericRead(_view.getInt64(offset, Endian.big), offset + 8);
      default:
        return _NumericRead(0, offset);
    }
  }
}

class _TarsHead {
  const _TarsHead({
    required this.startOffset,
    required this.dataOffset,
    required this.tag,
    required this.type,
  });

  final int startOffset;
  final int dataOffset;
  final int tag;
  final int type;
}

class _NumericRead {
  const _NumericRead(this.value, this.nextOffset);

  final int value;
  final int nextOffset;
}
