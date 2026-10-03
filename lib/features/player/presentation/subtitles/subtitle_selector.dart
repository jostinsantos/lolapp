// subtitles_modal.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OpenSubtitlesModal extends StatefulWidget {
  final String? imdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final String? currentSubtitleId;
  final double subtitleOffsetSec;
  final double subtitleFontSize;
  final bool subtitleBold;
  final double subtitleVerticalOffset;
  final List<Map<String, dynamic>> cues;
  final Duration currentPosition;
  final ValueListenable<Duration>? positionListenable;
  final ValueChanged<double> onOffsetChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<double> onVerticalOffsetChanged;
  final Future<void> Function(Map<String, dynamic> sub) onSubtitleSelected;
  final VoidCallback onDisable;

  const OpenSubtitlesModal({
    super.key,
    required this.imdbId,
    required this.mediaType,
    this.season,
    this.episode,
    this.currentSubtitleId,
    required this.subtitleOffsetSec,
    required this.subtitleFontSize,
    required this.subtitleBold,
    required this.subtitleVerticalOffset,
    required this.cues,
    required this.currentPosition,
    this.positionListenable,
    required this.onOffsetChanged,
    required this.onFontSizeChanged,
    required this.onBoldChanged,
    required this.onVerticalOffsetChanged,
    required this.onSubtitleSelected,
    required this.onDisable,
  });

  static Future<void> show({
    required BuildContext context,
    required String? imdbId,
    required String mediaType,
    int? season,
    int? episode,
    String? currentSubtitleId,
    required double subtitleOffsetSec,
    required double subtitleFontSize,
    required bool subtitleBold,
    required double subtitleVerticalOffset,
    required List<Map<String, dynamic>> cues,
    required Duration currentPosition,
    ValueListenable<Duration>? positionListenable,
    required ValueChanged<double> onOffsetChanged,
    required ValueChanged<double> onFontSizeChanged,
    required ValueChanged<bool> onBoldChanged,
    required ValueChanged<double> onVerticalOffsetChanged,
    required Future<void> Function(Map<String, dynamic> sub) onSubtitleSelected,
    required VoidCallback onDisable,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (_) => OpenSubtitlesModal(
        imdbId: imdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        currentSubtitleId: currentSubtitleId,
        subtitleOffsetSec: subtitleOffsetSec,
        subtitleFontSize: subtitleFontSize,
        subtitleBold: subtitleBold,
        subtitleVerticalOffset: subtitleVerticalOffset,
        cues: cues,
        currentPosition: currentPosition,
        positionListenable: positionListenable,
        onOffsetChanged: onOffsetChanged,
        onFontSizeChanged: onFontSizeChanged,
        onBoldChanged: onBoldChanged,
        onVerticalOffsetChanged: onVerticalOffsetChanged,
        onSubtitleSelected: onSubtitleSelected,
        onDisable: onDisable,
      ),
    );
  }

  @override
  State<OpenSubtitlesModal> createState() => _OpenSubtitlesModalState();
}

class _OpenSubtitlesModalState extends State<OpenSubtitlesModal> {
  static const Color accentPurple = Color(0xFF9C27B0);
  static const Color accentPurpleLight = Color(0xFFCE93D8);
  static const String _prefLangKey = 'opensubtitles_preferred_lang';

  static const String _prefOffsetKey = 'subtitle_offset_sec';
  static const String _prefFontSizeKey = 'subtitle_font_size';
  static const String _prefBoldKey = 'subtitle_bold';
  static const String _prefVerticalOffsetKey = 'subtitle_vertical_offset';

  bool _loading = true;
  String? _error;
  Map<String, List<Map<String, dynamic>>> _byLang = {};
  List<String> _sortedLangs = [];
  String _currentLang = 'spa';

  late double _localOffset;
  late double _localFontSize;
  late bool _localBold;
  late double _localVerticalOffset;

