// player_widgets/subtitles_modal_tv.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OpenSubtitlesModalTv extends StatefulWidget {
  /// El player asigna esto para recuperar el foco al cerrar el panel de sync.
  static VoidCallback? restorePlayerFocus;

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
  final ValueChanged<double> onOffsetChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<double> onVerticalOffsetChanged;
  final Future<void> Function(Map<String, dynamic> sub) onSubtitleSelected;
  final VoidCallback onDisable;

  const OpenSubtitlesModalTv({
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
      builder: (_) => OpenSubtitlesModalTv(
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
  State<OpenSubtitlesModalTv> createState() => _OpenSubtitlesModalTvState();
}

class _OpenSubtitlesModalTvState extends State<OpenSubtitlesModalTv> {
  static const Color accentPurple = Color(0xFF9C27B0);
  static const Color accentPurpleLight = Color(0xFFCE93D8);

  static const String _prefLangKey = 'opensubtitles_preferred_lang';
  static const String _prefOffsetKey = 'subtitle_offset_sec';

  bool _loading = true;
  String? _error;
  Map<String, List<Map<String, dynamic>>> _byLang = {};
  List<String> _sortedLangs = [];
  String _currentLang = 'spa';

  late double _localOffset;
  late double _localFontSize;
  late bool _localBold;
  late double _localVerticalOffset;

  final FocusNode _closeFocus = FocusNode();
  final FocusNode _disableFocus = FocusNode();
  final List<FocusNode> _langFocusNodes = [];
  final List<FocusNode> _subFocusNodes = [];
  final FocusNode _offsetMinusFocus = FocusNode();
  final FocusNode _offsetPlusFocus = FocusNode();
  final FocusNode _offsetResetFocus = FocusNode();
  final FocusNode _fontMinusFocus = FocusNode();
  final FocusNode _fontPlusFocus = FocusNode();
  final FocusNode _boldFocus = FocusNode();
  final FocusNode _heightMinusFocus = FocusNode();
  final FocusNode _heightPlusFocus = FocusNode();
  final FocusNode _heightResetFocus = FocusNode();
  final FocusNode _syncFocus = FocusNode();

  final ScrollController _styleScrollController = ScrollController();
  final ScrollController _langScrollController = ScrollController();
  final ScrollController _subScrollController = ScrollController();

  final GlobalKey _offsetRowKey = GlobalKey();
  final GlobalKey _offsetResetKey = GlobalKey();
  final GlobalKey _fontRowKey = GlobalKey();
  final GlobalKey _boldKey = GlobalKey();
  final GlobalKey _heightRowKey = GlobalKey();
  final GlobalKey _heightResetKey = GlobalKey();
  final GlobalKey _syncKey = GlobalKey();

  int _col = 0;
  int _langIndex = 0;
  int _subIndex = 0;
  int _styleIndex = 0;

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
    _fetchSubtitles();
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    _disableFocus.dispose();
    for (final n in _langFocusNodes) {
      n.dispose();
    }
    for (final n in _subFocusNodes) {
      n.dispose();
    }
    _offsetMinusFocus.dispose();
    _offsetPlusFocus.dispose();
    _offsetResetFocus.dispose();
    _fontMinusFocus.dispose();
    _fontPlusFocus.dispose();
    _boldFocus.dispose();
    _heightMinusFocus.dispose();
    _heightPlusFocus.dispose();
    _heightResetFocus.dispose();
    _syncFocus.dispose();
    _styleScrollController.dispose();
    _langScrollController.dispose();
    _subScrollController.dispose();
    super.dispose();
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

      final langIdx = sorted.indexOf(current);
      if (mounted) {
        setState(() {
          _byLang = byLang;
          _sortedLangs = sorted;
          _currentLang = current;
          _langIndex = langIdx >= 0 ? langIdx : 0;
          _loading = false;
        });
        _rebuildLangFocus();
        _rebuildSubFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_langFocusNodes.isNotEmpty) {
            final idx = _langIndex.clamp(0, _langFocusNodes.length - 1);
            _langFocusNodes[idx].requestFocus();
            _scrollLangTo(idx);
          }
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

  void _rebuildLangFocus() {
    for (final n in _langFocusNodes) {
      n.dispose();
    }
    _langFocusNodes
      ..clear()
      ..addAll(List.generate(_sortedLangs.length, (_) => FocusNode()));
  }

  void _rebuildSubFocus() {
    for (final n in _subFocusNodes) {
      n.dispose();
    }
    final list = _byLang[_currentLang] ?? [];
    _subFocusNodes
      ..clear()
      ..addAll(List.generate(list.length, (_) => FocusNode()));
  }

  void _changeLang(String lang) {
    setState(() {
      _currentLang = lang;
      _subIndex = 0;
      final idx = _sortedLangs.indexOf(lang);
      if (idx >= 0) _langIndex = idx;
    });
    _savePreferredLang(lang);
    _rebuildSubFocus();
  }

  void _scrollLangTo(int index) {
    if (!_langScrollController.hasClients) return;
    const itemH = 52.0;
    final offset = (index * itemH) - 80;
    _langScrollController.animateTo(
      offset.clamp(0.0, _langScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollSubTo(int index) {
    if (!_subScrollController.hasClients) return;
    const itemH = 90.0;
    final offset = (index * itemH) - 60;
    _subScrollController.animateTo(
      offset.clamp(0.0, _subScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollStyleToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_col < 2) {
        setState(() => _col++);
        _focusCurrent();
      } else {
        _moveStyleHorizontal(1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_col == 2) {
        if (_styleIndex == 1 || _styleIndex == 4 || _styleIndex == 7) {
          setState(() => _styleIndex--);
          _focusStyle(_styleIndex);
        } else {
          setState(() => _col = 1);
          _focusCurrent();
        }
      } else if (_col > 0) {
        setState(() => _col--);
        _focusCurrent();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveVertical(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveVertical(-1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveStyleHorizontal(int dir) {
    int next = _styleIndex;
    if (dir > 0) {
      if (_styleIndex == 0) {
        next = 1;
      } else if (_styleIndex == 3) {
        next = 4;
      } else if (_styleIndex == 6) {
        next = 7;
      }
    } else {
      if (_styleIndex == 1) {
        next = 0;
      } else if (_styleIndex == 4) {
        next = 3;
      } else if (_styleIndex == 7) {
        next = 6;
      }
    }
    if (next != _styleIndex) {
      setState(() => _styleIndex = next);
      _focusStyle(next);
    }
  }

  void _moveVertical(int dir) {
    if (_col == 0) {
      if (_sortedLangs.isEmpty) return;
      final next = (_langIndex + dir).clamp(0, _sortedLangs.length - 1);
      if (next != _langIndex) {
        setState(() => _langIndex = next);
        _langFocusNodes[next].requestFocus();
        _scrollLangTo(next);
      }
    } else if (_col == 1) {
      final list = _byLang[_currentLang] ?? [];
      if (list.isEmpty) return;
      final next = (_subIndex + dir).clamp(0, list.length - 1);
      if (next != _subIndex) {
        setState(() => _subIndex = next);
        _subFocusNodes[next].requestFocus();
        _scrollSubTo(next);
      }
    } else {
      int next = _styleIndex;
      if (dir > 0) {
        if (_styleIndex <= 1) {
          next = 2;
        } else if (_styleIndex == 2) {
          next = 3;
        } else if (_styleIndex == 3 || _styleIndex == 4) {
          next = 5;
        } else if (_styleIndex == 5) {
          next = 6;
        } else if (_styleIndex == 6 || _styleIndex == 7) {
          next = 8;
        } else if (_styleIndex == 8) {
          next = 9;
        }
      } else {
        if (_styleIndex == 9) {
          next = 8;
        } else if (_styleIndex == 8) {
          next = 6;
        } else if (_styleIndex == 6 || _styleIndex == 7) {
          next = 5;
        } else if (_styleIndex == 5) {
          next = 3;
        } else if (_styleIndex == 3 || _styleIndex == 4) {
          next = 2;
        } else if (_styleIndex == 2) {
          next = 0;
        }
      }
      if (next != _styleIndex) {
        setState(() => _styleIndex = next);
        _focusStyle(next);
      }
    }
  }

  void _focusCurrent() {
    if (_col == 0 && _langFocusNodes.isNotEmpty) {
      final i = _langIndex.clamp(0, _langFocusNodes.length - 1);
      _langFocusNodes[i].requestFocus();
      _scrollLangTo(i);
    } else if (_col == 1 && _subFocusNodes.isNotEmpty) {
      final i = _subIndex.clamp(0, _subFocusNodes.length - 1);
      _subFocusNodes[i].requestFocus();
      _scrollSubTo(i);
    } else if (_col == 2) {
      _focusStyle(_styleIndex);
    } else if (_col == 1 && _subFocusNodes.isEmpty) {
      setState(() => _col = 2);
      _focusStyle(_styleIndex);
    }
  }

  void _focusStyle(int index) {
    switch (index) {
      case 0:
        _offsetMinusFocus.requestFocus();
        _scrollStyleToKey(_offsetRowKey);
        break;
      case 1:
        _offsetPlusFocus.requestFocus();
        _scrollStyleToKey(_offsetRowKey);
        break;
      case 2:
        _offsetResetFocus.requestFocus();
        _scrollStyleToKey(_offsetResetKey);
        break;
      case 3:
        _fontMinusFocus.requestFocus();
        _scrollStyleToKey(_fontRowKey);
        break;
      case 4:
        _fontPlusFocus.requestFocus();
        _scrollStyleToKey(_fontRowKey);
        break;
      case 5:
        _boldFocus.requestFocus();
        _scrollStyleToKey(_boldKey);
        break;
      case 6:
        _heightMinusFocus.requestFocus();
        _scrollStyleToKey(_heightRowKey);
        break;
      case 7:
        _heightPlusFocus.requestFocus();
        _scrollStyleToKey(_heightRowKey);
        break;
      case 8:
        _heightResetFocus.requestFocus();
        _scrollStyleToKey(_heightResetKey);
        break;
      case 9:
        _syncFocus.requestFocus();
        _scrollStyleToKey(_syncKey);
        break;
    }
  }

  void _openSyncByLineModal() {
    final onOffset = widget.onOffsetChanged;
    final initialOffset = _localOffset;
    final overlay = Overlay.of(context, rootOverlay: true);

    Navigator.pop(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFloatingOffsetPanel(
        overlay: overlay,
        initialOffset: initialOffset,
        onOffsetChanged: onOffset,
      );
    });
  }

  void _showFloatingOffsetPanel({
    required OverlayState overlay,
    required double initialOffset,
    required ValueChanged<double> onOffsetChanged,
  }) {
    late OverlayEntry entry;

    double localOffset = initialOffset.clamp(-30.0, 30.0);
    var panelAlive = true;

    final focusScope = FocusScopeNode(debugLabel: 'sync_scope');
    final focusClose = FocusNode(debugLabel: 'sync_close');
    final focusM1 = FocusNode(debugLabel: 'sync_m1');
    final focusM01 = FocusNode(debugLabel: 'sync_m01');
    final focusP01 = FocusNode(debugLabel: 'sync_p01');
    final focusP1 = FocusNode(debugLabel: 'sync_p1');
    final focusReset = FocusNode(debugLabel: 'sync_reset');

    final panelNodes = <FocusNode>[
      focusClose,
      focusM1,
      focusM01,
      focusP01,
      focusP1,
      focusReset,
    ];

    void reclaimFocus() {
      if (!panelAlive) return;
      final hasAny = panelNodes.any((n) => n.hasFocus) || focusScope.hasFocus;
      if (!hasAny) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!panelAlive) return;
          if (focusM1.canRequestFocus) focusM1.requestFocus();
        });
      }
    }

    void closePanel() {
      if (!panelAlive) return;
      panelAlive = false;
      FocusManager.instance.removeListener(reclaimFocus);
      try {
        entry.remove();
      } catch (_) {}
      focusScope.dispose();
      for (final n in panelNodes) {
        n.dispose();
      }
      // Devolver foco al player / controles
      final restore = OpenSubtitlesModalTv.restorePlayerFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restore?.call();
      });
    }

    void apply(double v, void Function(void Function()) setWin) {
      localOffset = v.clamp(-30.0, 30.0);
      onOffsetChanged(localOffset);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble(_prefOffsetKey, localOffset);
      });
      setWin(() {});
    }

    Widget tvBtn({
      required FocusNode node,
      required String label,
      required VoidCallback onSelect,
      FocusNode? left,
      FocusNode? right,
      FocusNode? up,
      FocusNode? down,
      bool wide = false,
    }) {
      return Focus(
        focusNode: node,
        onKeyEvent: (n, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;

          if (k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.enter) {
            onSelect();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.goBack ||
              k == LogicalKeyboardKey.browserBack) {
            closePanel();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowLeft) {
            (left ?? node).requestFocus();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            (right ?? node).requestFocus();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowUp) {
            (up ?? focusClose).requestFocus();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            (down ?? node).requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.handled;
        },
        child: Builder(
          builder: (ctx) {
            final has = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: onSelect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 14 : 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: has
                      ? accentPurple.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: has ? accentPurpleLight : Colors.white24,
                    width: has ? 2 : 1,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: wide ? 14 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    entry = OverlayEntry(
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setWin) {
            return Positioned(
              left: 0,
              right: 0,
              top: 28,
              child: FocusScope(
                node: focusScope,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    final k = event.logicalKey;
                    if (k == LogicalKeyboardKey.escape ||
                        k == LogicalKeyboardKey.goBack ||
                        k == LogicalKeyboardKey.browserBack) {
                      closePanel();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    elevation: 12,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xF01A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accentPurple.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Sincronizar subtítulos',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Focus(
                                focusNode: focusClose,
                                onKeyEvent: (n, e) {
                                  if (e is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final k = e.logicalKey;
                                  if (k == LogicalKeyboardKey.select ||
                                      k == LogicalKeyboardKey.enter ||
                                      k == LogicalKeyboardKey.escape ||
                                      k == LogicalKeyboardKey.goBack ||
                                      k == LogicalKeyboardKey.browserBack) {
                                    closePanel();
                                    return KeyEventResult.handled;
                                  }
                                  if (k == LogicalKeyboardKey.arrowDown) {
                                    focusM1.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.handled;
                                },
                                child: Builder(
                                  builder: (c) {
                                    final has = Focus.of(c).hasFocus;
                                    return GestureDetector(
                                      onTap: closePanel,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: has
                                              ? accentPurple.withValues(
                                                  alpha: 0.55)
                                              : Colors.white12,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: has
                                              ? Border.all(
                                                  color: accentPurpleLight,
                                                  width: 2)
                                              : null,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              tvBtn(
                                node: focusM1,
                                label: '−1s',
                                up: focusClose,
                                right: focusM01,
                                down: focusReset,
                                onSelect: () =>
                                    apply(localOffset - 1.0, setWin),
                              ),
                              const SizedBox(width: 6),
                              tvBtn(
                                node: focusM01,
                                label: '−0.1s',
                                up: focusClose,
                                left: focusM1,
                                right: focusP01,
                                down: focusReset,
                                onSelect: () =>
                                    apply(localOffset - 0.1, setWin),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                constraints:
                                    const BoxConstraints(minWidth: 72),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: accentPurple.withValues(
                                        alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  '${localOffset >= 0 ? '+' : ''}${localOffset.toStringAsFixed(1)}s',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              tvBtn(
                                node: focusP01,
                                label: '+0.1s',
                                up: focusClose,
                                left: focusM01,
                                right: focusP1,
                                down: focusReset,
                                onSelect: () =>
                                    apply(localOffset + 0.1, setWin),
                              ),
                              const SizedBox(width: 6),
                              tvBtn(
                                node: focusP1,
                                label: '+1s',
                                up: focusClose,
                                left: focusP01,
                                down: focusReset,
                                onSelect: () =>
                                    apply(localOffset + 1.0, setWin),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          tvBtn(
                            node: focusReset,
                            label: 'Reiniciar 0.0s',
                            wide: true,
                            up: focusM1,
                            down: focusReset,
                            onSelect: () => apply(0.0, setWin),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    FocusManager.instance.addListener(reclaimFocus);
    overlay.insert(entry);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (panelAlive && focusM1.canRequestFocus) focusM1.requestFocus();
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      if (panelAlive && focusM1.canRequestFocus && !focusM1.hasFocus) {
        focusM1.requestFocus();
      }
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (panelAlive && focusM1.canRequestFocus) {
        final hasAny = panelNodes.any((n) => n.hasFocus);
        if (!hasAny) focusM1.requestFocus();
      }
    });
  }

  Widget _styleFocusable({
    required FocusNode focusNode,
    required Widget child,
    required VoidCallback onSelect,
    required int styleIndex,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (has) {
        if (has) {
          setState(() {
            _col = 2;
            _styleIndex = styleIndex;
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            onSelect();
            return KeyEventResult.handled;
          }
          return _handleKey(node, event);
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: hasFocus
                  ? Border.all(color: accentPurpleLight, width: 2)
                  : null,
              color: hasFocus
                  ? accentPurple.withValues(alpha: 0.25)
                  : Colors.transparent,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _byLang[_currentLang] ?? [];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 580),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
              child: Row(
                children: [
                  const Text(
                    'Subtítulos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Focus(
                    focusNode: _disableFocus,
                    onKeyEvent: (n, e) {
                      if (e is KeyDownEvent &&
                          (e.logicalKey == LogicalKeyboardKey.select ||
                              e.logicalKey == LogicalKeyboardKey.enter)) {
                        widget.onDisable();
                        Navigator.pop(context);
                        return KeyEventResult.handled;
                      }
                      return _handleKey(n, e);
                    },
                    child: Builder(builder: (ctx) {
                      final has = Focus.of(ctx).hasFocus;
                      return TextButton(
                        onPressed: () {
                          widget.onDisable();
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: has
                              ? Colors.redAccent.withValues(alpha: 0.3)
                              : null,
                        ),
                        child: const Text(
                          'Desactivar',
                          style:
                              TextStyle(color: Colors.redAccent, fontSize: 15),
                        ),
                      );
                    }),
                  ),
                  Focus(
                    focusNode: _closeFocus,
                    onKeyEvent: (n, e) {
                      if (e is KeyDownEvent &&
                          (e.logicalKey == LogicalKeyboardKey.select ||
                              e.logicalKey == LogicalKeyboardKey.enter)) {
                        Navigator.pop(context);
                        return KeyEventResult.handled;
                      }
                      return _handleKey(n, e);
                    },
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 26),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: accentPurple))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 16)))
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // COLUMNA IDIOMAS
                            Container(
                              width: 180,
                              decoration: const BoxDecoration(
                                border: Border(
                                    right: BorderSide(color: Colors.white10)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(18, 14, 18, 10),
                                    child: Text(
                                      'Idiomas',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _langScrollController,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      itemCount: _sortedLangs.length,
                                      itemBuilder: (_, i) {
                                        final lang = _sortedLangs[i];
                                        final count = _byLang[lang]!.length;
                                        final isSelected =
                                            lang == _currentLang;

                                        return Focus(
                                          focusNode: _langFocusNodes.length > i
                                              ? _langFocusNodes[i]
                                              : FocusNode(),
                                          onFocusChange: (has) {
                                            if (has) {
                                              setState(() {
                                                _col = 0;
                                                _langIndex = i;
                                              });
                                              _scrollLangTo(i);
                                            }
                                          },
                                          onKeyEvent: (node, event) {
                                            if (event is KeyDownEvent) {
                                              if (event.logicalKey ==
                                                      LogicalKeyboardKey
                                                          .select ||
                                                  event.logicalKey ==
                                                      LogicalKeyboardKey
                                                          .enter) {
                                                _changeLang(lang);
                                                setState(() => _col = 1);
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) {
                                                  if (_subFocusNodes
                                                      .isNotEmpty) {
                                                    _subFocusNodes[0]
                                                        .requestFocus();
                                                  }
                                                });
                                                return KeyEventResult.handled;
                                              }
                                              return _handleKey(node, event);
                                            }
                                            return KeyEventResult.ignored;
                                          },
                                          child: Builder(
                                            builder: (context) {
                                              final hasFocus =
                                                  Focus.of(context).hasFocus;
                                              return GestureDetector(
                                                onTap: () {
                                                  _changeLang(lang);
                                                  setState(() => _col = 1);
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback(
                                                          (_) {
                                                    if (_subFocusNodes
                                                        .isNotEmpty) {
                                                      _subFocusNodes[0]
                                                          .requestFocus();
                                                    }
                                                  });
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .only(bottom: 5),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: hasFocus
                                                        ? accentPurple
                                                            .withValues(
                                                                alpha: 0.4)
                                                        : (isSelected
                                                            ? accentPurple
                                                                .withValues(
                                                                    alpha: 0.2)
                                                            : Colors
                                                                .transparent),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: hasFocus
                                                        ? Border.all(
                                                            color:
                                                                accentPurpleLight,
                                                            width: 1.5)
                                                        : null,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          _langDisplayName(
                                                              lang),
                                                          style: TextStyle(
                                                            color: hasFocus ||
                                                                    isSelected
                                                                ? Colors.white
                                                                : Colors
                                                                    .white70,
                                                            fontWeight: hasFocus ||
                                                                    isSelected
                                                                ? FontWeight
                                                                    .w600
                                                                : FontWeight
                                                                    .w400,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: hasFocus
                                                              ? accentPurpleLight
                                                              : Colors.white24,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      10),
                                                        ),
                                                        child: Text(
                                                          '$count',
                                                          style: TextStyle(
                                                            color: hasFocus
                                                                ? Colors.black
                                                                : Colors
                                                                    .white70,
                                                            fontSize: 12,
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
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // COLUMNA SUBTÍTULOS
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(18, 14, 18, 10),
                                    child: Text(
                                      'Subtítulos',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
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
                                                  color: Colors.white38,
                                                  fontSize: 15),
                                            ),
                                          )
                                        : ListView.builder(
                                            controller: _subScrollController,
                                            padding: const EdgeInsets
                                                .symmetric(horizontal: 14),
                                            itemCount: currentList.length,
                                            itemBuilder: (_, i) {
                                              final sub = currentList[i];
                                              final id =
                                                  sub['id']?.toString() ?? '';
                                              final name = sub[
                                                          'subtitleFileName']
                                                      ?.toString() ??
                                                  'Subtítulo';
                                              final release = sub[
                                                          'movieReleaseName']
                                                      ?.toString() ??
                                                  '';
                                              final isSelected =
                                                  widget.currentSubtitleId ==
                                                      id;

                                              return Focus(
                                                focusNode:
                                                    _subFocusNodes.length > i
                                                        ? _subFocusNodes[i]
                                                        : FocusNode(),
                                                onFocusChange: (has) {
                                                  if (has) {
                                                    setState(() {
                                                      _col = 1;
                                                      _subIndex = i;
                                                    });
                                                    _scrollSubTo(i);
                                                  }
                                                },
                                                onKeyEvent: (node, event) {
                                                  if (event is KeyDownEvent) {
                                                    if (event.logicalKey ==
                                                            LogicalKeyboardKey
                                                                .select ||
                                                        event.logicalKey ==
                                                            LogicalKeyboardKey
                                                                .enter) {
                                                      Navigator.pop(context);
                                                      widget
                                                          .onSubtitleSelected(
                                                              sub);
                                                      return KeyEventResult
                                                          .handled;
                                                    }
                                                    return _handleKey(
                                                        node, event);
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
                                                      onTap: () async {
                                                        Navigator.pop(
                                                            context);
                                                        await widget
                                                            .onSubtitleSelected(
                                                                sub);
                                                      },
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets
                                                                .only(
                                                                bottom: 8),
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: hasFocus
                                                              ? accentPurple
                                                                  .withValues(
                                                                      alpha:
                                                                          0.45)
                                                              : (isSelected
                                                                  ? accentPurple
                                                                      .withValues(
                                                                          alpha:
                                                                              0.25)
                                                                  : Colors
                                                                      .white
                                                                      .withValues(
                                                                          alpha:
                                                                              0.05)),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12),
                                                          border: hasFocus
                                                              ? Border.all(
                                                                  color:
                                                                      accentPurpleLight,
                                                                  width: 1.8)
                                                              : null,
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Container(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        3,
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
                                                                    style: TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.w600),
                                                                  ),
                                                                ),
                                                                const Spacer(),
                                                                if (isSelected)
                                                                  const Icon(
                                                                      Icons
                                                                          .check_rounded,
                                                                      color: Colors
                                                                          .white,
                                                                      size: 20),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                              name,
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 14,
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
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .grey[500],
                                                                  fontSize: 12,
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
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            // COLUMNA ESTILO
                            Container(
                              width: 220,
                              decoration: const BoxDecoration(
                                border: Border(
                                    left: BorderSide(color: Colors.white10)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16, 14, 16, 10),
                                    child: Text(
                                      'Estilo',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      controller: _styleScrollController,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Retraso de subtítulos',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                          const SizedBox(height: 10),
                                          KeyedSubtree(
                                            key: _offsetRowKey,
                                            child: Row(
                                              children: [
                                                _styleFocusable(
                                                  focusNode:
                                                      _offsetMinusFocus,
                                                  styleIndex: 0,
                                                  onSelect: () {
                                                    final v =
                                                        (_localOffset - 0.5)
                                                            .clamp(
                                                                -30.0, 30.0);
                                                    setState(() =>
                                                        _localOffset = v);
                                                    widget.onOffsetChanged(v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.remove,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 10),
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
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                _styleFocusable(
                                                  focusNode:
                                                      _offsetPlusFocus,
                                                  styleIndex: 1,
                                                  onSelect: () {
                                                    final v =
                                                        (_localOffset + 0.5)
                                                            .clamp(
                                                                -30.0, 30.0);
                                                    setState(() =>
                                                        _localOffset = v);
                                                    widget.onOffsetChanged(v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.add,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          KeyedSubtree(
                                            key: _offsetResetKey,
                                            child: _styleFocusable(
                                              focusNode: _offsetResetFocus,
                                              styleIndex: 2,
                                              onSelect: () {
                                                setState(() =>
                                                    _localOffset = 0.0);
                                                widget.onOffsetChanged(0.0);
                                              },
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                alignment: Alignment.center,
                                                child: const Text(
                                                  'Reiniciar retraso',
                                                  style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 14),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          const Text(
                                            'Tamaño de fuente',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                          const SizedBox(height: 10),
                                          KeyedSubtree(
                                            key: _fontRowKey,
                                            child: Row(
                                              children: [
                                                _styleFocusable(
                                                  focusNode:
                                                      _fontMinusFocus,
                                                  styleIndex: 3,
                                                  onSelect: () {
                                                    final v =
                                                        (_localFontSize - 1)
                                                            .clamp(
                                                                12.0, 36.0);
                                                    setState(() =>
                                                        _localFontSize = v);
                                                    widget
                                                        .onFontSizeChanged(v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.remove,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 10),
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
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                _styleFocusable(
                                                  focusNode: _fontPlusFocus,
                                                  styleIndex: 4,
                                                  onSelect: () {
                                                    final v =
                                                        (_localFontSize + 1)
                                                            .clamp(
                                                                12.0, 36.0);
                                                    setState(() =>
                                                        _localFontSize = v);
                                                    widget
                                                        .onFontSizeChanged(v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.add,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          const Text(
                                            'Estilo',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                          const SizedBox(height: 10),
                                          KeyedSubtree(
                                            key: _boldKey,
                                            child: _styleFocusable(
                                              focusNode: _boldFocus,
                                              styleIndex: 5,
                                              onSelect: () {
                                                setState(() =>
                                                    _localBold = !_localBold);
                                                widget
                                                    .onBoldChanged(_localBold);
                                              },
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  _localBold
                                                      ? 'Negrita'
                                                      : 'Normal',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: _localBold
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          const Text(
                                            'Altura (desde abajo)',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                          const SizedBox(height: 10),
                                          KeyedSubtree(
                                            key: _heightRowKey,
                                            child: Row(
                                              children: [
                                                _styleFocusable(
                                                  focusNode:
                                                      _heightMinusFocus,
                                                  styleIndex: 6,
                                                  onSelect: () {
                                                    final v =
                                                        (_localVerticalOffset -
                                                                8)
                                                            .clamp(
                                                                -40.0, 160.0);
                                                    setState(() =>
                                                        _localVerticalOffset =
                                                            v);
                                                    widget
                                                        .onVerticalOffsetChanged(
                                                            v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.remove,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 10),
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
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                _styleFocusable(
                                                  focusNode:
                                                      _heightPlusFocus,
                                                  styleIndex: 7,
                                                  onSelect: () {
                                                    final v =
                                                        (_localVerticalOffset +
                                                                8)
                                                            .clamp(
                                                                -40.0, 160.0);
                                                    setState(() =>
                                                        _localVerticalOffset =
                                                            v);
                                                    widget
                                                        .onVerticalOffsetChanged(
                                                            v);
                                                  },
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    alignment:
                                                        Alignment.center,
                                                    child: const Icon(
                                                        Icons.add,
                                                        color: Colors.white,
                                                        size: 22),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          KeyedSubtree(
                                            key: _heightResetKey,
                                            child: _styleFocusable(
                                              focusNode: _heightResetFocus,
                                              styleIndex: 8,
                                              onSelect: () {
                                                setState(() =>
                                                    _localVerticalOffset =
                                                        0);
                                                widget
                                                    .onVerticalOffsetChanged(
                                                        0);
                                              },
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                alignment: Alignment.center,
                                                child: const Text(
                                                  'Reiniciar altura',
                                                  style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 14),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          KeyedSubtree(
                                            key: _syncKey,
                                            child: _styleFocusable(
                                              focusNode: _syncFocus,
                                              styleIndex: 9,
                                              onSelect: _openSyncByLineModal,
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        vertical: 14),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                      0xFF7B1FA2),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10),
                                                ),
                                                child: const Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .center,
                                                  children: [
                                                    Icon(Icons.sync,
                                                        color: Colors.white,
                                                        size: 20),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Sincronizar línea',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
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