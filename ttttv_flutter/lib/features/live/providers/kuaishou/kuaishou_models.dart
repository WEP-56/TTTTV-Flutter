import '../../../../core/models/vod_models.dart';

class KuaishouQuality {
  const KuaishouQuality({
    required this.id,
    required this.name,
    required this.shortName,
    required this.level,
    required this.bitrate,
    required this.url,
  });

  final String id;
  final String name;
  final String shortName;
  final int level;
  final int bitrate;
  final String url;

  LivePlayQuality toPlayQuality() {
    return LivePlayQuality(
      id: id,
      name: name.isNotEmpty ? name : shortName,
      sort: level,
    );
  }
}

class KuaishouRoomProfile {
  const KuaishouRoomProfile({
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    required this.userAvatar,
    required this.online,
    required this.status,
    required this.isRecord,
    required this.url,
    required this.introduction,
    required this.notice,
    required this.qualities,
  });

  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final String userAvatar;
  final int online;
  final bool status;
  final bool isRecord;
  final String url;
  final String? introduction;
  final String? notice;
  final List<KuaishouQuality> qualities;

  LiveRoomDetail toDetail(String platform) {
    return LiveRoomDetail(
      platform: platform,
      roomId: roomId,
      title: title,
      cover: cover,
      userName: userName,
      userAvatar: userAvatar,
      online: online,
      status: status,
      isRecord: isRecord,
      url: url,
      introduction: introduction,
      notice: notice,
      showTime: null,
    );
  }
}
