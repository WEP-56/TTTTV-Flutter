import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalMediaProxy {
  LocalMediaProxy._();

  static final LocalMediaProxy instance = LocalMediaProxy._();

  HttpServer? _server;
  Future<HttpServer>? _starting;

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
              await request.response.close();
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
    final response = await _fetchUpstream(
      request,
      uri: uri,
      headers: headers,
    );
    final body = await utf8.decodeStream(response);
    final rewritten = _rewritePlaylist(
      body,
      baseUri: uri,
      serverPort: request.connectionInfo?.localPort ?? 0,
      headers: headers,
    );

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
      charset: 'utf-8',
    );
    request.response.write(rewritten);
    await request.response.close();
  }

  Future<void> _proxyBinary(
    HttpRequest request, {
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final response = await _fetchUpstream(
      request,
      uri: uri,
      headers: headers,
    );

    request.response.statusCode = response.statusCode;
    final contentType = response.headers.contentType;
    if (contentType != null) {
      request.response.headers.contentType = contentType;
    }
    final contentLength = response.headers.contentLength;
    if (contentLength >= 0) {
      request.response.headers.contentLength = contentLength;
    }

    await response.pipe(request.response);
  }

  Future<HttpClientResponse> _fetchUpstream(
    HttpRequest request, {
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    final upstream = await client.getUrl(uri);
    headers.forEach(upstream.headers.set);
    _copyRequestHeader(request, upstream, HttpHeaders.rangeHeader);
    _copyRequestHeader(request, upstream, HttpHeaders.acceptHeader);
    _copyRequestHeader(request, upstream, HttpHeaders.acceptEncodingHeader);

    final response = await upstream.close();
    if (response.statusCode >= 400) {
      request.response.statusCode = response.statusCode;
      await response.drain<void>();
      await request.response.close();
      throw HttpException('Upstream failed: ${response.statusCode}', uri: uri);
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
