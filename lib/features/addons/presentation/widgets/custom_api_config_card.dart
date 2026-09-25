// lib/.../custom_api_config_card.dart
// Mis Fuentes – mismo backend, diseño nuevo

import 'package:flutter/material.dart';
import '../../../../data/datasources/remote/sources/custom_api.dart'; // ajusta el import a tu ruta

class CustomApiConfigCard extends StatefulWidget {
  const CustomApiConfigCard({super.key});

  @override
  State<CustomApiConfigCard> createState() => _CustomApiConfigCardState();
}

class _CustomApiConfigCardState extends State<CustomApiConfigCard> {
  final _codigoCtrl = TextEditingController();
  bool _enabled = false;
  List<String> _sources = [];
  bool _loading = true;

  static const _purple = Color(0xFF9C27B0);
  static const _card = Color(0xFF1C1C1E);
  static const _greenIconBg = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await CustomApiConfig.load();
    final en = await CustomApiConfig.isEnabled();
    if (!mounted) return;
    setState(() {
      _sources = List.from(cfg.sources);
      _enabled = en;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final input = _codigoCtrl.text.trim();
    if (input.isEmpty) return;

    String? err;
    if (input.startsWith('http')) {
      err = await CustomApiConfig.addSource(fullUrl: input);
    } else {
      err = await CustomApiConfig.addSource(codigo: input);
    }

    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    _codigoCtrl.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fuente añadida'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _remove(String url) async {
    await CustomApiConfig.removeSource(url);
    await _load();
  }

  Future<void> _toggle(bool v) async {
    await CustomApiConfig.setEnabled(v);
    setState(() => _enabled = v);
  }

  String _labelOf(String url) {
    final codigo = CustomApiConfig.extractCodigo(url);
    if (codigo.isNotEmpty) return codigo;
    if (url.contains('modlyo.com')) return 'Modlyo';
    return 'API';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tarjeta única: switch + input + botón ──────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _greenIconBg.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cloud_rounded,
                      color: Color(0xFF4CAF50),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mis Fuentes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _enabled
                              ? 'Activa – puedes agregar fuentes'
                              : 'Desactivada',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: _toggle,
                    activeThumbColor: _purple,
                    activeTrackColor: _purple.withValues(alpha: 0.45),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: Colors.white12,
                  ),
                ],
              ),
              if (_enabled) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _codigoCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Código o URL completa',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: _purple.withValues(alpha: 0.7),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _add,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Agregar fuente',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Cada API añadida = tarjeta igual que las fuentes normales ──
        if (_enabled && _sources.isNotEmpty)
          ..._sources.map((url) {
            final label = _labelOf(url);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              decoration: BoxDecoration(
                color: _card,
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
                      color: _greenIconBg.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cloud_rounded,
                      color: Color(0xFF4CAF50),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          url,
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
                          'movie | tv  ·  custom',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _remove(url),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}