import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ManagedBackend {
  ManagedBackend._();

  static final ManagedBackend instance = ManagedBackend._();

  Process? _ownedProcess;
  bool _startAttempted = false;

  Future<void> ensureStarted() async {
    if (!Platform.isWindows) return;
    if (_startAttempted) return;
    _startAttempted = true;

    if (await _isHealthy()) {
      return;
    }

    final executable = _resolveBackendExecutable();
    if (executable == null) {
      return;
    }

    try {
      _ownedProcess = await Process.start(
        executable.path,
        const [],
        workingDirectory: executable.parent.path,
      );

      // Drain output to avoid pipe backpressure in long-running sessions.
      unawaited(_ownedProcess?.stdout.drain<void>());
      unawaited(_ownedProcess?.stderr.drain<void>());

      await _waitUntilHealthy();
    } catch (_) {
      await dispose();
    }
  }

  Future<void> dispose() async {
    final process = _ownedProcess;
    _ownedProcess = null;
    if (process == null) return;

    try {
      process.kill();
    } catch (_) {}

    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<bool> _isHealthy() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:5007/health'))
          .timeout(const Duration(seconds: 2));
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      final body = await utf8.decodeStream(response);
      client.close(force: true);
      if (response.statusCode != 200) {
        return false;
      }
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> &&
          decoded['status']?.toString().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> _waitUntilHealthy() async {
    const timeout = Duration(seconds: 12);
    const poll = Duration(milliseconds: 300);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy()) {
        return;
      }
      await Future<void>.delayed(poll);
    }
  }

  File? _resolveBackendExecutable() {
    final candidates = <String>{};

    final resolvedExecutable = File(Platform.resolvedExecutable);
    candidates.add(
      '${resolvedExecutable.parent.path}${Platform.pathSeparator}moovie.exe',
    );

    candidates
        .add('${Directory.current.path}${Platform.pathSeparator}moovie.exe');

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }
}
