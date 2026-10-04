import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Memoria de qué modelos de Kilo funcionan en este dispositivo.
/// Misma lógica que ModelMemory de Kino.
class ModelMemory {
  static const _prefsKey = 'kilo_model_memory_v1';
  static const rateLimitWaitMs = 10 * 60 * 1000;
  static const serverWaitMs = 5 * 60 * 1000;
  static const countCap = 20;

  final Map<String, _Record> _records = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((id, v) {
        if (v is! Map) return;
        _records[id] = _Record(
          successes: (v['e'] as num?)?.toInt() ?? 0,
          failures: (v['f'] as num?)?.toInt() ?? 0,
          waitUntilMs: (v['h'] as num?)?.toInt() ?? 0,
        );
      });
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      _records.forEach((id, r) {
        map[id] = {'e': r.successes, 'f': r.failures, 'h': r.waitUntilMs};
      });
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  /// Ordena modelos: primero los que han tenido éxito, excluye los en cooldown.
  Future<List<T>> order<T extends Object>(List<T> models) async {
    await _ensureLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scored = <(T, int)>[];
    for (final m in models) {
      final id = (m as dynamic).id as String;
      final r = _records[id];
      if (r != null && r.waitUntilMs > now) continue;
      scored.add((m, _score(r)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  void success(String id) {
    final r = _records[id] ?? const _Record();
    _records[id] = r.copyWith(
      successes: (r.successes + 1).clamp(0, countCap),
      waitUntilMs: 0,
    );
    _persist();
  }

  void failure(String id, ModelFailure failure) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = _records[id] ?? const _Record();
    switch (failure) {
      case RateLimited(:final retryAfterMs):
        _records[id] = r.copyWith(
          waitUntilMs: now + (retryAfterMs ?? rateLimitWaitMs),
        );
      case ServerFailure():
        _records[id] = r.copyWith(
          failures: (r.failures + 1).clamp(0, countCap),
          waitUntilMs: now + serverWaitMs,
        );
      case UnreadableFailure():
        return; // no cuenta
    }
    _persist();
  }

  int _score(_Record? r) {
    if (r == null) return 0;
    return r.successes - 2 * r.failures;
  }
}

class _Record {
  final int successes;
  final int failures;
  final int waitUntilMs;
  const _Record({
    this.successes = 0,
    this.failures = 0,
    this.waitUntilMs = 0,
  });
  _Record copyWith({int? successes, int? failures, int? waitUntilMs}) =>
      _Record(
        successes: successes ?? this.successes,
        failures: failures ?? this.failures,
        waitUntilMs: waitUntilMs ?? this.waitUntilMs,
      );
}

sealed class ModelFailure {
  const ModelFailure();
  factory ModelFailure.rateLimited([int? retryAfterMs]) =>
      RateLimited(retryAfterMs);
  static const server = ServerFailure();
  static const unreadable = UnreadableFailure();
}

class RateLimited extends ModelFailure {
  final int? retryAfterMs;
  const RateLimited(this.retryAfterMs);
}

class ServerFailure extends ModelFailure {
  const ServerFailure();
}

class UnreadableFailure extends ModelFailure {
  const UnreadableFailure();
}
