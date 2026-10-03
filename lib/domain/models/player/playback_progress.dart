class PlaybackProgress {
  final Duration position;
  final Duration duration;
  const PlaybackProgress({required this.position, required this.duration});
  double get fraction => duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;
}
