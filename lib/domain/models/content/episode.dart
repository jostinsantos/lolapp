class Episode {
  final int episodeNumber;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  const Episode({
    required this.episodeNumber,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.stillPath,
  });
}
