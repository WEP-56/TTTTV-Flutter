import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/platform/platform_window.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';
import '../data/douban_repository.dart';

/// Bangumi 新番日历页面。
///
/// 参考 luna-tv-fork 的动漫"每日放送"模式：
/// - 顶部星期选择器（周一 ~ 周日），默认选中今天
/// - 下方网格展示当天的番剧
/// - 点击卡片触发搜索
class BangumiCalendarPage extends ConsumerStatefulWidget {
  const BangumiCalendarPage({super.key});

  @override
  ConsumerState<BangumiCalendarPage> createState() =>
      _BangumiCalendarPageState();
}

class _BangumiCalendarPageState extends ConsumerState<BangumiCalendarPage> {
  static const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  // Bangumi API weekday.en: Mon, Tue, Wed, Thu, Fri, Sat, Sun
  static const _weekdayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late int _selectedDay; // 0-6 (Mon-Sun)
  Map<String, List<DoubanItem>>? _calendarData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // DateTime.weekday: 1=Mon, 7=Sun → index 0-6
    _selectedDay = DateTime.now().weekday - 1;
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(nativeVodDioProvider);
      final repo = DoubanRepository(dio: dio);
      final allItems = await repo.fetchBangumiCalendarFull();
      if (!mounted) return;
      setState(() {
        _calendarData = allItems;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _calendarData?[_weekdayKeys[_selectedDay]] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: PlatformDragToMoveArea(
          child: SizedBox(
            width: double.infinity,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('新番放送'),
            ),
          ),
        ),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _loadCalendar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 星期选择器
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '星期',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(7, (index) {
                        final isToday = index == DateTime.now().weekday - 1;
                        final isSelected = index == _selectedDay;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              _weekdayLabels[index],
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color:
                                    isToday && !isSelected ? cs.primary : null,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (_) =>
                                setState(() => _selectedDay = index),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 来源提示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '来自 Bangumi 番组计划',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          // 内容
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: cs.error),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: TextStyle(color: cs.error),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _loadCalendar,
                                child: const Text('重试')),
                          ],
                        ),
                      )
                    : items.isEmpty
                        ? const Center(child: Text('今日暂无新番'))
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140,
                              childAspectRatio: 0.56,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _AnimeCard(
                                item: item,
                                onTap: () => _openBangumiDetail(context, item),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

void _openBangumiDetail(BuildContext context, DoubanItem item) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailPage(
        initialItem: VodItem(
          sourceKey: '',
          vodId: '',
          vodName: item.title,
          vodPlayUrl: '',
          vodPic: item.poster,
          vodYear: item.year,
          vodRemarks: item.rate == null || item.rate!.isEmpty
              ? null
              : 'Bangumi ${item.rate}',
        ),
      ),
    ),
  );
}

class _AnimeCard extends StatelessWidget {
  const _AnimeCard({required this.item, required this.onTap});

  final DoubanItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.poster.isNotEmpty
                  ? Image.network(
                      item.poster,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.movie_outlined,
                            color: cs.onSurfaceVariant),
                      ),
                    )
                  : Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_outlined,
                          color: cs.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.rate != null && item.rate!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '⭐ ${item.rate}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
