class PlaybackItem {
  final String title;
  final String? url;
  final String mediaType;
  final int? tmdbId;
  const PlaybackItem({required this.title, this.url, required this.mediaType, this.tmdbId});
}
