import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config_shared.dart';
import 'tmdb_api_options.dart';
class ContenidoSection {
  final VoidCallback refresh;
  
  // General
  final bool tmdbEnrichment;
  final bool allowAdultContent;
  final bool showUnreleased;
  final bool showSeasonSpecials;
  final bool showUnreleasedEpisodes;
  
  // Filtro regional
  final bool regionalFilter;
  
  // Idioma de metadatos
  final bool spanishLatino;
  final bool spanishCastellano;
  final bool english;
  final bool disableNonLatinTitles;
  
  // Secciones del home
  final bool homeSessions;
  final bool homeFeaturedMovies;
  final bool homePopularMovies;
  final bool homePopularSeries;
  final bool homeYearMovies;
  final bool homeFeaturedSeries;
  final bool homeYearSeries;
  final bool homeTrendingMovies;
  final bool homeTrendingSeries;
  final bool homeLatest;

  // Callbacks para guardar cambios
  final Function(String key, bool value) onChanged;

  ContenidoSection({
    required this.refresh,
    required this.tmdbEnrichment,
    required this.allowAdultContent,
    required this.showUnreleased,
    required this.showSeasonSpecials,
    required this.showUnreleasedEpisodes,
    required this.regionalFilter,
    required this.spanishLatino,
    required this.spanishCastellano,
    required this.english,
    required this.disableNonLatinTitles,
    required this.homeSessions,
    required this.homeFeaturedMovies,
    required this.homePopularMovies,
    required this.homePopularSeries,
    required this.homeYearMovies,
    required this.homeFeaturedSeries,
    required this.homeYearSeries,
    required this.homeTrendingMovies,
    required this.homeTrendingSeries,
    required this.homeLatest,
    required this.onChanged,
  });

