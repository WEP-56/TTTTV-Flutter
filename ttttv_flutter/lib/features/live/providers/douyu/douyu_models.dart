import '../../../../core/models/vod_models.dart';

class DouyuPlayMetadata {
  const DouyuPlayMetadata({
    required this.cdns,
    required this.qualities,
  });

  final List<String> cdns;
  final List<LivePlayQuality> qualities;
}
