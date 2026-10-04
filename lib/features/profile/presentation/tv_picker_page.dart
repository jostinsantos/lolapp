// ============================================================
// tv_picker_page.dart
// Infinite scroll real + escala compacta para TV.
// Soporta también móvil vertical sin afectar a TV.
// ============================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _kAccent = Color(0xFFE50914);
const _kKeyColor = Color(0xFF2A2A38);
const _kRawBase =
    'https://raw.githubusercontent.com/lolapptv/addons/main/';

enum TvPickerMode { avatar, backdrop }

class TvPickerPage extends StatefulWidget {
  final TvPickerMode mode;
  final String? initial;

  const TvPickerPage({
    super.key,
    required this.mode,
    this.initial,
  });

  @override
  State<TvPickerPage> createState() => _TvPickerPageState();
}

class _TvPickerPageState extends State<TvPickerPage> {
  late String _selected;

  bool _loading = true;
  String? _error;

  List<_PickerCategory> _categories = [];
  int _categoryIndex = 0;

  int _visibleCount = 20;
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();

  bool get isAvatar => widget.mode == TvPickerMode.avatar;

  String get _manifestUrl =>
      '$_kRawBase${isAvatar ? 'avatar_manifest.json' : 'backdrop_manifest.json'}';

  _PickerCategory? get _currentCategory =>
      (_categories.isNotEmpty && _categoryIndex < _categories.length)
          ? _categories[_categoryIndex]
          : null;

  List<String> get _currentItems =>
      _currentCategory?.items ?? const <String>[];

  List<String> get _visibleItems {
    final items = _currentItems;
    if (items.length <= _visibleCount) return items;
    return items.sublist(0, _visibleCount);
  }

