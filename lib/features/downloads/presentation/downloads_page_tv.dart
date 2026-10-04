import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'download_manager.dart';
import 'local_player_tv.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

class DescargasPageTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const DescargasPageTv({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<DescargasPageTv> createState() => _DescargasPageTvState();
}

class _DescargasPageTvState extends State<DescargasPageTv>
    with WidgetsBindingObserver {
  final _dm = DownloadManager.instance;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'descargas_tv_root');
  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _epScrollCtrl = ScrollController();

  List<_TvDlItem> _rawItems = [];
  List<_TvGroup> _groups = [];

  bool _loading = true;
  String? _error;

  List<FocusNode> _itemNodes = [];
  List<FocusNode> _activeNodes = [];

  bool _drawerOpen = false;
  _TvGroup? _drawerGroup;
  int? _selectedSeason;
  final FocusNode _drawerRootFocus =
      FocusNode(debugLabel: 'drawer_series_root');
  final FocusNode _closeDrawerFocus =
      FocusNode(debugLabel: 'drawer_close');
  List<FocusNode> _seasonNodes = [];
  List<FocusNode> _epNodes = [];

  bool _modalOpen = false;
  _TvDlItem? _modalItem;
  final FocusNode _modalPlayFocus = FocusNode(debugLabel: 'modal_play');
  final FocusNode _modalDeleteFocus = FocusNode(debugLabel: 'modal_delete');
  final FocusNode _modalCancelFocus = FocusNode(debugLabel: 'modal_cancel');

  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  static const _longPressDuration = Duration(milliseconds: 550);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _forceLandscape();
    _dm.addListener(_onDm);
    _dm.loadSettings();
    _loadDownloads();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_rootFocus);
      _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _ignoreSelectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _dm.removeListener(_onDm);
    _rootFocus.dispose();
    _scrollCtrl.dispose();
    _epScrollCtrl.dispose();
    _drawerRootFocus.dispose();
    _closeDrawerFocus.dispose();
    _modalPlayFocus.dispose();
    _modalDeleteFocus.dispose();
    _modalCancelFocus.dispose();
    for (final n in _itemNodes) {
      n.dispose();
    }
    for (final n in _activeNodes) {
      n.dispose();
    }
    for (final n in _seasonNodes) {
      n.dispose();
    }
    for (final n in _epNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _forceLandscape() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _forceLandscape();
  }

  void _onDm() {
    if (!mounted) return;
    final prevActive = _activeNodes.length;
    setState(() {});
    if (_downloading.length != prevActive) _resyncActiveNodes();
  }

  List<ActiveDownload> get _downloading => _dm.all
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued)
      .toList();

  Future<void> _loadDownloads() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await _dm.getBaseDir();
      final list = <_TvDlItem>[];
      if (await base.exists()) {
        await for (final entity in base.list()) {
          if (entity is! Directory) continue;
          final metaFile = File('${entity.path}/meta.json');
          Map<String, dynamic>? meta;
          if (await metaFile.exists()) {
            try {
              meta = jsonDecode(await metaFile.readAsString())
                  as Map<String, dynamic>;
            } catch (_) {}
          }

          String? videoPath;
          final playlist = File('${entity.path}/playlist.m3u8');
          if (await playlist.exists()) {
            videoPath = playlist.path;
          } else {
            await for (final f in entity.list()) {
              if (f is File) {
                final name = f.path.toLowerCase();
                if (name.endsWith('.mp4') ||
                    name.endsWith('.mkv') ||
                    name.endsWith('.m4v') ||
                    name.endsWith('.m3u8')) {
                  videoPath = f.path;
                  break;
                }
              }
            }
          }
          if (videoPath == null) continue;

          final title = (meta?['titulo']?.toString().trim().isNotEmpty == true)
              ? meta!['titulo'].toString().trim()
              : entity.path.split(Platform.pathSeparator).last;

          DateTime? downloadedAt;
          final rawDate = meta?['downloadedAt']?.toString();
          if (rawDate != null) {
            downloadedAt = DateTime.tryParse(rawDate);
          }
          downloadedAt ??= (await entity.stat()).modified;

          list.add(_TvDlItem(
            folderPath: entity.path,
            videoPath: videoPath,
            title: title,
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
            downloadedAt: downloadedAt,
          ));
        }
      }

      list.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      final groups = _buildGroups(list);

      if (!mounted) return;

      for (final n in _itemNodes) {
        n.dispose();
      }
      _itemNodes =
          List.generate(groups.length, (i) => FocusNode(debugLabel: 'grp_$i'));

      setState(() {
        _rawItems = list;
        _groups = groups;
        _loading = false;
      });

      _resyncActiveNodes();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_activeNodes.isNotEmpty) {
          _activeNodes.first.requestFocus();
        } else if (_itemNodes.isNotEmpty) {
          _itemNodes.first.requestFocus();
        } else {
          _rootFocus.requestFocus();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  List<_TvGroup> _buildGroups(List<_TvDlItem> items) {
    final seriesMap = <String, List<_TvDlItem>>{};
    final movies = <_TvDlItem>[];

    for (final it in items) {
      final isSeries = (it.tipo == 'tv' || it.tipo == 'series') &&
          (it.temporada != null || it.capitulo != null);
      if (isSeries) {
        final key = it.tmdbId != null
            ? 'tmdb_${it.tmdbId}'
            : 'title_${it.title.toLowerCase().trim()}';
        seriesMap.putIfAbsent(key, () => []).add(it);
      } else {
        movies.add(it);
      }
    }

    final groups = <_TvGroup>[];

    for (final entry in seriesMap.entries) {
      final eps = entry.value;
      eps.sort((a, b) {
        final ta = a.temporada ?? 0;
        final tb = b.temporada ?? 0;
        if (ta != tb) return ta.compareTo(tb);
        return (a.capitulo ?? 0).compareTo(b.capitulo ?? 0);
      });
      final latest = eps
          .map((e) => e.downloadedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      groups.add(_TvGroup(
        isSeries: true,
        title: eps.first.title,
        posterUrl: eps.first.posterUrl,
        tmdbId: eps.first.tmdbId,
        episodes: eps,
        downloadedAt: latest,
      ));
    }

    for (final m in movies) {
      groups.add(_TvGroup(
        isSeries: false,
        title: m.title,
        posterUrl: m.posterUrl,
        tmdbId: m.tmdbId,
        episodes: [m],
        downloadedAt: m.downloadedAt,
      ));
    }

    groups.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return groups;
  }

  void _resyncActiveNodes() {
    for (final n in _activeNodes) {
      n.dispose();
    }
    _activeNodes = List.generate(
      _downloading.length,
      (i) => FocusNode(debugLabel: 'act_$i'),
    );
  }

  /// Evita que al volver del player se re-dispare el select del ítem enfocado.
  bool _ignoreSelectUntil = false;
  Timer? _ignoreSelectTimer;

  void _armIgnoreSelect({Duration duration = const Duration(milliseconds: 600)}) {
    _ignoreSelectUntil = true;
    _ignoreSelectTimer?.cancel();
    _ignoreSelectTimer = Timer(duration, () {
      _ignoreSelectUntil = false;
    });
  }

  List<LocalSeriesEpisode>? _seriesEpisodesFor(_TvDlItem item) {
    final isSeries = (item.tipo == 'tv' || item.tipo == 'series') &&
        item.temporada != null &&
        item.capitulo != null;
    if (!isSeries) return null;

    // Buscar el grupo de la misma serie
    _TvGroup? group;
    for (final g in _groups) {
      if (!g.isSeries) continue;
      if (item.tmdbId != null && g.tmdbId == item.tmdbId) {
        group = g;
        break;
      }
      if (g.episodes.any((e) => e.folderPath == item.folderPath)) {
        group = g;
        break;
      }
    }
    if (group == null || group.episodes.length < 2) return null;

    return group.episodes
        .map((e) => LocalSeriesEpisode(
              videoPath: e.videoPath,
              title: e.displayTitle,
              folderPath: e.folderPath,
              tmdbId: e.tmdbId,
              tipo: e.tipo,
              temporada: e.temporada,
              capitulo: e.capitulo,
            ))
        .toList();
  }

  void _playLocal(_TvDlItem item) {
    _forceLandscape();
    final seriesEps = _seriesEpisodesFor(item);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => LocalPlayerTvScreen(
          playlistPath: item.videoPath,
          title: item.displayTitle,
          folderPath: item.folderPath,
          tmdbId: item.tmdbId,
          tipo: item.tipo,
          temporada: item.temporada,
          capitulo: item.capitulo,
          seriesEpisodes: seriesEps,
        ),
      ),
    )
        .then((_) {
      if (!mounted) return;
      _forceLandscape();
      // Evita reabrir el player / drawer por un select residual al volver.
      _armIgnoreSelect();
      // Devolver foco al root, no al ítem que se acaba de reproducir.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_drawerOpen) {
          if (_epNodes.isNotEmpty) {
            // Mantener drawer abierto pero sin re-disparar play
            final idx = _drawerGroup?.episodes.indexWhere(
                  (e) => e.folderPath == item.folderPath,
                ) ??
                -1;
            if (idx >= 0 && idx < _epNodes.length) {
              _epNodes[idx].requestFocus();
            } else {
              _epNodes.first.requestFocus();
            }
          } else {
            _drawerRootFocus.requestFocus();
          }
        } else {
          _rootFocus.requestFocus();
        }
      });
    });
  }

  Future<void> _deleteItem(_TvDlItem item) async {
    try {
      final dir = Directory(item.folderPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      await _loadDownloads();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  Future<void> _deleteGroup(_TvGroup group) async {
    for (final ep in group.episodes) {
      try {
        final dir = Directory(ep.folderPath);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    await _loadDownloads();
  }

  void _cancelActive(ActiveDownload d) {
    _dm.cancel(d.id);
    setState(() {});
    _resyncActiveNodes();
  }

  void _goMenuOrBack() {
    if (_modalOpen) {
      _closeModal();
      return;
    }
    if (_drawerOpen) {
      _closeDrawer();
      return;
    }
    if (widget.onRequestMenuFocus != null) {
      widget.onRequestMenuFocus!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _scrollToFocused(BuildContext itemContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  void _startLongPress(VoidCallback onLong) {
    _longPressTimer?.cancel();
    _longPressTriggered = false;
    _longPressTimer = Timer(_longPressDuration, () {
      _longPressTriggered = true;
      onLong();
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  bool _handleSelectKey({
    required KeyEvent event,
    required VoidCallback onShort,
    required VoidCallback onLong,
  }) {
    final key = event.logicalKey;
    final isSelect = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space;

    if (!isSelect) return false;

    // Tras cerrar el local player, ignorar select residual que reabría la serie.
    if (_ignoreSelectUntil) {
      return true;
    }

    if (event is KeyDownEvent) {
      _startLongPress(onLong);
      return true;
    }
    if (event is KeyUpEvent) {
      _cancelLongPress();
      if (!_longPressTriggered) {
        onShort();
      }
      _longPressTriggered = false;
      return true;
    }
    return false;
  }

  void _openModal(_TvDlItem item) {
    _cancelLongPress();
    setState(() {
      _modalOpen = true;
      _modalItem = item;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _modalPlayFocus.requestFocus();
    });
  }

  void _closeModal() {
    final lastItem = _modalItem;
    setState(() {
      _modalOpen = false;
      _modalItem = null;
    });
    if (_drawerOpen) {
      if (_epNodes.isNotEmpty) {
        _epNodes.first.requestFocus();
      } else {
        _drawerRootFocus.requestFocus();
      }
    } else if (_itemNodes.isNotEmpty) {
      final idx = _groups.indexWhere((g) =>
          g.episodes.any((e) => e.folderPath == lastItem?.folderPath));
      if (idx >= 0 && idx < _itemNodes.length) {
        _itemNodes[idx].requestFocus();
      } else {
        _itemNodes.first.requestFocus();
      }
    } else {
      _rootFocus.requestFocus();
    }
  }

  void _openDrawer(_TvGroup group) {
    for (final n in _seasonNodes) {
      n.dispose();
    }
    for (final n in _epNodes) {
      n.dispose();
    }

    final seasons = group.seasons;
    _seasonNodes =
        List.generate(seasons.length, (i) => FocusNode(debugLabel: 'sea_$i'));
    final firstSeason = seasons.isNotEmpty ? seasons.first : null;
    final eps = firstSeason != null
        ? group.episodesForSeason(firstSeason)
        : <_TvDlItem>[];
    _epNodes =
        List.generate(eps.length, (i) => FocusNode(debugLabel: 'ep_$i'));

    setState(() {
      _drawerOpen = true;
      _drawerGroup = group;
      _selectedSeason = firstSeason;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_seasonNodes.isNotEmpty) {
        _seasonNodes.first.requestFocus();
      } else {
        _drawerRootFocus.requestFocus();
      }
    });
  }

  void _closeDrawer() {
    setState(() {
      _drawerOpen = false;
      _drawerGroup = null;
      _selectedSeason = null;
    });
    if (_itemNodes.isNotEmpty) {
      _itemNodes.first.requestFocus();
    } else {
      _rootFocus.requestFocus();
    }
  }

  void _selectSeason(int season) {
    final group = _drawerGroup;
    if (group == null) return;
    for (final n in _epNodes) {
      n.dispose();
    }
    final eps = group.episodesForSeason(season);
    _epNodes =
        List.generate(eps.length, (i) => FocusNode(debugLabel: 'ep_$i'));
    setState(() => _selectedSeason = season);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_epNodes.isNotEmpty) _epNodes.first.requestFocus();
    });
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      _goMenuOrBack();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_activeNodes.isNotEmpty) {
        _activeNodes.first.requestFocus();
      } else if (_itemNodes.isNotEmpty) {
        _itemNodes.first.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _forceLandscape();
    final active = _downloading;
    final screenW = MediaQuery.of(context).size.width;
    final crossAxisCount = screenW > 1200 ? 6 : (screenW > 900 ? 5 : 4);

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: _onRootKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(color: _kAccent),
                            )
                          : _error != null
                              ? Center(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                        color: Colors.redAccent),
                                  ),
                                )
                              : CustomScrollView(
                                  controller: _scrollCtrl,
                                  slivers: [
                                    if (active.isNotEmpty) ...[
                                      const SliverToBoxAdapter(
                                        child: Padding(
                                          padding: EdgeInsets.only(bottom: 10),
                                          child: Text(
                                            'En curso',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (ctx, i) {
                                            final d = active[i];
                                            final node =
                                                i < _activeNodes.length
                                                    ? _activeNodes[i]
                                                    : FocusNode();
                                            final pct = (d.progress * 100)
                                                .clamp(0, 100)
                                                .round();
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: Focus(
                                                focusNode: node,
                                                onFocusChange: (has) {
                                                  if (has &&
                                                      node.context != null) {
                                                    _scrollToFocused(
                                                        node.context!);
                                                  }
                                                },
                                                onKeyEvent: (n, event) {
                                                  if (event
                                                      is! KeyDownEvent) {
                                                    return KeyEventResult
                                                        .ignored;
                                                  }
                                                  final key =
                                                      event.logicalKey;
                                                  if (key ==
                                                          LogicalKeyboardKey
                                                              .select ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .enter) {
                                                    _cancelActive(d);
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                  if (key ==
                                                          LogicalKeyboardKey
                                                              .arrowLeft ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .goBack ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .escape) {
                                                    _goMenuOrBack();
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                  if (key ==
                                                      LogicalKeyboardKey
                                                          .arrowUp) {
                                                    if (i > 0) {
                                                      _activeNodes[i - 1]
                                                          .requestFocus();
                                                    } else {
                                                      _rootFocus
                                                          .requestFocus();
                                                    }
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                  if (key ==
                                                      LogicalKeyboardKey
                                                          .arrowDown) {
                                                    if (i <
                                                        _activeNodes
                                                                .length -
                                                            1) {
                                                      _activeNodes[i + 1]
                                                          .requestFocus();
                                                    } else if (_itemNodes
                                                        .isNotEmpty) {
                                                      _itemNodes.first
                                                          .requestFocus();
                                                    }
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                  return KeyEventResult
                                                      .ignored;
                                                },
                                                child: Builder(
                                                  builder: (context) {
                                                    final hasFocus =
                                                        Focus.of(context)
                                                            .hasFocus;
                                                    return GestureDetector(
                                                      onTap: () =>
                                                          _cancelActive(d),
                                                      child:
                                                          AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    140),
                                                        width:
                                                            double.infinity,
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: _kCard,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12),
                                                          border:
                                                              Border.all(
                                                            color: hasFocus
                                                                ? _kAccent
                                                                : Colors
                                                                    .transparent,
                                                            width: 2.5,
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              d.displayTitle,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  TextStyle(
                                                                color: hasFocus
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .white70,
                                                                fontSize:
                                                                    15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 10),
                                                            LinearProgressIndicator(
                                                              value: d.progress >
                                                                      0.01
                                                                  ? d.progress
                                                                  : null,
                                                              color:
                                                                  _kAccent,
                                                              backgroundColor:
                                                                  Colors
                                                                      .white12,
                                                              minHeight: 5,
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                              '$pct% · ${d.statusText} · OK para cancelar',
                                                              style:
                                                                  TextStyle(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.5),
                                                                fontSize:
                                                                    12,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                          childCount: active.length,
                                        ),
                                      ),
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 12),
                                      ),
                                    ],
                                    const SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: Text(
                                          'Completadas',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_groups.isEmpty)
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 40),
                                          child: Center(
                                            child: Text(
                                              'No hay descargas',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.4),
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: 14,
                                          crossAxisSpacing: 14,
                                          childAspectRatio: 0.62,
                                        ),
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (ctx, i) {
                                            final group = _groups[i];
                                            final node =
                                                i < _itemNodes.length
                                                    ? _itemNodes[i]
                                                    : FocusNode();
                                            return Focus(
                                              focusNode: node,
                                              onFocusChange: (has) {
                                                if (has &&
                                                    node.context != null) {
                                                  _scrollToFocused(
                                                      node.context!);
                                                }
                                              },
                                              onKeyEvent: (n, event) {
                                                final handled =
                                                    _handleSelectKey(
                                                  event: event,
                                                  onShort: () {
                                                    if (group.isSeries) {
                                                      _openDrawer(group);
                                                    } else {
                                                      _playLocal(group
                                                          .episodes.first);
                                                    }
                                                  },
                                                  onLong: () {
                                                    _openModal(group
                                                        .episodes.first);
                                                  },
                                                );
                                                if (handled) {
                                                  return KeyEventResult
                                                      .handled;
                                                }

                                                if (event
                                                    is! KeyDownEvent) {
                                                  return KeyEventResult
                                                      .ignored;
                                                }
                                                final key =
                                                    event.logicalKey;

                                                if (key ==
                                                    LogicalKeyboardKey
                                                        .contextMenu) {
                                                  _openModal(group
                                                      .episodes.first);
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                if (key ==
                                                    LogicalKeyboardKey
                                                        .delete) {
                                                  if (group.isSeries) {
                                                    _deleteGroup(group);
                                                  } else {
                                                    _deleteItem(group
                                                        .episodes.first);
                                                  }
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                if (key ==
                                                        LogicalKeyboardKey
                                                            .arrowLeft ||
                                                    key ==
                                                        LogicalKeyboardKey
                                                            .goBack ||
                                                    key ==
                                                        LogicalKeyboardKey
                                                            .escape) {
                                                  if (i % crossAxisCount ==
                                                      0) {
                                                    _goMenuOrBack();
                                                  } else if (i > 0) {
                                                    _itemNodes[i - 1]
                                                        .requestFocus();
                                                  }
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                if (key ==
                                                    LogicalKeyboardKey
                                                        .arrowRight) {
                                                  if (i <
                                                      _itemNodes.length -
                                                          1) {
                                                    _itemNodes[i + 1]
                                                        .requestFocus();
                                                  }
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                if (key ==
                                                    LogicalKeyboardKey
                                                        .arrowUp) {
                                                  final up =
                                                      i - crossAxisCount;
                                                  if (up >= 0) {
                                                    _itemNodes[up]
                                                        .requestFocus();
                                                  } else if (_activeNodes
                                                      .isNotEmpty) {
                                                    _activeNodes.last
                                                        .requestFocus();
                                                  } else {
                                                    _rootFocus
                                                        .requestFocus();
                                                  }
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                if (key ==
                                                    LogicalKeyboardKey
                                                        .arrowDown) {
                                                  final down =
                                                      i + crossAxisCount;
                                                  if (down <
                                                      _itemNodes.length) {
                                                    _itemNodes[down]
                                                        .requestFocus();
                                                  } else if (i <
                                                      _itemNodes.length -
                                                          1) {
                                                    _itemNodes.last
                                                        .requestFocus();
                                                  }
                                                  return KeyEventResult
                                                      .handled;
                                                }
                                                return KeyEventResult
                                                    .ignored;
                                              },
                                              child: Builder(
                                                builder: (context) {
                                                  final hasFocus =
                                                      Focus.of(context)
                                                          .hasFocus;
                                                  return GestureDetector(
                                                    onTap: () {
                                                      if (group.isSeries) {
                                                        _openDrawer(group);
                                                      } else {
                                                        _playLocal(group
                                                            .episodes
                                                            .first);
                                                      }
                                                    },
                                                    onLongPress: () {
                                                      _openModal(group
                                                          .episodes.first);
                                                    },
                                                    child:
                                                        AnimatedContainer(
                                                      duration:
                                                          const Duration(
                                                              milliseconds:
                                                                  140),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: _kCard,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    12),
                                                        border: Border.all(
                                                          color: hasFocus
                                                              ? _kAccent
                                                              : Colors
                                                                  .transparent,
                                                          width: 2.5,
                                                        ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Expanded(
                                                            child: ClipRRect(
                                                              borderRadius:
                                                                  const BorderRadius
                                                                      .vertical(
                                                                top: Radius
                                                                    .circular(
                                                                        10),
                                                              ),
                                                              child: group.posterUrl !=
                                                                          null &&
                                                                      group
                                                                          .posterUrl!
                                                                          .isNotEmpty
                                                                  ? Image
                                                                      .network(
                                                                      group
                                                                          .posterUrl!,
                                                                      fit: BoxFit
                                                                          .cover,
                                                                      width:
                                                                          double
                                                                              .infinity,
                                                                      errorBuilder: (_,
                                                                              __,
                                                                              ___) =>
                                                                          _posterPlaceholderLarge(),
                                                                    )
                                                                  : _posterPlaceholderLarge(),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .fromLTRB(
                                                                    8,
                                                                    8,
                                                                    8,
                                                                    10),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  group
                                                                      .title,
                                                                  maxLines:
                                                                      2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      TextStyle(
                                                                    color: hasFocus
                                                                        ? Colors
                                                                            .white
                                                                        : Colors
                                                                            .white70,
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    height:
                                                                        1.2,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    height:
                                                                        4),
                                                                Text(
                                                                  group.isSeries
                                                                      ? '${group.episodes.length} ep · ${group.seasons.length} temp'
                                                                      : 'Película',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .white
                                                                        .withValues(
                                                                            alpha: 0.45),
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                          childCount: _groups.length,
                                        ),
                                      ),
                                  ],
                                ),
                    ),
                  ],
                ),
              ),
              if (_drawerOpen && _drawerGroup != null) _buildSeriesDrawer(),
              if (_modalOpen && _modalItem != null) _buildActionModal(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterPlaceholderLarge() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      width: 48,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 28),
    );
  }

  Widget _buildSeriesDrawer() {
    final group = _drawerGroup!;
    final seasons = group.seasons;
    final selected = _selectedSeason;
    final eps = selected != null
        ? group.episodesForSeason(selected)
        : <_TvDlItem>[];

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.55,
      child: Focus(
        focusNode: _drawerRootFocus,
        onKeyEvent: (n, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.arrowLeft) {
            _closeDrawer();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: const Color(0xFF121214),
          elevation: 16,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Focus(
                        focusNode: _closeDrawerFocus,
                        onKeyEvent: (n, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          final key = event.logicalKey;
                          if (key == LogicalKeyboardKey.select ||
                              key == LogicalKeyboardKey.enter) {
                            _closeDrawer();
                            return KeyEventResult.handled;
                          }
                          if (key == LogicalKeyboardKey.arrowDown) {
                            if (_seasonNodes.isNotEmpty) {
                              _seasonNodes.first.requestFocus();
                            } else if (_epNodes.isNotEmpty) {
                              _epNodes.first.requestFocus();
                            }
                            return KeyEventResult.handled;
                          }
                          if (key == LogicalKeyboardKey.arrowLeft ||
                              key == LogicalKeyboardKey.goBack ||
                              key == LogicalKeyboardKey.escape) {
                            _closeDrawer();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (c) {
                          final has = Focus.of(c).hasFocus;
                          return GestureDetector(
                            onTap: _closeDrawer,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: has
                                    ? _kAccent.withValues(alpha: 0.25)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      has ? _kAccent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.close,
                                color: has ? Colors.white : Colors.white54,
                                size: 24,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: seasons.length,
                    itemBuilder: (ctx, i) {
                      final s = seasons[i];
                      final node = i < _seasonNodes.length
                          ? _seasonNodes[i]
                          : FocusNode();
                      final isSel = s == selected;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Focus(
                          focusNode: node,
                          onFocusChange: (has) {
                            if (has && node.context != null) {
                              _scrollToFocused(node.context!);
                            }
                          },
                          onKeyEvent: (n, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter) {
                              _selectSeason(s);
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              if (i > 0) {
                                _seasonNodes[i - 1].requestFocus();
                              } else {
                                _closeDrawer();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowRight) {
                              if (i < _seasonNodes.length - 1) {
                                _seasonNodes[i + 1].requestFocus();
                              } else {
                                _closeDrawerFocus.requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _closeDrawerFocus.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowDown) {
                              if (_epNodes.isNotEmpty) {
                                _epNodes.first.requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.goBack ||
                                key == LogicalKeyboardKey.escape) {
                              _closeDrawer();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(builder: (c) {
                            final has = Focus.of(c).hasFocus;
                            return GestureDetector(
                              onTap: () => _selectSeason(s),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? _kAccent.withValues(alpha: 0.25)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: has
                                        ? _kAccent
                                        : (isSel
                                            ? _kAccent.withValues(
                                                alpha: 0.5)
                                            : Colors.transparent),
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  'T$s',
                                  style: TextStyle(
                                    color: has || isSel
                                        ? Colors.white
                                        : Colors.white60,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: eps.isEmpty
                      ? Center(
                          child: Text(
                            'Sin episodios',
                            style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.4)),
                          ),
                        )
                      : ListView.builder(
                          controller: _epScrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(12, 10, 12, 20),
                          itemCount: eps.length,
                          itemBuilder: (ctx, i) {
                            final ep = eps[i];
                            final node = i < _epNodes.length
                                ? _epNodes[i]
                                : FocusNode();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Focus(
                                focusNode: node,
                                onFocusChange: (has) {
                                  if (has && node.context != null) {
                                    _scrollToFocused(node.context!);
                                  }
                                },
                                onKeyEvent: (n, event) {
                                  final handled = _handleSelectKey(
                                    event: event,
                                    onShort: () => _playLocal(ep),
                                    onLong: () => _openModal(ep),
                                  );
                                  if (handled) {
                                    return KeyEventResult.handled;
                                  }

                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final key = event.logicalKey;

                                  if (key ==
                                          LogicalKeyboardKey.contextMenu ||
                                      key == LogicalKeyboardKey.delete) {
                                    _openModal(ep);
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowUp) {
                                    if (i > 0) {
                                      _epNodes[i - 1].requestFocus();
                                    } else if (_seasonNodes.isNotEmpty) {
                                      final si = seasons.indexOf(
                                          selected ?? seasons.first);
                                      if (si >= 0 &&
                                          si < _seasonNodes.length) {
                                        _seasonNodes[si].requestFocus();
                                      } else {
                                        _closeDrawerFocus.requestFocus();
                                      }
                                    } else {
                                      // Sin temporadas → foco directo a la X
                                      _closeDrawerFocus.requestFocus();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowDown) {
                                    if (i < _epNodes.length - 1) {
                                      _epNodes[i + 1].requestFocus();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  if (key ==
                                          LogicalKeyboardKey.arrowLeft ||
                                      key == LogicalKeyboardKey.goBack ||
                                      key == LogicalKeyboardKey.escape) {
                                    _closeDrawer();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Builder(builder: (c) {
                                  final has = Focus.of(c).hasFocus;
                                  return GestureDetector(
                                    onTap: () => _playLocal(ep),
                                    onLongPress: () => _openModal(ep),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: has
                                            ? _kAccent.withValues(
                                                alpha: 0.15)
                                            : _kCard,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: has
                                              ? _kAccent
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            'E${(ep.capitulo ?? 0).toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              color: has
                                                  ? _kAccent
                                                  : Colors.white54,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              ep.title,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: has
                                                    ? Colors.white
                                                    : Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.play_arrow_rounded,
                                            color: has
                                                ? _kAccent
                                                : Colors.white38,
                                            size: 26,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionModal() {
    final item = _modalItem!;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _modalActionBtn(
                        focusNode: _modalPlayFocus,
                        label: 'Reproducir',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        onPressed: () {
                          _closeModal();
                          _playLocal(item);
                        },
                        onRight: () => _modalDeleteFocus.requestFocus(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _modalActionBtn(
                        focusNode: _modalDeleteFocus,
                        label: 'Eliminar',
                        icon: Icons.delete_outline_rounded,
                        primary: false,
                        onPressed: () async {
                          _closeModal();
                          await _deleteItem(item);
                        },
                        onLeft: () => _modalPlayFocus.requestFocus(),
                        onRight: () => _modalCancelFocus.requestFocus(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _modalActionBtn(
                        focusNode: _modalCancelFocus,
                        label: 'Cancelar',
                        icon: Icons.close_rounded,
                        primary: false,
                        onPressed: _closeModal,
                        onLeft: () => _modalDeleteFocus.requestFocus(),
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

  Widget _modalActionBtn({
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback onPressed,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          _closeModal();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final has = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: primary
                  ? (has ? _kAccent : _kAccent.withValues(alpha: 0.8))
                  : (has
                      ? Colors.red.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: has
                    ? (primary ? _kAccent : Colors.redAccent)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _TvDlItem {
  final String folderPath;
  final String videoPath;
  final String title;
  final int? tmdbId;
  final String? tipo;
  final int? temporada;
  final int? capitulo;
  final String? posterUrl;
  final DateTime downloadedAt;

  _TvDlItem({
    required this.folderPath,
    required this.videoPath,
    required this.title,
    this.tmdbId,
    this.tipo,
    this.temporada,
    this.capitulo,
    this.posterUrl,
    required this.downloadedAt,
  });

  String get displayTitle {
    if (temporada != null && capitulo != null) {
      final s = temporada!.toString().padLeft(2, '0');
      final e = capitulo!.toString().padLeft(2, '0');
      return '$title · T$s C$e';
    }
    return title;
  }
}

class _TvGroup {
  final bool isSeries;
  final String title;
  final String? posterUrl;
  final int? tmdbId;
  final List<_TvDlItem> episodes;
  final DateTime downloadedAt;

  _TvGroup({
    required this.isSeries,
    required this.title,
    this.posterUrl,
    this.tmdbId,
    required this.episodes,
    required this.downloadedAt,
  });

  List<int> get seasons {
    final set = <int>{};
    for (final e in episodes) {
      if (e.temporada != null) set.add(e.temporada!);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<_TvDlItem> episodesForSeason(int season) {
    return episodes.where((e) => e.temporada == season).toList()
      ..sort((a, b) => (a.capitulo ?? 0).compareTo(b.capitulo ?? 0));
  }
}