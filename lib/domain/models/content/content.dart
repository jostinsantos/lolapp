/// Base content model (movie / series).
class Content {
  final int id;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType; // movie | tv
  final double? voteAverage;
  final String? releaseDate;

  const Content({
    required this.id,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    this.voteAverage,
    this.releaseDate,
  });
}
