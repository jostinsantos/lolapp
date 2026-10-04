import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// «Corriente» estilo Nuvio / Elite-Badges.
///
/// Formatos soportados:
///
/// 1) Elite / Nuvio (filters + pattern regex + imageURL):
/// ```json
/// {
///   "filters": [
///     { "id":"remux", "name":"REMUX", "pattern":"(?i)\\bremux\\b",
///       "imageURL":"https://…/remux.png", "isEnabled": true }
///   ],
///   "groups": [ … ]
/// }
/// ```
///
/// 2) Simple:
/// ```json
/// {
///   "id": "pack1",
///   "name": "Pack",
///   "badges": [
///     { "match": "netflix", "logo": "https://…", "label": "Netflix" }
///   ]
/// }
/// ```
class StreamBadgeRepository extends ChangeNotifier {
  StreamBadgeRepository._();
  static final StreamBadgeRepository instance = StreamBadgeRepository._();

  static const _prefsKey = 'stream_badge_packs_v1';

  final _http = http.Client();
  List<StreamBadgePack> _packs = [];
  bool _loaded = false;

  List<StreamBadgePack> get packs => List.unmodifiable(_packs);
  List<StreamBadgePack> get enabledPacks =>
      _packs.where((p) => p.enabled).toList();

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _packs = list
            .whereType<Map>()
            .map((e) => StreamBadgePack.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _packs = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_packs.map((e) => e.toJson()).toList()),
    );
  }

  Future<StreamBadgePack> installFromUrl(String url) async {
    await init();
    final res = await _http
        .get(Uri.parse(url.trim()), headers: {
          'Accept': 'application/json',
          'User-Agent': 'LolPlusTV/1.0',
        })
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return installFromJson(res.body, sourceUrl: url.trim());
  }

  Future<StreamBadgePack> installFromJson(String raw, {String? sourceUrl}) async {
    await init();
    final decoded = jsonDecode(raw);
    final pack = StreamBadgePack.fromRaw(decoded, sourceUrl: sourceUrl);
    if (pack.badges.isEmpty) {
      throw FormatException(
        'El pack no tiene badges/filters reconocibles '
        '(se esperan "filters" con pattern+imageURL o "badges" con match+logo)',
      );
    }
    final idx = _packs.indexWhere((p) => p.id == pack.id);
    if (idx >= 0) {
      _packs[idx] = pack.copyWith(enabled: _packs[idx].enabled);
    } else {
      _packs.add(pack);
    }
    await _persist();
    notifyListeners();
    return pack;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await init();
    final i = _packs.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _packs[i] = _packs[i].copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await init();
    _packs.removeWhere((p) => p.id == id);
    await _persist();
    notifyListeners();
  }

  /// Primera insignia que coincida (compat).
  StreamBadgeMatch? matchBadge(String text) {
    final all = matchAllBadges(text);
    return all.isEmpty ? null : all.first;
  }

  /// Todas las insignias que coincidan (Elite: varias por stream).
  List<StreamBadgeMatch> matchAllBadges(String text) {
    if (text.isEmpty) return const [];
    final out = <StreamBadgeMatch>[];
    final seen = <String>{};
    for (final pack in enabledPacks) {
      for (final b in pack.badges) {
        if (!b.enabled) continue;
        if (!b.matches(text)) continue;
        final key = b.logo ?? b.label;
        if (!seen.add(key)) continue;
        out.add(StreamBadgeMatch(
          logo: b.logo,
          label: b.label,
          groupId: b.groupId,
        ));
      }
    }
    return out;
  }
}

class StreamBadgePack {
  final String id;
  final String name;
  final String? sourceUrl;
  final List<StreamBadgeRule> badges;
  final bool enabled;

  const StreamBadgePack({
    required this.id,
    required this.name,
    this.sourceUrl,
    required this.badges,
    this.enabled = true,
  });

  StreamBadgePack copyWith({bool? enabled}) => StreamBadgePack(
        id: id,
        name: name,
        sourceUrl: sourceUrl,
        badges: badges,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'badges': badges.map((e) => e.toJson()).toList(),
        'enabled': enabled,
      };

  factory StreamBadgePack.fromJson(Map<String, dynamic> j) {
    // Ya normalizado en almacenamiento
    final badgesRaw = j['badges'] as List? ?? j['filters'] as List? ?? [];
    return StreamBadgePack(
      id: (j['id'] ?? 'pack_${j['name'] ?? 'x'}').toString(),
      name: (j['name'] ?? j['id'] ?? 'Pack').toString(),
      sourceUrl: j['sourceUrl']?.toString(),
      badges: badgesRaw
          .whereType<Map>()
          .map((e) => StreamBadgeRule.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.pattern.isNotEmpty || b.match.isNotEmpty)
          .toList(),
      enabled: j['enabled'] != false,
    );
  }

