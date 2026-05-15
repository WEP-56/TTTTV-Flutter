import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 本地 HLS 代理服务器。
///
/// 改进点（相对旧实现）：
/// - 共享一个 [HttpClient] 实例，复用 socket / TLS / DNS，
///   消除"每个 segment 都重新握手"造成的间歇性卡顿
/// - 缓存键加入 headers hash，避免不同 Referer 间的串味
/// - 区分点播 (`#EXT-X-ENDLIST`) 与直播：
///   点播 playlist 缓存 3 分钟，直播完全不缓存
/// - 客户端断开（拖进度条、关播放器）时，主动中止上游请求
class LocalMediaProxy {
  LocalMediaProxy._();

  static final LocalMediaProxy instance = LocalMediaProxy._();

  static const _vodPlaylistTtl = Duration(minutes: 3);
  static const _maxCachedPlaylists = 64;
  final Map<String, _CachedPlaylist> _playlistCache = {};

  HttpServer? _server;
  Future<HttpServer>? _starting;

  /// 共享给所有上游请求的 HttpClient。Dart 的 [HttpClient] 默认开启
  /// keep-alive；只要不被释放就会复用底层连接，对 HLS 的反复小请求
  /// 收益巨大。
  HttpClient? _sharedClient;

  HttpClient get _httpClient {
    final existing = _sharedClient;
    if (existing != null) return existing;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 8
      ..autoUncompress = true;
    _sharedClient = client;
    return client;
  }

  Future<String> createHlsProxyUrl({
    required String url,
    required Map<String, String> headers,
  }) async {
    final server = await _ensureStarted();
    return _buildProxyUri(
      server,
      path: '/proxy/m3u8',
      url: url,
      headers: headers,
    ).toString();
  }

  Future<HttpServer> _ensureStarted() async {
    if (_server != null) {
      return _server!;
    }
    if (_starting != null) {
      return _starting!;
    }

    final completer = Completer<HttpServer>();
    _starting = completer.future;

    () async {
      try {
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
          shared: true,
        );
        _server = server;
        unawaited(
          server.forEach((request) async {
            try {
              await _handleRequest(request);
            } catch (_) {
              try {
                request.response.statusCode = HttpStatus.internalServerError;
              } catch (_) {}
              try {
                await request.response.close();
              } catch (_) {}
            }
          }),
        );
        completer.complete(server);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _starting = null;
      }
    }();

