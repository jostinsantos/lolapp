import 'package:flutter/material.dart';
import '../../../../data/ai/ai_usage_tracker.dart';
import '../../../../data/recommendations/for_you_generator.dart';
import '../../../../data/ai/ai_client.dart';

/// Sección de configuración: uso de IA (tokens / peticiones por hora).
class AiUsageSection extends StatefulWidget {
  const AiUsageSection({super.key});

  @override
  State<AiUsageSection> createState() => _AiUsageSectionState();
}

class _AiUsageSectionState extends State<AiUsageSection> {
  AiUsageSummary? _summary;
  bool _loading = true;
  int? _forYouLastMs;
  bool _forYouFail = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final s = await AiUsageTracker.instance.summary();
    // Marcas de Para ti
    int last = 0;
    bool fail = false;
    try {
      // leer marks vía prefs indirectamente: generar no; solo cached
      final gen = ForYouGenerator(ai: AiClient());
      final cached = await gen.loadCached();
      if (cached.isNotEmpty) {
        last = cached.first.generadoAt;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _summary = s;
        _forYouLastMs = last > 0 ? last : null;
        _forYouFail = fail;
        _loading = false;
      });
    }
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'chat':
        return 'Lolbot';
      case 'foryou':
        return 'Para ti';
      default:
        return k;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'Inteligencia artificial',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Kilo AI (gratis). Límite aprox. 200 usos por hora por IP. '
            'Las recomendaciones se regeneran cada 20 horas para ahorrar cuota.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.purpleAccent,
                strokeWidth: 2,
              ),
            ),
          )
        else if (s != null) ...[
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.purpleAccent, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Uso esta hora',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${s.usesThisHour} / ${s.limitPerHour}',
                      style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.hourProgress,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    color: s.hourProgress > 0.85
                        ? Colors.orangeAccent
                        : Colors.purpleAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quedan ${s.remainingThisHour} usos esta hora · '
                  '~${s.tokensThisHour} tokens estimados',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          _card(
            child: Column(
              children: [
                _row('Usos hoy', '${s.usesToday}'),
                _row('Tokens hoy (est.)', '${s.tokensToday}'),
                _row(
                  'Última gen. Para ti',
                  _forYouLastMs != null
                      ? _fmtTime(_forYouLastMs!)
                      : 'aún no',
                ),
                _row('Ventana regeneración', '20 horas'),
              ],
            ),
          ),
          if (s.recent.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Actividad reciente',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _card(
              child: Column(
                children: s.recent.take(12).map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          e.success ? Icons.check_circle : Icons.error_outline,
                          size: 16,
                          color: e.success
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_kindLabel(e.kind)} · ${e.model.isEmpty ? 'kilo' : e.model}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${e.totalTokens > 0 ? '${e.totalTokens} tok · ' : ''}${_fmtTime(e.atMs)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualizar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.purpleAccent,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1a1a2e),
                        title: const Text('Borrar historial de IA?',
                            style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'No borra tus recomendaciones guardadas, solo el contador de usos.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Borrar',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await AiUsageTracker.instance.clear();
                      await _refresh();
                    }
                  },
                  child: const Text(
                    'Borrar contador',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
