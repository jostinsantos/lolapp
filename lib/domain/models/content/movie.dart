import 'content.dart';
class Movie extends Content {
  const Movie({
    required super.id,
    required super.title,
    super.overview,
    super.posterPath,
    super.backdropPath,
    super.voteAverage,
    super.releaseDate,
  }) : super(mediaType: 'movie');
}
