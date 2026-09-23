import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv_config_shared.dart';
import '../../../../core/constants/tmdb_apis.dart';
/// Pestaña Contenido — StatefulWidget independiente.
class ContenidoTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const ContenidoTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<ContenidoTab> createState() => ContenidoTabState();
}

class ContenidoTabState extends State<ContenidoTab>
    with AutomaticKeepAliveClientMixin {
  bool _tmdbEnrichment = true;
  bool _allowAdultContent = false;
  bool _showUnreleased = false;
  bool _showSeasonSpecials = false;
  bool _showUnreleasedEpisodes = false;
  bool _homeSessions = true;
  bool _homeFeaturedMovies = true;
  bool _homePopularMovies = true;
  bool _homePopularSeries = true;
  bool _homeYearMovies = true;
  bool _homeFeaturedSeries = true;
  bool _homeYearSeries = true;
  bool _homeTrendingMovies = true;
  bool _homeTrendingSeries = true;
  bool _homeLatest = true;
  bool _regionalPeru = false;
  bool _spanishLatino = true;
  bool _spanishCastellano = false;
  bool _english = false;
  bool _disableNonLatinTitles = false;

  late final FocusNode _btnTmdbEnrichment;
  late final FocusNode _btnAdultContent;
  late final FocusNode _btnUnreleased;
  late final FocusNode _btnSeasonSpecials;
  late final FocusNode _btnUnreleasedEpisodes;
  late final FocusNode _btnHomeSessions;
  late final FocusNode _btnHomeFeaturedMovies;
  late final FocusNode _btnHomePopularMovies;
  late final FocusNode _btnHomePopularSeries;
  late final FocusNode _btnHomeYearMovies;
  late final FocusNode _btnHomeFeaturedSeries;
  late final FocusNode _btnHomeYearSeries;
  late final FocusNode _btnHomeTrendingMovies;
  late final FocusNode _btnHomeTrendingSeries;
  late final FocusNode _btnHomeLatest;
  late final FocusNode _btnRegionalPeru;
  late final FocusNode _btnSpanishLatino;
  late final FocusNode _btnSpanishCastellano;
  late final FocusNode _btnEnglish;
  late final FocusNode _btnDisableNonLatin;

  FocusNode get firstFocusNode => _btnTmdbEnrichment;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnTmdbEnrichment = FocusNode(debugLabel: 'cfg_tmdb');
    _btnAdultContent = FocusNode(debugLabel: 'cfg_adult');
    _btnUnreleased = FocusNode(debugLabel: 'cfg_unreleased');
    _btnSeasonSpecials = FocusNode(debugLabel: 'cfg_season_specials');
    _btnUnreleasedEpisodes = FocusNode(debugLabel: 'cfg_unreleased_episodes');
    _btnHomeSessions = FocusNode(debugLabel: 'cfg_home_sessions');
    _btnHomeFeaturedMovies = FocusNode(debugLabel: 'cfg_home_featured_movies');
    _btnHomePopularMovies = FocusNode(debugLabel: 'cfg_home_popular_movies');
    _btnHomePopularSeries = FocusNode(debugLabel: 'cfg_home_popular_series');
    _btnHomeYearMovies = FocusNode(debugLabel: 'cfg_home_year_movies');
    _btnHomeFeaturedSeries = FocusNode(debugLabel: 'cfg_home_featured_series');
    _btnHomeYearSeries = FocusNode(debugLabel: 'cfg_home_year_series');
    _btnHomeTrendingMovies = FocusNode(debugLabel: 'cfg_home_trending_movies');
    _btnHomeTrendingSeries = FocusNode(debugLabel: 'cfg_home_trending_series');
    _btnHomeLatest = FocusNode(debugLabel: 'cfg_home_latest');
    _btnRegionalPeru = FocusNode(debugLabel: 'cfg_regional_peru');
    _btnSpanishLatino = FocusNode(debugLabel: 'cfg_spanish_latino');
    _btnSpanishCastellano = FocusNode(debugLabel: 'cfg_spanish_castellano');
    _btnEnglish = FocusNode(debugLabel: 'cfg_english');
    _btnDisableNonLatin = FocusNode(debugLabel: 'cfg_disable_non_latin');
    _loadSettings();
  }

  @override
  void dispose() {
    _btnTmdbEnrichment.dispose();
    _btnAdultContent.dispose();
    _btnUnreleased.dispose();
    _btnSeasonSpecials.dispose();
    _btnUnreleasedEpisodes.dispose();
    _btnHomeSessions.dispose();
    _btnHomeFeaturedMovies.dispose();
    _btnHomePopularMovies.dispose();
    _btnHomePopularSeries.dispose();
    _btnHomeYearMovies.dispose();
    _btnHomeFeaturedSeries.dispose();
    _btnHomeYearSeries.dispose();
    _btnHomeTrendingMovies.dispose();
    _btnHomeTrendingSeries.dispose();
    _btnHomeLatest.dispose();
    _btnRegionalPeru.dispose();
    _btnSpanishLatino.dispose();
    _btnSpanishCastellano.dispose();
    _btnEnglish.dispose();
    _btnDisableNonLatin.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tmdbEnrichment = prefs.getBool('tmdb_enrichment') ?? true;
      _allowAdultContent = prefs.getBool('allow_adult_content') ?? false;
      _showUnreleased = prefs.getBool('show_unreleased') ?? false;
      _showSeasonSpecials = prefs.getBool('show_season_specials') ?? false;
      _showUnreleasedEpisodes =
          prefs.getBool('show_unreleased_episodes') ?? false;
      _homeSessions = prefs.getBool('home_sessions') ?? true;
      _homeFeaturedMovies = prefs.getBool('home_featured_movies') ?? true;
      _homePopularMovies = prefs.getBool('home_popular_movies') ?? true;
      _homePopularSeries = prefs.getBool('home_popular_series') ?? true;
      _homeYearMovies = prefs.getBool('home_year_movies') ?? true;
      _homeFeaturedSeries = prefs.getBool('home_featured_series') ?? true;
      _homeYearSeries = prefs.getBool('home_year_series') ?? true;
      _homeTrendingMovies = prefs.getBool('home_trending_movies') ?? true;
      _homeTrendingSeries = prefs.getBool('home_trending_series') ?? true;
      _homeLatest = prefs.getBool('home_latest') ?? true;
      _regionalPeru = prefs.getBool('regional_peru') ?? false;
      _spanishLatino = prefs.getBool('spanish_latino') ?? true;
      _spanishCastellano = prefs.getBool('spanish_castellano') ?? false;
      _english = prefs.getBool('english') ?? false;
      if (_spanishLatino) {
        _spanishCastellano = false;
        _english = false;
      } else if (_spanishCastellano) {
        _english = false;
      } else if (!_english) {
        _spanishLatino = true;
      }
      _disableNonLatinTitles =
          prefs.getBool('disable_non_latin_titles') ?? false;
    });
  }

  Future<void> _set(String key, bool value, void Function(bool) apply) async {
    await saveBool(key, value);
    if (!mounted) return;
    setState(() => apply(value));
  }

  Future<void> _setHomeSession(String key, bool value) async {
    await saveBool(key, value);
    if (!mounted) return;
    setState(() {
      switch (key) {
        case 'home_sessions':
          _homeSessions = value;
          break;
        case 'home_featured_movies':
          _homeFeaturedMovies = value;
          break;
        case 'home_popular_movies':
          _homePopularMovies = value;
          break;
        case 'home_popular_series':
          _homePopularSeries = value;
          break;
        case 'home_year_movies':
          _homeYearMovies = value;
          break;
        case 'home_featured_series':
          _homeFeaturedSeries = value;
          break;
        case 'home_year_series':
          _homeYearSeries = value;
          break;
        case 'home_trending_movies':
          _homeTrendingMovies = value;
          break;
        case 'home_trending_series':
          _homeTrendingSeries = value;
          break;
        case 'home_latest':
          _homeLatest = value;
          break;
      }
    });
  }

  Future<void> _setRegionalPeru(bool value) async {
    await saveBool('regional_peru', value);
    await saveBool('regional_filter', value);
    if (!mounted) return;
    setState(() => _regionalPeru = value);
  }

  /// Solo un idioma de metadatos / API TMDB.
  Future<void> _setMetadataLanguage(String which) async {
    final latino = which == 'latino';
    final cast = which == 'castellano';
    final eng = which == 'english';
    await saveBool('spanish_latino', latino);
    await saveBool('spanish_castellano', cast);
    await saveBool('english', eng);
    if (latino) await TmdbApis.setLanguage('es-MX');
    if (cast) await TmdbApis.setLanguage('es-ES');
    if (eng) await TmdbApis.setLanguage('en-US');
    if (!mounted) return;
    setState(() {
      _spanishLatino = latino;
      _spanishCastellano = cast;
      _english = eng;
    });
  }

  void requestFirstFocus() => _btnTmdbEnrichment.requestFocus();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('GENERAL', first: true),
        SourceToggleCard(
          title: 'Enriquecimiento TMDB',
          subtitleEnabled: 'Logos e info extra desde TMDB',
          subtitleDisabled: 'Sin logos / enrich extra',
          enabled: _tmdbEnrichment,
          loading: false,
          icon: Icons.auto_awesome_rounded,
          accentColor: const Color(0xFF8B5CF6),
          focusNode: _btnTmdbEnrichment,
          onTap: () => _set('tmdb_enrichment', !_tmdbEnrichment,
              (v) => _tmdbEnrichment = v),
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () => _btnAdultContent.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Contenido para adultos',
          subtitleEnabled: 'Se muestra contenido marcado como adulto',
          subtitleDisabled: 'Ocultar contenido adulto',
          enabled: _allowAdultContent,
          loading: false,
          icon: Icons.explicit_rounded,
          accentColor: const Color(0xFFEF4444),
          focusNode: _btnAdultContent,
          onTap: () => _set('allow_adult_content', !_allowAdultContent,
              (v) => _allowAdultContent = v),
          onArrowUp: () => _btnTmdbEnrichment.requestFocus(),
          onArrowDown: () => _btnUnreleased.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Sin estrenar (catálogo)',
          subtitleEnabled: 'Incluye estrenos futuros en listados',
          subtitleDisabled: 'Solo títulos ya disponibles',
          enabled: _showUnreleased,
          loading: false,
          icon: Icons.upcoming_rounded,
          accentColor: const Color(0xFF14B8A6),
          focusNode: _btnUnreleased,
          onTap: () => _set(
              'show_unreleased', !_showUnreleased, (v) => _showUnreleased = v),
          onArrowUp: () => _btnAdultContent.requestFocus(),
          onArrowDown: () => _btnSeasonSpecials.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Temporadas especiales (T0)',
          subtitleEnabled: 'Muestra temporada 0 / especiales',
          subtitleDisabled: 'Oculta temporada 0 y especiales',
          enabled: _showSeasonSpecials,
          loading: false,
          icon: Icons.folder_special_rounded,
          accentColor: const Color(0xFFA855F7),
          focusNode: _btnSeasonSpecials,
          onTap: () => _set('show_season_specials', !_showSeasonSpecials,
              (v) => _showSeasonSpecials = v),
          onArrowUp: () => _btnUnreleased.requestFocus(),
          onArrowDown: () => _btnUnreleasedEpisodes.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Capítulos sin estrenar',
          subtitleEnabled: 'Incluye episodios con fecha futura',
          subtitleDisabled: 'Solo episodios ya emitidos',
          enabled: _showUnreleasedEpisodes,
          loading: false,
          icon: Icons.event_busy_rounded,
          accentColor: const Color(0xFFEC4899),
          focusNode: _btnUnreleasedEpisodes,
          onTap: () => _set('show_unreleased_episodes', !_showUnreleasedEpisodes,
              (v) => _showUnreleasedEpisodes = v),
          onArrowUp: () => _btnSeasonSpecials.requestFocus(),
          onArrowDown: () => _btnRegionalPeru.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Filtro regional',
          subtitleEnabled: 'Excluye asiático / indio / ruso',
          subtitleDisabled: 'Sin filtro por idioma original',
          enabled: _regionalPeru,
          loading: false,
          icon: Icons.public_rounded,
          accentColor: const Color(0xFF0EA5E9),
          focusNode: _btnRegionalPeru,
          onTap: () => _setRegionalPeru(!_regionalPeru),
          onArrowUp: () => _btnUnreleasedEpisodes.requestFocus(),
          onArrowDown: () => _btnDisableNonLatin.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Ocultar títulos no latinos',
          subtitleEnabled: 'Solo títulos mayormente latinos',
          subtitleDisabled: 'Mostrar todos los títulos',
          enabled: _disableNonLatinTitles,
          loading: false,
          icon: Icons.translate_rounded,
          accentColor: const Color(0xFF64748B),
          focusNode: _btnDisableNonLatin,
          onTap: () => _set('disable_non_latin_titles', !_disableNonLatinTitles,
              (v) => _disableNonLatinTitles = v),
          onArrowUp: () => _btnRegionalPeru.requestFocus(),
          onArrowDown: () => _btnSpanishLatino.requestFocus(),
        ),
        sectionTitle('IDIOMA DE METADATOS (solo uno)'),
        SourceToggleCard(
          title: 'Español latino',
          subtitleEnabled: 'API TMDB es-MX (activo)',
          subtitleDisabled: 'Toca para activar',
          enabled: _spanishLatino,
          loading: false,
          icon: Icons.language_rounded,
          accentColor: const Color(0xFF22C55E),
          focusNode: _btnSpanishLatino,
          onTap: () => _setMetadataLanguage('latino'),
          onArrowUp: () => _btnDisableNonLatin.requestFocus(),
          onArrowDown: () => _btnSpanishCastellano.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Español castellano',
          subtitleEnabled: 'API TMDB es-ES (activo)',
          subtitleDisabled: 'Toca para activar',
          enabled: _spanishCastellano,
          loading: false,
          icon: Icons.language_rounded,
          accentColor: const Color(0xFF3B82F6),
          focusNode: _btnSpanishCastellano,
          onTap: () => _setMetadataLanguage('castellano'),
          onArrowUp: () => _btnSpanishLatino.requestFocus(),
          onArrowDown: () => _btnEnglish.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Inglés',
          subtitleEnabled: 'API TMDB en-US (activo)',
          subtitleDisabled: 'Toca para activar',
          enabled: _english,
          loading: false,
          icon: Icons.language_rounded,
          accentColor: const Color(0xFFF59E0B),
          focusNode: _btnEnglish,
          onTap: () => _setMetadataLanguage('english'),
          onArrowUp: () => _btnSpanishCastellano.requestFocus(),
          onArrowDown: () => _btnHomeSessions.requestFocus(),
        ),
        sectionTitle('SECCIONES DEL HOME'),
        SourceToggleCard(
          title: 'Continuar viendo',
          subtitleEnabled: 'Sesiones / historial en home',
          subtitleDisabled: 'Oculto en home',
          enabled: _homeSessions,
          loading: false,
          icon: Icons.history_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeSessions,
          onTap: () => _setHomeSession('home_sessions', !_homeSessions),
          onArrowUp: () => _btnEnglish.requestFocus(),
          onArrowDown: () => _btnHomeFeaturedMovies.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Destacadas (películas)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeFeaturedMovies,
          loading: false,
          icon: Icons.star_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeFeaturedMovies,
          onTap: () =>
              _setHomeSession('home_featured_movies', !_homeFeaturedMovies),
          onArrowUp: () => _btnHomeSessions.requestFocus(),
          onArrowDown: () => _btnHomePopularMovies.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Populares (películas)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homePopularMovies,
          loading: false,
          icon: Icons.local_fire_department_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomePopularMovies,
          onTap: () =>
              _setHomeSession('home_popular_movies', !_homePopularMovies),
          onArrowUp: () => _btnHomeFeaturedMovies.requestFocus(),
          onArrowDown: () => _btnHomePopularSeries.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Populares (series)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homePopularSeries,
          loading: false,
          icon: Icons.local_fire_department_outlined,
          accentColor: kConfigAccent,
          focusNode: _btnHomePopularSeries,
          onTap: () =>
              _setHomeSession('home_popular_series', !_homePopularSeries),
          onArrowUp: () => _btnHomePopularMovies.requestFocus(),
          onArrowDown: () => _btnHomeYearMovies.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Por año (películas)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeYearMovies,
          loading: false,
          icon: Icons.calendar_month_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeYearMovies,
          onTap: () => _setHomeSession('home_year_movies', !_homeYearMovies),
          onArrowUp: () => _btnHomePopularSeries.requestFocus(),
          onArrowDown: () => _btnHomeFeaturedSeries.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Destacadas (series)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeFeaturedSeries,
          loading: false,
          icon: Icons.star_outline_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeFeaturedSeries,
          onTap: () =>
              _setHomeSession('home_featured_series', !_homeFeaturedSeries),
          onArrowUp: () => _btnHomeYearMovies.requestFocus(),
          onArrowDown: () => _btnHomeYearSeries.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Por año (series)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeYearSeries,
          loading: false,
          icon: Icons.date_range_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeYearSeries,
          onTap: () => _setHomeSession('home_year_series', !_homeYearSeries),
          onArrowUp: () => _btnHomeFeaturedSeries.requestFocus(),
          onArrowDown: () => _btnHomeTrendingMovies.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Tendencias (películas)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeTrendingMovies,
          loading: false,
          icon: Icons.trending_up_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeTrendingMovies,
          onTap: () =>
              _setHomeSession('home_trending_movies', !_homeTrendingMovies),
          onArrowUp: () => _btnHomeYearSeries.requestFocus(),
          onArrowDown: () => _btnHomeTrendingSeries.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Tendencias (series)',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeTrendingSeries,
          loading: false,
          icon: Icons.trending_up_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeTrendingSeries,
          onTap: () =>
              _setHomeSession('home_trending_series', !_homeTrendingSeries),
          onArrowUp: () => _btnHomeTrendingMovies.requestFocus(),
          onArrowDown: () => _btnHomeLatest.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Últimos / recientes',
          subtitleEnabled: 'Visible en home',
          subtitleDisabled: 'Oculto',
          enabled: _homeLatest,
          loading: false,
          icon: Icons.new_releases_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnHomeLatest,
          onTap: () => _setHomeSession('home_latest', !_homeLatest),
          onArrowUp: () => _btnHomeTrendingSeries.requestFocus(),
          onArrowDown: () {},
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
