import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/sources.dart';
import '../../../../data/datasources/remote/sources/custom_api.dart';
import '../tv_config_shared.dart';
class FuentesTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;
  final FocusNode? firstFocusNode;

  const FuentesTab({
    super.key,
    required this.onRequestTabFocus,
    this.firstFocusNode,
  });

  @override
  State<FuentesTab> createState() => FuentesTabState();
}

class FuentesTabState extends State<FuentesTab>
    with AutomaticKeepAliveClientMixin {
  String _seleccionarServidores = 'auto';
  String _idiomaAudio = 'latino';
  String _subtituloPred = 'spa';
  bool _reutilizarUltimoEnlace = false;
  int _ttlHours = 12;

  final Map<String, bool> _sourceEnabled = {};
  final Map<String, bool> _sourceLoading = {};
  final Map<String, FocusNode> _sourceFocusNodes = {};

  bool _customEnabled = false;
  List<String> _customSources = [];
  bool _customLoading = true;
  bool _dialogOpen = false;

  late final FocusNode _btnModoAuto;
  late final FocusNode _btnModoManual;
  late final FocusNode _btnAudioLat;
  late final FocusNode _btnAudioCas;
  late final FocusNode _btnAudioSub;
  late final FocusNode _btnSubSpa;
  late final FocusNode _btnSubEng;
  late final FocusNode _btnReutilizar;
  late final List<FocusNode> _ttlNodes;
  late final FocusNode _btnMisFuentesToggle;
  late final FocusNode _btnAgregarFuente;
  late final FocusNode _inputFocus;
  late final FocusNode _btnAceptar;
  late final FocusNode _btnCancelar;
  final Map<String, FocusNode> _customItemFocus = {};

  final TextEditingController _codigoCtrl = TextEditingController();

  static const _ttlOptions = [1, 6, 12, 24, 48];
  static const _purple = Color(0xFF9C27B0);

  FocusNode get firstFocusNode => _btnModoAuto;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    for (final s in kRegisteredSources) {
      if (s.id == 'customapi') continue;
      _sourceFocusNodes[s.id] = FocusNode(debugLabel: 'cfg_${s.id}');
      _sourceEnabled[s.id] = true;
      _sourceLoading[s.id] = true;
    }

    _btnModoAuto = FocusNode(debugLabel: 'cfg_modo_auto');
    _btnModoManual = FocusNode(debugLabel: 'cfg_modo_manual');
    _btnAudioLat = FocusNode(debugLabel: 'cfg_audio_lat');
    _btnAudioCas = FocusNode(debugLabel: 'cfg_audio_cas');
    _btnAudioSub = FocusNode(debugLabel: 'cfg_audio_sub');
    _btnSubSpa = FocusNode(debugLabel: 'cfg_sub_spa');
    _btnSubEng = FocusNode(debugLabel: 'cfg_sub_eng');
    _btnReutilizar = FocusNode(debugLabel: 'cfg_reutilizar');
    _ttlNodes = List.generate(
      _ttlOptions.length,
      (i) => FocusNode(debugLabel: 'cfg_ttl_${_ttlOptions[i]}'),
    );
    _btnMisFuentesToggle = FocusNode(debugLabel: 'cfg_mis_fuentes_toggle');
    _btnAgregarFuente = FocusNode(debugLabel: 'cfg_agregar_fuente');
    _inputFocus = FocusNode(debugLabel: 'cfg_input_api');
    _btnAceptar = FocusNode(debugLabel: 'cfg_aceptar');
    _btnCancelar = FocusNode(debugLabel: 'cfg_cancelar');

    _loadSettings();
    _loadCustomApis();
  }

  @override
  void dispose() {
    for (final n in _sourceFocusNodes.values) {
      n.dispose();
    }
    for (final n in _customItemFocus.values) {
      n.dispose();
    }
    _btnModoAuto.dispose();
    _btnModoManual.dispose();
    _btnAudioLat.dispose();
    _btnAudioCas.dispose();
    _btnAudioSub.dispose();
    _btnSubSpa.dispose();
    _btnSubEng.dispose();
    _btnReutilizar.dispose();
    for (final n in _ttlNodes) {
      n.dispose();
    }
    _btnMisFuentesToggle.dispose();
    _btnAgregarFuente.dispose();
    _inputFocus.dispose();
    _btnAceptar.dispose();
    _btnCancelar.dispose();
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await prefs.setBool('verificar_servidores', true);
    await prefs.setBool('un_servidor_por_idioma', false);
    await prefs.setBool('mostrar_servidores_player', true);

    setState(() {
      _seleccionarServidores =
          prefs.getString('seleccionar_servidores') ?? 'auto';
      _idiomaAudio = prefs.getString('idioma_audio_predeterminado') ?? 'latino';

      final subRaw = prefs.getString('subtitulo_predeterminado') ?? 'spa';
      if (subRaw == 'es' ||
          subRaw == 'es_MX' ||
          subRaw == 'es_ES' ||
          subRaw == 'spa') {
        _subtituloPred = 'spa';
      } else {
        _subtituloPred = 'eng';
      }

      _reutilizarUltimoEnlace =
          prefs.getBool('reutilizar_ultimo_enlace') ?? false;
      _ttlHours = prefs.getInt('servidores_cache_ttl_hours') ?? 12;

      for (final s in kRegisteredSources) {
        if (s.id == 'customapi') continue;
        final v = prefs.getBool(s.prefsKey);
        _sourceEnabled[s.id] = v ?? true;
        _sourceLoading[s.id] = false;
        if (v == null) {
          prefs.setBool(s.prefsKey, true);
        }
      }
    });
  }

  Future<void> _loadCustomApis() async {
    try {
      final cfg = await CustomApiConfig.load();
      final en = await CustomApiConfig.isEnabled();
      if (!mounted) return;

      for (final url in cfg.sources) {
        _customItemFocus.putIfAbsent(
          url,
          () => FocusNode(debugLabel: 'cfg_custom_$url'),
        );
      }

      setState(() {
        _customSources = List.from(cfg.sources);
        _customEnabled = en;
        _customLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando Mis Fuentes: $e');
      if (mounted) setState(() => _customLoading = false);
    }
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _setModo(String value) async {
    await _saveString('seleccionar_servidores', value);
    if (!mounted) return;
    setState(() => _seleccionarServidores = value);
  }

  Future<void> _setIdiomaAudio(String value) async {
    await _saveString('idioma_audio_predeterminado', value);
    if (!mounted) return;
    setState(() => _idiomaAudio = value);
  }

  Future<void> _setSubtitulo(String value) async {
    await _saveString('subtitulo_predeterminado', value);
    if (!mounted) return;
    setState(() => _subtituloPred = value);
  }

  Future<void> _setReutilizar(bool value) async {
    await _saveBool('reutilizar_ultimo_enlace', value);
    if (!mounted) return;
    setState(() => _reutilizarUltimoEnlace = value);
  }

  Future<void> _setTtl(int hours) async {
    await _saveInt('servidores_cache_ttl_hours', hours);
    if (!mounted) return;
    setState(() => _ttlHours = hours);
  }

  Future<void> _setSourceEnabled(SourceDefinition source, bool value) async {
    await _saveBool(source.prefsKey, value);
    if (!mounted) return;
    setState(() => _sourceEnabled[source.id] = value);
  }

  Future<void> _toggleCustom(bool v) async {
    await CustomApiConfig.setEnabled(v);
    if (!mounted) return;
    setState(() => _customEnabled = v);
  }

  // ── Modal encima de TODO (tabs incluidos) ─────────────────────────────

  void _openInputOverlay() {
    if (_dialogOpen) return;
    _dialogOpen = true;
    _codigoCtrl.clear();

    showGeneralDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'Agregar fuente',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Material(
                color: Colors.transparent,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.escape ||
                        event.logicalKey == LogicalKeyboardKey.goBack ||
                        event.logicalKey == LogicalKeyboardKey.browserBack) {
                      if (_inputFocus.hasFocus) {
                        _inputFocus.unfocus();
                        SystemChannels.textInput
                            .invokeMethod('TextInput.hide');
                        _btnCancelar.requestFocus();
                        return KeyEventResult.handled;
                      }
                      _closeInputOverlay();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _purple.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Agregar fuente',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Código (ej. 44029) o URL completa',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _codigoCtrl,
                          focusNode: _inputFocus,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          cursorColor: _purple,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.url,
                          onSubmitted: (_) {
                            _inputFocus.unfocus();
                            SystemChannels.textInput
                                .invokeMethod('TextInput.hide');
                            _btnAceptar.requestFocus();
                          },
                          decoration: InputDecoration(
                            hintText: 'Código o URL completa',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _purple,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Focus(
                                focusNode: _btnCancelar,
                                onKeyEvent: (n, e) {
                                  if (e is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final key = e.logicalKey;
                                  if (key == LogicalKeyboardKey.select ||
                                      key == LogicalKeyboardKey.enter) {
                                    _closeInputOverlay();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowRight) {
                                    _btnAceptar.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowUp) {
                                    _inputFocus.requestFocus();
                                    SystemChannels.textInput
                                        .invokeMethod('TextInput.show');
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.escape ||
                                      key == LogicalKeyboardKey.goBack ||
                                      key ==
                                          LogicalKeyboardKey.browserBack) {
                                    _closeInputOverlay();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Builder(
                                  builder: (context) {
                                    final focused =
                                        Focus.of(context).hasFocus;
                                    return GestureDetector(
                                      onTap: _closeInputOverlay,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        height: 48,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: focused
                                                ? Colors.white70
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Text(
                                          'Cancelar',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Focus(
                                focusNode: _btnAceptar,
                                onKeyEvent: (n, e) {
                                  if (e is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final key = e.logicalKey;
                                  if (key == LogicalKeyboardKey.select ||
                                      key == LogicalKeyboardKey.enter) {
                                    _acceptCustom();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowLeft) {
                                    _btnCancelar.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowUp) {
                                    _inputFocus.requestFocus();
                                    SystemChannels.textInput
                                        .invokeMethod('TextInput.show');
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.escape ||
                                      key == LogicalKeyboardKey.goBack ||
                                      key ==
                                          LogicalKeyboardKey.browserBack) {
                                    _closeInputOverlay();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Builder(
                                  builder: (context) {
                                    final focused =
                                        Focus.of(context).hasFocus;
                                    return GestureDetector(
                                      onTap: _acceptCustom,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        height: 48,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _purple,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: focused
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Text(
                                          'Aceptar',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.06),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    ).then((_) {
      _dialogOpen = false;
      _codigoCtrl.clear();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _btnAgregarFuente.requestFocus();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _closeInputOverlay() {
    _inputFocus.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _codigoCtrl.clear();
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
    _dialogOpen = false;
  }

  Future<void> _acceptCustom() async {
    final input = _codigoCtrl.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un código o una URL'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String? err;
    if (input.startsWith('http')) {
      err = await CustomApiConfig.addSource(fullUrl: input);
    } else {
      err = await CustomApiConfig.addSource(codigo: input);
    }

    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    _closeInputOverlay();
    await _loadCustomApis();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fuente añadida'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeCustom(String url) async {
    await CustomApiConfig.removeSource(url);
    _customItemFocus[url]?.dispose();
    _customItemFocus.remove(url);
    await _loadCustomApis();
  }

  String _labelOf(String url) {
    final codigo = CustomApiConfig.extractCodigo(url);
    if (codigo.isNotEmpty) return codigo;
    if (url.contains('modlyo.com')) return 'Modlyo';
    return 'API';
  }

  void requestFirstFocus() {
    _btnModoAuto.requestFocus();
  }

  List<SourceDefinition> get _normalSources =>
      kRegisteredSources.where((s) => s.id != 'customapi').toList();

  void _ensureFocusedVisible(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = context;
      if (!ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  FocusNode? _firstSourceNode() {
    final list = _normalSources;
    if (list.isEmpty) return null;
    return _sourceFocusNodes[list.first.id];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sources = _normalSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('REPRODUCCIÓN', first: true),
        _choiceRow(
          children: [
            _chip(
              focusNode: _btnModoAuto,
              selected: _seleccionarServidores == 'auto',
              label: 'Automático',
              icon: Icons.bolt_rounded,
              onTap: () => _setModo('auto'),
              onUp: widget.onRequestTabFocus,
              onDown: () => _btnAudioLat.requestFocus(),
              onLeft: widget.onRequestTabFocus,
              onRight: () => _btnModoManual.requestFocus(),
            ),
            const SizedBox(width: 12),
            _chip(
              focusNode: _btnModoManual,
              selected: _seleccionarServidores == 'manual',
              label: 'Manual',
              icon: Icons.list_alt_rounded,
              onTap: () => _setModo('manual'),
              onUp: widget.onRequestTabFocus,
              onDown: () => _btnAudioCas.requestFocus(),
              onLeft: () => _btnModoAuto.requestFocus(),
              onRight: null,
            ),
          ],
          hint: _seleccionarServidores == 'auto'
              ? 'Resuelve el m3u8 y abre el player directo'
              : 'Muestra la lista de servidores para elegir',
        ),

        const SizedBox(height: 18),
        sectionTitle('IDIOMA DE AUDIO'),
        _choiceRow(
          children: [
            _chip(
              focusNode: _btnAudioLat,
              selected: _idiomaAudio == 'latino',
              label: 'Latino',
              onTap: () => _setIdiomaAudio('latino'),
              onUp: () => _btnModoAuto.requestFocus(),
              onDown: () => _btnSubSpa.requestFocus(),
              onLeft: widget.onRequestTabFocus,
              onRight: () => _btnAudioCas.requestFocus(),
            ),
            const SizedBox(width: 12),
            _chip(
              focusNode: _btnAudioCas,
              selected: _idiomaAudio == 'castellano',
              label: 'Castellano',
              onTap: () => _setIdiomaAudio('castellano'),
              onUp: () => _btnModoAuto.requestFocus(),
              onDown: () => _btnSubSpa.requestFocus(),
              onLeft: () => _btnAudioLat.requestFocus(),
              onRight: () => _btnAudioSub.requestFocus(),
            ),
            const SizedBox(width: 12),
            _chip(
              focusNode: _btnAudioSub,
              selected: _idiomaAudio == 'subtitulado',
              label: 'Subtitulado',
              onTap: () => _setIdiomaAudio('subtitulado'),
              onUp: () => _btnModoManual.requestFocus(),
              onDown: () => _btnSubEng.requestFocus(),
              onLeft: () => _btnAudioCas.requestFocus(),
              onRight: null,
            ),
          ],
          hint: 'Prioridad al resolver el primer servidor válido',
        ),

        const SizedBox(height: 18),
        sectionTitle('SUBTÍTULO'),
        _choiceRow(
          children: [
            _chip(
              focusNode: _btnSubSpa,
              selected: _subtituloPred == 'spa',
              label: 'SPA',
              onTap: () => _setSubtitulo('spa'),
              onUp: () => _btnAudioLat.requestFocus(),
              onDown: () => _btnReutilizar.requestFocus(),
              onLeft: widget.onRequestTabFocus,
              onRight: () => _btnSubEng.requestFocus(),
            ),
            const SizedBox(width: 12),
            _chip(
              focusNode: _btnSubEng,
              selected: _subtituloPred == 'eng',
              label: 'ENG',
              onTap: () => _setSubtitulo('eng'),
              onUp: () => _btnAudioSub.requestFocus(),
              onDown: () => _btnReutilizar.requestFocus(),
              onLeft: () => _btnSubSpa.requestFocus(),
              onRight: null,
            ),
          ],
          hint: 'Idioma preferido al cargar subtítulos',
        ),

        const SizedBox(height: 18),
        sectionTitle('OPCIONES'),
        _FocusScrollWrapper(
          focusNode: _btnReutilizar,
          child: SourceToggleCard(
            title: 'Reutilizar último enlace',
            subtitleEnabled: 'Usa el último m3u8 exitoso si sigue válido',
            subtitleDisabled: 'Siempre busca de nuevo',
            enabled: _reutilizarUltimoEnlace,
            loading: false,
            icon: Icons.history_rounded,
            accentColor: const Color(0xFFEC4899),
            focusNode: _btnReutilizar,
            onTap: () => _setReutilizar(!_reutilizarUltimoEnlace),
            onArrowUp: () => _btnSubSpa.requestFocus(),
            onArrowDown: () => _ttlNodes.first.requestFocus(),
            onArrowLeft: widget.onRequestTabFocus,
          ),
        ),

        const SizedBox(height: 18),
        sectionTitle('TTL DE CACHÉ'),
        _choiceRow(
          children: List.generate(_ttlOptions.length, (i) {
            final h = _ttlOptions[i];
            final label = h < 24 ? '${h}h' : '${h ~/ 24}d';
            return Padding(
              padding: EdgeInsets.only(
                right: i < _ttlOptions.length - 1 ? 10 : 0,
              ),
              child: _chip(
                focusNode: _ttlNodes[i],
                selected: _ttlHours == h,
                label: label,
                onTap: () => _setTtl(h),
                onUp: () => _btnReutilizar.requestFocus(),
                onDown: () => _btnMisFuentesToggle.requestFocus(),
                onLeft: i > 0
                    ? () => _ttlNodes[i - 1].requestFocus()
                    : widget.onRequestTabFocus,
                onRight: i < _ttlOptions.length - 1
                    ? () => _ttlNodes[i + 1].requestFocus()
                    : null,
              ),
            );
          }),
          hint: 'Tras este tiempo se vuelven a buscar servidores',
        ),

        // ── MIS FUENTES ─────────────────────────────────────────────────
        const SizedBox(height: 18),
        sectionTitle('MIS FUENTES'),
        if (_customLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else ...[
          _FocusScrollWrapper(
            focusNode: _btnMisFuentesToggle,
            child: SourceToggleCard(
              title: 'Mis Fuentes',
              subtitleEnabled: 'Activa – puedes agregar fuentes',
              subtitleDisabled: 'Desactivada',
              enabled: _customEnabled,
              loading: false,
              icon: Icons.cloud_rounded,
              accentColor: _purple,
              focusNode: _btnMisFuentesToggle,
              onTap: () => _toggleCustom(!_customEnabled),
              onArrowUp: () => _ttlNodes.first.requestFocus(),
              onArrowDown: () {
                if (_customEnabled) {
                  _btnAgregarFuente.requestFocus();
                } else {
                  _firstSourceNode()?.requestFocus();
                }
              },
              onArrowLeft: widget.onRequestTabFocus,
            ),
          ),
          if (_customEnabled) ...[
            const SizedBox(height: 12),
            Focus(
              focusNode: _btnAgregarFuente,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter) {
                  _openInputOverlay();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  _btnMisFuentesToggle.requestFocus();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  if (_customSources.isNotEmpty) {
                    _customItemFocus[_customSources.first]?.requestFocus();
                  } else {
                    _firstSourceNode()?.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  widget.onRequestTabFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  if (focused) _ensureFocusedVisible(context);
                  return GestureDetector(
                    onTap: () {
                      _btnAgregarFuente.requestFocus();
                      _openInputOverlay();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _purple,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: focused ? Colors.white : Colors.transparent,
                          width: 2.2,
                        ),
                      ),
                      child: const Text(
                        'Agregar fuente',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ...List.generate(_customSources.length, (i) {
              final url = _customSources[i];
              final node = _customItemFocus[url]!;
              final isLast = i == _customSources.length - 1;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _FocusScrollWrapper(
                  focusNode: node,
                  child: Focus(
                    focusNode: node,
                    onKeyEvent: (n, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter) {
                        _removeCustom(url);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowUp) {
                        if (i == 0) {
                          _btnAgregarFuente.requestFocus();
                        } else {
                          _customItemFocus[_customSources[i - 1]]
                              ?.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        if (!isLast) {
                          _customItemFocus[_customSources[i + 1]]
                              ?.requestFocus();
                        } else {
                          _firstSourceNode()?.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        widget.onRequestTabFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: focused
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.08),
                              width: focused ? 2.2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cloud_rounded,
                                color: Color(0xFF4CAF50),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _labelOf(url),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeCustom(url),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ],
        ],

        // ── FUENTES (siempre visibles) ──────────────────────────────────
        const SizedBox(height: 18),
        sectionTitle('FUENTES DISPONIBLES'),
        Text(
          _seleccionarServidores == 'auto'
              ? 'Modo automático: se usan las fuentes activas.'
              : 'Activa o desactiva cada fuente.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(sources.length, (i) {
          final source = sources[i];
          final isFirst = i == 0;
          final isLast = i == sources.length - 1;
          final node = _sourceFocusNodes[source.id]!;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: _FocusScrollWrapper(
              focusNode: node,
              child: SourceToggleCard(
                title: source.label,
                subtitleEnabled: '${source.label} activado',
                subtitleDisabled: '${source.label} desactivado',
                enabled: _sourceEnabled[source.id] ?? true,
                loading: _sourceLoading[source.id] ?? false,
                icon: source.icon,
                accentColor: source.badgeColor,
                focusNode: node,
                onTap: () => _setSourceEnabled(
                  source,
                  !(_sourceEnabled[source.id] ?? true),
                ),
                onArrowUp: () {
                  if (isFirst) {
                    if (_customEnabled && _customSources.isNotEmpty) {
                      _customItemFocus[_customSources.last]?.requestFocus();
                    } else if (_customEnabled) {
                      _btnAgregarFuente.requestFocus();
                    } else {
                      _btnMisFuentesToggle.requestFocus();
                    }
                  } else {
                    _sourceFocusNodes[sources[i - 1].id]?.requestFocus();
                  }
                },
                onArrowDown: () {
                  if (!isLast) {
                    _sourceFocusNodes[sources[i + 1].id]?.requestFocus();
                  }
                },
                onArrowLeft: widget.onRequestTabFocus,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _choiceRow({
    required List<Widget> children,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: children),
        const SizedBox(height: 8),
        Text(
          hint,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required FocusNode focusNode,
    required bool selected,
    required String label,
    required VoidCallback onTap,
    required VoidCallback? onUp,
    required VoidCallback? onDown,
    required VoidCallback? onLeft,
    required VoidCallback? onRight,
    IconData? icon,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown();
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
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          if (hasFocus) _ensureFocusedVisible(context);
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? kConfigAccent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (selected
                          ? kConfigAccent
                          : Colors.white.withValues(alpha: 0.08)),
                  width: hasFocus ? 2.2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: selected || hasFocus
                          ? Colors.white
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FocusScrollWrapper extends StatefulWidget {
  final FocusNode focusNode;
  final Widget child;

  const _FocusScrollWrapper({
    required this.focusNode,
    required this.child,
  });

  @override
  State<_FocusScrollWrapper> createState() => _FocusScrollWrapperState();
}

class _FocusScrollWrapperState extends State<_FocusScrollWrapper> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _FocusScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focusNode.hasFocus || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}