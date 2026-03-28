import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/live_provider.dart';

const liveCustomM3uStorageKey = 'live_custom_m3u_sources';
const liveCustomM3uDefaultSourceId = 'ccsh-live-platforms';
const liveCustomM3uDefaultSourceUrl =
    'https://raw.githubusercontent.com/CCSH/IPTV/refs/heads/main/live_platforms.m3u';

class LiveM3uSourceStore {
  Future<List<LiveImportedSource>> loadSources() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(liveCustomM3uStorageKey);

    if (raw == null || raw.isEmpty) {
      final defaults = _defaultSources;
      await saveSources(defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw);
      final items = (decoded as List<dynamic>)
          .whereType<Map>()
          .map((item) => LiveImportedSource.fromJson(
                Map<String, dynamic>.from(item.cast<String, dynamic>()),
              ))
          .toList();

      if (items.isEmpty) {
        final defaults = _defaultSources;
        await saveSources(defaults);
        return defaults;
      }

      if (!items.any((item) => item.id == liveCustomM3uDefaultSourceId)) {
        final merged = <LiveImportedSource>[
          _defaultSources.first,
          ...items,
        ];
        await saveSources(merged);
        return merged;
      }

      return items;
    } catch (_) {
      final defaults = _defaultSources;
      await saveSources(defaults);
      return defaults;
    }
  }

  Future<void> saveSources(List<LiveImportedSource> sources) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      liveCustomM3uStorageKey,
      jsonEncode(sources.map((item) => item.toJson()).toList()),
    );
  }

  bool isProtectedSource(LiveImportedSource source) {
    return source.id == liveCustomM3uDefaultSourceId;
  }

  Future<void> removeSource(String sourceId) async {
    final sources = await loadSources();
    final nextSources = sources
        .where(
          (source) => source.id != sourceId || isProtectedSource(source),
        )
        .toList();
    await saveSources(nextSources);
  }

  List<LiveImportedSource> get _defaultSources {
    return [
      LiveImportedSource(
        id: liveCustomM3uDefaultSourceId,
        name: 'CCSH Live Platforms',
        type: LiveImportedSourceType.network,
        value: liveCustomM3uDefaultSourceUrl,
      ),
    ];
  }
}
