class WatchHistory {
  final int tmdbId;
  final String mediaType;
  final String title;
  final Duration position;
  final Duration duration;
  final DateTime watchedAt;
  const WatchHistory({required this.tmdbId, required this.mediaType, required this.title, required this.position, required this.duration, required this.watchedAt});
}
