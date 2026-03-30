import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/vod_models.dart';
import '../domain/favorites_repository.dart';

class LocalFavoritesRepository implements FavoritesRepository {
  static const _favoritesKey = 'vod_local_favorites_v1';

  @override
  Future<List<FavoriteItem>> fetchFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => FavoriteItem.fromJson(
              Map<String, dynamic>.from(item.cast<String, dynamic>()),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addFavorite(VodItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await fetchFavorites();
    final next = favorites
        .where(
          (favorite) => !(favorite.vodId == item.vodId &&
              favorite.sourceKey == item.sourceKey),
        )
        .toList();

    next.insert(
      0,
      FavoriteItem(
        vodId: item.vodId,
        sourceKey: item.sourceKey,
        vodName: item.vodName,
        createdTime: DateTime.now().millisecondsSinceEpoch,
        vodPic: item.vodPic,
        vodRemarks: item.vodRemarks,
        vodActor: item.vodActor,
        vodDirector: item.vodDirector,
        vodContent: item.vodContent,
      ),
    );

    await prefs.setString(
      _favoritesKey,
      jsonEncode(next.take(500).map(_favoriteToJson).toList()),
    );
  }

  @override
  Future<void> deleteFavorite({
    required String vodId,
    required String sourceKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await fetchFavorites();
    final next = favorites
        .where(
          (favorite) =>
              !(favorite.vodId == vodId && favorite.sourceKey == sourceKey),
        )
        .toList();
    await prefs.setString(
      _favoritesKey,
      jsonEncode(next.map(_favoriteToJson).toList()),
    );
  }

  @override
  Future<bool> checkFavorite({
    required String vodId,
    required String sourceKey,
  }) async {
    final favorites = await fetchFavorites();
    return favorites.any(
      (favorite) => favorite.vodId == vodId && favorite.sourceKey == sourceKey,
    );
  }

  @override
  Future<void> clearFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
  }

  Map<String, dynamic> _favoriteToJson(FavoriteItem item) {
    return {
      'vod_id': item.vodId,
      'source_key': item.sourceKey,
      'vod_name': item.vodName,
      'created_time': item.createdTime,
      'vod_pic': item.vodPic,
      'vod_remarks': item.vodRemarks,
      'vod_actor': item.vodActor,
      'vod_director': item.vodDirector,
      'vod_content': item.vodContent,
    };
  }
}
