// lib/servicios/buscarfuentes.dart  (o lib/tv/descrubir/buscarfuentes.dart)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/scrapers/base/scraper_context.dart';
import '../../../data/scrapers/base/registry.dart';
import '../../../data/scrapers/base/buscador.dart';
import '../domain/derivar.dart'; // DerivarTvPage

// Opcional: si tienes MenuPositionPref en TV
// import '../../settings/presentation/tv_settings.dart';

const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kKeyColor = Color(0xFF2A2A38);
const kCardBg = Color(0xFF1a1a2e);

class BuscarFuentesPage extends StatefulWidget {
  final void Function(BuscarFuentesPageState)? onPageCreated;

  const BuscarFuentesPage({super.key, this.onPageCreated});

  @override
  State<BuscarFuentesPage> createState() => BuscarFuentesPageState();
}

class BuscarFuentesPageState extends State<BuscarFuentesPage> {
  String _query = '';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<BuscadorItem> _items = [];

  /// 'todas' | id de fuente (misma lógica que móvil)
  String _searchTipo = 'todas';

  Timer? _debounce;
  int _searchId = 0;

  bool _showAccents = false;

  /// true mientras el campo de texto está habilitado para recibir el
  /// teclado del sistema (Android TV).
  bool _sysKeyboard = false;

  final FocusNode _aKeyFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode(skipTraversal: true);
  final FocusNode _filterFocusNode = FocusNode();
  final FocusNode _firstResultFocus = FocusNode(debugLabel: 'firstResult');
  final TextEditingController _inputController = TextEditingController();

  String _menuPosition = 'top';

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onInputFocusChanged);
    // _loadMenuPosition(); // descomenta si usas MenuPositionPref
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPageCreated?.call(this);
      _aKeyFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _aKeyFocusNode.dispose();
    _inputFocusNode.dispose();
    _filterFocusNode.dispose();
    _firstResultFocus.dispose();
    _inputController.dispose();
    super.dispose();
  }

  FocusNode getAKeyFocusNode() => _aKeyFocusNode;

  String get _searchTipoLabel {
    if (_searchTipo == 'todas') return 'Todas las fuentes';
    final f = fuenteById(_searchTipo);
    return f?.label ?? _searchTipo;
  }

  String get _searchTipoChipLabel {
    if (_searchTipo == 'todas') return 'Todas';
    final f = fuenteById(_searchTipo);
    return f?.label ?? _searchTipo;
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

  void _onKeyTap(String char) => _setQuery(_query + char);

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

  void _toggleAccents() => setState(() => _showAccents = !_showAccents);

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

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _doSearch();
    });
  }

  /// Misma lógica que móvil: buscarEnFuentes(q, tipo)
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
      final res = await buscarEnFuentes(q: q, tipo: _searchTipo);

      if (currentId != _searchId || !mounted) return;

      if (!res.ok) {
        setState(() {
          _error = res.error ?? 'Error en la búsqueda';
          _items = [];
          _loading = false;
        });
        return;
      }

      final flat = <BuscadorItem>[];
      res.resultados.forEach((_, list) => flat.addAll(list));

      setState(() {
        _items = flat;
        _loading = false;
      });
    } catch (_) {
      if (currentId != _searchId || !mounted) return;
      setState(() {
        _error = 'Sin conexión o error de red';
        _items = [];
        _loading = false;
      });
    }
  }

  void _changeSearchTipo(String tipo) {
    if (tipo == _searchTipo) return;
    setState(() => _searchTipo = tipo);
    if (_query.trim().length >= 2) _doSearch();
  }

  void _showFilterDialog() {
    final options = <({String id, String label})>[
      (id: 'todas', label: 'Todas las fuentes'),
      ...fuentesConBusqueda.map((f) => (id: f.id, label: f.label)),
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: kCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buscar en',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final opt = options[i];
                          final selected = _searchTipo == opt.id;
                          return _FilterOptionTile(
                            label: opt.label,
                            selected: selected,
                            autofocus: selected || (i == 0 && !selected),
                            onTap: () {
                              Navigator.pop(ctx);
                              _changeSearchTipo(opt.id);
                            },
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
      },
    );
  }

  void _openDerivar(BuscadorItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DerivarTvPage(
          servicio: item.sitio,
          url: item.url,
          titulo: item.titulo,
          tipo: item.tipo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSide = _menuPosition == 'side';

    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Padding(
          // Antes: top: isSide ? 12 : 70  → demasiado margen
          padding: EdgeInsets.only(top: isSide ? 8 : 12, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Teclado + filtro debajo ──
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
                        // Botón + teclado + filtro con scroll (pantallas pequeñas)
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SystemKeyboardButton(
                                  onTap: _openSystemKeyboard,
                                ),
                                const SizedBox(height: 8),
                                _Keyboard(
                                  showAccents: _showAccents,
                                  onKey: _onKeyTap,
                                  onBackspace: _onBackspace,
                                  onClear: _onClear,
                                  onToggleAccents: _toggleAccents,
                                  aKeyFocusNode: _aKeyFocusNode,
                                ),
                                const SizedBox(height: 14),
                                // Filtro de fuentes DEBAJO del teclado
                                Text(
                                  'Fuente',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _FuenteFilterButton(
                                  focusNode: _filterFocusNode,
                                  label: _searchTipoChipLabel,
                                  onTap: _showFilterDialog,
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
              // ── Resultados ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
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
            'Escribe para buscar en las fuentes\nen tiempo real.',
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
          '${_items.length} resultado${_items.length == 1 ? '' : 's'} · $_searchTipoLabel',
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
            onTap: _openDerivar,
          ),
        ),
      ],
    );
  }
}

