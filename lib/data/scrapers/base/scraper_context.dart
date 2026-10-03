// lib/fuentes/apis/home/fuente.dart
import 'base_home_scraper.dart';
import 'buscador.dart';
/// Configuración de una fuente (sitio de streaming).
///
/// Para agregar una fuente nueva:
/// 1. Crea el scraper (fetch / search) en su archivo.
/// 2. Añade una entrada en [fuentesRegistry] (o en el archivo de la fuente
///    y expórtala desde registry.dart).
/// 3. No hace falta tocar pag.dart.
class Fuente {
  /// Identificador único (minúsculas, sin espacios). Se usa en URLs, badges, etc.
  final String id;

  /// Nombre visible en la UI.
  final String label;

  /// Tipos que soporta para listado: movie, tv, anime, dorama, tendencias, episodios...
  final List<String> tipos;

  /// Géneros disponibles (slugs). Lista vacía = no hay filtro por género.
  final List<String> generos;

  /// Si true, el primer "género" vacío puede alternar a "Populares" (SeriesKao).
  final bool supportsPopulares;

  /// Si true, aparece en el selector de servicio (listado).
  final bool hasListing;

  /// Si true, aparece en el filtro de búsqueda.
  final bool hasSearch;

  /// Carga de listado. Solo se llama si [hasListing] es true.
  final Future<ScraperResult> Function({
    String? tipo,
    String? genero,
    bool populares,
    int page,
  })? fetch;

  /// Búsqueda por texto. Solo se llama si [hasSearch] es true.
  final Future<List<BuscadorItem>> Function(String q)? search;

  const Fuente({
    required this.id,
    required this.label,
    this.tipos = const ['movie', 'tv'],
    this.generos = const [],
    this.supportsPopulares = false,
    this.hasListing = true,
    this.hasSearch = true,
    this.fetch,
    this.search,
  });

  /// Etiqueta legible de un tipo.
  static String tipoLabel(String tipo) {
    switch (tipo) {
      case 'movie':
      case 'pelicula':
        return 'Películas';
      case 'tv':
      case 'serie':
        return 'Series';
      case 'anime':
        return 'Animes';
      case 'dorama':
        return 'Doramas';
      case 'ova':
        return 'OVAs';
      case 'ona':
        return 'ONAs';
      case 'especial':
        return 'Especiales';
      case 'tendencias':
        return 'Tendencias';
      case 'episodios':
        return 'Episodios';
      default:
        return tipo;
    }
  }

  /// Etiqueta legible de un género (slug).
  static String generoLabel(String genero) {
    if (genero.isEmpty) return 'Recientes';
    return genero
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}