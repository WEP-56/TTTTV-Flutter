import '../../../core/models/vod_models.dart';

abstract class SourcesRepository {
  Future<List<SiteWithStatus>> fetchSites();

  Future<void> toggleSite({
    required String key,
    required bool enabled,
  });

  Future<void> addSource(AddSourceRequest request);

  Future<void> deleteSource(String key);

  Future<RemoteSourcesResponse> fetchRemoteSources({String? url});

  Future<AddSourcesBatchResult> addSourcesBatch(List<RemoteSource> sources);
}