  static const Map<String, String> _langNames = {
    'spa': 'Español',
    'eng': 'Inglés',
    'fre': 'Francés',
    'ita': 'Italiano',
    'por': 'Portugués',
    'pob': 'Portugués (BR)',
    'ger': 'Alemán',
    'deu': 'Alemán',
    'rus': 'Ruso',
    'ara': 'Árabe',
    'chi': 'Chino',
    'jpn': 'Japonés',
    'kor': 'Coreano',
    'pol': 'Polaco',
    'dut': 'Holandés',
    'nld': 'Holandés',
    'tur': 'Turco',
    'fin': 'Finés',
    'swe': 'Sueco',
    'nor': 'Noruego',
    'dan': 'Danés',
    'gre': 'Griego',
    'ell': 'Griego',
    'heb': 'Hebreo',
    'hun': 'Húngaro',
    'cze': 'Checo',
    'slo': 'Eslovaco',
    'rum': 'Rumano',
    'ron': 'Rumano',
    'bul': 'Búlgaro',
    'ukr': 'Ucraniano',
    'hrv': 'Croata',
    'srp': 'Serbio',
    'est': 'Estonio',
    'per': 'Persa',
    'fas': 'Persa',
    'vie': 'Vietnamita',
    'tha': 'Tailandés',
    'ind': 'Indonesio',
    'may': 'Malayo',
    'alb': 'Albanés',
  };

  String _langDisplayName(String code) =>
      _langNames[code.toLowerCase()] ?? code.toUpperCase();

  @override
  void initState() {
    super.initState();
    _localOffset = widget.subtitleOffsetSec;
    _localFontSize = widget.subtitleFontSize;
    _localBold = widget.subtitleBold;
    _localVerticalOffset = widget.subtitleVerticalOffset;
    _loadCachedConfig();
    _fetchSubtitles();
  }

  Future<void> _loadCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedOffset = prefs.getDouble(_prefOffsetKey);
      final cachedFontSize = prefs.getDouble(_prefFontSizeKey);
      final cachedBold = prefs.getBool(_prefBoldKey);
      final cachedVerticalOffset = prefs.getDouble(_prefVerticalOffsetKey);

      if (!mounted) return;

      setState(() {
        _localOffset = cachedOffset ?? widget.subtitleOffsetSec;
        _localFontSize = cachedFontSize ?? widget.subtitleFontSize;
        _localBold = cachedBold ?? widget.subtitleBold;
        _localVerticalOffset =
            cachedVerticalOffset ?? widget.subtitleVerticalOffset;
      });

