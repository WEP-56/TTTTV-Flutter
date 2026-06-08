import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';

Future<void> openPlayerFromHistory(
  BuildContext context,
  WidgetRef ref,
  WatchHistoryItem item,
) async {
  final fallback = VodItem.fromHistory(item);
  final matched = await _matchHistoryBeforeOpen(
    context,
    ref,
    item,
    fallback: fallback,
  );
  if (!context.mounted) return;
  _openDetailPage(
    context,
    matched ?? fallback,
    initialHistory: item,
  );
}

Future<void> openPlayerFromFavorite(
  BuildContext context,
  WidgetRef ref,
  FavoriteItem item,
) async {
  final fallback = VodItem.fromFavorite(item);
  final history = await _findHistoryForFavorite(ref, item);
  if (!context.mounted) return;

  if (history == null) {
    _openDetailPage(context, fallback);
    return;
  }

  final matched = await _matchHistoryBeforeOpen(
    context,
    ref,
    history,
    fallback: fallback,
  );
  if (!context.mounted) return;
  _openDetailPage(
    context,
    matched ?? fallback,
    initialHistory: history,
  );
}

Future<VodItem?> _matchHistoryBeforeOpen(
  BuildContext context,
  WidgetRef ref,
  WatchHistoryItem history, {
  required VodItem fallback,
}) async {
  _showMatchingDialog(context);
  try {
    final detail = await ref.read(searchRepositoryProvider).getDetail(
          sourceKey: history.sourceKey,
          vodId: history.vodId,
        );
    final sites = await ref.read(sourcesRepositoryProvider).fetchSites();
    final site =
        sites.where((item) => item.key == detail.sourceKey).firstOrNull;
    final referer = site?.detailUrl ?? site?.baseUrl ?? '';
    final playResult = await ref
        .read(playRepositoryProvider)
        .parsePlayUrl(detail.vodPlayUrl, referer: referer);
    if (playResult.sources.isEmpty) {
      throw StateError('历史片源暂无可播放剧集');
    }
    return detail;
  } catch (error) {
    if (context.mounted) {
      _showMatchFallbackMessage(context, error);
    }
    return null;
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

Future<WatchHistoryItem?> _findHistoryForFavorite(
  WidgetRef ref,
  FavoriteItem favorite,
) async {
  final history = await ref.read(historyRepositoryProvider).fetchHistory();
  WatchHistoryItem? sameSource;
  for (final item in history) {
    if (item.vodId == favorite.vodId && item.sourceKey == favorite.sourceKey) {
      sameSource = item;
      break;
    }
  }
  if (sameSource != null) return sameSource;

  final favoriteTitle =
      _normalizeTitle(favorite.searchTitle ?? favorite.vodName);
  for (final item in history) {
    final historyTitle = _normalizeTitle(item.searchTitle ?? item.vodName);
    if (favoriteTitle.isNotEmpty && favoriteTitle == historyTitle) {
      return item;
    }
  }
  return null;
}

void _showMatchingDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const AlertDialog(
        title: Text('正在匹配观看进度'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 16),
            Text('正在优先加载上次播放使用的片源...'),
          ],
        ),
      );
    },
  );
}

void _showMatchFallbackMessage(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(content: Text('未能匹配观看进度，已打开详情页继续搜索：$error')),
  );
}

String _normalizeTitle(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，,·・\-—_（）()【】\[\]]'), '')
      .toLowerCase();
}

void _openDetailPage(
  BuildContext context,
  VodItem item, {
  WatchHistoryItem? initialHistory,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailPage(
        initialItem: item,
        initialHistory: initialHistory,
      ),
    ),
  );
}
