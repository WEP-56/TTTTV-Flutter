import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheUsage {
  const CacheUsage({
    required this.diskBytes,
    required this.memoryBytes,
  });

  final int diskBytes;
  final int memoryBytes;

  int get totalBytes => diskBytes + memoryBytes;
}

class StorageManager {
  Future<CacheUsage> getCacheUsage() async {
    final tempDirectory = await getTemporaryDirectory();
    final diskBytes = await _computeDirectorySize(tempDirectory);
    final memoryBytes = PaintingBinding.instance.imageCache.currentSizeBytes;
    return CacheUsage(
      diskBytes: diskBytes,
      memoryBytes: memoryBytes,
    );
  }

  Future<CacheUsage> clearCache() async {
    final usage = await getCacheUsage();
    final tempDirectory = await getTemporaryDirectory();
    await _clearDirectory(tempDirectory);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    return usage;
  }

  Future<int> _computeDirectorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var total = 0;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Ignore unreadable files so one bad entry does not block the summary.
        }
      }
    }
    return total;
  }

  Future<void> _clearDirectory(Directory directory) async {
    if (!await directory.exists()) {
      return;
    }

    await for (final entity
        in directory.list(recursive: false, followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Ignore deletion failures to keep the rest of the cleanup moving.
      }
    }
  }
}
