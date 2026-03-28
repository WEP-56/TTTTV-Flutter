class M3uMediaItem {
  const M3uMediaItem({
    required this.title,
    required this.link,
    required this.attributes,
  });

  final String title;
  final String link;
  final Map<String, String> attributes;
}

class M3uPlaylist {
  const M3uPlaylist({
    required this.items,
  });

  final List<M3uMediaItem> items;
}

class M3uParser {
  static final RegExp _attributePattern = RegExp(r'([\w-]+)="([^"]*)"');

  M3uPlaylist parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final items = <M3uMediaItem>[];
    Map<String, String>? pendingAttributes;
    String? pendingTitle;

    for (final line in lines) {
      if (line.startsWith('#EXTM3U')) {
        continue;
      }

      if (line.startsWith('#EXTINF')) {
        final separatorIndex = line.indexOf(',');
        final infoSegment =
            separatorIndex >= 0 ? line.substring(0, separatorIndex) : line;
        final titleSegment = separatorIndex >= 0
            ? line.substring(separatorIndex + 1).trim()
            : '';

        pendingAttributes = _parseAttributes(infoSegment);
        pendingTitle = titleSegment.isEmpty ? '未命名直播源' : titleSegment;
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      items.add(
        M3uMediaItem(
          title: pendingTitle?.isNotEmpty == true ? pendingTitle! : line,
          link: line,
          attributes: Map<String, String>.unmodifiable(
            pendingAttributes ?? const <String, String>{},
          ),
        ),
      );

      pendingAttributes = null;
      pendingTitle = null;
    }

    return M3uPlaylist(items: items);
  }

  Map<String, String> _parseAttributes(String infoSegment) {
    final attributes = <String, String>{};
    for (final match in _attributePattern.allMatches(infoSegment)) {
      final key = match.group(1);
      final value = match.group(2);
      if (key == null || value == null) continue;
      attributes[key] = value;
    }
    return attributes;
  }
}
