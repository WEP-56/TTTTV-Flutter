import '../../../../core/models/vod_models.dart';

class DouyinDanmakuArgs {
  const DouyinDanmakuArgs({
    required this.webRid,
    required this.roomId,
    required this.userId,
    required this.cookie,
    required this.signature,
  });

  final String webRid;
  final String roomId;
  final String userId;
  final String cookie;
  final String signature;
}

class DouyinQualityOption {
  const DouyinQualityOption({
    required this.id,
    required this.name,
    required this.sort,
    required this.urls,
  });

  final String id;
  final String name;
  final int sort;
  final List<String> urls;

  LivePlayQuality toPlayQuality() {
    return LivePlayQuality(
      id: id,
      name: name,
      sort: sort,
    );
  }
}

class DouyinRoomProfile {
  const DouyinRoomProfile({
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
  final List<DouyinQualityOption> qualities;

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
