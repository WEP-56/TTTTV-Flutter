import '../../../core/models/vod_models.dart';

abstract class SearchRepository {
  Future<SearchResult> search(String keyword, {bool bypass = false});

  Future<VodItem> getDetail({
    required String sourceKey,
    required String vodId,
  });
}
