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
    final next = history
        .where(
          (item) => !(item.vodId == request.vodId &&
              item.sourceKey == request.sourceKey),
        )
        .toList();

    next.insert(
      0,
      WatchHistoryItem(
        vodId: request.vodId,
        sourceKey: request.sourceKey,
        vodName: request.vodName,
        vodPic: request.vodPic,
        lastPlayTime: DateTime.now().millisecondsSinceEpoch,
        progress: request.progress,
        episode: request.episode,
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await fetchHistory();
    final next = history
        .where(
          (item) => !(item.vodId == vodId && item.sourceKey == sourceKey),
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
      'last_play_time': item.lastPlayTime,
      'progress': item.progress,
      'episode': item.episode,
    };
  }
}
