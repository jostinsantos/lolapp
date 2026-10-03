class WatchLater {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterPath;
  final DateTime addedAt;
  const WatchLater({required this.tmdbId, required this.mediaType, required this.title, this.posterPath, required this.addedAt});
}
