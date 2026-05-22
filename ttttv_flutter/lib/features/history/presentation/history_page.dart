import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../player/application/resume_play_launcher.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No watch history yet'));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(historyItemsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    title: Text(item.vodName),
                    subtitle: Text(
                      [
                        item.sourceKey,
                        _episodeLabel(item),
                      ].join(' / '),
                    ),
                    trailing: Text('${item.progress.round()}s'),
                    onTap: () =>
                        unawaited(openPlayerFromHistory(context, ref, item)),
                  ),
                );
              },
            ),
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  String _episodeLabel(WatchHistoryItem item) {
    if (item.episodeIndex != null) {
      return '第${item.episodeIndex! + 1}集';
    }
    if (item.episode != null && item.episode!.isNotEmpty) {
      return item.episode!;
    }
    return '单集';
  }
}
