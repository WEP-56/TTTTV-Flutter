import '../../../core/models/vod_models.dart';

abstract class FavoritesRepository {
  Future<List<FavoriteItem>> fetchFavorites();

  Future<void> addFavorite(VodItem item);

  Future<void> deleteFavorite({
    required String vodId,
    required String sourceKey,
  });

  Future<bool> checkFavorite({
    required String vodId,
    required String sourceKey,
  });

  Future<void> clearFavorites();
}