  bool get _hasMore => _visibleCount < _currentItems.length;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial ?? '';
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadMore();
    });
    _loadManifest();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() => _maybeLoadMore();

  void _maybeLoadMore() {
    if (!mounted || !_hasMore) return;
    if (!_scroll.hasClients) {
      _loadMore();
      return;
    }
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) {
      _loadMore();
      return;
    }
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadManifest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final list = _parseManifest(decoded);

      if (!mounted) return;
      setState(() {
        _categories = list;
        _categoryIndex = 0;
        _visibleCount = _pageSize;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeLoadMore();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la lista ($e)';
        _loading = false;
      });
    }
  }

  List<_PickerCategory> _parseManifest(dynamic decoded) {
    final out = <_PickerCategory>[];

    if (decoded is Map && decoded['categories'] is List) {
      for (final c in decoded['categories'] as List) {
        if (c is! Map) continue;
        final name = c['name']?.toString() ?? 'Sin nombre';
        final items = <String>[];
        final rawItems = c['items'];
        if (rawItems is List) {
          for (final it in rawItems) {
            final s = it.toString().trim();
            if (s.isNotEmpty) items.add(_normalizeUrl(s));
          }
        }
        if (items.isNotEmpty) {
          out.add(_PickerCategory(name: name, items: items));
        }
      }
    } else if (decoded is List) {
      final items = <String>[];
      for (final it in decoded) {
        final s = it.toString().trim();
        if (s.isNotEmpty) items.add(_normalizeUrl(s));
      }
      if (items.isNotEmpty) {
        out.add(_PickerCategory(name: 'Todas', items: items));
      }
    }

    return out;
  }

  String _normalizeUrl(String url) {
    if (url.startsWith('http')) return url;
    return '$_kRawBase${url.startsWith('/') ? url.substring(1) : url}';
  }

  Future<void> _openUrlDialog() async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _UrlInputDialog(
        title: isAvatar ? 'URL del avatar' : 'URL del fondo',
        initialText: _selected.startsWith('http') &&
                !_allItems.contains(_selected)
            ? _selected
            : '',
      ),
    );
    if (res != null && res.trim().isNotEmpty) {
      setState(() => _selected = res.trim());
    }
  }

  List<String> get _allItems {
    final out = <String>[];
    for (final c in _categories) {
      out.addAll(c.items);
    }
    return out;
  }

  void _confirm() => Navigator.pop(context, _selected);

  void _selectCategory(int i) {
    if (i < 0 || i >= _categories.length) return;
    setState(() {
      _categoryIndex = i;
      _visibleCount = _pageSize;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _loadMore() {
    if (!_hasMore) return;
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(
        0,
        _currentItems.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (_hasMore &&
          (pos.maxScrollExtent <= 0 ||
              pos.pixels >= pos.maxScrollExtent - 400)) {
        _loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vertical =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    // En horizontal (TV) dejamos EXACTAMENTE lo de antes.
    final hPad = vertical ? 16.0 : 24.0;
    final vPad = 12.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Cabecera ─────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isAvatar ? 'Elegir avatar' : 'Elegir fondo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: vertical ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _HeaderAction(
                    label: 'URL manual',
                    icon: Icons.link,
                    small: true,
                    iconOnly: vertical,
                    onTap: _openUrlDialog,
                  ),
                  const SizedBox(width: 10),
                  _HeaderAction(
                    label: 'Guardar',
                    icon: Icons.check,
                    primary: true,
                    small: true,
                    iconOnly: vertical,
                    onTap: _selected.isNotEmpty ? _confirm : null,
                  ),
                ],
              ),

              // ─── Chips de categorías ───────────────────────────
              if (!_loading && _error == null && _categories.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final cat = _categories[i];
                      final active = i == _categoryIndex;
                      return _CategoryChip(
                        label: cat.name,
                        count: cat.items.length,
                        active: active,
                        onTap: () => _selectCategory(i),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 10),
              Expanded(child: _buildBody(vertical)),
              const SizedBox(height: 8),

              // ─── Preview inferior ─────────────────────────────
              Row(
                children: [
                  Container(
                    width: isAvatar ? 40 : (vertical ? 60 : 72),
                    height: 40,
                    decoration: BoxDecoration(
                      shape:
                          isAvatar ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius:
                          isAvatar ? null : BorderRadius.circular(6),
                      color: Colors.white12,
                      border: Border.all(color: Colors.white24, width: 1.2),
                      image: _selected.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(_selected),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _selected.isEmpty
                        ? Icon(
                            isAvatar ? Icons.person : Icons.image,
                            color: Colors.white54,
                            size: 18,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? 'Sin selección'
                          : _allItems.contains(_selected)
                              ? 'Predefinido'
                              : _selected,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (_hasMore)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool vertical) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _HeaderAction(
              label: 'Reintentar',
              icon: Icons.refresh,
              primary: true,
              onTap: _loadManifest,
            ),
          ],
        ),
      );
    }
    if (_currentItems.isEmpty) {
      return const Center(
        child: Text(
          'No hay opciones disponibles',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final crossCount = isAvatar
        ? (vertical ? 4 : 8)
        : (vertical ? 2 : 4);

    return GridView.builder(
      controller: _scroll,
      itemCount: _visibleItems.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: isAvatar ? 1 : 16 / 9,
      ),
      itemBuilder: (_, i) {
        final url = _visibleItems[i];
        final selected = _selected == url;
        return _PickerTile(
          url: url,
          selected: selected,
          circular: isAvatar,
          onTap: () => setState(() => _selected = url),
        );
      },
    );
  }
}

class _PickerCategory {
  final String name;
  final List<String> items;
  const _PickerCategory({required this.name, required this.items});
}

class _CategoryChip extends StatefulWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? _kAccent
        : (_focused ? Colors.white.withOpacity(0.14) : Colors.white10);
    final fg = widget.active
        ? Colors.white
        : (_focused ? Colors.white : Colors.white70);

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 10,
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

class _PickerTile extends StatefulWidget {
  final String url;
  final bool selected;
  final bool circular;
  final VoidCallback onTap;

  const _PickerTile({
    required this.url,
    required this.selected,
    required this.circular,
    required this.onTap,
  });

  @override
  State<_PickerTile> createState() => _PickerTileState();
}

class _PickerTileState extends State<_PickerTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius:
                widget.circular ? null : BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : (widget.selected ? _kAccent : Colors.white24),
              width: _focused || widget.selected ? 2.5 : 1.2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
            image: DecorationImage(
              image: NetworkImage(widget.url),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool small;
  final bool iconOnly;

  const _HeaderAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.small = false,
    this.iconOnly = false,
  });

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final bg = disabled
        ? Colors.white10
        : (_focused
            ? Colors.white
            : (widget.primary ? _kAccent : Colors.white.withOpacity(0.08)));
    final fg = disabled
        ? Colors.white38
        : (_focused ? Colors.black : Colors.white);

    final hPad = widget.iconOnly ? 8.0 : (widget.small ? 10.0 : 14.0);
    final vPad = widget.small ? 7.0 : 9.0;
    final iconSize = widget.small ? 16.0 : 18.0;
    final fontSize = widget.small ? 11.5 : 13.0;

    return Focus(
      canRequestFocus: !disabled,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 1.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: iconSize, color: fg),
              if (!widget.iconOnly) ...[
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Modal de URL con teclado propio.
// En horizontal (TV) mantiene ancho 620.
// En vertical se ajusta al ancho de pantalla.
// ============================================================
class _UrlInputDialog extends StatefulWidget {
  final String title;
  final String initialText;

  const _UrlInputDialog({
    required this.title,
    this.initialText = '',
  });

  @override
  State<_UrlInputDialog> createState() => _UrlInputDialogState();
}

class _UrlInputDialogState extends State<_UrlInputDialog> {
  late String _text;

  static const _rowsNormal = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
    ['o', 'p', 'q', 'r', 's', 't', 'u'],
    ['v', 'w', 'x', 'y', 'z', 'ñ', '.'],
  ];

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
  }

  void _append(String c) {
    if (_text.length >= 300) return;
    setState(() => _text += c);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _clear() => setState(() => _text = '');

  void _submit() => Navigator.pop(context, _text);

  @override
  Widget build(BuildContext context) {
    final vertical =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: vertical ? 16 : 60,
        vertical: 40,
      ),
      child: Container(
        width: vertical ? double.infinity : 620,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1.2),
              ),
              child: Text(
                _text.isEmpty ? 'https://...' : _text,
                style: TextStyle(
                  color: _text.isEmpty ? Colors.white38 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in _rowsNormal)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in row)
                          _UrlKey(label: c, onTap: () => _append(c)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _UrlKey(label: '/', onTap: () => _append('/')),
                    _UrlKey(label: ':', onTap: () => _append(':')),
                    _UrlKey(label: '.', onTap: () => _append('.')),
                    _UrlKey(label: '-', onTap: () => _append('-')),
                    _UrlKey(label: '_', onTap: () => _append('_')),
                    _UrlKey(label: '?', onTap: () => _append('?')),
                    _UrlKey(label: '=', onTap: () => _append('=')),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _UrlKey(
                      label: ' ',
                      icon: Icons.space_bar,
                      flex: 3,
                      onTap: () => _append(' '),
                    ),
                    _UrlKey(label: '@', onTap: () => _append('@')),
                    _UrlKey(
                      label: '⌫',
                      icon: Icons.backspace_outlined,
                      flex: 2,
                      onTap: _backspace,
                    ),
                    _UrlKey(
                      label: 'Limpiar',
                      text: true,
                      flex: 2,
                      onTap: _clear,
                    ),
                    _UrlKey(
                      label: 'OK',
                      primary: true,
                      flex: 2,
                      onTap: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UrlKey extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool primary;
  final bool text;

  const _UrlKey({
    required this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.primary = false,
    this.text = false,
  });

  @override
  State<_UrlKey> createState() => _UrlKeyState();
}

class _UrlKeyState extends State<_UrlKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? Colors.white
        : (widget.primary ? _kAccent : _kKeyColor);
    final fg = _focused ? Colors.black : Colors.white;

    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: widget.icon != null
                  ? Icon(widget.icon, size: 16, color: fg)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: widget.text ? 12 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}