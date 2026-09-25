import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/sources.dart';
import '../config_shared.dart';
import '../../../addons/presentation/widgets/custom_api_config_card.dart'; // ajusta la ruta si hace falta

class FuentesSection extends StatefulWidget {
  final bool verificarServidores;
  final bool unServidorPorIdioma;
  final bool mostrarServidoresEnPlayer;
  final bool idiomaPredEnabled;
  final IdiomaPred idiomaPred;
  final FuenteSeleccion seleccionFuente;
  final bool reutilizarUltimoEnlace;
  final Map<String, bool> sourceEnabled;
  final Map<String, bool> sourceLoading;
  final int fuentesActivas;
  final ValueChanged<bool> onVerificarChanged;
  final ValueChanged<bool> onUnServidorChanged;
  final ValueChanged<bool> onMostrarServidoresEnPlayerChanged;
  final ValueChanged<bool> onIdiomaPredEnabledChanged;
  final ValueChanged<IdiomaPred> onIdiomaPredChanged;
  final ValueChanged<FuenteSeleccion> onSeleccionFuenteChanged;
  final ValueChanged<bool> onReutilizarChanged;
  final Function(SourceDefinition, bool) onSourceChanged;
  final Future<bool?> Function(
    String title,
    String body, {
    String confirmLabel,
    Color accent,
  }) showConfirmDialog;

  const FuentesSection({
    super.key,
    required this.verificarServidores,
    required this.unServidorPorIdioma,
    required this.mostrarServidoresEnPlayer,
    required this.idiomaPredEnabled,
    required this.idiomaPred,
    required this.seleccionFuente,
    required this.reutilizarUltimoEnlace,
    required this.sourceEnabled,
    required this.sourceLoading,
    required this.fuentesActivas,
    required this.onVerificarChanged,
    required this.onUnServidorChanged,
    required this.onMostrarServidoresEnPlayerChanged,
    required this.onIdiomaPredEnabledChanged,
    required this.onIdiomaPredChanged,
    required this.onSeleccionFuenteChanged,
    required this.onReutilizarChanged,
    required this.onSourceChanged,
    required this.showConfirmDialog,
  });

  @override
  State<FuentesSection> createState() => _FuentesSectionState();
}

class _FuentesSectionState extends State<FuentesSection> {
  bool _reutilizarUltimoEnlace = false;
  int _ttlHours = 12;

  /// Cuántos servidores se comprueban a la vez (1–5). Más = más rápido, más calor/batería.
  int _concurrentChecks = 2;

  String _seleccionarServidores = 'auto';
  String _idiomaAudioPredeterminado = 'latino';
  String _subtituloPredeterminado = 'spa';

  final Map<String, bool> _sourceEnabled = {};
  final Map<String, bool> _sourceLoading = {};
  int _fuentesActivas = 0;
  bool _isLoading = true;

  static const String _keyReutilizarUltimoEnlace = 'reutilizar_ultimo_enlace';
  static const String _keyTtlHours = 'servidores_cache_ttl_hours';
  static const String _keySeleccionarServidores = 'seleccionar_servidores';
  static const String _keyIdiomaAudioPred = 'idioma_audio_predeterminado';
  static const String _keySubtituloPred = 'subtitulo_predeterminado';

  /// Leída por ServerLoader / player al resolver servidores en paralelo.
  static const String keyConcurrentChecks = 'servidores_concurrent_checks';
  static const int concurrentChecksMin = 1;
  static const int concurrentChecksMax = 5;
  static const int concurrentChecksDefault = 2;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  Future<void> _cargarConfiguracion() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      _reutilizarUltimoEnlace =
          prefs.getBool(_keyReutilizarUltimoEnlace) ?? false;
      _ttlHours = prefs.getInt(_keyTtlHours) ?? 12;
      _seleccionarServidores =
          prefs.getString(_keySeleccionarServidores) ?? 'auto';
      _idiomaAudioPredeterminado =
          prefs.getString(_keyIdiomaAudioPred) ?? 'latino';

      final concurrent = prefs.getInt(keyConcurrentChecks) ?? concurrentChecksDefault;
      _concurrentChecks = concurrent.clamp(concurrentChecksMin, concurrentChecksMax);

      final subRaw = prefs.getString(_keySubtituloPred) ?? 'spa';
      if (subRaw == 'es' ||
          subRaw == 'es_MX' ||
          subRaw == 'es_ES' ||
          subRaw == 'spa') {
        _subtituloPredeterminado = 'spa';
      } else {
        _subtituloPredeterminado = 'eng';
      }

      _sourceEnabled.clear();
      _sourceLoading.clear();
      for (final s in kRegisteredSources) {
        final defaultOn = s.id != 'customapi';
        _sourceEnabled[s.id] = prefs.getBool(s.prefsKey) ?? defaultOn;
        if (!prefs.containsKey(s.prefsKey)) {
          await prefs.setBool(s.prefsKey, defaultOn);
        }
        _sourceLoading[s.id] = false;
      }
      _fuentesActivas = _sourceEnabled.values.where((v) => v).length;