    return completer.future;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final upstreamUrl = request.uri.queryParameters['url'];
    if (upstreamUrl == null || upstreamUrl.trim().isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final headers = _decodeHeaders(request.uri.queryParameters['headers']);
    final uri = Uri.parse(upstreamUrl);

    switch (request.uri.path) {
      case '/proxy/m3u8':
        await _proxyPlaylist(
          request,
          uri: uri,
          headers: headers,
        );
        return;
      case '/proxy/segment':
      case '/proxy/key':
        await _proxyBinary(
          request,
          uri: uri,
          headers: headers,
        );
        return;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _proxyPlaylist(
    HttpRequest request, {
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final cacheKey = _playlistCacheKey(uri, headers);

    final cached = _playlistCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      _writePlaylistResponse(request.response, cached.content);
      await request.response.close();
      return;
    }

    final upstream = await _fetchUpstream(
      request,
      uri: uri,
      headers: headers,
    );
    if (upstream == null) {
      // 已经写过错误状态码，不再处理
      return;
    }

    final body = await utf8.decodeStream(upstream);
    final rewritten = _rewritePlaylist(
      body,
      baseUri: uri,
      serverPort: request.connectionInfo?.localPort ?? 0,
      headers: headers,
    );

    // 只有点播（含 ENDLIST）才缓存，直播流不缓存
    if (_isVodPlaylist(rewritten)) {
      _cachePlaylist(cacheKey, rewritten);
    }

    _writePlaylistResponse(request.response, rewritten);
    await request.response.close();
  }

  void _writePlaylistResponse(HttpResponse response, String content) {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
      charset: 'utf-8',
    );
    // playlist 体积小，禁用任何中间缓存，避免 mediakit 复用过期 playlist
    response.headers
        .set(HttpHeaders.cacheControlHeader, 'no-store, max-age=0');
    response.write(content);
  }

  String _playlistCacheKey(Uri uri, Map<String, String> headers) {
    final headerSignature = headers.entries
        .map((e) => '${e.key.toLowerCase()}=${e.value}')
        .toList()
      ..sort();
    final raw = '${uri.toString()}|${headerSignature.join('&')}';
    final digest = md5.convert(utf8.encode(raw));
    return digest.toString();
  }

  bool _isVodPlaylist(String content) {
    return content.contains('#EXT-X-ENDLIST');
  }

  void _cachePlaylist(String key, String content) {
    if (_playlistCache.length >= _maxCachedPlaylists) {
      final oldest = _playlistCache.entries.reduce(
        (a, b) =>
            a.value.expiresAt.isBefore(b.value.expiresAt) ? a : b,
      );
      _playlistCache.remove(oldest.key);
    }
    _playlistCache[key] = _CachedPlaylist(
      content: content,
      expiresAt: DateTime.now().add(_vodPlaylistTtl),
    );
  }

  Future<void> _proxyBinary(
    HttpRequest request, {
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final upstream = await _fetchUpstream(
      request,
      uri: uri,
      headers: headers,
    );
    if (upstream == null) return;

    request.response.statusCode = upstream.statusCode;

    final contentType = upstream.headers.contentType;
    if (contentType != null) {
      request.response.headers.contentType = contentType;
    }
    // 如果上游被自动解压（Content-Encoding 不为空），原始 Content-Length 已失真，
    // 直接转发会导致 mediakit 等待错误的字节数 → 永久缓冲。改用分块编码。
    final wasCompressed =
        upstream.headers.value(HttpHeaders.contentEncodingHeader) != null;
    final contentLength = upstream.headers.contentLength;
    if (!wasCompressed && contentLength >= 0) {
      request.response.headers.contentLength = contentLength;
    }
    final acceptRanges = upstream.headers.value(HttpHeaders.acceptRangesHeader);
    if (acceptRanges != null) {
      request.response.headers
          .set(HttpHeaders.acceptRangesHeader, acceptRanges);
    }
    final contentRange =
        upstream.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      request.response.headers
          .set(HttpHeaders.contentRangeHeader, contentRange);
    }

    // 客户端断开（拖动进度条、切换分辨率）时主动中止上游
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<void>();
    subscription = upstream.listen(
      (chunk) {
        try {
          request.response.add(chunk);
        } catch (error) {
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      cancelOnError: true,
    );

    unawaited(
      request.response.done.catchError((Object _) {
        // 客户端断开时取消订阅，HttpClient 会自动释放连接
        subscription?.cancel();
      }),
    );

    try {
      await completer.future;
    } catch (_) {
      // 上游中断或客户端断开，吞掉异常
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<HttpClientResponse?> _fetchUpstream(
    HttpRequest request, {
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final HttpClientRequest upstream;
    try {
      upstream = await _httpClient.getUrl(uri);
    } catch (error) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return null;
    }

    headers.forEach(upstream.headers.set);
    _copyRequestHeader(request, upstream, HttpHeaders.rangeHeader);
    _copyRequestHeader(request, upstream, HttpHeaders.acceptHeader);
    _copyRequestHeader(request, upstream, HttpHeaders.acceptEncodingHeader);

    HttpClientResponse response;
    try {
      response = await upstream.close();
    } catch (error) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return null;
    }

    if (response.statusCode >= 400) {
      request.response.statusCode = response.statusCode;
      await response.drain<void>();
      await request.response.close();
      return null;
    }
    return response;
  }

  void _copyRequestHeader(
    HttpRequest request,
    HttpClientRequest upstream,
    String name,
  ) {
    final values = request.headers[name];
    if (values == null || values.isEmpty) {
      return;
    }
    upstream.headers.set(name, values.join(','));
  }

  String _rewritePlaylist(
    String content, {
    required Uri baseUri,
    required int serverPort,
    required Map<String, String> headers,
  }) {
    final lines = const LineSplitter().convert(content);
    final rewritten = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.add(line);
        continue;
      }

      if (trimmed.startsWith('#EXT-X-KEY')) {
        rewritten.add(
          _rewriteDirectiveUri(
            line,
            attributeName: 'URI',
            baseUri: baseUri,
            serverPort: serverPort,
            path: '/proxy/key',
            headers: headers,
          ),
        );
        continue;
      }

      if (trimmed.startsWith('#EXT-X-MAP')) {
        rewritten.add(
          _rewriteDirectiveUri(
            line,
            attributeName: 'URI',
            baseUri: baseUri,
            serverPort: serverPort,
            path: '/proxy/segment',
            headers: headers,
          ),
        );
        continue;
      }

      if (trimmed.startsWith('#')) {
        rewritten.add(line);
        continue;
      }

      final resolved = baseUri.resolve(trimmed).toString();
      final path = _isLikelyHls(trimmed) ? '/proxy/m3u8' : '/proxy/segment';
      rewritten.add(
        _buildProxyUri(
          null,
          port: serverPort,
          path: path,
          url: resolved,
          headers: headers,
        ).toString(),
      );
    }

    return rewritten.join('\n');
  }

  String _rewriteDirectiveUri(
    String line, {
    required String attributeName,
    required Uri baseUri,
    required int serverPort,
    required String path,
    required Map<String, String> headers,
  }) {
    final pattern = RegExp('$attributeName="([^"]+)"');
    final match = pattern.firstMatch(line);
    if (match == null) {
      return line;
    }

    final original = match.group(1);
    if (original == null || original.isEmpty) {
      return line;
    }

    final resolved = baseUri.resolve(original).toString();
    final proxy = _buildProxyUri(
      null,
      port: serverPort,
      path: path,
      url: resolved,
      headers: headers,
    ).toString();
    return line.replaceFirst(original, proxy);
  }

  Uri _buildProxyUri(
    HttpServer? server, {
    int? port,
    required String path,
    required String url,
    required Map<String, String> headers,
  }) {
    final effectivePort = server?.port ?? port ?? 0;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: effectivePort,
      path: path,
      queryParameters: {
        'url': url,
        'headers': base64UrlEncode(utf8.encode(jsonEncode(headers))),
      },
    );
  }

  Map<String, String> _decodeHeaders(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(raw))));
      if (decoded is! Map) {
        return const {};
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  bool _isLikelyHls(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('m3u8');
  }
}

class _CachedPlaylist {
  _CachedPlaylist({required this.content, required this.expiresAt});
  final String content;
  final DateTime expiresAt;
}
