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
  _openDetailPage(
    context,
    fallback,
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

  _openDetailPage(
    context,
    VodItem.fromHistory(history),
    initialHistory: history,
  );
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
    final sameYear = favorite.year == null ||
        favorite.year!.isEmpty ||
        item.year == null ||
        item.year!.isEmpty ||
        favorite.year == item.year;
    if (favoriteTitle.isNotEmpty && favoriteTitle == historyTitle && sameYear) {
      return item;
    }
  }
  return null;
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
