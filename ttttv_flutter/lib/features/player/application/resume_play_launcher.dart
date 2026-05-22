import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';
import '../presentation/player_page.dart';

Future<void> openPlayerFromHistory(
  BuildContext context,
  WidgetRef ref,
  WatchHistoryItem item,
) {
  return _openPlayerFromSavedItem(
    context: context,
    ref: ref,
    sourceKey: item.sourceKey,
    vodId: item.vodId,
    fallbackItem: VodItem.fromHistory(item),
    resumeProgress: item.progress,
    resumeEpisode: item.episode,
    resumeSourceIndex: item.sourceIndex,
    resumeEpisodeIndex: item.episodeIndex,
  );
}

Future<void> openPlayerFromFavorite(
  BuildContext context,
  WidgetRef ref,
  FavoriteItem item,
) async {
  final history = await ref.read(historyRepositoryProvider).fetchHistory();
  final matches = history
      .where((h) => h.vodId == item.vodId && h.sourceKey == item.sourceKey)
      .toList(growable: false);
  final resumeItem = matches.isEmpty ? null : matches.first;
  if (!context.mounted) return;

  return _openPlayerFromSavedItem(
    context: context,
    ref: ref,
    sourceKey: item.sourceKey,
    vodId: item.vodId,
    fallbackItem: VodItem.fromFavorite(item),
    resumeProgress: resumeItem?.progress ?? 0,
    resumeEpisode: resumeItem?.episode,
    resumeSourceIndex: resumeItem?.sourceIndex,
    resumeEpisodeIndex: resumeItem?.episodeIndex,
  );
}

Future<void> _openPlayerFromSavedItem({
  required BuildContext context,
  required WidgetRef ref,
  required String sourceKey,
  required String vodId,
  required VodItem fallbackItem,
  required double resumeProgress,
  required String? resumeEpisode,
  required int? resumeSourceIndex,
  required int? resumeEpisodeIndex,
}) async {
  _showLoadingMessage(context);
  try {
    final detail = await ref.read(searchRepositoryProvider).getDetail(
          sourceKey: sourceKey,
          vodId: vodId,
        );
    if (!context.mounted) return;

    if (detail.vodPlayUrl.trim().isEmpty) {
      _openDetailPage(context, detail);
      return;
    }

    final sites = await ref.read(sourcesRepositoryProvider).fetchSites();
    final site = sites.where((s) => s.key == detail.sourceKey).firstOrNull;
    final referer = site?.detailUrl ?? site?.baseUrl ?? '';
    final playResult = await ref
        .read(playRepositoryProvider)
        .parsePlayUrl(detail.vodPlayUrl, referer: referer);
    if (!context.mounted) return;

    if (playResult.sources.isEmpty) {
      _openDetailPage(context, detail);
      return;
    }

    final (sourceIndex, episodeIndex) = _locateEpisode(
      playResult,
      episodeName: resumeEpisode,
      sourceIndex: resumeSourceIndex,
      episodeIndex: resumeEpisodeIndex,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          detail: detail,
          playResult: playResult,
          initialSourceIndex: sourceIndex,
          initialEpisodeIndex: episodeIndex,
          initialProgress: resumeProgress,
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    _showFallbackMessage(context, error);
    _openDetailPage(context, fallbackItem);
  }
}

void _openDetailPage(BuildContext context, VodItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailPage(initialItem: item),
    ),
  );
}

(int, int) _locateEpisode(
  PlayResult result, {
  required String? episodeName,
  required int? sourceIndex,
  required int? episodeIndex,
}) {
  if (sourceIndex != null &&
      episodeIndex != null &&
      sourceIndex >= 0 &&
      sourceIndex < result.sources.length &&
      episodeIndex >= 0 &&
      episodeIndex < result.sources[sourceIndex].episodes.length) {
    return (sourceIndex, episodeIndex);
  }
  if (episodeName == null || episodeName.isEmpty) return (0, 0);
  for (var si = 0; si < result.sources.length; si++) {
    final episodes = result.sources[si].episodes;
    for (var ei = 0; ei < episodes.length; ei++) {
      if (episodes[ei].name == episodeName) {
        return (si, ei);
      }
    }
  }
  return (0, 0);
}

void _showLoadingMessage(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(content: Text('正在加载播放信息...')),
  );
}

void _showFallbackMessage(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(content: Text('加载播放信息失败，已打开详情页：$error')),
  );
}