  List<Widget> build() {
    return [
      const TmdbApiOptions(),
      _sectionHeader('GENERAL'),
      _buildToggleCard(
        title: 'Enriquecimiento TMDB',
        subtitleOn: 'Metadatos enriquecidos',
        subtitleOff: 'Desactivado',
        enabled: tmdbEnrichment,
        onChanged: (v) => _saveAndRefresh('tmdb_enrichment', v),
        icon: Icons.auto_awesome_rounded,
        accent: const Color(0xFF8B5CF6),
      ),
      _buildToggleCard(
        title: 'Contenido adulto',
        subtitleOn: 'Permitido',
        subtitleOff: 'Oculto',
        enabled: allowAdultContent,
        onChanged: (v) => _saveAndRefresh('allow_adult_content', v),
        icon: Icons.no_adult_content_rounded,
        accent: Colors.redAccent,
      ),
      _buildToggleCard(
        title: 'Mostrar no estrenados',
        subtitleOn: 'Películas/series futuras visibles',
        subtitleOff: 'Ocultos',
        enabled: showUnreleased,
        onChanged: (v) => _saveAndRefresh('show_unreleased', v),
        icon: Icons.upcoming_rounded,
      ),
      _buildToggleCard(
        title: 'Especiales de temporada',
        subtitleOn: 'Visibles',
        subtitleOff: 'Ocultos',
        enabled: showSeasonSpecials,
        onChanged: (v) => _saveAndRefresh('show_season_specials', v),
        icon: Icons.star_border_rounded,
      ),
      _buildToggleCard(
        title: 'Episodios no estrenados',
        subtitleOn: 'Visibles',
        subtitleOff: 'Ocultos',
        enabled: showUnreleasedEpisodes,
        onChanged: (v) => _saveAndRefresh('show_unreleased_episodes', v),
        icon: Icons.event_busy_rounded,
      ),
      
      _sectionHeader('FILTRO REGIONAL'),
      _buildToggleCard(
        title: 'Filtro regional (Perú)',
        subtitleOn: 'Activado',
        subtitleOff: 'Desactivado',
        enabled: regionalFilter,
        onChanged: (v) => _saveAndRefresh('regional_filter', v),
        icon: Icons.public_rounded,
        accent: const Color(0xFFEF4444),
      ),
      
      _sectionHeader('IDIOMA DE METADATOS (solo uno)'),
      _buildToggleCard(
        title: 'Español Latino',
        subtitleOn: 'API TMDB en es-MX (activo)',
        subtitleOff: 'Toca para activar',
        enabled: spanishLatino,
        onChanged: (v) => _saveAndRefresh('spanish_latino', v),
        icon: Icons.language_rounded,
        accent: const Color(0xFF22C55E),
      ),
      _buildToggleCard(
        title: 'Español Castellano',
        subtitleOn: 'API TMDB en es-ES (activo)',
        subtitleOff: 'Toca para activar',
        enabled: spanishCastellano,
        onChanged: (v) => _saveAndRefresh('spanish_castellano', v),
        icon: Icons.language_rounded,
        accent: const Color(0xFF3B82F6),
      ),
      _buildToggleCard(
        title: 'Inglés',
        subtitleOn: 'API TMDB en en-US (activo)',
        subtitleOff: 'Toca para activar',
        enabled: english,
        onChanged: (v) => _saveAndRefresh('english', v),
        icon: Icons.language_rounded,
        accent: const Color(0xFFF59E0B),
      ),
      _buildToggleCard(
        title: 'Desactivar títulos no latinos',
        subtitleOn: 'Solo títulos latinos',
        subtitleOff: 'Todos los títulos',
        enabled: disableNonLatinTitles,
        onChanged: (v) => _saveAndRefresh('disable_non_latin_titles', v),
        icon: Icons.translate_rounded,
      ),
      
      _sectionHeader('SECCIONES DEL HOME'),
      _buildToggleCard(
        title: 'Continuar viendo',
        subtitleOn: 'Sesiones / historial en home',
        subtitleOff: 'Oculto en home',
        enabled: homeSessions,
        onChanged: (v) => _saveAndRefresh('home_sessions', v),
        icon: Icons.history_rounded,
      ),
      _buildToggleCard(
        title: 'Destacadas (películas)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeFeaturedMovies,
        onChanged: (v) => _saveAndRefresh('home_featured_movies', v),
        icon: Icons.star_rounded,
      ),
      _buildToggleCard(
        title: 'Populares (películas)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homePopularMovies,
        onChanged: (v) => _saveAndRefresh('home_popular_movies', v),
        icon: Icons.local_fire_department_rounded,
      ),
      _buildToggleCard(
        title: 'Populares (series)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homePopularSeries,
        onChanged: (v) => _saveAndRefresh('home_popular_series', v),
        icon: Icons.local_fire_department_outlined,
      ),
      _buildToggleCard(
        title: 'Por año (películas)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeYearMovies,
        onChanged: (v) => _saveAndRefresh('home_year_movies', v),
        icon: Icons.calendar_month_rounded,
      ),
      _buildToggleCard(
        title: 'Destacadas (series)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeFeaturedSeries,
        onChanged: (v) => _saveAndRefresh('home_featured_series', v),
        icon: Icons.star_outline_rounded,
      ),
      _buildToggleCard(
        title: 'Por año (series)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeYearSeries,
        onChanged: (v) => _saveAndRefresh('home_year_series', v),
        icon: Icons.date_range_rounded,
      ),
      _buildToggleCard(
        title: 'Tendencias (películas)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeTrendingMovies,
        onChanged: (v) => _saveAndRefresh('home_trending_movies', v),
        icon: Icons.trending_up_rounded,
      ),
      _buildToggleCard(
        title: 'Tendencias (series)',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeTrendingSeries,
        onChanged: (v) => _saveAndRefresh('home_trending_series', v),
        icon: Icons.trending_up_rounded,
      ),
      _buildToggleCard(
        title: 'Últimos / recientes',
        subtitleOn: 'Visible en home',
        subtitleOff: 'Oculto',
        enabled: homeLatest,
        onChanged: (v) => _saveAndRefresh('home_latest', v),
        icon: Icons.new_releases_rounded,
      ),
    ];
  }

  void _saveAndRefresh(String key, bool value) {
    onChanged(key, value);
    refresh();
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    Color accent = kAccentColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled 
                    ? accent.withValues(alpha: 0.15) 
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon, 
                color: enabled ? accent : Colors.white70, 
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? subtitleOn : subtitleOff,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: accent,
              activeTrackColor: accent.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}