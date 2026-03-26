import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favoritesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No favorites yet'));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(favoriteItemsProvider.future),
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
                        if (item.vodRemarks != null) item.vodRemarks!,
                      ].join(' / '),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailPage(
                            initialItem: VodItem.fromFavorite(item),
                          ),
                        ),
                      );
                    },
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
}
