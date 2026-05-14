import '../../../core/models/vod_models.dart';

typedef OnSourceBatch = void Function(List<VodItem> batch);

abstract class SearchRepository {
  Future<SearchResult> search(String keyword, {bool bypass = false, OnSourceBatch? onBatch});

  Future<VodItem> getDetail({
    required String sourceKey,
    required String vodId,
  });
}
