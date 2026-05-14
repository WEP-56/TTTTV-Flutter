import '../../search/domain/search_repository.dart';

enum CachedPageStatus { ok, timeout, forbidden }

class CachedPageEntry {
  CachedPageEntry({
    required this.expiresAt,
    required this.status,
    required this.data,
    this.pageCount,
  });

  final DateTime expiresAt;
  final CachedPageStatus status;
  final List<VodItem> data;
  final int? pageCount;
}

class SearchCache {
  static const _ttl = Duration(minutes: 10);
  static const _maxEntries = 1000;
  final Map<String, CachedPageEntry> _cache = {};

  String _key(String sourceKey, String query, int page) =>
      '$sourceKey::$query::$page';

  CachedPageEntry? get(String sourceKey, String query, int page) {
    final key = _key(sourceKey, query.trim(), page);
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return entry;
  }

  void set(
    String sourceKey,
    String query,
    int page,
    CachedPageStatus status,
    List<VodItem> data, {
    int? pageCount,
  }) {
    _evictIfNeeded();
    final key = _key(sourceKey, query.trim(), page);
    _cache[key] = CachedPageEntry(
      expiresAt: DateTime.now().add(_ttl),
      status: status,
      data: data,
      pageCount: pageCount,
    );
  }

  void _evictIfNeeded() {
    if (_cache.length < _maxEntries) return;

    final now = DateTime.now();
    _cache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));

    if (_cache.length >= _maxEntries) {
      final sorted = _cache.entries.toList()
        ..sort((a, b) => a.value.expiresAt.compareTo(b.value.expiresAt));
      final toRemove = _cache.length - _maxEntries + 50;
      for (var i = 0; i < toRemove && i < sorted.length; i++) {
        _cache.remove(sorted[i].key);
      }
    }
  }
}
