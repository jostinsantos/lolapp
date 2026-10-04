import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Registro de un uso de la IA (Kilo).
class AiUsageEvent {
  final int atMs;
  final String kind; // chat | foryou | other
  final String model;
  final int promptTokens; // estimado si no viene del API
  final int completionTokens;
  final bool success;

  const AiUsageEvent({
    required this.atMs,
    required this.kind,
    required this.model,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.success = true,
  });

  int get totalTokens => promptTokens + completionTokens;

  Map<String, dynamic> toJson() => {
        'at': atMs,
        'k': kind,
        'm': model,
        'pt': promptTokens,
        'ct': completionTokens,
        'ok': success,
      };

  factory AiUsageEvent.fromJson(Map<String, dynamic> j) => AiUsageEvent(
        atMs: (j['at'] as num?)?.toInt() ?? 0,
        kind: j['k']?.toString() ?? 'other',
        model: j['m']?.toString() ?? '',
        promptTokens: (j['pt'] as num?)?.toInt() ?? 0,
        completionTokens: (j['ct'] as num?)?.toInt() ?? 0,
        success: j['ok'] != false,
      );
}

/// Resumen de uso por hora / día.
class AiUsageSummary {
  final int usesThisHour;
  final int usesToday;
  final int tokensThisHour;
  final int tokensToday;
  final int limitPerHour; // Kilo ~200/h por IP
  final List<AiUsageEvent> recent;

  const AiUsageSummary({
    required this.usesThisHour,
    required this.usesToday,
    required this.tokensThisHour,
    required this.tokensToday,
    required this.limitPerHour,
    required this.recent,
  });

  double get hourProgress =>
      limitPerHour <= 0 ? 0 : (usesThisHour / limitPerHour).clamp(0.0, 1.0);

  int get remainingThisHour =>
      (limitPerHour - usesThisHour).clamp(0, limitPerHour);
}

/// Tracker persistente de usos de Kilo IA.
class AiUsageTracker {
  static const _prefsKey = 'ai_usage_events_v1';
  static const limitPerHour = 200; // límite aproximado de Kilo por IP
  static const _maxStored = 500;

  static final AiUsageTracker instance = AiUsageTracker._();
  AiUsageTracker._();

  List<AiUsageEvent> _events = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _events = list
          .map((e) => AiUsageEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _prune();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_events.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _prune() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - 7 * 24 * 60 * 60 * 1000;
    _events = _events.where((e) => e.atMs >= cutoff).toList();
    if (_events.length > _maxStored) {
      _events = _events.sublist(_events.length - _maxStored);
    }
  }

  /// Registra un uso. [promptTokens]/[completionTokens] estimados si no vienen del API.
  Future<void> record({
    required String kind,
    String model = 'kilo',
    int promptTokens = 0,
    int completionTokens = 0,
    bool success = true,
  }) async {
    await _ensureLoaded();
    _events.add(AiUsageEvent(
      atMs: DateTime.now().millisecondsSinceEpoch,
      kind: kind,
      model: model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      success: success,
    ));
    _prune();
    await _persist();
  }

  /// Estima tokens a partir del texto (~4 chars/token).
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil().clamp(1, 100000);
  }

  Future<AiUsageSummary> summary() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final hourStart = now.subtract(Duration(
      minutes: now.minute,
      seconds: now.second,
      milliseconds: now.millisecond,
    )).millisecondsSinceEpoch;
    final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    var usesH = 0, usesD = 0, tokH = 0, tokD = 0;
    for (final e in _events) {
      if (e.atMs >= dayStart) {
        usesD++;
        tokD += e.totalTokens;
      }
      if (e.atMs >= hourStart) {
        usesH++;
        tokH += e.totalTokens;
      }
    }

    final recent = List<AiUsageEvent>.from(_events.reversed.take(30));
    return AiUsageSummary(
      usesThisHour: usesH,
      usesToday: usesD,
      tokensThisHour: tokH,
      tokensToday: tokD,
      limitPerHour: limitPerHour,
      recent: recent,
    );
  }

  Future<void> clear() async {
    _events = [];
    await _persist();
  }
}