  /// Acepta JSON Elite (`filters`) o simple (`badges`).
  factory StreamBadgePack.fromRaw(dynamic decoded, {String? sourceUrl}) {
    if (decoded is List) {
      return StreamBadgePack(
        id: 'pack_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Pack importado',
        sourceUrl: sourceUrl,
        badges: decoded
            .whereType<Map>()
            .map((e) => StreamBadgeRule.fromJson(Map<String, dynamic>.from(e)))
            .where((b) => b.pattern.isNotEmpty || b.match.isNotEmpty)
            .toList(),
      );
    }
    if (decoded is! Map) {
      throw FormatException('JSON de pack inválido');
    }
    final j = Map<String, dynamic>.from(decoded);

    // Elite-Badges / Nuvio: { filters: [...], groups: [...] }
    final filters = j['filters'] as List?;
    if (filters != null && filters.isNotEmpty) {
      final rules = <StreamBadgeRule>[];
      for (final f in filters) {
        if (f is! Map) continue;
        final m = Map<String, dynamic>.from(f);
        // Solo type filter (ignorar otros tipos si hubiera)
        final type = (m['type'] ?? 'filter').toString().toLowerCase();
        if (type != 'filter') continue;
        final rule = StreamBadgeRule.fromJson(m);
        if (rule.pattern.isEmpty && rule.match.isEmpty) continue;
        rules.add(rule);
      }
      var name = (j['name'] ?? '').toString();
      if (name.isEmpty && sourceUrl != null) {
        name = sourceUrl.split('/').where((s) => s.isNotEmpty).last;
        if (name.endsWith('.json')) {
          name = name.substring(0, name.length - 5);
        }
      }
      if (name.isEmpty) name = 'Elite Badges';
      final id = (j['id'] ?? name).toString().toLowerCase().replaceAll(' ', '-');
      return StreamBadgePack(
        id: id,
        name: name,
        sourceUrl: sourceUrl ?? j['sourceUrl']?.toString(),
        badges: rules,
      );
    }

    // Formato simple con badges
    return StreamBadgePack.fromJson({
      ...j,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
    });
  }
}

class StreamBadgeRule {
  /// Texto simple (formato viejo)
  final String match;
  /// Regex estilo Elite: `(?i)\bremux\b`
  final String pattern;
  final String? logo;
  final String label;
  final String? groupId;
  final bool enabled;

  const StreamBadgeRule({
    this.match = '',
    this.pattern = '',
    this.logo,
    required this.label,
    this.groupId,
    this.enabled = true,
  });

  bool matches(String text) {
    if (pattern.isNotEmpty) {
      try {
        // Elite patterns suelen traer (?i) dentro; en Dart usamos caseSensitive:false
        var p = pattern;
        var caseSensitive = true;
        if (p.startsWith('(?i)')) {
          caseSensitive = false;
          p = p.substring(4);
        } else if (p.startsWith('(?-i)')) {
          p = p.substring(5);
        }
        final re = RegExp(p, caseSensitive: caseSensitive);
        return re.hasMatch(text);
      } catch (e) {
        debugPrint('[Badge] regex inválida "$pattern": $e');
        // fallback contains
        return match.isNotEmpty &&
            text.toLowerCase().contains(match.toLowerCase());
      }
    }
    if (match.isEmpty) return false;
    return text.toLowerCase().contains(match.toLowerCase());
  }

  Map<String, dynamic> toJson() => {
        'match': match,
        if (pattern.isNotEmpty) 'pattern': pattern,
        if (logo != null) 'logo': logo,
        'label': label,
        if (groupId != null) 'groupId': groupId,
        'enabled': enabled,
      };

  factory StreamBadgeRule.fromJson(Map<String, dynamic> j) {
    final pattern = (j['pattern'] ?? '').toString();
    final match = (j['match'] ?? j['provider'] ?? '').toString();
    final logo = j['logo']?.toString() ??
        j['imageURL']?.toString() ??
        j['imageUrl']?.toString() ??
        j['image']?.toString();
    final label = (j['label'] ?? j['name'] ?? j['id'] ?? match).toString();
    final enabled = j['isEnabled'] != false && j['enabled'] != false;
    return StreamBadgeRule(
      match: match.isNotEmpty
          ? match
          : (label.isNotEmpty ? label : ''),
      pattern: pattern,
      logo: logo,
      label: label.isNotEmpty ? label : 'Badge',
      groupId: j['groupId']?.toString(),
      enabled: enabled,
    );
  }
}

class StreamBadgeMatch {
  final String? logo;
  final String label;
  final String? groupId;
  const StreamBadgeMatch({
    this.logo,
    required this.label,
    this.groupId,
  });
}
