import '../../../core/models/vod_models.dart';
import '../domain/play_repository.dart';
import 'local_media_proxy.dart';

class NativePlayRepository implements PlayRepository {
  const NativePlayRepository();

  static const Map<String, String> _baseHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
  };

  @override
  Future<PlayResult> parsePlayUrl(String playUrl, {String referer = ''}) async {
    final normalizedReferer = referer.trim();
    final sources = <PlaySource>[];
    final sourceParts = playUrl.split(r'$$$');

    for (var sourceIndex = 0; sourceIndex < sourceParts.length; sourceIndex++) {
      final sourcePart = sourceParts[sourceIndex].trim();
      if (sourcePart.isEmpty) {
        continue;
      }

      final episodes = <PlayEpisode>[];
      for (final episodePart in sourcePart.split('#')) {
        final normalizedEpisode = episodePart.trim();
        if (normalizedEpisode.isEmpty) {
          continue;
        }

        final splitIndex = normalizedEpisode.indexOf(r'$');
        if (splitIndex <= 0 || splitIndex >= normalizedEpisode.length - 1) {
          continue;
        }

        final name = normalizedEpisode.substring(0, splitIndex).trim();
        final url = normalizedEpisode.substring(splitIndex + 1).trim();
        if (name.isEmpty || url.isEmpty) {
          continue;
        }

        episodes.add(
          PlayEpisode(
            name: name,
            url: url,
            proxyUrl: await _buildProxyUrl(url, normalizedReferer),
            httpHeaders: _buildHttpHeaders(
              url,
              normalizedReferer,
              proxied: _isLikelyHls(url),
            ),
          ),
        );
      }

      if (episodes.isEmpty) {
        continue;
      }

      sources.add(
        PlaySource(
          name: '播放源 ${sourceIndex + 1}',
          episodes: episodes,
        ),
      );
    }

    return PlayResult(sources: sources);
  }

  Future<String?> _buildProxyUrl(String url, String referer) async {
    if (!_isLikelyHls(url)) {
      return null;
    }

    try {
      return await LocalMediaProxy.instance.createHlsProxyUrl(
        url: url,
        headers: _buildUpstreamHeaders(referer),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, String>? _buildHttpHeaders(
    String url,
    String referer, {
    required bool proxied,
  }) {
    if (proxied) {
      return null;
    }

    final urlUri = Uri.tryParse(url);
    if (urlUri == null || !urlUri.hasScheme) {
      return _buildUpstreamHeaders(referer);
    }

    return _buildUpstreamHeaders(referer);
  }

  Map<String, String> _buildUpstreamHeaders(String referer) {
    if (referer.isEmpty) {
      return _baseHeaders;
    }

    final headers = <String, String>{
      ..._baseHeaders,
      'Referer': referer,
    };

    final refererUri = Uri.tryParse(referer);
    if (refererUri != null &&
        refererUri.hasScheme &&
        refererUri.host.isNotEmpty) {
      headers['Origin'] = '${refererUri.scheme}://${refererUri.host}';
    }

    return headers;
  }

  bool _isLikelyHls(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('m3u8');
  }
}