// ── Input ──────────────────────────────────────────────────────────────────

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

// ── Botón: abrir teclado del sistema (Android TV) ──────────────────────────

class _SystemKeyboardButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SystemKeyboardButton({required this.onTap});

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

// ── Filtro fuente (debajo del teclado) ─────────────────────────────────────

class _FuenteFilterButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final VoidCallback onTap;

  const _FuenteFilterButton({
    required this.focusNode,
    required this.label,
    required this.onTap,
  });

  @override
  State<_FuenteFilterButton> createState() => _FuenteFilterButtonState();
}

class _FuenteFilterButtonState extends State<_FuenteFilterButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _hasFocus
                ? kAccentColor.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hasFocus ? kAccentColor : Colors.white24,
              width: _hasFocus ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 18,
                color: kAccentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: _hasFocus ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterOptionTile extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _FilterOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_FilterOptionTile> createState() => _FilterOptionTileState();
}

class _FilterOptionTileState extends State<_FilterOptionTile> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.selected
                ? kAccentColor.withValues(alpha: 0.22)
                : (_hasFocus
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected || _hasFocus
                  ? kAccentColor.withValues(alpha: 0.75)
                  : Colors.white.withValues(alpha: 0.08),
              width: _hasFocus || widget.selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected || _hasFocus
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 15,
                    fontWeight: widget.selected || _hasFocus
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(Icons.check_rounded, color: kAccentColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Teclado ────────────────────────────────────────────────────────────────

class _Keyboard extends StatelessWidget {
  final bool showAccents;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onToggleAccents;
  final FocusNode aKeyFocusNode;

  const _Keyboard({
    required this.showAccents,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onToggleAccents,
    required this.aKeyFocusNode,
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
                      focusNode: (!showAccents && char == 'a')
                          ? aKeyFocusNode
                          : null,
                      allowLeftEscape: leftEdge.contains(char),
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
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(label: 'ñ', onTap: () => onKey('ñ')),
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
                  ),
                  const SizedBox(width: 6),
                  _KeyButton(
                    icon: Icons.backspace_outlined,
                    onTap: onBackspace,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          Row(
            children: [
              _KeyButton(
                icon: Icons.close,
                onTap: onClear,
                allowLeftEscape: true,
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

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.focusNode,
    this.allowLeftEscape = false,
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

  const _AccentToggleKey({required this.isActive, required this.onTap});

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

// ── Grid resultados (BuscadorItem) ─────────────────────────────────────────

class _ResultsGrid extends StatelessWidget {
  final List<BuscadorItem> items;
  final FocusNode? firstItemFocusNode;
  final void Function(BuscadorItem item) onTap;

  const _ResultsGrid({
    required this.items,
    this.firstItemFocusNode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.5);

    return GridView.builder(
      itemCount: items.length,
      addAutomaticKeepAlives: false,
      cacheExtent: 280,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final memW = (120 * dpr).round();
        return RepaintBoundary(
          child: _PosterCard(
            item: item,
            memCacheWidth: memW,
            focusNode: index == 0 ? firstItemFocusNode : null,
            onTap: () => onTap(item),
          ),
        );
      },
    );
  }
}

class _PosterCard extends StatefulWidget {
  final BuscadorItem item;
  final int memCacheWidth;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _PosterCard({
    required this.item,
    required this.memCacheWidth,
    this.focusNode,
    required this.onTap,
  });

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final poster = item.imagen;
    final year = item.anio?.toString() ?? '';
    final hasRating = item.rating != null && item.rating! > 0;
    final ratingText = hasRating ? item.rating!.toStringAsFixed(1) : '';

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
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
                      if (poster.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: widget.memCacheWidth,
                          fadeInDuration: const Duration(milliseconds: 100),
                          placeholder: (_, _) =>
                              const ColoredBox(color: Color(0xFF1c1c1c)),
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: Color(0xFF1c1c1c),
                            child: Icon(Icons.movie, color: Colors.white24),
                          ),
                        )
                      else
                        const ColoredBox(
                          color: Color(0xFF1c1c1c),
                          child: Icon(Icons.movie, color: Colors.white24),
                        ),
                      Positioned(
                        left: 4,
                        top: 4,
                        right: 4,
                        child: Row(
                          children: [
                            _Tag(text: item.sitio),
                            if (year.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              _Tag(text: year),
                            ],
                          ],
                        ),
                      ),
                      if (hasRating)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 11,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  ratingText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
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
            const SizedBox(height: 4),
            Text(
              item.titulo,
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