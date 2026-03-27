import '../../../../core/models/vod_models.dart';

enum HuyaLineType {
  flv,
  hls,
}

class HuyaDanmakuArgs {
  const HuyaDanmakuArgs({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
  });

  final int ayyuid;
  final int topSid;
  final int subSid;
}

class HuyaBitRate {
  const HuyaBitRate({
    required this.name,
    required this.bitRate,
  });

  final String name;
  final int bitRate;

  LivePlayQuality toQuality() {
    return LivePlayQuality(
      id: bitRate.toString(),
      name: name,
      sort: bitRate == 0 ? 1 << 30 : bitRate,
    );
  }
}

class HuyaStreamLine {
  const HuyaStreamLine({
    required this.baseUrl,
    required this.streamName,
    required this.antiCode,
    required this.cdnType,
    required this.type,
    required this.presenterUid,
  });

  final String baseUrl;
  final String streamName;
  final String antiCode;
  final String cdnType;
  final HuyaLineType type;
  final int presenterUid;

  String get extension => type == HuyaLineType.hls ? 'm3u8' : 'flv';
}

class HuyaRoomProfile {
  const HuyaRoomProfile({
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    required this.userAvatar,
    required this.online,
    required this.introduction,
    required this.notice,
    required this.status,
    required this.isRecord,
    required this.url,
    required this.streamLines,
    required this.bitRates,
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
  });

  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final String userAvatar;
  final int online;
  final String? introduction;
  final String? notice;
  final bool status;
  final bool isRecord;
  final String url;
  final List<HuyaStreamLine> streamLines;
  final List<HuyaBitRate> bitRates;
  final int ayyuid;
  final int topSid;
  final int subSid;

  LiveRoomDetail toDetail(String platform) {
    return LiveRoomDetail(
      platform: platform,
      roomId: roomId,
      title: title,
      cover: cover,
      userName: userName,
      userAvatar: userAvatar,
      online: online,
      introduction: introduction,
      notice: notice,
      status: status,
      isRecord: isRecord,
      url: url,
      showTime: null,
    );
  }
}
