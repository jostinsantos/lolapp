import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../content/presentation/tv_content_page.dart';
import '../../content/presentation/tv_content_options_modal.dart';
import '../../../data/datasources/remote/tmdb/tmdb_search.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kKeyColor = Color(0xFF2A2A38);

class BuscarPage extends StatefulWidget {
  final void Function(BuscarPageState)? onPageCreated;
  final VoidCallback? onRequestMenuFocus;

  const BuscarPage({
    super.key,
    this.onPageCreated,
    this.onRequestMenuFocus,
  });

  @override
  State<BuscarPage> createState() => BuscarPageState();
}

class BuscarPageState extends State<BuscarPage> {
  final TmdbSearchService _tmdbSearch = TmdbSearchService();

  String _query = '';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  Timer? _debounce;
  int _searchId = 0;

  bool _showAccents = false;

  /// true mientras el campo de texto está habilitado para recibir el
  /// teclado del sistema (Android TV).
  bool _sysKeyboard = false;

  final FocusNode _aKeyFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode(skipTraversal: true);
  final FocusNode _firstResultFocus = FocusNode(debugLabel: 'firstResult');
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onInputFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPageCreated?.call(this);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _aKeyFocusNode.dispose();
    _inputFocusNode.dispose();
    _firstResultFocus.dispose();
    _inputController.dispose();
    super.dispose();
  }

  FocusNode getAKeyFocusNode() => _aKeyFocusNode;

  void _goMenu() {
    widget.onRequestMenuFocus?.call();
  }

  // ── Teclado del sistema (Android TV) ────────────────────────────────────

  /// Si el campo pierde el foco (el usuario navegó con el D-pad a otro lado)
  /// se vuelve a excluir del foco para no interferir con el teclado propio.
  void _onInputFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (!_inputFocusNode.hasFocus) _sysKeyboard = false;
    });
  }

  Future<void> _openSystemKeyboard() async {
    setState(() => _sysKeyboard = true);

    // Esperar a que el campo deje de estar excluido del foco
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    _inputFocusNode.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  /// El usuario pulsó "Siguiente" / "Buscar" en el teclado del sistema:
  /// cierra el teclado, busca y pasa el foco al primer resultado.
  Future<void> _onSystemKeyboardSubmit() async {
    _debounce?.cancel();
    _inputFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (_sysKeyboard) setState(() => _sysKeyboard = false);

    if (_query.trim().isEmpty) {
      _aKeyFocusNode.requestFocus();
      return;
    }

    await _doSearch();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_items.isNotEmpty) {
        _firstResultFocus.requestFocus();
      } else {
        _aKeyFocusNode.requestFocus();
      }
    });
  }

  // ── Consulta ────────────────────────────────────────────────────────────

  void _setQuery(String value) {
    _query = value;
    if (_inputController.text != value) {
      _inputController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    setState(() {});
    _scheduleSearch();
  }

  void _onKeyTap(String char) {
    _setQuery(_query + char);
  }

  void _onBackspace() {
    if (_query.isEmpty) return;
    _setQuery(_query.substring(0, _query.length - 1));
  }

  void _onClear() {
    _debounce?.cancel();
    _setQuery('');
    setState(() {
      _items = [];
      _searched = false;
      _error = null;
      _loading = false;
    });
  }

  void _toggleAccents() {
    setState(() => _showAccents = !_showAccents);
  }

  void _scheduleSearch() {
    _debounce?.cancel();

    final q = _query.trim();
    if (q.isEmpty) {
      setState(() {
        _items = [];
        _searched = false;
        _error = null;
        _loading = false;
      });
      return;
    }

    if (q.length < 2) {
      setState(() {
        _loading = false;
        _searched = false;
        _items = [];
      });
      return;
    }

    setState(() => _loading = true);

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _doSearch();
    });
  }

  Future<void> _doSearch() async {
    final q = _query.trim();
    if (q.isEmpty) return;

    final currentId = ++_searchId;

    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final json = await _tmdbSearch.search(q, limit: 30);

      if (currentId != _searchId || !mounted) return;

      if (json['success'] == true) {
        final items = List<Map<String, dynamic>>.from(
          json['data']?['items'] ?? [],
        );
        setState(() {
          _items = items;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'No se pudo buscar';
          _items = [];
          _loading = false;
        });
      }
    } catch (e) {
      if (currentId != _searchId || !mounted) return;
      setState(() {
        _error = 'Sin conexión o error de red';
        _items = [];
        _loading = false;
      });
    }
  }

  void _openContent(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo = item['media_type']?.toString() ?? 'movie';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: id,
          tmdbId: id,
          mediaType: tipo,
        ),
      ),
    );
  }

  void _openOpciones(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo = item['media_type']?.toString() ?? 'movie';

    showContenidoOpcionesModal(
      context,
      tmdbId: id,
      tipo: tipo,
      idcontenido: id,
      titulo: item['title']?.toString() ?? item['titulo']?.toString(),
      posterUrl: item['poster_path']?.toString() ?? item['poster']?.toString(),
      backdropUrl:
          item['backdrop_path']?.toString() ?? item['backdrop']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 260,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SearchInput(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          enabled: _sysKeyboard,
                          onChanged: (v) {
                            _query = v;
                            setState(() {});
                            _scheduleSearch();
                          },
                          onSubmitted: (_) => _onSystemKeyboardSubmit(),
                        ),
                        const SizedBox(height: 12),
                        // Botón + teclado con scroll (pantallas pequeñas)
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SystemKeyboardButton(
                                  onTap: _openSystemKeyboard,
                                  onRequestMenuFocus: _goMenu,
                                ),
                                const SizedBox(height: 8),
                                _Keyboard(
                                  showAccents: _showAccents,
                                  onKey: _onKeyTap,
                                  onBackspace: _onBackspace,
                                  onClear: _onClear,
                                  onToggleAccents: _toggleAccents,
                                  aKeyFocusNode: _aKeyFocusNode,
                                  onRequestMenuFocus: _goMenu,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                  child: _buildResultsArea(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _doSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (!_searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 60),
          child: Text(
            'Escribe para buscar películas y series\nen tiempo real.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados para "$_query"',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resultados de búsqueda',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_items.length} título${_items.length == 1 ? '' : 's'} encontrado${_items.length == 1 ? '' : 's'}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _ResultsGrid(
            items: _items,
            firstItemFocusNode: _firstResultFocus,
            onTap: _openContent,
            onLongPress: _openOpciones,
          ),
        ),
      ],
    );
  }
}

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// false = el campo NO recibe foco (modo teclado propio en pantalla).
  /// true  = el campo puede recibir foco y abrir el teclado del sistema.
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: !enabled,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focusNode.hasFocus
                ? Colors.white.withValues(alpha: 0.45)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                // "Siguiente" / "Buscar" del teclado del sistema
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onSubmitted(controller.text),
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                enableInteractiveSelection: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: kAccentColor,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Buscar...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón que abre el teclado del sistema de Android TV.
class _SystemKeyboardButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onRequestMenuFocus;

  const _SystemKeyboardButton({
    required this.onTap,
    this.onRequestMenuFocus,
  });

  @override
  State<_SystemKeyboardButton> createState() => _SystemKeyboardButtonState();
}

