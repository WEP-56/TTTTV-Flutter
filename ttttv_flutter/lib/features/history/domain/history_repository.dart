import '../../../core/models/vod_models.dart';

abstract class HistoryRepository {
  Future<List<WatchHistoryItem>> fetchHistory();

  Future<void> addHistory(WatchHistoryUpsert request);

  Future<void> deleteHistory({
    required String vodId,
    required String sourceKey,
    int? sourceIndex,
    int? episodeIndex,
    String? episode,
  });

  Future<void> clearHistory();
}
