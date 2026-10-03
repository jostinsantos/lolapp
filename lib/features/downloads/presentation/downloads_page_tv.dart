import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'download_manager.dart';
import 'local_player_page.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Página de descargas TV — layout 100 % vertical + foco D-pad.
/// Hereda el foco del menú lateral mediante [onRequestMenuFocus] y
/// [onMainFocusNodeCreated].
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

class _DescargasPageTvState extends State<DescargasPageTv> {
  final _dm = DownloadManager.instance;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'descargas_tv_root');
  final ScrollController _scrollCtrl = ScrollController();

  List<_TvDlItem> _items = [];
  bool _loading = true;
  String? _error;

  List<FocusNode> _itemNodes = [];
  List<FocusNode> _activeNodes = [];

  @override
  void initState() {
    super.initState();
    // Forzar orientación libre (TV) — no heredar lock de player horizontal
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
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
    _dm.removeListener(_onDm);
    _rootFocus.dispose();
    _scrollCtrl.dispose();
    for (final n in _itemNodes) {
      n.dispose();
    }
    for (final n in _activeNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onDm() {
    if (!mounted) return;
    final prevActive = _activeNodes.length;
    setState(() {});
    if (_downloading.length != prevActive) {
      _resyncActiveNodes();
    }
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
          // Preferir playlist.m3u8 (HLS completo). Nunca un .ts suelto.
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
          ));
        }
      }
      list.sort((a, b) => b.title.compareTo(a.title));
      if (!mounted) return;
      for (final n in _itemNodes) {
        n.dispose();
      }
      _itemNodes =
          List.generate(list.length, (i) => FocusNode(debugLabel: 'dl_$i'));
      setState(() {
        _items = list;
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

  void _resyncActiveNodes() {
    for (final n in _activeNodes) {
      n.dispose();
    }
    _activeNodes = List.generate(
      _downloading.length,
      (i) => FocusNode(debugLabel: 'act_$i'),
    );
  }

  void _playLocal(_TvDlItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalPlayerScreen(
          playlistPath: item.videoPath,
          title: item.title,
        ),
      ),
    );
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

  void _cancelActive(ActiveDownload d) {
    _dm.cancel(d.id);
    setState(() {});
    _resyncActiveNodes();
  }

  void _goMenuOrBack() {
    if (widget.onRequestMenuFocus != null) {
      widget.onRequestMenuFocus!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// Auto-scroll suave: centra el widget enfocado en el viewport.
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
    final active = _downloading;

    // Una sola lista vertical: activas + completadas
    final sectionActive = active.isNotEmpty ? 1 + active.length : 0;
    // header "Completadas" + items
    final totalSlivers = 2 + sectionActive + (_items.isEmpty ? 1 : _items.length);

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: _onRootKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
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
                                style:
                                    const TextStyle(color: Colors.redAccent),
                              ),
                            )
                          : ListView(
                              controller: _scrollCtrl,
                              // Layout vertical obligatorio
                              scrollDirection: Axis.vertical,
                              children: [
                                // ── En curso (vertical) ──────────────────
                                if (active.isNotEmpty) ...[
                                  const Text(
                                    'En curso',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...List.generate(active.length, (i) {
                                    final d = active[i];
                                    final node = i < _activeNodes.length
                                        ? _activeNodes[i]
                                        : FocusNode();
                                    final pct = (d.progress * 100)
                                        .clamp(0, 100)
                                        .round();
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
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
                                          if (key ==
                                                  LogicalKeyboardKey.select ||
                                              key ==
                                                  LogicalKeyboardKey.enter) {
                                            _cancelActive(d);
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                                  LogicalKeyboardKey
                                                      .arrowLeft ||
                                              key ==
                                                  LogicalKeyboardKey.goBack ||
                                              key ==
                                                  LogicalKeyboardKey.escape) {
                                            _goMenuOrBack();
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                              LogicalKeyboardKey.arrowUp) {
                                            if (i > 0) {
                                              _activeNodes[i - 1]
                                                  .requestFocus();
                                            } else {
                                              _rootFocus.requestFocus();
                                            }
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                              LogicalKeyboardKey.arrowDown) {
                                            if (i <
                                                _activeNodes.length - 1) {
                                              _activeNodes[i + 1]
                                                  .requestFocus();
                                            } else if (_itemNodes
                                                .isNotEmpty) {
                                              _itemNodes.first
                                                  .requestFocus();
                                            }
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: Builder(
                                          builder: (context) {
                                            final hasFocus =
                                                Focus.of(context).hasFocus;
                                            return GestureDetector(
                                              onTap: () => _cancelActive(d),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 140),
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.all(14),
                                                decoration: BoxDecoration(
                                                  color: _kCard,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14),
                                                  border: Border.all(
                                                    color: hasFocus
                                                        ? Colors.white
                                                        : Colors.white12,
                                                    width:
                                                        hasFocus ? 2.2 : 1,
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
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                        height: 10),
                                                    LinearProgressIndicator(
                                                      value: d.progress >
                                                              0.01
                                                          ? d.progress
                                                          : null,
                                                      color: _kAccent,
                                                      backgroundColor:
                                                          Colors.white12,
                                                      minHeight: 5,
                                                    ),
                                                    const SizedBox(
                                                        height: 8),
                                                    Text(
                                                      '$pct% · ${d.statusText} · OK para cancelar',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: 0.5),
                                                        fontSize: 12,
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
                                  }),
                                  const SizedBox(height: 12),
                                ],

                                // ── Completadas ──────────────────────────
                                const Text(
                                  'Completadas',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                if (_items.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 24),
                                    child: Text(
                                      'No hay descargas completadas',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 15,
                                      ),
                                    ),
                                  )
                                else
                                  ...List.generate(_items.length, (i) {
                                    final item = _items[i];
                                    final node = i < _itemNodes.length
                                        ? _itemNodes[i]
                                        : FocusNode();
                                    final epLabel = (item.temporada !=
                                                null &&
                                            item.capitulo != null)
                                        ? 'T${item.temporada.toString().padLeft(2, '0')} C${item.capitulo.toString().padLeft(2, '0')}'
                                        : null;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
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
                                          if (key ==
                                                  LogicalKeyboardKey
                                                      .select ||
                                              key ==
                                                  LogicalKeyboardKey.enter) {
                                            _playLocal(item);
                                            return KeyEventResult.handled;
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
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                              LogicalKeyboardKey.arrowUp) {
                                            if (i > 0) {
                                              _itemNodes[i - 1]
                                                  .requestFocus();
                                            } else if (_activeNodes
                                                .isNotEmpty) {
                                              _activeNodes.last
                                                  .requestFocus();
                                            } else {
                                              _rootFocus.requestFocus();
                                            }
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                              LogicalKeyboardKey
                                                  .arrowDown) {
                                            if (i <
                                                _itemNodes.length - 1) {
                                              _itemNodes[i + 1]
                                                  .requestFocus();
                                            }
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                              LogicalKeyboardKey.delete) {
                                            _deleteItem(item);
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: Builder(
                                          builder: (context) {
                                            final hasFocus =
                                                Focus.of(context).hasFocus;
                                            return GestureDetector(
                                              onTap: () =>
                                                  _playLocal(item),
                                              onLongPress: () =>
                                                  _deleteItem(item),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 140),
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.all(
                                                        14),
                                                decoration: BoxDecoration(
                                                  color: _kCard,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14),
                                                  border: Border.all(
                                                    color: hasFocus
                                                        ? Colors.white
                                                        : Colors.white10,
                                                    width: hasFocus
                                                        ? 2.2
                                                        : 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 52,
                                                      height: 72,
                                                      decoration:
                                                          BoxDecoration(
                                                        color:
                                                            Colors.white12,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    8),
                                                      ),
                                                      child: item.posterUrl !=
                                                                  null &&
                                                              item
                                                                  .posterUrl!
                                                                  .isNotEmpty
                                                          ? ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              child:
                                                                  Image
                                                                      .network(
                                                                item
                                                                    .posterUrl!,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder:
                                                                    (_,
                                                                        __,
                                                                        ___) =>
                                                                        const Icon(
                                                                  Icons
                                                                      .movie_rounded,
                                                                  color: Colors
                                                                      .white38,
                                                                ),
                                                              ),
                                                            )
                                                          : const Icon(
                                                              Icons
                                                                  .movie_rounded,
                                                              color: Colors
                                                                  .white38,
                                                            ),
                                                    ),
                                                    const SizedBox(
                                                        width: 14),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            item.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          if (epLabel !=
                                                              null) ...[
                                                            const SizedBox(
                                                                height: 4),
                                                            Text(
                                                              epLabel,
                                                              style:
                                                                  TextStyle(
                                                                color: _kAccent
                                                                    .withValues(
                                                                        alpha:
                                                                            0.9),
                                                                fontSize:
                                                                    13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                            'OK: reproducir · Delete: borrar',
                                                            style:
                                                                TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.4),
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Icon(
                                                      Icons
                                                          .play_circle_outline_rounded,
                                                      color: hasFocus
                                                          ? _kAccent
                                                          : Colors.white38,
                                                      size: 32,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
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

  _TvDlItem({
    required this.folderPath,
    required this.videoPath,
    required this.title,
    this.tmdbId,
    this.tipo,
    this.temporada,
    this.capitulo,
    this.posterUrl,
  });
}