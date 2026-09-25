import 'content.dart';
class Series extends Content {
  final int? numberOfSeasons;
  const Series({
    required super.id,
    required super.title,
    super.overview,
    super.posterPath,
    super.backdropPath,
    super.voteAverage,
    super.releaseDate,
    this.numberOfSeasons,
  }) : super(mediaType: 'tv');
}
