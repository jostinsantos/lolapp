import 'package:flutter/material.dart';


import '../../../settings/presentation/notifications/episode_reminder_service.dart';
import 'tmdb_upcoming_service.dart';

const _orange = Color(0xFFFF6B00);

/// Modal: próximos estrenos + avisos a las 11:00. Errores se muestran aquí (no dialog genérico).
class UpcomingEpisodesModal extends StatefulWidget {
  final int tmdbId;
  final String seriesTitle;

  const UpcomingEpisodesModal({
    super.key,
    required this.tmdbId,
    required this.seriesTitle,
  });

  static Future<void> show({
    required BuildContext context,
    required int tmdbId,
    required String seriesTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpcomingEpisodesModal(
        tmdbId: tmdbId,
        seriesTitle: seriesTitle,
      ),
    );
  }

  @override
  State<UpcomingEpisodesModal> createState() => _UpcomingEpisodesModalState();
}

class _UpcomingEpisodesModalState extends State<UpcomingEpisodesModal> {
  final _svc = EpisodeReminderService.instance;
  final _tmdb = TmdbUpcomingService();

  List<Map<String, dynamic>> _episodes = [];
  Set<String> _scheduled = {};
  bool _loading = true;
  bool _busyAll = false;
  final Set<String> _busy = {};
  String _status = '';

  /// Error visible dentro del modal
  String? _errorTitle;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorTitle = null;
      _errorDetail = null;
    });
    try {
      final result = await _tmdb.fetchUpcoming(tmdbId: widget.tmdbId);
      final keys = await _svc.scheduledKeysForSeries(widget.tmdbId);
      if (!mounted) return;
      setState(() {
        _episodes = result.episodes;
        _status = result.status;
        _scheduled = keys;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorTitle = 'No se pudieron cargar los capítulos';
          _errorDetail = e.toString();
        });
      }
    }
  }

  void _showError(String title, [String? detail]) {
    setState(() {
      _errorTitle = title;
      _errorDetail = detail;
    });
  }

  void _clearError() {
    if (_errorTitle != null) {
      setState(() {
        _errorTitle = null;
        _errorDetail = null;
      });
    }
  }

  DateTime? _parseAirDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _fmtDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _daysLeft(DateTime air) {
    final today = DateTime.now();
    final a = DateTime(air.year, air.month, air.day);
    final t = DateTime(today.year, today.month, today.day);
    final diff = a.difference(t).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff == 1) return 'Mañana';
    return 'En $diff días';
  }

  Future<void> _toggleOne(Map<String, dynamic> ep) async {
    final season = (ep['season_number'] as num?)?.toInt();
    final episode = (ep['episode_number'] as num?)?.toInt();
    final air = _parseAirDate(ep['air_date']);
    if (season == null || episode == null || air == null) return;

    final key = '${widget.tmdbId}_S${season}_E$episode';
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    _clearError();

    final wasOn = _scheduled.contains(key);
    try {
      if (wasOn) {
        await _svc.cancel(
          tmdbId: widget.tmdbId,
          season: season,
          episode: episode,
        );
        if (mounted) setState(() => _scheduled.remove(key));
      } else {
        final r = await _svc.schedule(
          tmdbId: widget.tmdbId,
          season: season,
          episode: episode,
          seriesTitle: widget.seriesTitle,
          episodeTitle: ep['name']?.toString() ?? '',
          airDate: air,
        );
        if (!mounted) return;
        if (r.ok) {
          setState(() => _scheduled.add(key));
        } else {
          _showError(
            r.error ?? 'No se pudo programar',
            r.errorDetail,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error inesperado', e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _activateAll() async {
    if (_episodes.isEmpty || _busyAll) return;
    setState(() => _busyAll = true);
    _clearError();
    try {
      final r = await _svc.scheduleAll(
        tmdbId: widget.tmdbId,
        seriesTitle: widget.seriesTitle,
        episodes: _episodes,
      );
      final keys = await _svc.scheduledKeysForSeries(widget.tmdbId);
      if (!mounted) return;
      setState(() => _scheduled = keys);
      if (r.ok == 0 && r.error != null) {
        _showError(r.error!, r.detail);
      } else if (r.ok < _episodes.length && r.error != null) {
        _showError(
          'Se activaron ${r.ok} de ${_episodes.length}',
          r.error,
        );
      }
    } catch (e) {
      if (mounted) _showError('Error al activar todos', e.toString());
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  Future<void> _cancelAll() async {
    if (_busyAll) return;
    setState(() => _busyAll = true);
    _clearError();
    try {
      await _svc.cancelAllForSeries(widget.tmdbId);
      if (mounted) setState(() => _scheduled = {});
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  bool get _allOn {
    if (_episodes.isEmpty) return false;
    for (final ep in _episodes) {
      final s = (ep['season_number'] as num?)?.toInt() ?? 0;
      final e = (ep['episode_number'] as num?)?.toInt() ?? 0;
      if (!_scheduled.contains('${widget.tmdbId}_S${s}_E$e')) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Color(0xFF141418),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: _orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Próximos estrenos',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.seriesTitle.isNotEmpty
                            ? widget.seriesTitle
                            : 'Avisos a las 11:00 el día del estreno',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
          ),

          // Banner de error dentro del modal
          if (_errorTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _errorTitle!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_errorDetail != null &&
                              _errorDetail!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _errorDetail!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _clearError,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (!_loading && _episodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busyAll
                      ? null
                      : (_allOn ? _cancelAll : _activateAll),
                  icon: _busyAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _allOn
                              ? Icons.notifications_off_rounded
                              : Icons.notifications_active_rounded,
                          size: 20,
                        ),
                  label: Text(
                    _allOn
                        ? 'Cancelar todos los avisos'
                        : 'Activar aviso en todos',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allOn ? Colors.white12 : _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                color: _orange,
                strokeWidth: 2.5,
              ),
            )
          else if (_episodes.isEmpty && _errorTitle == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
              child: Column(
                children: [
                  Icon(Icons.event_busy_rounded,
                      color: Colors.grey[600], size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No hay capítulos por estrenar',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _status.isNotEmpty
                        ? 'Estado TMDB: $_status'
                        : 'Cuando haya fechas futuras aparecerán aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            )
          else if (_episodes.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + bottom),
                itemCount: _episodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final ep = _episodes[i];
                  final season =
                      (ep['season_number'] as num?)?.toInt() ?? 0;
                  final episode =
                      (ep['episode_number'] as num?)?.toInt() ?? 0;
                  final name =
                      ep['name']?.toString() ?? 'Episodio $episode';
                  final air = _parseAirDate(ep['air_date']);
                  final key = '${widget.tmdbId}_S${season}_E$episode';
                  final isOn = _scheduled.contains(key);
                  final busy = _busy.contains(key);
                  final sLabel =
                      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: busy ? null : () => _toggleOne(ep),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isOn
                              ? _orange.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isOn
                                ? _orange.withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isOn
                                    ? _orange.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isOn
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_none_rounded,
                                color: isOn ? _orange : Colors.white70,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$sLabel · $name',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (air != null)
                                    Text(
                                      '${_fmtDate(air)}  ·  ${_daysLeft(air)}  ·  11:00',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (busy)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: _orange,
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isOn
                                      ? _orange.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isOn ? 'Programado' : 'Avisarme',
                                  style: TextStyle(
                                    color: isOn ? _orange : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}