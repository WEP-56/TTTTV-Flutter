import '../../../core/models/vod_models.dart';

abstract class PlayRepository {
  Future<PlayResult> parsePlayUrl(String playUrl, {String referer = ''});
}
