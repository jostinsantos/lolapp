import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../content/presentation/content_page.dart';
import '../../player/presentation/player_page.dart';
import '../../content/presentation/content_options_modal.dart';
import '../../downloads/presentation/download_manager.dart';
import '../../downloads/presentation/local_player_page.dart';
import '../../../supabase/supabase_data.dart';

const _kAccent = Colors.purpleAccent;
const _kGreen = Color(0xFF4CAF50);
const _kOrange = Color(0xFFFF9800);
const _kCard = Color(0xFF1a1a2e);
const _kBg = Colors.black;
const _kCardBg = Color(0xFF1a1a2e);
const _kSectionTitle = TextStyle(
  fontFamily: 'sans-serif',
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w700,
);

/// Pestaña principal de la biblioteca unificada
enum _Tab { guardados, historial, descargas }

/// Filtro de tipo de contenido
enum _TipoFilter { todos, peliculas, series }

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class BibliotecaUnificadaPage extends StatefulWidget {
  const BibliotecaUnificadaPage({super.key});

  @override
  State<BibliotecaUnificadaPage> createState() =>
      BibliotecaUnificadaPageState();
}

class BibliotecaUnificadaPageState extends State<BibliotecaUnificadaPage>
    with AutomaticKeepAliveClientMixin {
  final _dm = DownloadManager.instance;

  // Igual que antes: arranca en Guardados
  _Tab _tab = _Tab.guardados;
  _TipoFilter _tipo = _TipoFilter.todos;

  // ── Guardados / Historial ────────────────────────────────────────────────
  List<Map<String, dynamic>> _historial = [];
  List<Map<String, dynamic>> _guardados = [];

  // ── Descargas ────────────────────────────────────────────────────────────
  List<_DownloadItem> _items = [];
  List<_DownloadItem> _incomplete = [];
  // Solo spinner en la PRIMERA carga si aún no hay nada en memoria
  bool _initialLoading = true;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {}; // folderPath o "g:tmdbId" / "h:key"

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dm.addListener(_onDm);
    _dm.loadSettings();
    // Tiempo real: cuando se guarda/quita desde el modal u otra pantalla
    GuardadosBus.version.addListener(_onExternalChange);
    // Carga silenciosa (sin bloquear UI como el GuardadosPage original con cache)
    _loadAll(silent: false);
  }

  @override
  void dispose() {
    _dm.removeListener(_onDm);
    GuardadosBus.version.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onDm() {
    if (!mounted) return;
    setState(() {});
    final justDone = _dm.all.any((d) => d.status == DownloadStatus.completed);
    if (justDone) _loadDownloads();
  }

  void _onExternalChange() {
    if (!mounted) return;
    // Refresh silencioso en tiempo real (como antes)
    _loadGuardadosYHistorial();
  }

  void refresh() => _loadAll(silent: true);

  /// [silent] = true → no muestra spinner (pull-to-refresh / bus / volver a la tab)
  Future<void> _loadAll({bool silent = true}) async {
    if (!silent &&
        _guardados.isEmpty &&
        _historial.isEmpty &&
        _items.isEmpty &&
        _incomplete.isEmpty) {
      if (mounted) setState(() => _initialLoading = true);
    }
    _error = null;
    await Future.wait([
      _loadGuardadosYHistorial(),
      _loadDownloads(),
    ]);
    if (mounted) setState(() => _initialLoading = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  GUARDADOS + HISTORIAL  (misma lógica que GuardadosPage)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Idéntico a GuardadosPage._load() para historial + mi lista
  Future<void> _loadGuardadosYHistorial() async {
    final historial = await _loadHistorial();
    final guardados = await GuardadosCache.getAll(); // ← igual que antes

    if (!mounted) return;
    setState(() {
      _historial = historial;
      _guardados = guardados;
    });
  }

  /// Historial desde Supabase (logueado) o cache local (invitado).
  /// Normaliza campos para que la UI (poster, idcontenido, segundo, etc.) funcione.
  Future<List<Map<String, dynamic>>> _loadHistorial() async {
    try {
      final list = await SupabaseData.getHistorial();
      final result = <Map<String, dynamic>>[];

      for (final raw in list) {
        final data = Map<String, dynamic>.from(raw);
        final tmdbId = data['tmdb_id'] ?? data['idcontenido'] ?? 0;
        final id = tmdbId is int ? tmdbId : int.tryParse('$tmdbId') ?? 0;
        if (id <= 0) continue;

        final segundo = data['progress_seconds'] as int? ??
            data['segundo'] as int? ??
            0;
        if (segundo < 5) continue;

        final tipo = (data['tipo'] ?? 'movie').toString().toLowerCase();
        final isTv = tipo.contains('tv') || tipo.contains('serie');
        // 0 es sentinela en BD para movies; en UI no mostrar S0E0
        int? season = data['season'] is int
            ? data['season'] as int
            : int.tryParse('${data['season'] ?? data['temporada'] ?? ''}');
        int? episode = data['episode'] is int
            ? data['episode'] as int
            : int.tryParse('${data['episode'] ?? data['capitulo'] ?? ''}');
        if (!isTv || season == 0) season = null;
        if (!isTv || episode == 0) episode = null;

        // Clave estable para selección / borrado
        final cacheKey = data['id']?.toString() ??
            'hist_${id}_${tipo}_${season ?? 0}_${episode ?? 0}';

        // Poster: priorizar URL completa ya guardada en Supabase
        String poster = '';
        for (final key in [
          'poster',
          'poster_path',
          'posterUrl',
          'backdrop',
          'backdrop_path',
        ]) {
          final v = data[key]?.toString() ?? '';
          if (v.isEmpty) continue;
          if (v.startsWith('http://') || v.startsWith('https://')) {
            poster = v;
            break;
          }
          if (v.startsWith('/')) {
            poster = 'https://image.tmdb.org/t/p/w500$v';
            break;
          }
          if (v.contains('.') && !v.contains(' ')) {
            poster = 'https://image.tmdb.org/t/p/w500/${v.startsWith('/') ? v.substring(1) : v}';
            break;
          }
        }

        result.add({
          ...data,
          'idcontenido': id,
          'tmdb_id': id,
          'segundo': segundo,
          'progress_seconds': segundo,
          'temporada': season,
          'capitulo': episode,
          'tipo': tipo,
          'titulo': data['titulo']?.toString() ??
              data['title']?.toString() ??
              '',
          'poster': poster,
          'backdrop': data['backdrop']?.toString() ?? poster,
          'duration': data['duration_seconds'] ?? data['duration'],
          'timestamp': data['updated_at']?.toString() ??
              data['created_at']?.toString() ??
              data['timestamp']?.toString() ??
              '',
          '_cacheKey': cacheKey,
          '_supabaseId': data['id']?.toString(),
        });
      }

      result.sort((a, b) {
        final ta = a['timestamp']?.toString() ?? '';
        final tb = b['timestamp']?.toString() ?? '';
        return tb.compareTo(ta);
      });
      return result;
    } catch (e) {
      debugPrint('[Biblioteca] _loadHistorial error: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> get _filteredGuardados {
    if (_tipo == _TipoFilter.todos) return _guardados;
    return _guardados.where((item) {
      final t = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? 'movie')
          .toString()
          .toLowerCase();
      if (_tipo == _TipoFilter.peliculas) return t == 'movie' || t == 'pelicula';
      return t == 'tv' || t == 'serie' || t == 'series';
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredHistorial {
    if (_tipo == _TipoFilter.todos) return _historial;
    return _historial.where((item) {
      final t = (item['tipo'] ?? 'movie').toString().toLowerCase();
      if (_tipo == _TipoFilter.peliculas) return t == 'movie' || t == 'pelicula';
      return t == 'tv' || t == 'serie' || t == 'series';
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DESCARGAS (lógica de DescargasPage)
  // ═══════════════════════════════════════════════════════════════════════════

  List<ActiveDownload> get _downloading => _dm.all
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued)
      .toList();

  List<ActiveDownload> get _cancelled => _dm.all
      .where((d) =>
          d.status == DownloadStatus.cancelled ||
          d.status == DownloadStatus.failed)
      .toList();

  static ({String series, String? episode}) _parseTitle(String raw) {
    final t = raw.trim();
    final re = RegExp(
      r'^(.*?)\s*[_\-\s]?T(\d{1,2})\s*[CE](\d{1,2})\s*$',
      caseSensitive: false,
    );
    final m = re.firstMatch(t);
    if (m != null) {
      final series = m.group(1)!.trim().replaceAll(RegExp(r'[_\s]+$'), '');
      final season = m.group(2)!.padLeft(2, '0');
      final ep = m.group(3)!.padLeft(2, '0');
      return (series: series.isEmpty ? t : series, episode: 'T$season C$ep');
    }
    return (series: t, episode: null);
  }

  static String? _episodeLabel(_DownloadItem item) {
    if (item.temporada != null && item.capitulo != null) {
      final s = item.temporada!.toString().padLeft(2, '0');
      final e = item.capitulo!.toString().padLeft(2, '0');
      return 'T$s C$e';
    }
    return _parseTitle(item.title).episode;
  }

  static String _seriesName(_DownloadItem item) {
    final fromMeta = item.title.trim();
    if (fromMeta.isNotEmpty) {
      final parsed = _parseTitle(fromMeta);
      return parsed.series;
    }
    return _parseTitle(item.title).series;
  }

  List<_SeriesGroup> get _groups {
    final map = <String, List<_DownloadItem>>{};
    for (final item in _filteredDownloadItems) {
      final series = _seriesName(item);
      map.putIfAbsent(series, () => []).add(item);
    }
    final groups = map.entries.map((e) {
      final list = e.value
        ..sort((a, b) {
          final ta = a.temporada ?? 0;
          final ca = a.capitulo ?? 0;
          final tb = b.temporada ?? 0;
          final cb = b.capitulo ?? 0;
          if (ta != tb) return ta.compareTo(tb);
          if (ca != cb) return ca.compareTo(cb);
          final ea = _episodeLabel(a) ?? '';
          final eb = _episodeLabel(b) ?? '';
          return ea.compareTo(eb);
        });
      return _SeriesGroup(title: e.key, episodes: list);
    }).toList();
    groups.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return groups;
  }

  List<_DownloadItem> get _filteredDownloadItems {
    if (_tipo == _TipoFilter.todos) return _items;
    return _items.where((item) {
      final t = (item.tipo ?? '').toLowerCase();
      if (_tipo == _TipoFilter.peliculas) {
        return t == 'movie' || t == 'pelicula' || t.isEmpty;
      }
      return t == 'tv' || t == 'serie' || t == 'series';
    }).toList();
  }

  List<_DownloadItem> get _filteredIncomplete {
    if (_tipo == _TipoFilter.todos) return _incomplete;
    return _incomplete.where((item) {
      final t = (item.tipo ?? '').toLowerCase();
      if (_tipo == _TipoFilter.peliculas) {
        return t == 'movie' || t == 'pelicula' || t.isEmpty;
      }
      return t == 'tv' || t == 'serie' || t == 'series';
    }).toList();
  }

  Set<String> get _activeFolderPaths {
    final set = <String>{};
    for (final d in _dm.all) {
      if (d.folderPath != null &&
          (d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.queued)) {
        set.add(d.folderPath!);
      }
    }
    return set;
  }

  Future<Directory> _getBaseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/lolplustv_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Map<String, dynamic>?> _readMeta(String folderPath) async {
    try {
      final f = File('$folderPath/meta.json');
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString());
      if (map is Map) return Map<String, dynamic>.from(map);
    } catch (_) {}
    return null;
  }

  Future<void> _loadDownloads() async {
    if (!_selectMode) {
      // no forzar loading si solo actualizamos
    }
    try {
      final base = await _getBaseDir();
      final completed = <_DownloadItem>[];
      final incomplete = <_DownloadItem>[];
      final activePaths = _activeFolderPaths;

      await for (final entity in base.list()) {
        if (entity is! Directory) continue;
        if (activePaths.contains(entity.path)) continue;

        final playlist = File('${entity.path}/playlist.m3u8');
        final name = entity.path.split(Platform.pathSeparator).last;
        final stat = await entity.stat();
        final size = await _folderSize(entity);
        final titleFromFolder = name.replaceAll('_', ' ');
        final meta = await _readMeta(entity.path);

        final title = (meta?['titulo']?.toString().trim().isNotEmpty == true)
            ? meta!['titulo'].toString().trim()
            : titleFromFolder;

        final posterFile = meta?['posterFile']?.toString();
        final backdropFile = meta?['backdropFile']?.toString();

        final item = _DownloadItem(
          folderPath: entity.path,
          playlistPath: await playlist.exists() ? playlist.path : '',
          title: title,
          modified: stat.modified,
          sizeBytes: size,
          isIncomplete: !await playlist.exists(),
          tmdbId: meta?['tmdbId'] is int
              ? meta!['tmdbId'] as int
              : int.tryParse('${meta?['tmdbId'] ?? ''}'),
          tipo: meta?['tipo']?.toString(),
          temporada: meta?['temporada'] is int
              ? meta!['temporada'] as int
              : int.tryParse('${meta?['temporada'] ?? ''}'),
          capitulo: meta?['capitulo'] is int
              ? meta!['capitulo'] as int
              : int.tryParse('${meta?['capitulo'] ?? ''}'),
          posterUrl: meta?['posterUrl']?.toString(),
          backdropUrl: meta?['backdropUrl']?.toString(),
          posterFile: posterFile,
          backdropFile: backdropFile,
        );

        if (item.isIncomplete) {
          incomplete.add(item);
        } else {
          completed.add(item);
        }
      }

      completed.sort((a, b) => b.modified.compareTo(a.modified));
      incomplete.sort((a, b) => b.modified.compareTo(a.modified));

      if (!mounted) return;
      setState(() {
        _items = completed;
        _incomplete = incomplete;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<int> _folderSize(Directory dir) async {
    int total = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _endEstimateLabel(ActiveDownload d) {
    final eta = d.etaSeconds;
    if (eta == null) return 'Fin: calculando…';
    final end = DateTime.now().add(Duration(seconds: eta));
    return 'Fin ~ ${_fmtTime(end)}';
  }

  // ─── Poster ──────────────────────────────────────────────────────────────
  Widget _buildPoster({
    Key? key,
    String? localPath,
    String? remoteUrl,
    double width = 48,
    double height = 48,
    double radius = 12,
  }) {
    Widget child;
    if (localPath != null && File(localPath).existsSync()) {
      child = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _posterFallback(),
      );
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: remoteUrl,
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorWidget: (_, __, ___) => _posterFallback(),
        placeholder: (_, __) => _posterFallback(),
      );
    } else {
      child = _posterFallback();
    }

    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _posterFallback() {
    return Container(
      color: _kCardBg,
      child: Icon(
        Icons.movie_rounded,
        color: Colors.white.withValues(alpha: 0.25),
        size: 24,
      ),
    );
  }

  /// Idéntico a PageContenido._firstUrl (lo que se usa al GUARDAR en favoritos)
  static String _firstUrl(dynamic value) {
    if (value == null) return '';
    String str = value.toString().trim();
    if (str.isEmpty || str == 'null' || str == 'undefined') return '';

    // URL limpia
    if (str.startsWith('http') && !str.contains('[')) {
      return str.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
    }

    // URL embebida / escapada
    final match = RegExp(r'https?:\\?/\\?/[^\s,"\]\\]+').firstMatch(str);
    if (match != null) {
      return match.group(0)!.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
    }

    // Lista JSON-like: ["https://..."]
    try {
      String cleaned = str
          .replaceAll(r'\/', '/')
          .replaceAll("'", '"')
          .replaceAll('""', '"');
      if (!cleaned.startsWith('[')) cleaned = '[$cleaned]';
      final list = jsonDecode(cleaned);
      if (list is List && list.isNotEmpty) {
        return list.first.toString().replaceAll(r'\/', '/');
      }
    } catch (_) {}

    return '';
  }

  /// Path relativo TMDB → URL completa (si _firstUrl no encontró http)
  static String _resolveImageUrl(dynamic value, {String size = 'w500'}) {
    // 1) Misma lógica que content_page al guardar
    final fromFirst = _firstUrl(value);
    if (fromFirst.isNotEmpty) {
      if (fromFirst.startsWith('http')) return fromFirst;
      value = fromFirst;
    }

    if (value == null) return '';
    String s = value.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return '';

    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    if (s.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/$size$s';
    }

    if (s.contains('.') && !s.contains(' ') && !s.startsWith('http')) {
      final path = s.startsWith('/') ? s : '/$s';
      return 'https://image.tmdb.org/t/p/$size$path';
    }

    if (s.contains('t/p/')) {
      return 'https://image.tmdb.org/${s.replaceFirst(RegExp(r'^/+'), '')}';
    }

    return '';
  }

  /// Poster desde GuardadosCache / Supabase / historial
  /// Campos que PageContenido escribe: poster, poster_path, backdrop_path, logo_path
  static String _posterFromItem(Map<String, dynamic> item) {
    final candidates = [
      item['poster'],
      item['poster_path'],
      item['posterUrl'],
      item['poster_url'],
      item['backdrop'],
      item['backdrop_path'],
      item['backdropUrl'],
      item['backdrop_url'],
      item['logo_path'],
      item['logo'],
    ];
    for (final c in candidates) {
      final url = _resolveImageUrl(c);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  // ─── Selección ───────────────────────────────────────────────────────────
  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selected.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  List<String> get _allSelectableIds {
    switch (_tab) {
      case _Tab.descargas:
        return [..._items, ..._incomplete].map((e) => e.folderPath).toList();
      case _Tab.guardados:
        return _filteredGuardados
            .map((e) => 'g:${e['tmdb_id'] ?? e['idtmdb'] ?? e['idcontenido']}')
            .toList();
      case _Tab.historial:
        return _filteredHistorial
            .map((e) => 'h:${e['_cacheKey'] ?? e['idcontenido']}')
            .toList();
    }
  }

  void _selectAll() {
    setState(() {
      final all = _allSelectableIds;
      if (_selected.length == all.length && all.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Borrar ${_selected.length} elemento${_selected.length == 1 ? '' : 's'}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (_tab == _Tab.descargas) {
      for (final path in _selected.toList()) {
        try {
          _DownloadItem? item;
          for (final e in [..._items, ..._incomplete]) {
            if (e.folderPath == path) {
              item = e;
              break;
            }
          }
          if (item != null) {
            await _dm.unmarkDownloaded(
              tmdbId: item.tmdbId,
              tipo: item.tipo,
              temporada: item.temporada,
              capitulo: item.capitulo,
            );
          }
          final dir = Directory(path);
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }
      await _loadDownloads();
    } else if (_tab == _Tab.historial) {
      for (final id in _selected.toList()) {
        if (!id.startsWith('h:')) continue;
        final key = id.substring(2);
        // Buscar el item en _historial para tener tmdb_id / tipo / season / episode
        final match = _historial.cast<Map?>().firstWhere(
          (e) {
            if (e == null) return false;
            return '${e['_cacheKey']}' == key ||
                '${e['idcontenido']}' == key ||
                '${e['_supabaseId']}' == key;
          },
          orElse: () => null,
        );
        if (match != null) {
          final tmdbId = match['tmdb_id'] as int? ??
              match['idcontenido'] as int? ??
              0;
          final tipo = (match['tipo'] ?? 'movie').toString().toLowerCase();
          final season = match['temporada'] as int? ?? match['season'] as int?;
          final episode = match['capitulo'] as int? ?? match['episode'] as int?;
          if (tmdbId > 0) {
            await SupabaseData.removeHistorial(
              tmdbId: tmdbId,
              tipo: tipo.contains('tv') || tipo.contains('serie') ? 'tv' : 'movie',
              season: season,
              episode: episode,
            );
          }
        } else {
          // Fallback: borrar de SharedPreferences por si quedó cache viejo
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        }
      }
      await _loadGuardadosYHistorial();
    } else if (_tab == _Tab.guardados) {
      // Quitar de Mi lista usando el mismo toggle del modal
      try {
        final all = await GuardadosCache.getAll();
        for (final id in _selected.toList()) {
          if (!id.startsWith('g:')) continue;
          final rawId = id.substring(2);
          final match = all.cast<Map?>().firstWhere(
            (e) {
              if (e == null) return false;
              final x = '${e['tmdb_id'] ?? e['idtmdb'] ?? e['idcontenido']}';
              return x == rawId;
            },
            orElse: () => null,
          );
          if (match != null) {
            await GuardadosCache.toggle(Map<String, dynamic>.from(match));
          }
        }
      } catch (e) {
        debugPrint('Error eliminando guardados: $e');
      }
      await _loadGuardadosYHistorial();
    }

    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  // ─── Acciones individuales ───────────────────────────────────────────────
  void _openHistorial(Map<String, dynamic> item) {
    final rawId = item['idcontenido'] ?? item['tmdb_id'] ?? 0;
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    if (id <= 0) return;
    final temporada = item['temporada'] is int
        ? item['temporada'] as int
        : int.tryParse('${item['temporada'] ?? ''}');
    final capitulo = item['capitulo'] is int
        ? item['capitulo'] as int
        : int.tryParse('${item['capitulo'] ?? ''}');
    final tipo = (item['tipo'] ?? 'movie').toString().toLowerCase();
    final titulo = item['titulo']?.toString() ?? '';
    final videoUrl = item['videoUrl']?.toString() ?? '';
    final idioma = item['idioma']?.toString();

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              videoUrl: videoUrl,
              idcontenido: id,
              tmdbId: id,
              temporada: temporada,
              capitulo: capitulo,
              tipo: tipo,
              titulo: titulo,
              idioma: idioma,
            ),
          ),
        )
        .then((_) => _loadGuardadosYHistorial());
  }

  void _openGuardado(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ??
        item['idtmdb'] as int? ??
        item['idcontenido'] as int? ??
        0;
    final tipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? 'movie')
        .toString()
        .toLowerCase();
    if (id <= 0) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PageContenido(
              idcontenido: id,
              tmdbId: id,
              mediaType: tipo,
            ),
          ),
        )
        .then((_) => _loadGuardadosYHistorial());
  }

  void _showOpcionesModal(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ??
        item['idtmdb'] as int? ??
        item['idcontenido'] as int? ??
        0;
    if (id <= 0) return;

    final tipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? 'movie')
        .toString()
        .toLowerCase();

    final titulo = item['titulo']?.toString() ??
        item['title']?.toString() ??
        item['name']?.toString() ??
        'Sin título';

    // Misma resolución agresiva de poster que la galería
    final poster = _posterFromItem(item);
    final backdrop = _resolveImageUrl(
      item['backdrop'] ??
          item['backdrop_path'] ??
          item['backdropUrl'] ??
          item['poster'] ??
          item['poster_path'],
      size: 'w780',
    );

    showContenidoOpcionesModal(
      context,
      tmdbId: id,
      idcontenido: id,
      tipo: tipo,
      titulo: titulo,
      posterUrl: poster.isNotEmpty ? poster : null,
      backdropUrl: backdrop.isNotEmpty ? backdrop : null,
    ).then((_) {
      if (mounted) _loadGuardadosYHistorial();
    });
  }

  /// Long-press en una descarga → mismo modal de opciones
  void _showOpcionesModalDownload(_DownloadItem item) {
    final id = item.tmdbId ?? 0;
    if (id <= 0) return;
    final tipo = (item.tipo ?? 'movie').toLowerCase();
    final poster = _resolveImageUrl(item.posterUrl) ;
    final local = item.localPosterPath;
    // Preferir URL remota; si no hay, el modal no muestra local file (solo URL)
    showContenidoOpcionesModal(
      context,
      tmdbId: id,
      idcontenido: id,
      tipo: tipo,
      titulo: item.title,
      posterUrl: poster.isNotEmpty
          ? poster
          : (local != null ? null : null),
      backdropUrl: _resolveImageUrl(item.backdropUrl, size: 'w780').isNotEmpty
          ? _resolveImageUrl(item.backdropUrl, size: 'w780')
          : null,
    ).then((_) {
      if (mounted) {
        _loadGuardadosYHistorial();
        _loadDownloads();
      }
    });
  }

  Future<void> _deleteOneDownload(_DownloadItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          item.isIncomplete ? 'Eliminar incompleta' : 'Eliminar descarga',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          item.isIncomplete
              ? '¿Borrar la descarga incompleta "${item.title}"?'
              : '¿Borrar "${item.title}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _dm.unmarkDownloaded(
        tmdbId: item.tmdbId,
        tipo: item.tipo,
        temporada: item.temporada,
        capitulo: item.capitulo,
      );
      final dir = Directory(item.folderPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      await _loadDownloads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al borrar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _deleteAllIncomplete() async {
    if (_incomplete.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Limpiar incompletas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Borrar las ${_incomplete.length} descargas incompletas?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar todas',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final item in _incomplete) {
      try {
        await _dm.unmarkDownloaded(
          tmdbId: item.tmdbId,
          tipo: item.tipo,
          temporada: item.temporada,
          capitulo: item.capitulo,
        );
        final dir = Directory(item.folderPath);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    await _loadDownloads();
  }

  void _clearCancelled() {
    for (final d in _cancelled) {
      _dm.remove(d.id);
    }
    setState(() {});
  }

  void _openPlayer(_DownloadItem item) {
    if (item.isIncomplete || item.playlistPath.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalPlayerScreen(
          playlistPath: item.playlistPath,
          title: item.title,
        ),
      ),
    );
  }

  void _openPageContenido(_DownloadItem item) {
    final tmdb = item.tmdbId;
    if (tmdb == null || tmdb <= 0) return;
    final tipo = item.tipo ?? 'tv';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: tmdb,
          tmdbId: tmdb,
          mediaType: tipo,
        ),
      ),
    );
  }

  void _openSeriesSheet(_SeriesGroup group) {
    if (_selectMode) {
      final allSelected =
          group.episodes.every((e) => _selected.contains(e.folderPath));
      setState(() {
        if (allSelected) {
          for (final e in group.episodes) {
            _selected.remove(e.folderPath);
          }
        } else {
          for (final e in group.episodes) {
            _selected.add(e.folderPath);
          }
        }
      });
      return;
    }

    if (group.episodes.length == 1 &&
        _episodeLabel(group.episodes.first) == null) {
      _openPlayer(group.episodes.first);
      return;
    }

    final hasTmdb =
        group.episodes.any((e) => e.tmdbId != null && e.tmdbId! > 0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.65;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxH),
              decoration: BoxDecoration(
                color: _kCard.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${group.episodes.length} capítulo${group.episodes.length == 1 ? '' : 's'} · ${_formatSize(group.totalBytes)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 13,
                                ),
                              ),
                              if (hasTmdb) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    final first = group.episodes.firstWhere(
                                      (e) => e.tmdbId != null && e.tmdbId! > 0,
                                      orElse: () => group.episodes.first,
                                    );
                                    Navigator.pop(ctx);
                                    _openPageContenido(first);
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _kAccent,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon:
                                      const Icon(Icons.list_rounded, size: 18),
                                  label: const Text(
                                    'Ver más capítulos',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      color: Colors.white.withValues(alpha: 0.08), height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        14,
                        10,
                        14,
                        16 + MediaQuery.paddingOf(ctx).bottom,
                      ),
                      itemCount: group.episodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final ep = group.episodes[i];
                        final epLabel = _episodeLabel(ep);
                        final label = epLabel ?? ep.title;
                        return Material(
                          color: _kBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(ctx);
                              _openPlayer(ep);
                            },
                            onLongPress: () {
                              Navigator.pop(ctx);
                              _deleteOneDownload(ep);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  _buildPoster(
                                    localPath: ep.localPosterPath,
                                    remoteUrl: ep.posterUrl,
                                    width: 42,
                                    height: 42,
                                    radius: 11,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _formatSize(ep.sizeBytes),
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.4),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConcurrencySheet() async {
    int current = _dm.segmentConcurrency;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kCard.withValues(alpha: 0.95),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20 + MediaQuery.paddingOf(ctx).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hilos de descarga',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Segmentos en paralelo por descarga (1–8).\nMás hilos = más rápido, más uso de red/CPU.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '$current',
                        style: const TextStyle(
                          color: _kAccent,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Slider(
                        value: current.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        activeColor: _kAccent,
                        inactiveColor: Colors.white24,
                        label: '$current',
                        onChanged: (v) => setModal(() => current = v.round()),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _dm.setSegmentConcurrency(current);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Guardar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showStorageSheet() async {
    final stats = await _dm.storageStats();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: _kCard.withValues(alpha: 0.92),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Almacenamiento',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _statRow(Icons.folder_rounded, 'Usado por descargas',
                      _formatSize(stats.usedBytes)),
                  const SizedBox(height: 10),
                  _statRow(Icons.downloading_rounded, 'Descargas activas',
                      '${_downloading.length}'),
                  const SizedBox(height: 10),
                  _statRow(Icons.video_library_rounded, 'Completadas',
                      '${_items.length}'),
                  const SizedBox(height: 10),
                  _statRow(Icons.warning_amber_rounded, 'Inconclusas',
                      '${_incomplete.length}'),
                  const SizedBox(height: 10),
                  _statRow(Icons.bolt_rounded, 'Hilos por descarga',
                      '${_dm.segmentConcurrency}'),
                  if (_incomplete.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteAllIncomplete();
                        },
                        icon: const Icon(Icons.cleaning_services_rounded,
                            size: 18),
                        label: const Text('Limpiar todas las incompletas'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                          side: const BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kBg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _selectMode
              ? '${_selected.length} seleccionada${_selected.length == 1 ? '' : 's'}'
              : 'Biblioteca',
          style: const TextStyle(
            fontFamily: 'sans-serif',
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: 'Seleccionar todo',
              icon: Icon(
                _selected.length == _allSelectableIds.length &&
                        _allSelectableIds.isNotEmpty
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: Colors.white70,
              ),
              onPressed: _allSelectableIds.isEmpty ? null : _selectAll,
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: Icon(
                Icons.delete_rounded,
                color: _selected.isEmpty ? Colors.white24 : Colors.redAccent,
              ),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
            IconButton(
              tooltip: 'Cancelar',
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: _toggleSelectMode,
            ),
          ] else ...[
            // Botones de descargas solo en pestaña Descargas
            if (_tab == _Tab.descargas) ...[
              if (_items.isNotEmpty || _incomplete.isNotEmpty)
                IconButton(
                  tooltip: 'Seleccionar',
                  icon: const Icon(Icons.checklist_rounded,
                      color: Colors.white70),
                  onPressed: _toggleSelectMode,
                ),
              IconButton(
                tooltip: 'Hilos de descarga',
                icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                onPressed: _showConcurrencySheet,
              ),
              IconButton(
                tooltip: 'Almacenamiento',
                icon: const Icon(Icons.storage_rounded, color: Colors.white70),
                onPressed: _showStorageSheet,
              ),
            ] else ...[
              // Guardados / Historial: solo seleccionar (tiempo real vía GuardadosBus)
              if ((_tab == _Tab.guardados && _filteredGuardados.isNotEmpty) ||
                  (_tab == _Tab.historial && _filteredHistorial.isNotEmpty))
                IconButton(
                  tooltip: 'Seleccionar',
                  icon: const Icon(Icons.checklist_rounded,
                      color: Colors.white70),
                  onPressed: _toggleSelectMode,
                ),
            ],
            // Sin botón de recargar: se actualiza solo con GuardadosBus / DownloadManager
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Tabs principales: Guardados | Historial | Descargados ──────
          _buildMainTabs(),
          // ── Filtro Todos / Películas / Series ──────────────────────────
          _buildTipoFilters(),
          // ── Contenido ──────────────────────────────────────────────────
          Expanded(
            child: _initialLoading &&
                    _guardados.isEmpty &&
                    _historial.isEmpty &&
                    _items.isEmpty &&
                    _incomplete.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _kAccent,
                      strokeWidth: 2.5,
                    ),
                  )
                : _error != null &&
                        _items.isEmpty &&
                        _incomplete.isEmpty &&
                        _tab == _Tab.descargas
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: _kAccent,
                        backgroundColor: _kCard,
                        onRefresh: () => _loadAll(silent: true),
                        child: _buildBody(bottomPad),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTabs() {
    final counts = {
      _Tab.guardados: _guardados.length,
      _Tab.historial: _historial.length,
      _Tab.descargas: _items.length + _incomplete.length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _mainTabChip(_Tab.guardados, 'Guardados', counts[_Tab.guardados]!),
            _mainTabChip(_Tab.historial, 'Historial', counts[_Tab.historial]!),
            _mainTabChip(
                _Tab.descargas, 'Descargados', counts[_Tab.descargas]!),
          ],
        ),
      ),
    );
  }

  Widget _mainTabChip(_Tab tab, String label, int count) {
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectMode) {
            setState(() {
              _selectMode = false;
              _selected.clear();
            });
          }
          setState(() => _tab = tab);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.deepPurple],
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _kAccent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'sans-serif',
                    color: selected ? Colors.white : Colors.white60,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                    height: 1.2,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'sans-serif',
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoFilters() {
    int countTodos;
    int countPelis;
    int countSeries;

    switch (_tab) {
      case _Tab.guardados:
        countTodos = _guardados.length;
        countPelis = _guardados.where((e) {
          final t = (e['tipo'] ?? e['type'] ?? e['media_type'] ?? 'movie')
              .toString()
              .toLowerCase();
          return t == 'movie' || t == 'pelicula';
        }).length;
        countSeries = countTodos - countPelis;
        break;
      case _Tab.historial:
        countTodos = _historial.length;
        countPelis = _historial.where((e) {
          final t = (e['tipo'] ?? 'movie').toString().toLowerCase();
          return t == 'movie' || t == 'pelicula';
        }).length;
        countSeries = countTodos - countPelis;
        break;
      case _Tab.descargas:
        countTodos = _items.length + _incomplete.length;
        countPelis = [..._items, ..._incomplete].where((e) {
          final t = (e.tipo ?? '').toLowerCase();
          return t == 'movie' || t == 'pelicula' || t.isEmpty;
        }).length;
        countSeries = countTodos - countPelis;
        break;
    }

    // Chips horizontales estilo Home (géneros) — sin aplastar el texto
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: [
          _tipoChip(_TipoFilter.todos, 'Todos', countTodos),
          const SizedBox(width: 8),
          _tipoChip(_TipoFilter.peliculas, 'Películas', countPelis),
          const SizedBox(width: 8),
          _tipoChip(_TipoFilter.series, 'Series', countSeries),
        ],
      ),
    );
  }

  Widget _tipoChip(_TipoFilter f, String label, int count) {
    final selected = _tipo == f;
    return GestureDetector(
      onTap: () => setState(() => _tipo = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Colors.purpleAccent, Colors.deepPurple],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'sans-serif',
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                height: 1.2,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'sans-serif',
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(double bottomPad) {
    switch (_tab) {
      case _Tab.guardados:
        return _buildGuardadosList(bottomPad);
      case _Tab.historial:
        return _buildHistorialList(bottomPad);
      case _Tab.descargas:
        return _buildDescargasList(bottomPad);
    }
  }

  // ─── GALERÍA GUARDADOS (igual al original: grid 3 columnas) ──────────────
  Widget _buildGuardadosList(double bottomPad) {
    final list = _filteredGuardados;
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
          _emptyState(
            Icons.bookmark_border_rounded,
            'Aún no has guardado nada',
            'Guarda películas y series desde su ficha',
          ),
        ],
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 100 + bottomPad),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 120 / 180,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final item = list[i];
        final id =
            'g:${item['tmdb_id'] ?? item['idtmdb'] ?? item['idcontenido']}';
        final selected = _selected.contains(id);
        final poster = _posterFromItem(item);
        final year = () {
          final rd = item['release_date']?.toString() ??
              item['first_air_date']?.toString() ??
              '';
          if (rd.length >= 4) return rd.substring(0, 4);
          return item['year']?.toString() ?? '';
        }();

        return GestureDetector(
          onTap: () {
            if (_selectMode) {
              _toggleSelect(id);
            } else {
              _openGuardado(item);
            }
          },
          onLongPress: () {
            if (_selectMode) {
              _toggleSelect(id);
            } else {
              // Mantener pulsado → modal de opciones (como el original)
              _showOpcionesModal(item);
            }
          },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _kCardBg,
                  border: selected
                      ? Border.all(color: _kAccent, width: 2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: poster.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        fadeInDuration: const Duration(milliseconds: 100),
                        placeholder: (_, __) =>
                            const ColoredBox(color: _kCardBg),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: _kCardBg,
                          child: Icon(Icons.movie,
                              color: Colors.white24, size: 28),
                        ),
                      )
                    : const ColoredBox(
                        color: _kCardBg,
                        child: Icon(Icons.movie,
                            color: Colors.white24, size: 28),
                      ),
              ),
              if (year.isNotEmpty && !_selectMode)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      year,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (_selectMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected ? _kAccent : Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─── GALERÍA HISTORIAL (banners como el original Continuar viendo) ───────
  Widget _buildHistorialList(double bottomPad) {
    final list = _filteredHistorial;
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
          _emptyState(
            Icons.history_rounded,
            'No hay historial',
            'Los títulos que veas aparecerán aquí',
          ),
        ],
      );
    }

    // Grid de banners estilo original (2 columnas en pantallas normales)
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 100 + bottomPad),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final item = list[i];
        final id = 'h:${item['_cacheKey'] ?? item['idcontenido']}';
        final selected = _selected.contains(id);
        final title = item['titulo']?.toString() ??
            item['title']?.toString() ??
            'Sin título';
        final tipo = (item['tipo'] ?? 'movie').toString().toLowerCase();
        final segundo = item['segundo'] as int? ?? 0;
        final m = segundo ~/ 60;
        final s = segundo % 60;
        final timeLabel =
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

        String meta;
        if (tipo == 'tv' &&
            item['temporada'] != null &&
            item['capitulo'] != null) {
          meta =
              'T${item['temporada'].toString().padLeft(2, '0')}E${item['capitulo'].toString().padLeft(2, '0')}';
        } else {
          meta = tipo == 'tv' ? 'Serie' : 'Película';
        }

        // Backdrop preferido, si no poster (misma lógica _firstUrl que content_page)
        String image = _resolveImageUrl(item['backdrop'], size: 'w780');
        if (image.isEmpty) {
          image = _resolveImageUrl(item['backdrop_path'], size: 'w780');
        }
        if (image.isEmpty) image = _posterFromItem(item);

        return GestureDetector(
          onTap: () {
            if (_selectMode) {
              _toggleSelect(id);
            } else {
              _openHistorial(item);
            }
          },
          onLongPress: () {
            if (_selectMode) {
              _toggleSelect(id);
            } else {
              _showOpcionesModal(item);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                image.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 100),
                        placeholder: (_, __) =>
                            const ColoredBox(color: Color(0xFF1a1a1a)),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: Color(0xFF1a1a1a),
                          child: Icon(Icons.movie,
                              color: Colors.white24, size: 36),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFF1a1a1a),
                        child:
                            Icon(Icons.movie, color: Colors.white24, size: 36),
                      ),
                // Gradiente inferior
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Barra de progreso
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.white.withValues(alpha: 0.2),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (segundo / 4200).clamp(0.06, 1.0),
                      child: Container(color: _kAccent),
                    ),
                  ),
                ),
                // Tiempo
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      timeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: Container(
                      color: _kAccent.withValues(alpha: 0.25),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: _kAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── LISTA DESCARGAS ─────────────────────────────────────────────────────
  Widget _buildDescargasList(double bottomPad) {
    final downloading = _downloading;
    final cancelled = _cancelled;
    final groups = _groups;
    final incomplete = _filteredIncomplete;
    final isEmpty = downloading.isEmpty &&
        cancelled.isEmpty &&
        groups.isEmpty &&
        incomplete.isEmpty;

    if (isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
          _emptyState(
            Icons.download_for_offline_outlined,
            'No hay descargas',
            'Usa “Descarga directa” en el extractor',
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 100 + bottomPad),
      children: [
        if (downloading.isNotEmpty) ...[
          _sectionHeader('Descargando', downloading.length),
          const SizedBox(height: 8),
          ...downloading.map(_buildActiveCard),
          const SizedBox(height: 20),
        ],
        if (cancelled.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: _sectionHeader('Cancelados', cancelled.length),
              ),
              TextButton(
                onPressed: _clearCancelled,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Limpiar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...cancelled.map(_buildCancelledCard),
          const SizedBox(height: 20),
        ],
        if (incomplete.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: _sectionHeader('Inconclusas', incomplete.length),
              ),
              if (!_selectMode)
                TextButton(
                  onPressed: _deleteAllIncomplete,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Limpiar todas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...incomplete.map(_buildIncompleteCard),
          const SizedBox(height: 20),
        ],
        if (groups.isNotEmpty) ...[
          _sectionHeader('Descargados', groups.length),
          const SizedBox(height: 8),
          ...groups.map(_buildSeriesCard),
        ],
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 42,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(title, style: _kSectionTitle),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontFamily: 'sans-serif',
              color: _kAccent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Cards de descargas (reutilizadas) ───────────────────────────────────
  Widget _buildActiveCard(ActiveDownload d) {
    final pct = (d.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final threads = _dm.segmentConcurrency;
    final segInfo = d.totalSegments > 0
        ? 'Segmento ${d.completedSegments}/${d.totalSegments}'
        : d.statusText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: _kCard.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _kGreen.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildPoster(
                      remoteUrl: d.posterUrl,
                      width: 44,
                      height: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            segInfo,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _dm.cancel(d.id),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 14, color: _kGreen.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Text(
                      '$threads hilos',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Inicio ${_fmtTime(d.startedAt)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _endEstimateLabel(d),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: d.progress > 0.02 ? d.progress : null,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: _kGreen,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: _kGreen,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      d.etaLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelledCard(ActiveDownload d) {
    final isFailed = d.status == DownloadStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.35),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            _buildPoster(
              remoteUrl: d.posterUrl,
              width: 48,
              height: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFailed ? 'Fallido' : 'Cancelado',
                    style: TextStyle(
                      color: Colors.redAccent.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              onPressed: () {
                _dm.remove(d.id);
                setState(() {});
              },
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white38,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompleteCard(_DownloadItem item) {
    final selected = _selected.contains(item.folderPath);
    final epLabel = _episodeLabel(item);
    final displayTitle =
        epLabel != null ? '${item.title} · $epLabel' : item.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (_selectMode) {
                _toggleSelect(item.folderPath);
              }
            },
            onLongPress: () {
              if (_selectMode) {
                _toggleSelect(item.folderPath);
              } else {
                _showOpcionesModalDownload(item);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: selected
                    ? _kOrange.withValues(alpha: 0.18)
                    : _kCard.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _kOrange.withValues(alpha: 0.6)
                      : _kOrange.withValues(alpha: 0.35),
                  width: selected ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  _selectMode
                      ? Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: selected
                                ? _kOrange
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            selected
                                ? Icons.check_rounded
                                : Icons.circle_outlined,
                            color: selected ? Colors.white : Colors.white38,
                            size: 22,
                          ),
                        )
                      : _buildPoster(
                          localPath: item.localPosterPath,
                          remoteUrl: item.posterUrl,
                          width: 48,
                          height: 48,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Inconclusa · ${_formatSize(item.sizeBytes)}',
                          style: TextStyle(
                            color: _kOrange.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_selectMode)
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteOneDownload(item),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesCard(_SeriesGroup group) {
    final allSelected =
        group.episodes.every((e) => _selected.contains(e.folderPath));
    final someSelected =
        group.episodes.any((e) => _selected.contains(e.folderPath));
    final epCount = group.episodes.length;
    final first = group.episodes.first;
    final String subtitle;
    if (epCount > 1) {
      subtitle = '$epCount capítulos · ${_formatSize(group.totalBytes)}';
    } else {
      final epLabel = _episodeLabel(first);
      subtitle = epLabel != null
          ? '$epLabel · ${_formatSize(group.totalBytes)}'
          : _formatSize(group.totalBytes);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openSeriesSheet(group),
              onLongPress: () {
                if (_selectMode) {
                  _openSeriesSheet(group); // toggle selección del grupo
                } else {
                  // Modal del primer episodio con tmdbId
                  final first = group.episodes.firstWhere(
                    (e) => e.tmdbId != null && e.tmdbId! > 0,
                    orElse: () => group.episodes.first,
                  );
                  _showOpcionesModalDownload(first);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: someSelected
                      ? _kAccent.withValues(alpha: 0.18)
                      : _kCard.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: someSelected
                        ? _kAccent.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.1),
                    width: someSelected ? 1.5 : 0.8,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _selectMode
                          ? Container(
                              key: const ValueKey('check'),
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: allSelected
                                    ? _kAccent
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: allSelected
                                    ? null
                                    : Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                      ),
                              ),
                              child: Icon(
                                allSelected
                                    ? Icons.check_rounded
                                    : Icons.circle_outlined,
                                color:
                                    allSelected ? Colors.white : Colors.white38,
                                size: 22,
                              ),
                            )
                          : _buildPoster(
                              key: const ValueKey('poster'),
                              localPath: first.localPosterPath,
                              remoteUrl: first.posterUrl,
                              width: 48,
                              height: 48,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_selectMode)
                      Icon(
                        epCount > 1
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODELOS
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadItem {
  final String folderPath;
  final String playlistPath;
  final String title;
  final DateTime modified;
  final int sizeBytes;
  final bool isIncomplete;
  final int? tmdbId;
  final String? tipo;
  final int? temporada;
  final int? capitulo;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterFile;
  final String? backdropFile;

  _DownloadItem({
    required this.folderPath,
    required this.playlistPath,
    required this.title,
    required this.modified,
    required this.sizeBytes,
    this.isIncomplete = false,
    this.tmdbId,
    this.tipo,
    this.temporada,
    this.capitulo,
    this.posterUrl,
    this.backdropUrl,
    this.posterFile,
    this.backdropFile,
  });

  String? get localPosterPath =>
      posterFile != null ? '$folderPath/$posterFile' : null;
}

class _SeriesGroup {
  final String title;
  final List<_DownloadItem> episodes;

  _SeriesGroup({required this.title, required this.episodes});

  int get totalBytes => episodes.fold(0, (sum, e) => sum + e.sizeBytes);
}