      widget.onOffsetChanged(_localOffset);
      widget.onFontSizeChanged(_localFontSize);
      widget.onBoldChanged(_localBold);
      widget.onVerticalOffsetChanged(_localVerticalOffset);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localOffset = widget.subtitleOffsetSec;
        _localFontSize = widget.subtitleFontSize;
        _localBold = widget.subtitleBold;
        _localVerticalOffset = widget.subtitleVerticalOffset;
      });
    }
  }

  Future<void> _saveCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefOffsetKey, _localOffset);
      await prefs.setDouble(_prefFontSizeKey, _localFontSize);
      await prefs.setBool(_prefBoldKey, _localBold);
      await prefs.setDouble(_prefVerticalOffsetKey, _localVerticalOffset);
    } catch (_) {}
  }

  Future<void> _savePreferredLang(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLangKey, lang);
    } catch (_) {}
  }

  Future<String?> _loadPreferredLang() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefLangKey);
    } catch (_) {
      return null;
    }
  }

  String? _buildApiUrl() {
    final imdb = widget.imdbId?.trim() ?? '';
    if (imdb.isEmpty) return null;
    if (widget.mediaType == 'tv') {
      final s = widget.season ?? 1;
      final e = widget.episode ?? 1;
      return 'https://opensubtitles-v3.strem.io/subtitles/series/$imdb:$s:$e.json';
    }
    return 'https://opensubtitles-v3.strem.io/subtitles/movie/$imdb.json';
  }

  Future<void> _fetchSubtitles() async {
    final url = _buildApiUrl();
    if (url == null) {
      setState(() {
        _loading = false;
        _error = 'No se encontró IMDb ID';
      });
      return;
    }

    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      final list = (data['subtitles'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final Map<String, List<Map<String, dynamic>>> byLang = {};
      for (final s in list) {
        final lang = (s['lang'] ?? 'unk').toString().toLowerCase();
        byLang.putIfAbsent(lang, () => []).add(s);
      }

      const preferred = ['spa', 'eng', 'fre', 'ita', 'por', 'pob'];
      final sorted = byLang.keys.toList()
        ..sort((a, b) {
          final ia = preferred.indexOf(a);
          final ib = preferred.indexOf(b);
          if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
          if (ia >= 0) return -1;
          if (ib >= 0) return 1;
          return a.compareTo(b);
        });

      final savedLang = await _loadPreferredLang();
      String current = 'spa';
      if (savedLang != null && byLang.containsKey(savedLang)) {
        current = savedLang;
      } else if (!byLang.containsKey(current) && sorted.isNotEmpty) {
        current = sorted.first;
      }

      if (mounted) {
        setState(() {
          _byLang = byLang;
          _sortedLangs = sorted;
          _currentLang = current;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error al cargar subtítulos';
        });
      }
    }
  }

  void _changeLang(String lang) {
    setState(() => _currentLang = lang);
    _savePreferredLang(lang);
  }

  Widget _styleBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  String _formatCueTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ms = d.inMilliseconds.remainder(1000);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}.'
          '${ms.toString().padLeft(3, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${ms.toString().padLeft(3, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SINCRONIZACIÓN MANUAL — independiente del State del modal
  // ═══════════════════════════════════════════════════════════════════════════

  void _openSyncWindow() {
    if (widget.cues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay subtítulos cargados todavía')),
      );
      return;
    }

    // Capturar TODO antes de cerrar (el State se destruye con el pop)
    final cues = List<Map<String, dynamic>>.from(widget.cues);
    final positionListenable = widget.positionListenable;
    final initialPosition =
        widget.positionListenable?.value ?? widget.currentPosition;
    final onOffsetChanged = widget.onOffsetChanged;
    final initialOffset = _localOffset;

    final imdbId = widget.imdbId;
    final mediaType = widget.mediaType;
    final season = widget.season;
    final episode = widget.episode;
    final currentSubtitleId = widget.currentSubtitleId;
    final fontSize = _localFontSize;
    final bold = _localBold;
    final verticalOffset = _localVerticalOffset;
    final onFontSizeChanged = widget.onFontSizeChanged;
    final onBoldChanged = widget.onBoldChanged;
    final onVerticalOffsetChanged = widget.onVerticalOffsetChanged;
    final onSubtitleSelected = widget.onSubtitleSelected;
    final onDisable = widget.onDisable;

    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final mqSize = MediaQuery.of(context).size;

    navigator.pop();

    Future.microtask(() {
      _insertFloatingSyncWindow(
        overlay: overlay,
        messenger: messenger,
        mediaQuerySize: mqSize,
        cues: cues,
        positionListenable: positionListenable,
        initialPosition: initialPosition,
        initialOffset: initialOffset,
        onOffsetChanged: onOffsetChanged,
        onCloseAndReopen: (double finalOffset) {
          Future.delayed(const Duration(milliseconds: 150), () {
            final ctx = navigator.context;
            if (!ctx.mounted) return;
            OpenSubtitlesModal.show(
              context: ctx,
              imdbId: imdbId,
              mediaType: mediaType,
              season: season,
              episode: episode,
              currentSubtitleId: currentSubtitleId,
              subtitleOffsetSec: finalOffset,
              subtitleFontSize: fontSize,
              subtitleBold: bold,
              subtitleVerticalOffset: verticalOffset,
              cues: cues,
              currentPosition:
                  positionListenable?.value ?? initialPosition,
              positionListenable: positionListenable,
              onOffsetChanged: onOffsetChanged,
              onFontSizeChanged: onFontSizeChanged,
              onBoldChanged: onBoldChanged,
              onVerticalOffsetChanged: onVerticalOffsetChanged,
              onSubtitleSelected: onSubtitleSelected,
              onDisable: onDisable,
            );
          });
        },
      );
    });
  }

   void _insertFloatingSyncWindow({
    required OverlayState overlay,
    required ScaffoldMessengerState messenger,
    required Size mediaQuerySize,
    required List<Map<String, dynamic>> cues,
    required ValueListenable<Duration>? positionListenable,
    required Duration initialPosition,
    required double initialOffset,
    required ValueChanged<double> onOffsetChanged,
    required void Function(double finalOffset) onCloseAndReopen,
  }) {
    late OverlayEntry overlayEntry;

    Offset windowOffset = const Offset(24, 72);
    Size windowSize = Size(
      (mediaQuerySize.width * 0.44).clamp(300.0, 560.0),
      (mediaQuerySize.height * 0.50).clamp(260.0, 560.0),
    );

    // Offset GLOBAL → afecta a TODOS los subtítulos a la vez
    double localOffset = initialOffset.clamp(-30.0, 30.0);
    final scrollController = ScrollController();
    Timer? pollTimer;

    Duration livePos() => positionListenable?.value ?? initialPosition;

    /// Tiempo de cue en el “reloj del video” (todos se mueven con el offset)
    Duration shifted(Duration original) {
      return original -
          Duration(milliseconds: (localOffset * 1000).round());
    }

    int cueIndexFor(Duration videoPos, double offset) {
      if (cues.isEmpty) return 0;
      final adjusted =
          videoPos + Duration(milliseconds: (offset * 1000).round());
      int best = 0;
      Duration bestDiff = const Duration(days: 1);
      for (int i = 0; i < cues.length; i++) {
        final start = cues[i]['start'] as Duration;
        final end = (cues[i]['end'] as Duration?) ?? start;
        if (adjusted >= start && adjusted <= end) return i;
        final mid = start +
            Duration(milliseconds: (end - start).inMilliseconds ~/ 2);
        final diff = (mid - adjusted).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = i;
        }
      }
      return best;
    }

    int currentIndex = cueIndexFor(livePos(), localOffset);

    void scrollToIndex(int index) {
      if (!scrollController.hasClients) return;
      const itemExtent = 52.0;
      final target = (index * itemExtent) - (windowSize.height * 0.3);
      scrollController.animateTo(
        target.clamp(0.0, scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }

    void applyOffset(double v, void Function(void Function()) setWin) {
      localOffset = v.clamp(-30.0, 30.0);
      onOffsetChanged(localOffset); // player: todos los subs a la vez
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble(_prefOffsetKey, localOffset);
      });
      setWin(() {
        currentIndex = cueIndexFor(livePos(), localOffset);
      });
    }

    Widget timeBtn({
      required String label,
      required VoidCallback onTap,
      bool accent = false,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: accent
                ? accentPurple.withValues(alpha: 0.45)
                : Colors.white12,
            borderRadius: BorderRadius.circular(8),
            border: accent
                ? Border.all(color: accentPurpleLight.withValues(alpha: 0.8))
                : null,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    overlayEntry = OverlayEntry(
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setWin) {
            pollTimer?.cancel();
            if (positionListenable == null) {
              pollTimer = Timer.periodic(
                const Duration(milliseconds: 300),
                (_) {
                  if (!overlayEntry.mounted) return;
                  final idx = cueIndexFor(livePos(), localOffset);
                  if (idx != currentIndex) {
                    setWin(() => currentIndex = idx);
                    scrollToIndex(idx);
                  } else {
                    setWin(() {});
                  }
                },
              );
            }

            Widget panel(Duration pos) {
              final idx = cueIndexFor(pos, localOffset);
              if (idx != currentIndex) {
                currentIndex = idx;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  scrollToIndex(currentIndex);
                });
              }

              return Positioned(
                left: windowOffset.dx,
                top: windowOffset.dy,
                child: Material(
                  color: Colors.transparent,
                  elevation: 16,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: windowSize.width,
                    height: windowSize.height,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentPurple.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Barra título (solo arrastre) ──
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (d) {
                                setWin(() {
                                  final size = MediaQuery.of(ctx).size;
                                  windowOffset = Offset(
                                    (windowOffset.dx + d.delta.dx).clamp(
                                      0.0,
                                      size.width - windowSize.width,
                                    ),
                                    (windowOffset.dy + d.delta.dy).clamp(
                                      0.0,
                                      size.height - windowSize.height,
                                    ),
                                  );
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.06),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.drag_handle,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Sincronizar subtítulos',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        pollTimer?.cancel();
                                        overlayEntry.remove();
                                        onCloseAndReopen(localOffset);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white70,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ── Tiempo actual del video ──
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 10, 14, 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    size: 16,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Video: ${_formatCueTime(pos)}',
                                    style: TextStyle(
                                      color: Colors.grey[300],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Controles de tiempo (afectan a TODOS) ──
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 8, 12, 8),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Ajuste (todos los subtítulos)',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      timeBtn(
                                        label: '−1s',
                                        onTap: () => applyOffset(
                                          localOffset - 1.0,
                                          setWin,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      timeBtn(
                                        label: '−0.1s',
                                        onTap: () => applyOffset(
                                          localOffset - 0.1,
                                          setWin,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets
                                              .symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                                alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: accentPurple
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: Text(
                                            '${localOffset >= 0 ? '+' : ''}${localOffset.toStringAsFixed(1)} s',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      timeBtn(
                                        label: '+0.1s',
                                        onTap: () => applyOffset(
                                          localOffset + 0.1,
                                          setWin,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      timeBtn(
                                        label: '+1s',
                                        onTap: () => applyOffset(
                                          localOffset + 1.0,
                                          setWin,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  timeBtn(
                                    label: 'Reiniciar (0.0 s)',
                                    accent: true,
                                    onTap: () =>
                                        applyOffset(0.0, setWin),
                                  ),
                                ],
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 0, 14, 6),
                              child: Text(
                                'Toca una línea para alinearla con el segundo actual',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 10,
                                ),
                              ),
                            ),

                            // ── Lista: tiempos YA desplazados (se ve el cambio en todos) ──
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 10,
                                ),
                                itemCount: cues.length,
                                itemBuilder: (_, i) {
                                  final cue = cues[i];
                                  final start = cue['start'] as Duration;
                                  final end =
                                      cue['end'] as Duration? ?? start;
                                  final text =
                                      (cue['text'] as String?) ?? '';
                                  final isCurrent = i == currentIndex;

                                  // Tiempos efectivos en el video (todos se mueven juntos)
                                  final sShow = shifted(start);
                                  final eShow = shifted(end);
                                  final timeStr =
                                      '${_formatCueTime(sShow)} → ${_formatCueTime(eShow)}';

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      onTap: () {
                                        // Esa línea en el segundo actual del video
                                        // → mueve TODOS los tiempos con el mismo offset
                                        final offsetSec =
                                            (start - pos).inMilliseconds /
                                                1000.0;
                                        applyOffset(offsetSec, setWin);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Todos ajustados: ${localOffset >= 0 ? '+' : ''}${localOffset.toStringAsFixed(2)} s',
                                            ),
                                            duration: const Duration(
                                                seconds: 1),
                                            backgroundColor:
                                                Colors.green[800],
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin:
                                            const EdgeInsets.symmetric(
                                                vertical: 2),
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? accentPurple.withValues(
                                                  alpha: 0.35)
                                              : Colors.white.withValues(
                                                  alpha: 0.04),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: isCurrent
                                              ? Border.all(
                                                  color: accentPurpleLight
                                                      .withValues(
                                                          alpha: 0.9),
                                                  width: 1.2,
                                                )
                                              : null,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                timeStr,
                                                style: TextStyle(
                                                  color: isCurrent
                                                      ? Colors.white
                                                      : Colors.grey[400],
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                text,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: isCurrent
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow
                                                    .ellipsis,
                                              ),
                                            ),
                                            if (isCurrent)
                                              Icon(
                                                Icons.play_arrow_rounded,
                                                size: 16,
                                                color: accentPurpleLight,
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
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              setWin(() {
                                windowSize = Size(
                                  (windowSize.width + d.delta.dx)
                                      .clamp(260.0, 640.0),
                                  (windowSize.height + d.delta.dy)
                                      .clamp(200.0, 560.0),
                                );
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.open_with,
                                color: Colors.white38,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (positionListenable != null) {
              return ValueListenableBuilder<Duration>(
                valueListenable: positionListenable,
                builder: (_, pos, __) => panel(pos),
              );
            }
            return panel(livePos());
          },
        );
      },
    );

    overlay.insert(overlayEntry);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToIndex(currentIndex);
    });
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // Estilo del modal principal
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateOffset(double value) {
    setState(() => _localOffset = value);
    widget.onOffsetChanged(value);
    _saveCachedConfig();
  }

  void _updateFontSize(double value) {
    setState(() => _localFontSize = value);
    widget.onFontSizeChanged(value);
    _saveCachedConfig();
  }

  void _updateBold(bool value) {
    setState(() => _localBold = value);
    widget.onBoldChanged(value);
    _saveCachedConfig();
  }

  void _updateVerticalOffset(double value) {
    setState(() => _localVerticalOffset = value);
    widget.onVerticalOffsetChanged(value);
    _saveCachedConfig();
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _byLang[_currentLang] ?? [];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 540),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
              child: Row(
                children: [
                  const Text(
                    'Subtítulos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      widget.onDisable();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Desactivar',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: accentPurple),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 158,
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Text(
                                      'Idiomas',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      itemCount: _sortedLangs.length,
                                      itemBuilder: (_, i) {
                                        final lang = _sortedLangs[i];
                                        final count = _byLang[lang]!.length;
                                        final isSelected =
                                            lang == _currentLang;

                                        return GestureDetector(
                                          onTap: () => _changeLang(lang),
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 4),
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accentPurple.withValues(
                                                      alpha: 0.35)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: isSelected
                                                  ? Border.all(
                                                      color:
                                                          accentPurpleLight,
                                                      width: 1.2,
                                                    )
                                                  : null,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _langDisplayName(lang),
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : Colors.white70,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? accentPurpleLight
                                                        : Colors.white24,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(10),
                                                  ),
                                                  child: Text(
                                                    '$count',
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.black
                                                          : Colors.white70,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Text(
                                      'Subtítulos',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: currentList.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No hay subtítulos',
                                              style: TextStyle(
                                                  color: Colors.white38),
                                            ),
                                          )
                                        : ListView.builder(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12),
                                            itemCount: currentList.length,
                                            itemBuilder: (_, i) {
                                              final sub = currentList[i];
                                              final id =
                                                  sub['id']?.toString() ??
                                                      '';
                                              final name = sub[
                                                          'subtitleFileName']
                                                      ?.toString() ??
                                                  'Subtítulo';
                                              final release = sub[
                                                          'movieReleaseName']
                                                      ?.toString() ??
                                                  '';
                                              final isSelected = widget
                                                      .currentSubtitleId ==
                                                  id;

                                              return GestureDetector(
                                                onTap: () async {
                                                  Navigator.pop(context);
                                                  await widget
                                                      .onSubtitleSelected(
                                                          sub);
                                                },
                                                child: Container(
                                                  margin:
                                                      const EdgeInsets.only(
                                                          bottom: 8),
                                                  padding:
                                                      const EdgeInsets.all(
                                                          12),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? accentPurple
                                                            .withValues(
                                                                alpha: 0.4)
                                                        : Colors.white
                                                            .withValues(
                                                                alpha:
                                                                    0.05),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(12),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? accentPurpleLight
                                                          : Colors
                                                              .transparent,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal:
                                                                  8,
                                                              vertical: 3,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: const Color(
                                                                  0xFF7B1FA2),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          6),
                                                            ),
                                                            child:
                                                                const Text(
                                                              'OpenSubtitles v3',
                                                              style:
                                                                  TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize:
                                                                    10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          if (isSelected)
                                                            const Icon(
                                                              Icons
                                                                  .check_rounded,
                                                              color: Colors
                                                                  .white,
                                                              size: 18,
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 8),
                                                      Text(
                                                        name,
                                                        style:
                                                            const TextStyle(
                                                          color:
                                                              Colors.white,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w500,
                                                        ),
                                                        maxLines: 2,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                      if (release
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          release,
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[500],
                                                            fontSize: 11,
                                                          ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 200,
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Text(
                                      'Estilo',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Retraso de subtítulos',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _styleBtn(
                                                icon: Icons.remove,
                                                onTap: () {
                                                  final v =
                                                      (_localOffset - 0.5)
                                                          .clamp(
                                                              -30.0, 30.0);
                                                  _updateOffset(v);
                                                },
                                              ),
                                              Expanded(
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white12,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(8),
                                                  ),
                                                  child: Text(
                                                    '${_localOffset >= 0 ? '+' : ''}${_localOffset.toStringAsFixed(1)}s',
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              _styleBtn(
                                                icon: Icons.add,
                                                onTap: () {
                                                  final v =
                                                      (_localOffset + 0.5)
                                                          .clamp(
                                                              -30.0, 30.0);
                                                  _updateOffset(v);
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton(
                                              onPressed: () {
                                                _updateOffset(0.0);
                                              },
                                              style: OutlinedButton
                                                  .styleFrom(
                                                foregroundColor:
                                                    Colors.white70,
                                                side: const BorderSide(
                                                    color: Colors.white24),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(8),
                                                ),
                                              ),
                                              child: const Text(
                                                  'Reiniciar retraso'),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Tamaño de fuente',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _styleBtn(
                                                icon: Icons.remove,
                                                onTap: () {
                                                  final v =
                                                      (_localFontSize - 1)
                                                          .clamp(
                                                              12.0, 36.0);
                                                  _updateFontSize(v);
                                                },
                                              ),
                                              Expanded(
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white12,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(8),
                                                  ),
                                                  child: Text(
                                                    '${_localFontSize.toInt()}sp',
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              _styleBtn(
                                                icon: Icons.add,
                                                onTap: () {
                                                  final v =
                                                      (_localFontSize + 1)
                                                          .clamp(
                                                              12.0, 36.0);
                                                  _updateFontSize(v);
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Estilo',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          GestureDetector(
                                            onTap: () {
                                              _updateBold(!_localBold);
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets
                                                      .symmetric(
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: _localBold
                                                    ? accentPurple
                                                        .withValues(
                                                            alpha: 0.4)
                                                    : Colors.white12,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        8),
                                                border: Border.all(
                                                  color: _localBold
                                                      ? accentPurpleLight
                                                      : Colors.transparent,
                                                ),
                                              ),
                                              child: Text(
                                                _localBold
                                                    ? 'Negrita'
                                                    : 'Normal',
                                                textAlign:
                                                    TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: _localBold
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Altura (desde abajo)',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _styleBtn(
                                                icon: Icons.remove,
                                                onTap: () {
                                                  final v =
                                                      (_localVerticalOffset -
                                                              8)
                                                          .clamp(-40.0,
                                                              160.0);
                                                  _updateVerticalOffset(v);
                                                },
                                              ),
                                              Expanded(
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white12,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(8),
                                                  ),
                                                  child: Text(
                                                    '${_localVerticalOffset.toInt()}',
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              _styleBtn(
                                                icon: Icons.add,
                                                onTap: () {
                                                  final v =
                                                      (_localVerticalOffset +
                                                              8)
                                                          .clamp(-40.0,
                                                              160.0);
                                                  _updateVerticalOffset(v);
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton(
                                              onPressed: () {
                                                _updateVerticalOffset(0);
                                              },
                                              style: OutlinedButton
                                                  .styleFrom(
                                                foregroundColor:
                                                    Colors.white70,
                                                side: const BorderSide(
                                                    color: Colors.white24),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(8),
                                                ),
                                              ),
                                              child: const Text(
                                                  'Reiniciar altura'),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: _openSyncWindow,
                                              icon: const Icon(Icons.sync,
                                                  size: 18),
                                              label: const Text(
                                                  'Sincronizar línea'),
                                              style:
                                                  ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF7B1FA2),
                                                foregroundColor:
                                                    Colors.white,
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubtitleUtils {
  static String srtToVtt(String srtContent) {
    final lines = srtContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final buffer = StringBuffer('WEBVTT\n\n');
    final timeRegex = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})',
    );

    int i = 0;
    while (i < lines.length) {
      final match = timeRegex.firstMatch(lines[i].trim());
      if (match != null) {
        final start =
            '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}:${match.group(3)}.${match.group(4)}';
        final end =
            '${match.group(5)!.padLeft(2, '0')}:${match.group(6)}:${match.group(7)}.${match.group(8)}';
        buffer.writeln('$start --> $end');
        i++;
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          buffer.writeln(lines[i].trim().replaceAll(RegExp(r'<[^>]*>'), ''));
          i++;
        }
        buffer.writeln();
      } else {
        i++;
      }
    }
    return buffer.toString();
  }

  static Future<String> downloadAndCache({
    required String url,
    required String cacheKey,
    required String fileName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Error HTTP ${res.statusCode}');

    String content = utf8.decode(res.bodyBytes, allowMalformed: true);

    if (!content.trimLeft().toUpperCase().startsWith('WEBVTT')) {
      content = srtToVtt(content);
    }

    await prefs.setString(cacheKey, content);
    return content;
  }
}