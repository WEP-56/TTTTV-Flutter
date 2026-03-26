class BackendConfig {
  const BackendConfig({
    required this.baseUrl,
  });

  final String baseUrl;

  const BackendConfig.localhost() : baseUrl = 'http://127.0.0.1:5007';
}
