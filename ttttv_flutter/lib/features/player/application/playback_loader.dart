import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Command completion does not mean the native decoder reached the position.
/// Callers must not save progress until this future succeeds.
Future<void> openPlayback({
  required Player player,
  required Media media,
  required bool play,
  required bool Function() isCurrent,
  Duration start = Duration.zero,
}) async {
  await player.open(
      Media(media.uri, httpHeaders: media.httpHeaders, start: start),
      play: play || start > Duration.zero);
  if (!isCurrent()) return;
  if (start > Duration.zero) {
    var reached = false;
    for (var attempt = 0; attempt < 3 && isCurrent(); attempt++) {
      final duration = player.state.duration;
      final target = duration > Duration.zero && start >= duration
          ? Duration(
              milliseconds: (duration.inMilliseconds - 1000)
                  .clamp(0, duration.inMilliseconds))
          : start;
      bool atTarget(Duration value) =>
          (value - target).abs() <= const Duration(seconds: 3);
      if (atTarget(player.state.position)) {
        reached = true;
        break;
      }
      final observed = player.stream.position
          .firstWhere(atTarget)
          .timeout(const Duration(seconds: 8))
          .then((_) => true, onError: (Object _) => false);
      if (attempt > 0 || player.state.duration > Duration.zero) {
        await player.seek(target);
      }
      reached = await observed;
      if (reached) break;
    }
    if (!isCurrent()) return;
    if (!reached) {
      await player.pause();
      throw StateError('未能恢复到上次进度，已保留历史记录，请重试或选择从头播放');
    }
  }
  if (!isCurrent()) return;
  if (play) {
    await player.play();
  } else {
    await player.pause();
  }
}
