// lib/fuentes/apis/home/registry.dart
//
// ÚNICO lugar donde se registran las fuentes.
// Para agregar una fuente nueva:
//   1. Implementa el scraper (fetch) y/o el parser de búsqueda (en buscador.dart).
//   2. Añade una entrada Fuente aquí.
//   3. pag.dart la usa automáticamente — no hace falta tocarlo.

import 'scraper_context.dart';
import '../home/serieskao_scraper.dart';
import '../home/tioplus_scraper.dart';
import '../home/cuevana_scraper.dart';
import '../home/pelisplus_scraper.dart';
import 'buscador.dart';
/// Todas las fuentes disponibles (listado + búsqueda).
final List<Fuente> fuentesRegistry = [
  // ── SeriesKao ──────────────────────────────────────────────────────────
  Fuente(
    id: 'serieskao',
    label: 'SeriesKao',
    tipos: SeriesKaoScraper.tiposDisponibles(),
    generos: SeriesKaoScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return SeriesKaoScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        populares: populares,
        page: page,
      );
    },
    search: BuscadorScraper.searchSeriesKao,
  ),

  // ── TioPlus ────────────────────────────────────────────────────────────
  Fuente(
    id: 'tioplus',
    label: 'TioPlus',
    tipos: TioPlusScraper.tiposDisponibles(),
    generos: const [
      'accion',
      'drama',
      'comedia',
      'terror',
      'romance',
      'ciencia-ficcion',
    ],
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return TioPlusScraper.fetch(
        tipo: tipo ?? 'movie',
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchTioPlus,
  ),

  // ── Cuevana ────────────────────────────────────────────────────────────
  Fuente(
    id: 'cuevana',
    label: 'Cuevana',
    tipos: CuevanaScraper.tiposDisponibles(),
    generos: CuevanaScraper.generos,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return CuevanaScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchCuevana,
  ),

  // ── PelisPlus ──────────────────────────────────────────────────────────
  Fuente(
    id: 'pelisplus',
    label: 'PelisPlus',
    tipos: PelisPlusScraper.tiposDisponibles(),
    generos: PelisPlusScraper.generos,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return PelisPlusScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchPelisPlus,
  ),

  // ── CineHax (solo búsqueda) ────────────────────────────────────────────
  Fuente(
    id: 'cinehax',
    label: 'CineHax',
    tipos: const ['movie', 'tv'],
    generos: const [],
    hasListing: false,
    hasSearch: true,
    search: BuscadorScraper.searchCineHax,
  ),
];

/// Fuentes que tienen listado (aparecen en el selector de servicio).
List<Fuente> get fuentesConListado =>
    fuentesRegistry.where((f) => f.hasListing).toList();

/// Fuentes que tienen búsqueda (aparecen en el filtro de búsqueda).
List<Fuente> get fuentesConBusqueda =>
    fuentesRegistry.where((f) => f.hasSearch).toList();

/// Busca una fuente por id.
Fuente? fuenteById(String id) {
  try {
    return fuentesRegistry.firstWhere((f) => f.id == id);
  } catch (_) {
    return null;
  }
}

/// API pública de búsqueda (usa el registry).
/// [tipo] = 'todas' | id de fuente (serieskao, cuevana, tioplus, cinehax, pelisplus, ...)
Future<BuscadorResult> buscarEnFuentes({
  required String q,
  String tipo = 'todas',
}) async {
  final query = q.trim();
  if (query.isEmpty) {
    return BuscadorResult(ok: false, error: 'Escribe algo para buscar');
  }

  final aBuscar = tipo == 'todas'
      ? fuentesConBusqueda
      : fuentesConBusqueda.where((f) => f.id == tipo).toList();

  if (aBuscar.isEmpty) {
    return BuscadorResult(
      ok: false,
      error: 'Fuente de búsqueda no encontrada: $tipo',
    );
  }

  final resultados = <String, List<BuscadorItem>>{};
  int total = 0;

  for (final fuente in aBuscar) {
    List<BuscadorItem> items = [];
    try {
      if (fuente.search != null) {
        items = await fuente.search!(query);
      }
    } catch (_) {
      items = [];
    }
    resultados[fuente.id] = items;
    total += items.length;
  }

  return BuscadorResult(
    ok: true,
    query: query,
    tipo: tipo,
    total: total,
    resultados: resultados,
  );
}