import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';
import '../config_shared.dart';

/// Opciones TMDB: idioma de la API + API propia del usuario.
class TmdbApiOptions extends StatefulWidget {
  const TmdbApiOptions({super.key});

  @override
  State<TmdbApiOptions> createState() => _TmdbApiOptionsState();
}

class _TmdbApiOptionsState extends State<TmdbApiOptions> {
  bool _loading = true;
  bool _useCustom = false;
  String _lang = 'es-MX';
  final _keyCtrl = TextEditingController();

  static const _langs = [
    ('es-MX', 'Español (México)'),
    ('es-ES', 'Español (España)'),
    ('en-US', 'English (US)'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final use = await TmdbApis.getUseCustomApi();
    final key = await TmdbApis.getCustomApiKey();
    final lang = await TmdbApis.getLanguage();
    if (!mounted) return;
    setState(() {
      _useCustom = use;
      _keyCtrl.text = key ?? '';
      _lang = lang;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(
            'API TMDB',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Idioma de la API',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Idioma de títulos y sinopsis que devuelve TMDB',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _langs.map((e) {
                  final selected = _lang == e.$1;
                  return ChoiceChip(
                    label: Text(e.$2),
                    selected: selected,
                    onSelected: (_) async {
                      await TmdbApis.setLanguage(e.$1);
                      // Exclusivo: desactiva los demás en preferencias de metadatos
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('spanish_latino', e.$1 == 'es-MX');
                      await prefs.setBool('spanish_castellano', e.$1 == 'es-ES');
                      await prefs.setBool('english', e.$1 == 'en-US');
                      setState(() => _lang = e.$1);
                    },
                    selectedColor: const Color(0xFF8B5CF6).withOpacity(0.35),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                    backgroundColor: Colors.white.withOpacity(0.06),
                  );
                }).toList(),
              ),
              const Divider(color: Colors.white12, height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF8B5CF6),
                title: const Text(
                  'Usar mi API de TMDB',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  'Si está off, la app rota entre las claves integradas',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _useCustom,
                onChanged: (v) async {
                  await TmdbApis.setUseCustomApi(v);
                  setState(() => _useCustom = v);
                },
              ),
              if (_useCustom) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _keyCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Tu API key de themoviedb.org',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (v) => TmdbApis.setCustomApiKey(v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
