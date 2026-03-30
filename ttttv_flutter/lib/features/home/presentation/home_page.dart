import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/network_permission_guide.dart';
import '../../../core/providers.dart';

final _homeDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      },
      responseType: ResponseType.plain,
    ),
  );
});

final bangumiRecommendationsProvider =
    FutureProvider<List<_HomeRecommendationItem>>((ref) async {
  final dio = ref.read(_homeDioProvider);
  final response =
      await dio.get<String>('https://bgm.tv/anime/browser?sort=rank');
  final html = response.data ?? '';

  final itemPattern = RegExp(
    r'<li id="item_\d+".*?<img src="([^"]+)".*?<h3>.*?<a [^>]*class="l">(.+?)</a>',
    dotAll: true,
  );

  return itemPattern
      .allMatches(html)
      .take(18)
      .map((match) {
        final cover = _normalizeUrl(match.group(1) ?? '');
        final title = _cleanHtmlText(match.group(2) ?? '');
        return _HomeRecommendationItem(
          title: title,
          coverUrl: cover,
          source: 'Bangumi',
        );
      })
      .where((item) => item.title.isNotEmpty)
      .toList();
});

final maoyanRecommendationsProvider =
    FutureProvider<List<_HomeRecommendationItem>>((ref) async {
  final dio = ref.read(_homeDioProvider);
  final searchRepository = ref.read(searchRepositoryProvider);
  final response =
      await dio.get<String>('https://piaofang.maoyan.com/web-heat');
  final html = response.data ?? '';

  final appDataPattern = RegExp(
    r'var AppData = (\{.*?\});\s*var isProduct',
    dotAll: true,
  );
  final match = appDataPattern.firstMatch(html);
  if (match == null) {
    return const [];
  }

  final appData = jsonDecode(match.group(1)!) as Map<String, dynamic>;
  final pageData = appData['pageData'] as Map<String, dynamic>? ?? const {};
  final webHeatData = (pageData['webHeatData'] as List?) ?? const [];

  final baseItems = webHeatData
      .take(18)
      .map((entry) {
        final map = entry as Map<String, dynamic>;
        final seriesInfo =
            map['seriesInfo'] as Map<String, dynamic>? ?? const {};
        final platformDesc = (seriesInfo['platformDesc'] ?? '').toString();
        final releaseInfo = (seriesInfo['releaseInfo'] ?? '').toString();
        return _HomeRecommendationItem(
          title: (seriesInfo['name'] ?? '').toString(),
          source: '猫眼热度榜',
          subtitle: [
            if (platformDesc.isNotEmpty) platformDesc,
            if (releaseInfo.isNotEmpty) releaseInfo,
          ].join(' · '),
        );
      })
      .where((item) => item.title.isNotEmpty)
      .toList();

  return Future.wait(
    baseItems.map((item) async {
      try {
        final result = await searchRepository.search(item.title);
        final coverUrl =
            result.items.isNotEmpty ? result.items.first.vodPic : null;
        return item.copyWith(coverUrl: coverUrl);
      } catch (_) {
        return item;
      }
    }),
  );
});

void _triggerSearch(WidgetRef ref, String title) {
  ref.read(pendingSearchProvider.notifier).state = title;
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _refreshRecommendations(WidgetRef ref) {
    ref.invalidate(bangumiRecommendationsProvider);
    ref.invalidate(maoyanRecommendationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('发现'),
          floating: true,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              tooltip: '刷新推荐',
              onPressed: () => _refreshRecommendations(ref),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        _RecommendationSection(
          title: '动漫区',
          subtitle: 'Bangumi 高分动画榜，点击后自动跳转搜索',
          provider: bangumiRecommendationsProvider,
          onTap: (title) => _triggerSearch(ref, title),
        ),
        _RecommendationSection(
          title: '影视区',
          subtitle: '猫眼全网热度榜，点击后自动跳转搜索',
          provider: maoyanRecommendationsProvider,
          onTap: (title) => _triggerSearch(ref, title),
          brandedPlaceholder: true,
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

class _RecommendationSection extends ConsumerWidget {
  const _RecommendationSection({
    required this.title,
    required this.subtitle,
    required this.provider,
    required this.onTap,
    this.brandedPlaceholder = false,
  });

  final String title;
  final String subtitle;
  final FutureProvider<List<_HomeRecommendationItem>> provider;
  final ValueChanged<String> onTap;
  final bool brandedPlaceholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return async.when(
      loading: () => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _SectionLoading(title: title, subtitle: subtitle),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _SectionError(
            title: title,
            subtitle: subtitle,
            error: '$error',
            showNetworkGuide: looksLikeNetworkPermissionIssue(error),
          ),
        ),
      ),
      data: (items) => SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 154,
                childAspectRatio: 0.62,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return GestureDetector(
                  onTap: () => onTap(item.title),
                  child: _RecommendationCard(
                    item: item,
                    brandedPlaceholder: brandedPlaceholder,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.item,
    required this.brandedPlaceholder,
  });

  final _HomeRecommendationItem item;
  final bool brandedPlaceholder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                ? Image.network(
                    item.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _PosterFallback(
                      title: item.title,
                      branded: brandedPlaceholder,
                    ),
                  )
                : _PosterFallback(
                    title: item.title,
                    branded: brandedPlaceholder,
                  ),
          ),
          Container(
            color: colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle?.isNotEmpty == true
                      ? item.subtitle!
                      : item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({
    required this.title,
    required this.branded,
  });

  final String title;
  final bool branded;

  @override
  Widget build(BuildContext context) {
    final seed = title.isEmpty ? 0 : title.codeUnitAt(0);
    final colors = branded
        ? const [Color(0xFF181E2A), Color(0xFF4A1F1F)]
        : const [Color(0xFF183B56), Color(0xFF101820)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.first.withValues(alpha: 0.94),
            Color.lerp(colors.first, colors.last, (seed % 7) / 10 + 0.2)!,
            colors.last.withValues(alpha: 0.98),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            top: -6,
            child: Icon(
              branded ? Icons.local_movies_rounded : Icons.animation_rounded,
              size: 72,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.title,
    required this.subtitle,
    required this.error,
    required this.showNetworkGuide,
  });

  final String title;
  final String subtitle;
  final String error;
  final bool showNetworkGuide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.errorContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: colorScheme.error),
            ),
            if (showNetworkGuide) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => showNetworkPermissionGuideDialog(context),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('检查联网权限'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeRecommendationItem {
  const _HomeRecommendationItem({
    required this.title,
    required this.source,
    this.coverUrl,
    this.subtitle,
  });

  final String title;
  final String source;
  final String? coverUrl;
  final String? subtitle;

  _HomeRecommendationItem copyWith({
    String? title,
    String? source,
    String? coverUrl,
    String? subtitle,
  }) {
    return _HomeRecommendationItem(
      title: title ?? this.title,
      source: source ?? this.source,
      coverUrl: coverUrl ?? this.coverUrl,
      subtitle: subtitle ?? this.subtitle,
    );
  }
}

String _normalizeUrl(String url) {
  if (url.startsWith('//')) {
    return 'https:$url';
  }
  return url;
}

String _cleanHtmlText(String text) {
  final withoutTags = text.replaceAll(RegExp(r'<[^>]+>'), '');
  return withoutTags
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', '\'')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}
