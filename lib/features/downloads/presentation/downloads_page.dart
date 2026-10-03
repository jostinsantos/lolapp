import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'download_manager.dart';
import 'local_player_page.dart';
// ⚠️ AJUSTA esta ruta a donde esté tu PageContenido
import '../../content/presentation/content_page.dart';
const _kAccent = Color(0xFFE50914);
const _kGreen = Color(0xFF4CAF50);
const _kOrange = Color(0xFFFF9800);
const _kCard = Color(0xFF1C1C1E);
const _kBg = Color(0xFF0A0A0A);

class DescargasPage extends StatefulWidget {
  const DescargasPage({super.key});

  @override
  State<DescargasPage> createState() => _DescargasPageState();
}

class _DescargasPageState extends State<DescargasPage> {
  final _dm = DownloadManager.instance;

  List<_DownloadItem> _items = [];
  List<_DownloadItem> _incomplete = [];
  bool _loading = true;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _dm.addListener(_onDm);
    _dm.loadSettings();
    _loadDownloads();
  }

  @override
  void dispose() {
    _dm.removeListener(_onDm);
    super.dispose();
  }

  void _onDm() {
    if (!mounted) return;
    setState(() {});
    final justDone = _dm.all.any((d) => d.status == DownloadStatus.completed);
    if (justDone) _loadDownloads();
  }

  /// Solo descargas realmente activas
  List<ActiveDownload> get _downloading => _dm.all
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued)
      .toList();

  /// Solo cancelados / fallidos
  List<ActiveDownload> get _cancelled => _dm.all
      .where((d) =>
          d.status == DownloadStatus.cancelled ||
          d.status == DownloadStatus.failed)
      .toList();

  /// Extrae nombre de serie y etiqueta Txx Cyy desde el título (fallback
  /// cuando no hay temporada/capitulo en meta).
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

  /// Etiqueta de episodio: prioriza temporada/capitulo de meta; si no, parsea el título.
  static String? _episodeLabel(_DownloadItem item) {
    if (item.temporada != null && item.capitulo != null) {
      final s = item.temporada!.toString().padLeft(2, '0');
      final e = item.capitulo!.toString().padLeft(2, '0');
      return 'T$s C$e';
    }
    return _parseTitle(item.title).episode;
  }

  /// Nombre de serie para agrupar.
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
    for (final item in _items) {
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
      setState(() {
        _loading = true;
        _error = null;
      });
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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

  // ─── Poster thumbnail ────────────────────────────────────────────────
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
      child = Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _posterFallback(),
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
      color: _kAccent.withValues(alpha: 0.15),
      child: const Icon(Icons.movie_rounded, color: _kAccent, size: 24),
    );
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selected.clear();
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  List<_DownloadItem> get _allSelectable => [..._items, ..._incomplete];

  void _selectAll() {
    setState(() {
      final all = _allSelectable;
      if (_selected.length == all.length && all.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((e) => e.folderPath));
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
          'Eliminar descargas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Borrar ${_selected.length} descarga${_selected.length == 1 ? '' : 's'}?',
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

    for (final path in _selected.toList()) {
      try {
        _DownloadItem? item;
        for (final e in _allSelectable) {
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
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    await _loadDownloads();
  }

  Future<void> _deleteOne(_DownloadItem item) async {
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

    // Un solo ítem y sin temporada/capítulo → abrir directo
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
                              _deleteOne(ep);
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

  @override
  Widget build(BuildContext context) {
    final downloading = _downloading;
    final cancelled = _cancelled;
    final groups = _groups;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isEmpty = downloading.isEmpty &&
        cancelled.isEmpty &&
        _items.isEmpty &&
        _incomplete.isEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _selectMode
              ? '${_selected.length} seleccionada${_selected.length == 1 ? '' : 's'}'
              : 'Descargas',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: 'Seleccionar todo',
              icon: Icon(
                _selected.length == _allSelectable.length &&
                        _allSelectable.isNotEmpty
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: Colors.white70,
              ),
              onPressed: _allSelectable.isEmpty ? null : _selectAll,
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
            if (_items.isNotEmpty || _incomplete.isNotEmpty)
              IconButton(
                tooltip: 'Seleccionar',
                icon:
                    const Icon(Icons.checklist_rounded, color: Colors.white70),
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
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: _loadDownloads,
            ),
          ],
        ],
      ),
      body: _loading && _items.isEmpty && _incomplete.isEmpty
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : _error != null && _items.isEmpty && _incomplete.isEmpty
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
              : isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: _kAccent,
                      backgroundColor: _kCard,
                      onRefresh: _loadDownloads,
                      child: ListView(
                        padding:
                            EdgeInsets.fromLTRB(16, 4, 16, 100 + bottomPad),
                        children: [
                          // ─── DESCARGANDO ─────────────────────────────
                          if (downloading.isNotEmpty) ...[
                            _sectionHeader('Descargando', downloading.length),
                            const SizedBox(height: 8),
                            ...downloading.map(_buildActiveCard),
                            const SizedBox(height: 20),
                          ],

                          // ─── CANCELADOS ──────────────────────────────
                          if (cancelled.isNotEmpty) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _sectionHeader(
                                      'Cancelados', cancelled.length),
                                ),
                                TextButton(
                                  onPressed: _clearCancelled,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Limpiar',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...cancelled.map(_buildCancelledCard),
                            const SizedBox(height: 20),
                          ],

                          // ─── INCONCLUSAS ─────────────────────────────
                          if (_incomplete.isNotEmpty) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _sectionHeader(
                                    'Inconclusas',
                                    _incomplete.length,
                                  ),
                                ),
                                if (!_selectMode)
                                  TextButton(
                                    onPressed: _deleteAllIncomplete,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.orangeAccent,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                            ..._incomplete.map(_buildIncompleteCard),
                            const SizedBox(height: 20),
                          ],

                          // ─── DESCARGADOS (Biblioteca) ────────────────
                          if (groups.isNotEmpty) ...[
                            _sectionHeader('Descargados', groups.length),
                            const SizedBox(height: 8),
                            ...groups.map(_buildSeriesCard),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildEmpty() {
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
              Icons.download_for_offline_outlined,
              size: 42,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No hay descargas',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Usa “Descarga directa” en el extractor',
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
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

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
              if (!_selectMode) {
                setState(() {
                  _selectMode = true;
                  _selected.add(item.folderPath);
                });
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
                      onPressed: () => _deleteOne(item),
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
                if (!_selectMode) {
                  setState(() {
                    _selectMode = true;
                    for (final e in group.episodes) {
                      _selected.add(e.folderPath);
                    }
                  });
                } else {
                  _openSeriesSheet(group);
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