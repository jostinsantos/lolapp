import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/sources.dart';
import '../../../core/constants/versiones.dart'; // ← VersionService

import 'config_shared.dart';
import 'content/content_section.dart';
import 'appearance/appearance_section.dart';
import 'player/player_section.dart';
import 'sources/sources_section.dart';
import 'cache/cache_section.dart';
import 'downloads/downloads_section.dart';
import 'supabase/supabase_section.dart';
import 'notifications/notifications_section.dart'; // Notificaciones
import '../../../presentation/mobile/mobile_shell.dart';
import '../../../core/constants/tmdb_apis.dart';
import '../../../supabase/supabase_config.dart';
import '../../profile/presentation/profile_selection_page.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  bool _loading = true;
  bool _loadingSettings = true;
  bool _supabaseActive = false;
  String? _supabaseUserName;
  String? _error;
  Map<String, dynamic>? _versionData;

  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  final Map<String, bool> _sourceEnabled = {};
  final Map<String, bool> _sourceLoading = {};

  bool _verificarServidores = true;
  bool _unServidorPorIdioma = true;
  bool _mostrarServidoresEnPlayer = true;
  bool _idiomaPredEnabled = false;
  IdiomaPred _idiomaPred = IdiomaPred.latino;

  FuenteSeleccion _seleccionFuente = FuenteSeleccion.manual;
  bool _reutilizarUltimoEnlace = false;

  bool _subsAlInicio = false;
  SubSize _subSize = SubSize.mediano;
  SubHeight _subHeight = SubHeight.media;
  bool _idmDownloadEnabled = false;

  bool _enableDownloads = true;
  bool _showDownloadButtonMain = true;
  bool _autoDirectDownload = false;
  IdiomaPred _downloadLanguage = IdiomaPred.latino;
  int _maxConcurrentDownloads = 2;

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
  bool _regionalFilter = false;
  bool _spanishLatino = true;
  bool _spanishCastellano = false;
  bool _english = false;
  bool _disableNonLatinTitles = false;

  int get _fuentesActivas => _sourceEnabled.values.where((v) => v).length;

  static const _socials = <_SocialItem>[
    _SocialItem(
      name: 'Instagram',
      url: 'https://instagram.com/lol_oficialapp',
      color: Color(0xFFE1306C),
      asset: 'assets/redes/instagram.png',
    ),
    _SocialItem(
      name: 'Telegram',
      url: 'https://t.me/lol_oficialapp',
      color: Color(0xFF0088CC),
      asset: 'assets/redes/telegram.png',
    ),
    _SocialItem(
      name: 'GitHub',
      url: 'https://github.com/lol-oficialapp',
      color: Color(0xFF8B949E),
      asset: 'assets/redes/github.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    for (final s in kRegisteredSources) {
      _sourceEnabled[s.id] = false;
      _sourceLoading[s.id] = true;
    }
    _checkVersion();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final s in kRegisteredSources) {
        _sourceEnabled[s.id] = prefs.getBool(s.prefsKey) ?? false;
        _sourceLoading[s.id] = false;
      }

      _verificarServidores = prefs.getBool('verificar_servidores') ?? true;
      _unServidorPorIdioma = prefs.getBool('un_servidor_por_idioma') ?? true;
      _mostrarServidoresEnPlayer =
          prefs.getBool('mostrar_servidores_player') ?? true;
      _idiomaPredEnabled =
          prefs.getBool('idioma_predeterminado_enabled') ?? false;

      final idiomaCode = prefs.getString('idioma_predeterminado') ?? 'es_MX';
      _idiomaPred = IdiomaPred.values.firstWhere(
        (e) => e.code == idiomaCode,
        orElse: () => IdiomaPred.latino,
      );

      _seleccionFuente = FuenteSeleccion.values.firstWhere(
        (e) => e.name == (prefs.getString('seleccion_fuente') ?? 'manual'),
        orElse: () => FuenteSeleccion.manual,
      );
      _reutilizarUltimoEnlace =
          prefs.getBool('reutilizar_ultimo_enlace') ?? false;

      _subsAlInicio = prefs.getBool('subtitulos_inicio') ?? false;
      final sizeCode = prefs.getString('subtitulo_tamano') ?? 'mediano';
      _subSize = SubSize.values.firstWhere(
        (e) => e.name == sizeCode,
        orElse: () => SubSize.mediano,
      );
      final heightCode = prefs.getString('subtitulo_altura') ?? 'media';
      _subHeight = SubHeight.values.firstWhere(
        (e) => e.name == heightCode,
        orElse: () => SubHeight.media,
      );
      _idmDownloadEnabled = prefs.getBool('idm_download_enabled') ?? false;

      _enableDownloads = prefs.getBool('enable_downloads') ?? true;
      _showDownloadButtonMain =
          prefs.getBool('show_download_button_main') ?? true;
      _autoDirectDownload = prefs.getBool('auto_direct_download') ?? false;
      _maxConcurrentDownloads =
          (prefs.getInt('max_concurrent_downloads') ?? 2).clamp(1, 5);

      final dlLangCode = prefs.getString('download_language') ?? 'es_MX';
      _downloadLanguage = IdiomaPred.values.firstWhere(
        (e) => e.code == dlLangCode,
        orElse: () => IdiomaPred.latino,
      );

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
      _regionalFilter = prefs.getBool('regional_filter') ??
          prefs.getBool('regional_peru') ??
          false;
      _spanishLatino = prefs.getBool('spanish_latino') ?? true;
      _spanishCastellano = prefs.getBool('spanish_castellano') ?? false;
      _english = prefs.getBool('english') ?? false;
      // Solo un idioma de metadatos activo
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

      _loadingSettings = false;
    });

    // Estado Supabase (para tarjeta Cambiar perfil)
    final sbActive = await SupabaseConfig.isSupabaseActive();
    final sbName = await SupabaseConfig.getCurrentUserName();
    if (mounted) {
      setState(() {
        _supabaseActive = sbActive;
        _supabaseUserName = sbName;
      });
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    String confirmLabel = 'Activar',
    Color accent = kAccentColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: kCardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _setSourceEnabled(SourceDefinition source, bool value) async {
    if (!mounted) return;
    setState(() => _sourceEnabled[source.id] = value);
    await _saveBool(source.prefsKey, value);
  }

  Future<void> _setVerificarServidores(bool value) async {
    if (value) {
      final ok = await _confirmDialog(
        title: 'Activar comprobación de servidores',
        body:
            'Se comprobará cada enlace antes de mostrarlo.\n\nEsto puede tomar más tiempo.',
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _verificarServidores = value);
    await _saveBool('verificar_servidores', value);
  }

  Future<void> _setUnServidorPorIdioma(bool value) async {
    if (!mounted) return;
    setState(() => _unServidorPorIdioma = value);
    await _saveBool('un_servidor_por_idioma', value);
  }

  Future<void> _setMostrarServidoresEnPlayer(bool value) async {
    if (!mounted) return;
    setState(() => _mostrarServidoresEnPlayer = value);
    await _saveBool('mostrar_servidores_player', value);
  }

  Future<void> _setIdiomaPredEnabled(bool value) async {
    if (value) {
      final ok = await _confirmDialog(
        title: 'Activar idioma predeterminado',
        body:
            'Al activar se elegirá automáticamente el idioma predeterminado para reproducir.\n\nSi "Mostrar lista de servidores en Player" está desactivado, se buscará un servidor de ese idioma y se abrirá el player directamente.',
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _idiomaPredEnabled = value);
    await _saveBool('idioma_predeterminado_enabled', value);
  }

  Future<void> _setIdiomaPred(IdiomaPred idioma) async {
    if (!mounted) return;
    setState(() => _idiomaPred = idioma);
    await _saveString('idioma_predeterminado', idioma.code);
  }

  Future<void> _setSeleccionFuente(FuenteSeleccion value) async {
    if (!mounted) return;
    setState(() => _seleccionFuente = value);
    await _saveString('seleccion_fuente', value.name);
  }

  Future<void> _setReutilizarUltimoEnlace(bool value) async {
    if (!mounted) return;
    setState(() => _reutilizarUltimoEnlace = value);
    await _saveBool('reutilizar_ultimo_enlace', value);
  }

  Future<void> _setSubsAlInicio(bool value) async {
    if (!mounted) return;
    setState(() => _subsAlInicio = value);
    await _saveBool('subtitulos_inicio', value);
  }

  Future<void> _setSubSize(SubSize size) async {
    if (!mounted) return;
    setState(() => _subSize = size);
    await _saveString('subtitulo_tamano', size.name);
  }

  Future<void> _setSubHeight(SubHeight height) async {
    if (!mounted) return;
    setState(() => _subHeight = height);
    await _saveString('subtitulo_altura', height.name);
  }

  Future<void> _setIdmDownloadEnabled(bool value) async {
    if (!mounted) return;
    setState(() => _idmDownloadEnabled = value);
    await _saveBool('idm_download_enabled', value);
  }

  Future<void> _setEnableDownloads(bool value) async {
    if (!mounted) return;
    setState(() => _enableDownloads = value);
    await _saveBool('enable_downloads', value);
    DownloadNavBus.bump();
  }

  Future<void> _setShowDownloadButtonMain(bool value) async {
    if (!mounted) return;
    setState(() => _showDownloadButtonMain = value);
    await _saveBool('show_download_button_main', value);
    DownloadNavBus.bump();
  }

  Future<void> _setAutoDirectDownload(bool value) async {
    if (value) {
      final ok = await _confirmDialog(
        title: 'Descarga directa automática',
        body:
            'Al activar, cuando haya un enlace directo disponible se iniciará la descarga automáticamente sin pedir confirmación.\n\n¿Deseas continuar?',
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _autoDirectDownload = value);
    await _saveBool('auto_direct_download', value);
  }

  Future<void> _setDownloadLanguage(IdiomaPred idioma) async {
    if (!mounted) return;
    setState(() => _downloadLanguage = idioma);
    await _saveString('download_language', idioma.code);
  }

  Future<void> _setMaxConcurrentDownloads(int value) async {
    final v = value.clamp(1, 5);
    if (!mounted) return;
    setState(() => _maxConcurrentDownloads = v);
    await _saveInt('max_concurrent_downloads', v);
  }

  Future<void> _setTmdbEnrichment(bool value) async {
    if (!mounted) return;
    setState(() => _tmdbEnrichment = value);
    await _saveBool('tmdb_enrichment', value);
  }

  Future<void> _setAllowAdultContent(bool value) async {
    if (!mounted) return;
    setState(() => _allowAdultContent = value);
    await _saveBool('allow_adult_content', value);
  }

  Future<void> _setShowUnreleased(bool value) async {
    if (!mounted) return;
    setState(() => _showUnreleased = value);
    await _saveBool('show_unreleased', value);
  }

  Future<void> _setShowSeasonSpecials(bool value) async {
    if (!mounted) return;
    setState(() => _showSeasonSpecials = value);
    await _saveBool('show_season_specials', value);
  }

  Future<void> _setShowUnreleasedEpisodes(bool value) async {
    if (!mounted) return;
    setState(() => _showUnreleasedEpisodes = value);
    await _saveBool('show_unreleased_episodes', value);
  }

  Future<void> _setHomeFlag(String key, bool value) async {
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
    await _saveBool(key, value);
  }

  Future<void> _setRegionalFilter(bool value) async {
    if (!mounted) return;
    setState(() => _regionalFilter = value);
    await _saveBool('regional_filter', value);
    await _saveBool('regional_peru', value);
  }

  /// Idioma de metadatos / API TMDB: solo uno activo.
  Future<void> _setMetadataLanguage(String which) async {
    if (!mounted) return;
    final latino = which == 'latino';
    final cast = which == 'castellano';
    final eng = which == 'english';
    setState(() {
      _spanishLatino = latino;
      _spanishCastellano = cast;
      _english = eng;
    });
    await _saveBool('spanish_latino', latino);
    await _saveBool('spanish_castellano', cast);
    await _saveBool('english', eng);
    // Sincronizar idioma real de la API TMDB
    if (latino) await TmdbApis.setLanguage('es-MX');
    if (cast) await TmdbApis.setLanguage('es-ES');
    if (eng) await TmdbApis.setLanguage('en-US');
  }

  Future<void> _setSpanishLatino(bool value) async {
    if (value) {
      await _setMetadataLanguage('latino');
    } else {
      // No permitir dejar todos apagados → volver a latino
      await _setMetadataLanguage('latino');
    }
  }

  Future<void> _setSpanishCastellano(bool value) async {
    if (value) {
      await _setMetadataLanguage('castellano');
    } else {
      await _setMetadataLanguage('latino');
    }
  }

  Future<void> _setEnglish(bool value) async {
    if (value) {
      await _setMetadataLanguage('english');
    } else {
      await _setMetadataLanguage('latino');
    }
  }

  Future<void> _setDisableNonLatinTitles(bool value) async {
    if (!mounted) return;
    setState(() => _disableNonLatinTitles = value);
    await _saveBool('disable_non_latin_titles', value);
  }

  void _onContenidoChanged(String key, bool value) {
    switch (key) {
      case 'tmdb_enrichment':
        _setTmdbEnrichment(value);
        break;
      case 'allow_adult_content':
        _setAllowAdultContent(value);
        break;
      case 'show_unreleased':
        _setShowUnreleased(value);
        break;
      case 'show_season_specials':
        _setShowSeasonSpecials(value);
        break;
      case 'show_unreleased_episodes':
        _setShowUnreleasedEpisodes(value);
        break;
      case 'regional_filter':
        _setRegionalFilter(value);
        break;
      case 'spanish_latino':
        _setSpanishLatino(value);
        break;
      case 'spanish_castellano':
        _setSpanishCastellano(value);
        break;
      case 'english':
        _setEnglish(value);
        break;
      case 'disable_non_latin_titles':
        _setDisableNonLatinTitles(value);
        break;
      case 'home_sessions':
      case 'home_featured_movies':
      case 'home_popular_movies':
      case 'home_popular_series':
      case 'home_year_movies':
      case 'home_featured_series':
      case 'home_year_series':
      case 'home_trending_movies':
      case 'home_trending_series':
      case 'home_latest':
        _setHomeFlag(key, value);
        break;
      default:
        _saveBool(key, value);
    }
  }

  Future<void> _switchToTv() async {
    final ok = await _confirmDialog(
      title: 'Cambiar a vista TV',
      body:
          'La aplicación se reiniciará para aplicar la interfaz optimizada para TV (orientación horizontal).\n\n¿Deseas continuar?',
      confirmLabel: 'Reiniciar ahora',
      accent: kAccentColor,
    );
    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'tv');

    if (!mounted) return;
    SystemNavigator.pop();
  }

  Future<void> _clearByPrefix(List<String> prefixes, String snackMsg) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) {
      return prefixes.any((p) => k.startsWith(p) || k == p);
    }).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor: kCardColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _clearHistorial() => _clearByPrefix([
        'cachePlayer_',
        'cachePlayerRapido_',
        'historial_',
      ], 'Historial borrado');

  Future<void> _clearGuardados() =>
      _clearByPrefix(['guardados_items', 'guardados_'], 'Guardados borrados');

  Future<void> _clearCacheServidores() =>
      _clearByPrefix(['serv_cache_'], 'Caché de servidores borrada');

  Future<void> _clearTodo() async {
    final ok = await _confirmDialog(
      title: 'Borrar todo',
      body:
          'Se eliminará historial, guardados, datos de reproducción y caché de servidores.\n\nLas configuraciones se conservan.',
      confirmLabel: 'Borrar todo',
      accent: Colors.redAccent,
    );
    if (ok != true) return;
    await _clearByPrefix([
      'cachePlayer_',
      'cachePlayerRapido_',
      'historial_',
      'guardados_items',
      'guardados_',
      'serv_cache_',
    ], 'Caché completa borrada');
  }

  Future<void> _openSocial(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri);
    } catch (e) {
      debugPrint('Error abriendo social: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
    }
  }

  // ==================== VERSIÓN (VersionService) ====================
  Future<void> _checkVersion() async {
    setState(() {
      _loading = true;
      _error = null;
      _downloadError = null;
    });

    try {
      final status = await VersionService.checkForUpdate();

      if (!mounted) return;

      if (status.latestVersion != null) {
        final v = status.latestVersion!;
        setState(() {
          _versionData = {
            'has_update': status.requiresUpdate,
            'is_required': status.isForceUpdate,
            'version_name': v.versionAceptada,
            'version_title': status.requiresUpdate
                ? 'Nueva versión ${v.versionAceptada}'
                : 'Estás al día',
            'version_description': v.novedades,
            'download_url': v.urlApk,
            'version_code': v.versionCodeAceptada,
          };
          _loading = false;
        });
      } else {
        setState(() {
          _versionData = {
            'has_update': false,
            'is_required': false,
            'version_name': VersionService.currentVersionName,
            'version_title': status.message,
            'version_description': '',
            'download_url': '',
            'version_code': VersionService.currentVersionCode,
          };
          _error = status.message.contains('No se pudo') ? 'Sin conexión' : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión';
        _loading = false;
        _versionData = {
          'has_update': false,
          'is_required': false,
          'version_name': VersionService.currentVersionName,
          'version_title': '',
          'version_description': '',
          'download_url': '',
          'version_code': VersionService.currentVersionCode,
        };
      });
    }
  }

  Future<void> _downloadAndInstallApk(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga');
      return;
    }

    if (!Platform.isAndroid) {
      await _openDownload(trimmed);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/lol_update.apk';
      final file = File(filePath);
      if (await file.exists()) await file.delete();

      final dio = Dio();
      await dio.download(
        trimmed,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (!mounted) return;

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        setState(() {
          _downloadError = result.message.isNotEmpty
              ? result.message
              : 'Activa “Instalar apps desconocidas” para esta app e inténtalo de nuevo.';
        });
      }
    } catch (e) {
      debugPrint('Error descarga APK: $e');
      if (mounted) {
        setState(() => _downloadError = 'Error al descargar: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openDownload(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error abriendo enlace: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
    }
  }

  void _openSection({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget Function(VoidCallback refresh) builder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setSectionState) {
            void refresh() {
              setSectionState(() {});
            }

            return _ConfigSectionPage(
              title: title,
              icon: icon,
              accent: accent,
              child: builder(refresh),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSocialRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _socials.length; i++) ...[
            if (i > 0) const SizedBox(width: 28),
            GestureDetector(
              onTap: () => _openSocial(_socials[i].url),
              behavior: HitTestBehavior.opaque,
              child: Image.asset(
                _socials[i].asset,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.link_rounded,
                  color: _socials[i].color,
                  size: 32,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    final hasUpdate = _versionData?['has_update'] == true;
    final isRequired = _versionData?['is_required'] == true;
    final latestName = _versionData?['version_name']?.toString() ?? '';
    final latestTitle = _versionData?['version_title']?.toString() ?? '';
    final description = _versionData?['version_description']?.toString() ?? '';
    final downloadUrl = _versionData?['download_url']?.toString() ?? '';

    final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
    final errorMsg = _downloadError ?? _error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUpdate
              ? (isRequired
                  ? kAccentColor.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15))
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasUpdate
                        ? kAccentColor.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasUpdate
                        ? Icons.system_update_rounded
                        : Icons.check_circle_outline_rounded,
                    color: hasUpdate ? kAccentColor : Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloading
                            ? (_downloadProgress > 0.02
                                ? 'Descargando $pct%'
                                : 'Descargando…')
                            : hasUpdate
                                ? (isRequired
                                    ? 'Actualización obligatoria'
                                    : 'Nueva versión disponible')
                                : 'Estás al día',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Versión actual: ${VersionService.currentVersionName} (${VersionService.currentVersionCode})',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasUpdate) ...[
            const Divider(color: Color(0xFF2C2C2E), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latestTitle.isNotEmpty
                        ? latestTitle
                        : 'Versión $latestName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v$latestName',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      description.replaceAll('\\n', '\n'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (errorMsg != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  errorMsg,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:
                        _downloadProgress > 0.02 ? _downloadProgress : null,
                    backgroundColor: Colors.white12,
                    color: kAccentColor,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_downloading || downloadUrl.isEmpty)
                      ? null
                      : () => _downloadAndInstallApk(downloadUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        kAccentColor.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _downloading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                value: _downloadProgress > 0.02
                                    ? _downloadProgress
                                    : null,
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _downloadProgress > 0.02
                                  ? 'Descargando $pct%'
                                  : 'Descargando…',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download_rounded, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Actualizar ahora',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ] else if (errorMsg != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                errorMsg,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final listBottomPad = 40.0 + bottomSafe + 72.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading && _loadingSettings
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              color: kAccentColor,
              backgroundColor: kCardColor,
              onRefresh: () async {
                await _checkVersion();
                await _loadAllSettings();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, 8, 16, listBottomPad),
                children: [
                  _buildSocialRow(),
                  if (_supabaseActive) ...[
                    const SizedBox(height: 8),
                    _buildSectionCard(
                      title: 'Cambiar perfil',
                      subtitle: _supabaseUserName != null
                          ? 'Perfil activo: $_supabaseUserName'
                          : 'Elige otro perfil de Supabase',
                      icon: Icons.switch_account_rounded,
                      accent: const Color(0xFF3ECF8E),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfileSelectionPage(
                              allowDismiss: true,
                              onProfileSelected: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        );
                        await _loadAllSettings();
                      },
                    ),
                  ],
                  _buildVersionCard(),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    title: 'Contenido',
                    subtitle:
                        'General, idioma de metadatos y secciones del home',
                    icon: Icons.movie_filter_rounded,
                    accent: const Color(0xFF8B5CF6),
                    onTap: () => _openSection(
                      title: 'Contenido',
                      icon: Icons.movie_filter_rounded,
                      accent: const Color(0xFF8B5CF6),
                      builder: (refresh) => Column(
                        children: ContenidoSection(
                          refresh: refresh,
                          tmdbEnrichment: _tmdbEnrichment,
                          allowAdultContent: _allowAdultContent,
                          showUnreleased: _showUnreleased,
                          showSeasonSpecials: _showSeasonSpecials,
                          showUnreleasedEpisodes: _showUnreleasedEpisodes,
                          regionalFilter: _regionalFilter,
                          spanishLatino: _spanishLatino,
                          spanishCastellano: _spanishCastellano,
                          english: _english,
                          disableNonLatinTitles: _disableNonLatinTitles,
                          homeSessions: _homeSessions,
                          homeFeaturedMovies: _homeFeaturedMovies,
                          homePopularMovies: _homePopularMovies,
                          homePopularSeries: _homePopularSeries,
                          homeYearMovies: _homeYearMovies,
                          homeFeaturedSeries: _homeFeaturedSeries,
                          homeYearSeries: _homeYearSeries,
                          homeTrendingMovies: _homeTrendingMovies,
                          homeTrendingSeries: _homeTrendingSeries,
                          homeLatest: _homeLatest,
                          onChanged: _onContenidoChanged,
                        ).build(),
                      ),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Apariencia',
                    subtitle: 'Vista TV y modo de interfaz',
                    icon: Icons.palette_rounded,
                    accent: const Color(0xFF0EA5E9),
                    onTap: () => _openSection(
                      title: 'Apariencia',
                      icon: Icons.palette_rounded,
                      accent: const Color(0xFF0EA5E9),
                      builder: (refresh) => Column(
                        children: AparienciaSection(
                          onSwitchToTv: _switchToTv,
                        ).build(),
                      ),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Fuentes',
                    subtitle:
                        'Selección automática, servidores y fuentes de video',
                    icon: Icons.stream_rounded,
                    accent: const Color(0xFFA855F7),
                    onTap: () => _openSection(
                      title: 'Fuentes',
                      icon: Icons.stream_rounded,
                      accent: const Color(0xFFA855F7),
                      builder: (refresh) => FuentesSection(
                        verificarServidores: _verificarServidores,
                        unServidorPorIdioma: _unServidorPorIdioma,
                        mostrarServidoresEnPlayer: _mostrarServidoresEnPlayer,
                        idiomaPredEnabled: _idiomaPredEnabled,
                        idiomaPred: _idiomaPred,
                        seleccionFuente: _seleccionFuente,
                        reutilizarUltimoEnlace: _reutilizarUltimoEnlace,
                        sourceEnabled: _sourceEnabled,
                        sourceLoading: _sourceLoading,
                        fuentesActivas: _fuentesActivas,
                        onVerificarChanged: (v) {
                          _setVerificarServidores(v).then((_) => refresh());
                        },
                        onUnServidorChanged: (v) {
                          _setUnServidorPorIdioma(v).then((_) => refresh());
                        },
                        onMostrarServidoresEnPlayerChanged: (v) {
                          _setMostrarServidoresEnPlayer(v)
                              .then((_) => refresh());
                        },
                        onIdiomaPredEnabledChanged: (v) {
                          _setIdiomaPredEnabled(v).then((_) => refresh());
                        },
                        onIdiomaPredChanged: (v) {
                          _setIdiomaPred(v).then((_) => refresh());
                        },
                        onSeleccionFuenteChanged: (v) {
                          _setSeleccionFuente(v).then((_) => refresh());
                        },
                        onReutilizarChanged: (v) {
                          _setReutilizarUltimoEnlace(v).then((_) => refresh());
                        },
                        onSourceChanged: (source, v) {
                          _setSourceEnabled(source, v).then((_) => refresh());
                        },
                        showConfirmDialog: (
                          title,
                          body, {
                          confirmLabel = 'Activar',
                          accent = kAccentColor,
                        }) {
                          return _confirmDialog(
                            title: title,
                            body: body,
                            confirmLabel: confirmLabel,
                            accent: accent,
                          );
                        },
                      ),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Player',
                    subtitle: 'Subtítulos, tamaño, altura y descarga',
                    icon: Icons.play_circle_outline_rounded,
                    accent: const Color(0xFF06B6D4),
                    onTap: () => _openSection(
                      title: 'Player',
                      icon: Icons.play_circle_outline_rounded,
                      accent: const Color(0xFF06B6D4),
                      builder: (refresh) => Column(
                        children: PlayerSection(
                          refresh: refresh,
                          subsAlInicio: _subsAlInicio,
                          subSize: _subSize,
                          subHeight: _subHeight,
                          idmDownloadEnabled: _idmDownloadEnabled,
                          onSubsChanged: (v) => _setSubsAlInicio(v),
                          onSubSizeChanged: (v) => _setSubSize(v),
                          onSubHeightChanged: (v) => _setSubHeight(v),
                          onIdmChanged: (v) => _setIdmDownloadEnabled(v),
                        ).build(),
                      ),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Descargas',
                    subtitle:
                        'Habilitar, menú, automática, simultáneas e idioma',
                    icon: Icons.download_rounded,
                    accent: const Color(0xFF22C55E),
                    onTap: () => _openSection(
                      title: 'Descargas',
                      icon: Icons.download_rounded,
                      accent: const Color(0xFF22C55E),
                      builder: (refresh) => DescargasSection(
                        enableDownloads: _enableDownloads,
                        showDownloadButtonMain: _showDownloadButtonMain,
                        autoDirectDownload: _autoDirectDownload,
                        downloadLanguage: _downloadLanguage,
                        maxConcurrentDownloads: _maxConcurrentDownloads,
                        onEnableDownloadsChanged: (v) {
                          _setEnableDownloads(v).then((_) => refresh());
                        },
                        onShowDownloadButtonMainChanged: (v) {
                          _setShowDownloadButtonMain(v).then((_) => refresh());
                        },
                        onAutoDirectDownloadChanged: (v) {
                          _setAutoDirectDownload(v).then((_) => refresh());
                        },
                        onDownloadLanguageChanged: (v) {
                          _setDownloadLanguage(v).then((_) => refresh());
                        },
                        onMaxConcurrentDownloadsChanged: (v) {
                          _setMaxConcurrentDownloads(v).then((_) => refresh());
                        },
                      ),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Notificaciones',
                    subtitle:
                        'Avisos de estrenos, hora y prueba',
                    icon: Icons.notifications_active_rounded,
                    accent: const Color(0xFFFF6B00),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsSectionPage(),
                        ),
                      );
                    },
                  ),
                  _buildSectionCard(
                    title: 'Supabase',
                    subtitle: 'Sincronizar perfiles y guardados en la nube',
                    icon: Icons.cloud_sync_rounded,
                    accent: const Color(0xFF3ECF8E),
                    onTap: () => _openSection(
                      title: 'Supabase',
                      icon: Icons.cloud_sync_rounded,
                      accent: const Color(0xFF3ECF8E),
                      builder: (refresh) => const SupabaseSection(),
                    ),
                  ),
                  _buildSectionCard(
                    title: 'Caché',
                    subtitle: 'Historial, guardados y servidores',
                    icon: Icons.storage_rounded,
                    accent: Colors.redAccent,
                    onTap: () => _openSection(
                      title: 'Caché',
                      icon: Icons.storage_rounded,
                      accent: Colors.redAccent,
                      builder: (refresh) => Column(
                        children: CacheSection(
                          onClearHistorial: _clearHistorial,
                          onClearGuardados: _clearGuardados,
                          onClearCacheServidores: _clearCacheServidores,
                          onClearTodo: _clearTodo,
                        ).build(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}


class _SocialItem {
  final String name;
  final String url;
  final Color color;
  final String asset;

  const _SocialItem({
    required this.name,
    required this.url,
    required this.color,
    required this.asset,
  });
}

class _ConfigSectionPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _ConfigSectionPage({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 40.0 + bottomSafe),
        children: [child],
      ),
    );
  }
}