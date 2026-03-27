import 'live_provider.dart';

class LiveProviderRegistry {
  LiveProviderRegistry(List<LiveProvider> providers)
      : _providers = List.unmodifiable(providers),
        _providerMap = {
          for (final provider in providers) provider.id: provider,
        };

  final List<LiveProvider> _providers;
  final Map<String, LiveProvider> _providerMap;

  List<LiveProvider> get providers => _providers;

  List<LiveProviderDescriptor> get descriptors {
    return _providers.map((provider) => provider.descriptor).toList();
  }

  LiveProvider get first {
    if (_providers.isEmpty) {
      throw StateError('No live providers have been registered.');
    }
    return _providers.first;
  }

  LiveProvider of(String providerId) {
    return _providerMap[providerId] ?? first;
  }
}
