import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../addons/presentation/widgets/custom_api_config_card.dart';
const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);
const _kBg = Color(0xFF0A0A0A);

class FuentesConfigScreen extends StatefulWidget {
  const FuentesConfigScreen({super.key});

  @override
  State<FuentesConfigScreen> createState() => _FuentesConfigScreenState();
}

class _FuentesConfigScreenState extends State<FuentesConfigScreen> {
  static const _sources =
      <(String id, String label, String prefsKey, Color color)>[
    ('embed69', 'Embed69', 'embed69_enabled', Color(0xFF3B82F6)),
    ('poseidon', 'Poseidon', 'poseidon_enabled', Color(0xFF8B5CF6)),
    ('cuevana', 'Cuevana', 'cuevana_enabled', Color(0xFF22C55E)),
    ('unlimplay', 'Unlimplay', 'unlimplay_enabled', Color(0xFFF59E0B)),
    ('cinesrc', 'CineSRC', 'cinesrc_enabled', Color(0xFF00FF66)),
    ('cinecalidad', 'Cinecalidad', 'cinecalidad_enabled', Color(0xFFEC4899)),
    ('tioplus', 'TioPlus', 'tioplus_enabled', Color(0xFF06B6D4)),
    ('fuegocine', 'FuegoCine', 'fuegocine_enabled', Color(0xFFFF6B00)),
    ('pelispedia', 'Pelispedia', 'pelispedia_enabled', Color(0xFF14B8A6)),
    ('smartpelis', 'SmartPelis', 'smartpelis_enabled', Color(0xFFF97316)),
    ('seriesmetro', 'SeriesMetro', 'seriesmetro_enabled', Color(0xFF6366F1)),
    ('customapi', 'Mis APIs', 'custom_api_enabled', Color(0xFF60A5FA)),
  ];

  bool _loading = true;
  bool _verificar = true;
  bool _unPorIdioma = true;
  bool _mostrarEnPlayer = true;
  bool _reutilizar = false;
  String _seleccion = 'manual';
  int _ttlHours = 12;
  int _capitulosPrecarga = 2;
  final Map<String, bool> _enabled = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    for (final s in _sources) {
      _enabled[s.$1] = p.getBool(s.$3) ?? false;
    }
    setState(() {
      _verificar = p.getBool('verificar_servidores') ?? true;
      _unPorIdioma = p.getBool('un_servidor_por_idioma') ?? true;
      _mostrarEnPlayer = p.getBool('mostrar_servidores_player') ?? true;
      _reutilizar = p.getBool('reutilizar_ultimo_enlace') ?? false;
      _seleccion = p.getString('seleccion_fuente') ?? 'manual';
      _ttlHours = p.getInt('servidores_cache_ttl_hours') ?? 12;
      _capitulosPrecarga = (p.getInt('capitulos_precarga') ?? 2).clamp(0, 10);
      _loading = false;
    });
  }

  Future<void> _setBool(String key, bool value, void Function() apply) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
    if (mounted) setState(apply);
  }

  Future<void> _setTtl(int hours) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('servidores_cache_ttl_hours', hours);
    if (mounted) setState(() => _ttlHours = hours);
  }

  Future<void> _setCapitulosPrecarga(int n) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('capitulos_precarga', n.clamp(0, 10));
    if (mounted) setState(() => _capitulosPrecarga = n.clamp(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        title: const Text('Fuentes', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _toggle(
                  'Comprobar servidores',
                  _verificar,
                  (v) => _setBool(
                    'verificar_servidores',
                    v,
                    () => _verificar = v,
                  ),
                  Icons.verified_rounded,
                  const Color(0xFF22C55E),
                ),
                _toggle(
                  '1 servidor por idioma',
                  _unPorIdioma,
                  (v) => _setBool(
                    'un_servidor_por_idioma',
                    v,
                    () => _unPorIdioma = v,
                  ),
                  Icons.filter_1_rounded,
                  const Color(0xFFF59E0B),
                ),
                _toggle(
                  'Lista en Player',
                  _mostrarEnPlayer,
                  (v) => _setBool(
                    'mostrar_servidores_player',
                    v,
                    () => _mostrarEnPlayer = v,
                  ),
                  Icons.playlist_play_rounded,
                  const Color(0xFFA855F7),
                ),
                _toggle(
                  'Reutilizar último enlace',
                  _reutilizar,
                  (v) => _setBool(
                    'reutilizar_ultimo_enlace',
                    v,
                    () => _reutilizar = v,
                  ),
                  Icons.replay_rounded,
                  const Color(0xFFEC4899),
                ),
                _section('CACHÉ DE SERVIDORES'),
                _ttlCard(),
                _precargaCard(),
                _section('MODO DE SELECCIÓN'),
                ...['manual', 'autoPrimera', 'autoIdioma'].map((m) {
                  final labels = {
                    'manual': 'Manual',
                    'autoPrimera': 'Auto · primera',
                    'autoIdioma': 'Auto · idioma',
                  };
                  final sel = _seleccion == m;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final p = await SharedPreferences.getInstance();
                          await p.setString('seleccion_fuente', m);
                          if (mounted) setState(() => _seleccion = m);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                sel
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: sel ? _kAccent : Colors.white54,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                labels[m]!,
                                style: TextStyle(
                                  color: Colors.white,
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
                }),
                _section('FUENTES DE VIDEO'),
                ..._sources.map((s) {
                  final on = _enabled[s.$1] ?? false;
                  return _toggle(
                    s.$2,
                    on,
                    (v) => _setBool(s.$3, v, () => _enabled[s.$1] = v),
                    s.$1 == 'customapi'
                        ? Icons.cloud_rounded
                        : Icons.stream_rounded,
                    s.$4,
                  );
                }),
                // Tarjeta para añadir códigos/URLs ilimitados
                if (_enabled['customapi'] == true) ...[
                  _section('MIS APIS · CÓDIGOS'),
                  const CustomApiConfigCard(),
                ],
              ],
            ),
    );
  }

  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _ttlCard() {
    final options = [1, 6, 12, 24, 48];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TTL de caché',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tras este tiempo se vuelve a buscar servidores',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((h) {
              final sel = _ttlHours == h;
              final label = h < 24 ? '${h}h' : '${h ~/ 24}d';
              return GestureDetector(
                onTap: () => _setTtl(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? _kAccent.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? _kAccent : Colors.transparent,
                      width: 1.5,
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

  Widget _precargaCard() {
    final options = [0, 1, 2, 3, 5];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Capítulos a precargar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _capitulosPrecarga == 0
                ? 'Precarga desactivada'
                : 'Precarga silenciosa de $_capitulosPrecarga episodio(s) siguientes',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((n) {
              final sel = _capitulosPrecarga == n;
              final label = n == 0 ? 'Off' : '$n';
              return GestureDetector(
                onTap: () => _setCapitulosPrecarga(n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? _kAccent.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? _kAccent : Colors.transparent,
                      width: 1.5,
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

  Widget _toggle(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
    Color accent,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (value ? accent : Colors.white)
                  .withValues(alpha: value ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: value ? accent : Colors.white70, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
}