      // Solo sincroniza reutilizar (NO toca verificar → no sale modal)
      widget.onReutilizarChanged(_reutilizarUltimoEnlace);
    } catch (e) {
      debugPrint('Error cargando configuración de fuentes: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _guardarBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _guardarString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _guardarInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _setReutilizarUltimoEnlace(bool value) async {
    await _guardarBool(_keyReutilizarUltimoEnlace, value);
    if (mounted) {
      setState(() => _reutilizarUltimoEnlace = value);
      widget.onReutilizarChanged(value);
    }
  }

  Future<void> _setTtlHours(int hours) async {
    await _guardarInt(_keyTtlHours, hours);
    if (mounted) setState(() => _ttlHours = hours);
  }

  Future<void> _setConcurrentChecks(int value) async {
    final v = value.clamp(concurrentChecksMin, concurrentChecksMax);
    await _guardarInt(keyConcurrentChecks, v);
    if (mounted) setState(() => _concurrentChecks = v);
  }

  Future<void> _setSeleccionarServidores(String value) async {
    await _guardarString(_keySeleccionarServidores, value);
    if (mounted) setState(() => _seleccionarServidores = value);
  }

  Future<void> _setIdiomaAudioPredeterminado(String value) async {
    await _guardarString(_keyIdiomaAudioPred, value);
    if (mounted) setState(() => _idiomaAudioPredeterminado = value);
  }

  Future<void> _setSubtituloPredeterminado(String value) async {
    await _guardarString(_keySubtituloPred, value);
    if (mounted) setState(() => _subtituloPredeterminado = value);
  }

  Future<void> _setSourceEnabled(SourceDefinition source, bool value) async {
    await _guardarBool(source.prefsKey, value);
    if (!mounted) return;
    setState(() {
      _sourceEnabled[source.id] = value;
      _fuentesActivas = _sourceEnabled.values.where((v) => v).length;
    });
    widget.onSourceChanged(source, value);
  }

  Future<void> _clearCacheFuentes() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = [
      _keyReutilizarUltimoEnlace,
      _keyTtlHours,
      keyConcurrentChecks,
      _keySeleccionarServidores,
      _keyIdiomaAudioPred,
      _keySubtituloPred,
      ...kRegisteredSources.map((s) => s.prefsKey),
    ];
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    await _cargarConfiguracion();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configuración de fuentes reiniciada'),
          backgroundColor: kCardColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Column(
      children: [
        // ── REPRODUCCIÓN ────────────────────────────────────────────────
        _sectionHeader('REPRODUCCIÓN'),
        _buildModeCard(),
        _buildIdiomaAudioCard(),
        _buildSubtituloCard(),
        _buildSimpleToggle(
          title: 'Reutilizar último enlace',
          subtitle: _reutilizarUltimoEnlace
              ? 'Usa el último m3u8 exitoso si sigue válido'
              : 'Siempre busca de nuevo',
          value: _reutilizarUltimoEnlace,
          onChanged: _setReutilizarUltimoEnlace,
          icon: Icons.history_rounded,
        ),

        // ── RENDIMIENTO ─────────────────────────────────────────────────
        _sectionHeader('RENDIMIENTO'),
        _buildConcurrentCard(),

        // ── CACHÉ ───────────────────────────────────────────────────────
        _sectionHeader('CACHÉ'),
        _buildTtlCard(),

        // ── MIS FUENTES (CustomApiConfig – se guardan bien) ─────────────
        _sectionHeader('MIS FUENTES'),
        const CustomApiConfigCard(),

        // ── FUENTES NORMALES ────────────────────────────────────────────
        _sectionHeader('FUENTES  ·  $_fuentesActivas activas'),
        _infoBanner(
          'Activa o desactiva cada fuente. Los cambios se aplican al instante.',
        ),

        ...kRegisteredSources
            .where((s) => s.id != 'customapi')
            .map((source) {
          final enabled = _sourceEnabled[source.id] ?? true;
          final loading = _sourceLoading[source.id] ?? false;
          return _buildSourceCard(
            source: source,
            enabled: enabled,
            loading: loading,
            onChanged: (v) => _setSourceEnabled(source, v),
          );
        }),

        const SizedBox(height: 8),
        _buildResetButton(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _infoBanner(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );
  }

  Widget _buildSourceCard({
    required SourceDefinition source,
    required bool enabled,
    required bool loading,
    required ValueChanged<bool> onChanged,
  }) {
    final description = _getSourceDescription(source.id);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              source.icon,
              color: const Color(0xFF4CAF50),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'movie | tv  ·  1.0.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: loading ? null : onChanged,
            activeThumbColor: const Color(0xFF9C27B0),
            activeTrackColor:
                const Color(0xFF9C27B0).withValues(alpha: 0.45),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }

  String _getSourceDescription(String id) {
    switch (id) {
      case 'embed69':
        return 'Embed69 – Servidores de streaming';
      case 'poseidon':
        return 'Poseidon – Enlaces directos de alta calidad';
      case 'cuevana':
        return 'Cuevana – Películas y series en español';
      case 'unlimplay':
        return 'Unlimplay – Streaming ilimitado';
      case 'cinesrc':
        return 'CineSRC – Fuentes de cine y series';
      case 'cinecalidad':
        return 'Cinecalidad – Películas en español latino';
      case 'tioplus':
        return 'TioPlus – Series y películas';
      case 'fuegocine':
        return 'FuegoCine – Contenido en alta definición';
      case 'hackstore':
        return 'HackStore – Servidores alternativos';
      case 'pelisplus':
        return 'PelisPlusHD – Películas y series HD';
      case 'pelispedia':
        return 'Pelispedia – Biblioteca de películas';
      case 'seriesmetro':
        return 'SeriesMetro – Series actualizadas';
      case 'smartpelis':
        return 'SmartPelis – Streaming inteligente';
      default:
        return 'Proveedor de contenido streaming';
    }
  }

  Widget _buildModeCard() {
    final options = [
      (
        'auto',
        'Automático',
        'Resuelve el mejor enlace y abre el player al instante',
        Icons.bolt_rounded,
      ),
      (
        'manual',
        'Manual',
        'Muestra la lista de servidores para elegir',
        Icons.list_alt_rounded,
      ),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selección de servidores',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((o) {
            final sel = _seleccionarServidores == o.$1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _setSeleccionarServidores(o.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? kAccentColor.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? kAccentColor.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.06),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: sel
                                ? kAccentColor.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            o.$4,
                            size: 20,
                            color: sel ? kAccentColor : Colors.white60,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.$2,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o.$3,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          sel
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: sel ? kAccentColor : Colors.white38,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIdiomaAudioCard() {
    final options = [
      ('latino', 'Latino', Icons.record_voice_over_rounded),
      ('castellano', 'Castellano', Icons.record_voice_over_outlined),
      ('subtitulado', 'Subtitulado', Icons.subtitles_rounded),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Idioma de audio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prioridad al resolver el primer servidor válido',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: options.map((o) {
              final sel = _idiomaAudioPredeterminado == o.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => _setIdiomaAudioPredeterminado(o.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: sel
                            ? kAccentColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? kAccentColor
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            o.$3,
                            size: 18,
                            color: sel ? kAccentColor : Colors.white54,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            o.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtituloCard() {
    final options = [
      ('spa', 'SPA'),
      ('eng', 'ENG'),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subtítulo preferido',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Idioma al cargar subtítulos en el player',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: options.map((o) {
              final sel = _subtituloPredeterminado == o.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => _setSubtituloPredeterminado(o.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: sel
                            ? kAccentColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? kAccentColor
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        o.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Cuántos servidores se comprueban en paralelo al resolver / verificar.
  Widget _buildConcurrentCard() {
    final options = const [1, 2, 3, 4, 5];
    String hintFor(int n) {
      switch (n) {
        case 1:
          return 'Más lento · menos calor y batería';
        case 2:
          return 'Equilibrado (recomendado)';
        case 3:
          return 'Más rápido · algo más de carga';
        case 4:
        case 5:
          return 'Máxima velocidad · más calor y consumo';
        default:
          return '';
      }
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 20,
                color: kAccentColor.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Comprobaciones en paralelo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cuántos servidores se prueban a la vez. Más hilos = más rápido, '
            'pero más CPU, red y calor en el móvil.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((n) {
              final sel = _concurrentChecks == n;
              return GestureDetector(
                onTap: () => _setConcurrentChecks(n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel
                        ? kAccentColor.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? kAccentColor
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            hintFor(_concurrentChecks),
            style: TextStyle(
              color: _concurrentChecks >= 4
                  ? const Color(0xFFFFB74D).withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTtlCard() {
    final options = const [1, 6, 12, 24, 48];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TTL de caché de servidores',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tras este tiempo se vuelven a buscar servidores',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((h) {
              final sel = _ttlHours == h;
              final label = h < 24 ? '${h}h' : '${h ~/ 24}d';
              return GestureDetector(
                onTap: () => _setTtlHours(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel
                        ? kAccentColor.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? kAccentColor
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    bool loading = false,
    Color accent = kAccentColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value
                  ? accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: value ? accent : Colors.white54,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading ? 'Cargando…' : subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white38,
              ),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: accent,
              activeTrackColor: accent.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _clearCacheFuentes,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restart_alt_rounded, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'Reiniciar configuración de fuentes',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}