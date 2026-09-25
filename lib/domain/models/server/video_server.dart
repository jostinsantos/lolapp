class VideoServer {
  final String id;
  final String name;
  final String? language;
  final String? quality;
  const VideoServer({required this.id, required this.name, this.language, this.quality});
}
