import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../domain/history_repository.dart';

class LocalHistoryRepository implements HistoryRepository {
  static const _historyKey = 'vod_local_history_v1';

  @override
  Future<List<WatchHistoryItem>> fetchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => WatchHistoryItem.fromJson(
              Map<String, dynamic>.from(item.cast<String, dynamic>()),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addHistory(WatchHistoryUpsert request) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await fetchHistory();
    final next = history.where((item) => !_isSameEntry(item, request)).toList();

    next.insert(
      0,
      WatchHistoryItem(
        vodId: request.vodId,
        sourceKey: request.sourceKey,
        vodName: request.vodName,
        vodPic: request.vodPic,
        sourceName: request.sourceName,
        year: request.year,
        totalEpisodes: request.totalEpisodes,
        totalTime: request.totalTime,
        searchTitle: request.searchTitle,
        lastPlayTime: DateTime.now().millisecondsSinceEpoch,
        progress: request.progress,
        episode: request.episode,
        sourceIndex: request.sourceIndex,
        episodeIndex: request.episodeIndex,
      ),
    );

    await prefs.setString(
      _historyKey,
      jsonEncode(next.take(500).map(_historyToJson).toList()),
    );
  }

  @override
  Future<void> deleteHistory({
    required String vodId,
    required String sourceKey,
    int? sourceIndex,
    int? episodeIndex,
    String? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await fetchHistory();
    final next = history
        .where(
          (item) => !(item.vodId == vodId &&
              item.sourceKey == sourceKey &&
              _matchesEpisode(
                item,
                sourceIndex: sourceIndex,
                episodeIndex: episodeIndex,
                episode: episode,
              )),
        )
        .toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(next.map(_historyToJson).toList()),
    );
  }

  @override
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Map<String, dynamic> _historyToJson(WatchHistoryItem item) {
    return {
      'vod_id': item.vodId,
      'source_key': item.sourceKey,
      'vod_name': item.vodName,
      'vod_pic': item.vodPic,
      'source_name': item.sourceName,
      'year': item.year,
      'total_episodes': item.totalEpisodes,
      'total_time': item.totalTime,
      'search_title': item.searchTitle,
      'last_play_time': item.lastPlayTime,
      'progress': item.progress,
      'play_time': item.progress,
      'save_time': item.lastPlayTime,
      'episode': item.episode,
      'source_index': item.sourceIndex,
      'episode_index': item.episodeIndex,
      'index': item.episodeIndex == null ? null : item.episodeIndex! + 1,
    };
  }

  bool _isSameEntry(WatchHistoryItem item, WatchHistoryUpsert request) {
    return item.vodId == request.vodId && item.sourceKey == request.sourceKey;
  }

  bool _matchesEpisode(
    WatchHistoryItem item, {
    int? sourceIndex,
    int? episodeIndex,
    String? episode,
  }) {
    if (sourceIndex != null && episodeIndex != null) {
      return item.sourceIndex == sourceIndex &&
          item.episodeIndex == episodeIndex;
    }
    if (episode != null && episode.isNotEmpty) {
      return item.episode == episode;
    }
    return item.sourceIndex == sourceIndex && item.episodeIndex == episodeIndex;
  }
}