class _SystemKeyboardButtonState extends State<_SystemKeyboardButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onRequestMenuFocus?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hasFocus ? Colors.white : kKeyColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hasFocus ? kAccentColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: _hasFocus ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Teclado del TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hasFocus ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keyboard extends StatelessWidget {
  final bool showAccents;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onToggleAccents;
  final FocusNode aKeyFocusNode;
  final VoidCallback? onRequestMenuFocus;

  const _Keyboard({
    required this.showAccents,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onToggleAccents,
    required this.aKeyFocusNode,
    this.onRequestMenuFocus,
  });

  static const _rowsNormal = [
    ['a', 'b', 'c', 'd', 'e'],
    ['f', 'g', 'h', 'i', 'j'],
    ['k', 'l', 'm', 'n', 'o'],
    ['p', 'q', 'r', 's', 't'],
    ['u', 'v', 'w', 'x', 'y'],
  ];

  static const _rowsAccents = [
    ['á', 'é', 'í', 'ó', 'ú'],
    ['ü', 'ñ', 'Á', 'É', 'Í'],
    ['Ó', 'Ú', 'Ü', '¿', '¡'],
    ['1', '2', '3', '4', '5'],
    ['6', '7', '8', '9', '0'],
  ];

  static const _leftEdgeNormal = {'a', 'f', 'k', 'p', 'u', 'z'};
  static const _leftEdgeAccents = {'á', 'ü', 'Ó', '1', '6'};

