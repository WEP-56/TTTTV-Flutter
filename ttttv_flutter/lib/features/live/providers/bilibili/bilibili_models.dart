class BilibiliDanmakuArgs {
  const BilibiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.buvid,
    required this.serverHost,
    required this.uid,
    required this.cookie,
  });

  final int roomId;
  final String token;
  final String buvid;
  final String serverHost;
  final int uid;
  final String cookie;
}