  @override
  Widget build(BuildContext context) {
    final rows = showAccents ? _rowsAccents : _rowsNormal;
    final leftEdge = showAccents ? _leftEdgeAccents : _leftEdgeNormal;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (final char in row) ...[
                    _KeyButton(
                      label: char,
                      onTap: () => onKey(char),
                      focusNode:
                          (!showAccents && char == 'a') ? aKeyFocusNode : null,
                      allowLeftEscape: leftEdge.contains(char),
                      onRequestMenuFocus: onRequestMenuFocus,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          if (!showAccents)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _KeyButton(
                    label: 'z',
                    onTap: () => onKey('z'),
                    allowLeftEscape: true,
                    onRequestMenuFocus: onRequestMenuFocus,
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(
                    label: 'ñ',
                    onTap: () => onKey('ñ'),
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(
                    label: ' ',
                    icon: Icons.space_bar,
                    onTap: () => onKey(' '),
                    flex: 2,
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(
                    icon: Icons.backspace_outlined,
                    onTap: onBackspace,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _KeyButton(
                    label: ' ',
                    icon: Icons.space_bar,
                    onTap: () => onKey(' '),
                    flex: 2,
                    allowLeftEscape: true,
                    onRequestMenuFocus: onRequestMenuFocus,
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(
                    icon: Icons.backspace_outlined,
                    onTap: onBackspace,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Container()),
                ],
              ),
            ),
          Row(
            children: [
              _KeyButton(
                icon: Icons.close,
                onTap: onClear,
                allowLeftEscape: true,
                onRequestMenuFocus: onRequestMenuFocus,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _AccentToggleKey(
                  isActive: showAccents,
                  onTap: onToggleAccents,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final FocusNode? focusNode;
  final bool allowLeftEscape;
  final VoidCallback? onRequestMenuFocus;

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.focusNode,
    this.allowLeftEscape = false,
    this.onRequestMenuFocus,
  });

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final button = Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (widget.allowLeftEscape) {
            widget.onRequestMenuFocus?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          decoration: BoxDecoration(
            color: _hasFocus ? Colors.white : kKeyColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hasFocus ? kAccentColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: widget.icon != null
              ? Icon(
                  widget.icon,
                  size: 18,
                  color: _hasFocus ? Colors.black : Colors.white70,
                )
              : Text(
                  widget.label ?? '',
                  style: TextStyle(
                    color: _hasFocus ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );

    return Expanded(flex: widget.flex, child: button);
  }
}

class _AccentToggleKey extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _AccentToggleKey({
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_AccentToggleKey> createState() => _AccentToggleKeyState();
}

class _AccentToggleKeyState extends State<_AccentToggleKey> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          decoration: BoxDecoration(
            color: widget.isActive
                ? (_hasFocus
                    ? kAccentColor
                    : kAccentColor.withValues(alpha: 0.9))
                : (_hasFocus ? Colors.white : kKeyColor),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hasFocus
                  ? (widget.isActive ? Colors.white : kAccentColor)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.isActive ? 'ABC' : 'ÁÉÍ',
            style: TextStyle(
              color: widget.isActive
                  ? Colors.white
                  : (_hasFocus ? Colors.black : Colors.white),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final FocusNode? firstItemFocusNode;
  final void Function(Map<String, dynamic> item) onTap;
  final void Function(Map<String, dynamic> item) onLongPress;

  const _ResultsGrid({
    required this.items,
    this.firstItemFocusNode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.5);

    return GridView.builder(
      itemCount: items.length,
      addAutomaticKeepAlives: false,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.6,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final title = item['title']?.toString() ?? '';
        final poster = item['poster_path']?.toString() ?? '';
        final year = item['year']?.toString() ?? '';
        final mediaType = item['media_type']?.toString() ?? 'movie';
        final typeLabel = mediaType == 'tv' ? 'Serie' : 'Película';
        final memW = (120 * dpr).round();

        return RepaintBoundary(
          child: _PosterCard(
            title: title,
            posterUrl: poster,
            year: year,
            typeLabel: typeLabel,
            memCacheWidth: memW,
            focusNode: index == 0 ? firstItemFocusNode : null,
            onTap: () => onTap(item),
            onLongPress: () => onLongPress(item),
          ),
        );
      },
    );
  }
}

class _PosterCard extends StatefulWidget {
  final String title;
  final String posterUrl;
  final String year;
  final String typeLabel;
  final int memCacheWidth;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PosterCard({
    required this.title,
    required this.posterUrl,
    required this.year,
    required this.typeLabel,
    required this.memCacheWidth,
    this.focusNode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _hasFocus = false;
  Timer? _holdTimer;
  bool _longFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _holdTimer?.cancel();
    _longFired = false;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      _longFired = true;
      widget.onLongPress();
    });
  }

  void _endHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_longFired) {
      widget.onTap();
    }
    _longFired = false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) {
            _startHold();
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _endHold();
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.mediaPlay)) {
          widget.onLongPress();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _hasFocus ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: widget.posterUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: widget.memCacheWidth,
                        fadeInDuration: const Duration(milliseconds: 120),
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFF1c1c1c)),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF1c1c1c),
                          child: const Icon(Icons.movie, color: Colors.white24),
                        ),
                      ),
                      Positioned(
                        left: 4,
                        top: 4,
                        right: 4,
                        child: Row(
                          children: [
                            _Tag(text: widget.typeLabel),
                            if (widget.year.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              _Tag(text: widget.year),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _hasFocus ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}