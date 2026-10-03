import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import '../models/content.dart';

/// Ejecuta addons JS estilo Nuvio / CineCalidad (CommonJS + getStreams).
/// - fetch/axios: puente Dart (onMessage 'httpFetch')
/// - setTimeout/setInterval reales: puente Dart (onMessage 'jsTimer')
/// - crypto-js y cheerio: cargados desde assets locales (sin depender de CDN)
class JsAddonRuntime {
  JsAddonRuntime._();
  static final JsAddonRuntime instance = JsAddonRuntime._();

  static const _cryptoAsset = 'assets/js/crypto-js.bundle.js';
  static const _cheerioAsset = 'assets/js/cheerio.bundle.js';
  static const _cryptoCdn = <String>[
    'https://cdnjs.cloudflare.com/ajax/libs/crypto-js/3.1.9-1/crypto-js.min.js',
    'https://cdn.jsdelivr.net/npm/crypto-js@3.1.9-1/crypto-js.js',
  ];
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  JavascriptRuntime? _rt;
  bool _ready = false;
  final Set<String> _loaded = {};
  final Map<String, int> _codeHash = {};
  final Set<Timer> _timers = {};

  bool _cryptoReady = false;
  bool _cheerioReady = false;
  Future<void>? _cryptoFuture;
  Future<void>? _cheerioFuture;

  // ---------------------------------------------------------------- init

  Future<void> ensureReady() async {
    if (_ready && _rt != null) return;
    _rt = getJavascriptRuntime(xhr: false);
    try {
      _rt!.enableHandlePromises();
    } catch (_) {}
    _registerHttpBridge();
    _registerTimerBridge();
    _installBasePolyfills();
    _ready = true;
  }

  String _run(String code) {
    final r = _rt!.evaluate(code);
    return r.isError ? 'err:${r.stringResult}' : r.stringResult;
  }

  // ---------------------------------------------------------------- timers

  void _registerTimerBridge() {
    _rt!.onMessage('jsTimer', (dynamic args) {
      try {
        final Map m = args is String ? jsonDecode(args) as Map : args as Map;
        final id = (m['id'] as num).toInt();
        final ms = (m['ms'] as num?)?.toInt() ?? 0;
        late Timer t;
        t = Timer(Duration(milliseconds: ms), () {
          _timers.remove(t);
          final rt = _rt;
          if (rt == null) return;
          try {
            rt.evaluate('globalThis.__fireTimer($id)');
            rt.executePendingJob();
          } catch (e) {
            debugPrint('[JsRuntime] timer error: $e');
          }
        });
        _timers.add(t);
      } catch (e) {
        debugPrint('[JsRuntime] jsTimer bridge error: $e');
      }
      return null;
    });
  }

  // ---------------------------------------------------------------- fetch

  void _registerHttpBridge() {
    _rt!.onMessage('httpFetch', (dynamic args) async {
      try {
        return await _httpFetch(args);
      } catch (e) {
        debugPrint('[JsRuntime] httpFetch error: $e');
        return _fetchError(e.toString());
      }
    });
  }

  String _fetchError(String msg) => jsonEncode({
        'ok': false,
        'status': 0,
        'body': '',
        'headers': <String, String>{},
        'error': msg,
      });

  Future<String> _httpFetch(dynamic args) async {
    Map<String, dynamic> map;
    if (args is String) {
      map = Map<String, dynamic>.from(jsonDecode(args) as Map);
    } else if (args is Map) {
      map = Map<String, dynamic>.from(args);
    } else {
      return _fetchError('bad args');
    }

    var uri = Uri.parse(map['url']?.toString() ?? '');
    var method = (map['method']?.toString() ?? 'GET').toUpperCase();
    String? body = map['body']?.toString();
    final manualRedirect = map['redirect']?.toString() == 'manual';

    final headers = <String, String>{};
    final rawH = map['headers'];
    if (rawH is Map) {
      rawH.forEach((k, v) {
        if (k != null && v != null) headers['$k'] = '$v';
      });
    }
    bool hasHeader(String n) => headers.keys.any((k) => k.toLowerCase() == n);
    if (!hasHeader('user-agent')) headers['User-Agent'] = _userAgent;
    if (!hasHeader('accept')) headers['Accept'] = '*/*';
    if (!hasHeader('accept-language')) {
      headers['Accept-Language'] = 'es-419,es;q=0.9,en;q=0.8';
    }

    final client = http.Client();
    try {
      var redirected = false;
      var hops = 0;
      while (true) {
        final req = http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll(headers);
        if (body != null && method != 'GET' && method != 'HEAD') {
          req.body = body;
        }
        final streamed =
            await client.send(req).timeout(const Duration(seconds: 18));
        final res = await http.Response.fromStream(streamed)
            .timeout(const Duration(seconds: 18));

        final isRedirect = const [301, 302, 303, 307, 308].contains(res.statusCode);
        final loc = res.headers['location'];
        if (isRedirect && !manualRedirect && loc != null && loc.isNotEmpty && hops < 6) {
          uri = uri.resolve(loc);
          hops++;
          redirected = true;
          if (res.statusCode == 303 ||
              ((res.statusCode == 301 || res.statusCode == 302) && method == 'POST')) {
            method = 'GET';
            body = null;
          }
          continue;
        }

        final ct = res.headers['content-type'] ?? '';
        final isLatin1 = RegExp(r'charset\s*=\s*"?(iso-8859-1|latin1|windows-1252)',
                caseSensitive: false)
            .hasMatch(ct);
        final text = isLatin1
            ? latin1.decode(res.bodyBytes)
            : utf8.decode(res.bodyBytes, allowMalformed: true);

        return jsonEncode({
          'ok': res.statusCode >= 200 && res.statusCode < 300,
          'status': res.statusCode,
          'body': text,
          'url': uri.toString(),
          'redirected': redirected,
          'headers': res.headers,
        });
      }
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------- polyfills

  void _installBasePolyfills() {
    final r = _rt!.evaluate(_polyfillsJs);
    if (r.isError) {
      debugPrint('[JsRuntime] ERROR instalando polyfills: ${r.stringResult}');
    }
  }

  // ---------------------------------------------------------------- crypto-js

  Future<void> ensureCryptoJs() async {
    if (_cryptoReady) return;
    await ensureReady();
    final pending = _cryptoFuture ??= _loadCryptoJs();
    try {
      await pending;
    } finally {
      if (!_cryptoReady) _cryptoFuture = null;
    }
  }

  Future<void> _loadCryptoJs() async {
    if (_run("(typeof globalThis.CryptoJS !== 'undefined' && !!globalThis.CryptoJS.AES) ? 'yes' : 'no'") == 'yes') {
      _cryptoReady = true;
      return;
    }
    final candidates = <String>['asset:$_cryptoAsset', ..._cryptoCdn];
    for (final c in candidates) {
      String? src;
      if (c.startsWith('asset:')) {
        try {
          src = await rootBundle.loadString(_cryptoAsset);
        } catch (e) {
          debugPrint('[JsRuntime] falta asset $_cryptoAsset ($e). Probando CDN...');
        }
      } else {
        src = await _download(c);
      }
      if (src == null || src.length < 1000) continue;

      final result = _run(_libLoaderJs(src, 'CryptoJS'));
      debugPrint('[JsRuntime] crypto-js ($c): $result');
      if (result == 'ok') {
        _cryptoReady = true;
        debugPrint('[JsRuntime] ✓ crypto-js listo');
        return;
      }
    }
    debugPrint('[JsRuntime] ✗ crypto-js no se pudo cargar');
  }

  // ---------------------------------------------------------------- cheerio

  Future<void> ensureCheerio() async {
    if (_cheerioReady) return;
    await ensureReady();
    final pending = _cheerioFuture ??= _loadCheerio();
    try {
      await pending;
    } finally {
      if (!_cheerioReady) _cheerioFuture = null;
    }
  }

  Future<void> _loadCheerio() async {
    if (_run("typeof globalThis.__cheerio !== 'undefined' ? 'yes' : 'no'") == 'yes') {
      _cheerioReady = true;
      return;
    }
    String src;
    try {
      src = await rootBundle.loadString(_cheerioAsset);
    } catch (e) {
      debugPrint('[JsRuntime] ✗ falta asset $_cheerioAsset ($e). '
          'Agrégalo en pubspec.yaml (assets/js/).');
      return;
    }
    final result = _run(_libLoaderJs(src, 'cheerio'));
    debugPrint('[JsRuntime] cheerio: $result');
    if (result == 'ok') {
      _cheerioReady = true;
      debugPrint('[JsRuntime] ✓ cheerio listo');
    } else {
      debugPrint('[JsRuntime] ✗ cheerio no se pudo cargar');
    }
  }

  /// Ejecuta un bundle (IIFE con global-name __libExport, o UMD) dentro de una
  /// función con `module`/`exports` locales, para que no dependa de globals.
  String _libLoaderJs(String src, String kind) {
    final srcLit = jsonEncode(src);
    final verify = kind == 'CryptoJS'
        ? "if (lib && lib.AES) { globalThis.CryptoJS = lib; return 'ok'; } return 'no-cryptojs';"
        : "var c = null; var cand = [lib, lib && lib.default, lib && lib.cheerio]; "
            "for (var i = 0; i < cand.length; i++) { if (cand[i] && typeof cand[i].load === 'function') { c = cand[i]; break; } } "
            "if (!c) return 'no-api'; "
            "var t = c.load('<div><a class=\"x\">hi</a></div>')('a.x').text(); "
            "if (t !== 'hi') return 'bad-smoke:' + t; "
            "globalThis.__cheerio = c; return 'ok';";
    return '''
(function () {
  try {
    var src = $srcLit;
    var m = { exports: {} };
    var fn = new Function('module', 'exports', 'define', 'require',
      src + '\\n;return (typeof __libExport !== "undefined") ? __libExport : ((module.exports && Object.keys(module.exports).length) ? module.exports : globalThis.CryptoJS);');
    var lib = fn.call(globalThis, m, m.exports, undefined, undefined);
    $verify
  } catch (e) {
    return 'err:' + String(e && e.message ? e.message : e);
  }
})();
''';
  }

  Future<String?> _download(String url, {int seconds = 20}) async {
    try {
      debugPrint('[JsRuntime] Descargando: $url');
      final res = await http.get(Uri.parse(url)).timeout(Duration(seconds: seconds));
      if (res.statusCode != 200) return null;
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('[JsRuntime] descarga falló ($url): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- addons

  Future<void> loadAddonCode(String addonId, String code) async {
    await ensureReady();

    // Mismo código ya cargado: no re-evaluar.
    if (_loaded.contains(addonId) && _codeHash[addonId] == code.hashCode) return;

    final needsCrypto = code.contains('crypto-js') ||
        code.contains('CryptoJS') ||
        code.contains("require('crypto") ||
        code.contains('require("crypto');
    final needsCheerio = code.contains('cheerio');

    if (needsCrypto) {
      await ensureCryptoJs();
      if (!_cryptoReady) {
        debugPrint('[JsRuntime] AVISO: $addonId necesita crypto-js pero no cargó');
      }
    }
    if (needsCheerio) {
      await ensureCheerio();
      if (!_cheerioReady) {
        debugPrint('[JsRuntime] AVISO: $addonId necesita cheerio pero no cargó');
      }
    }

    final idLit = jsonEncode(addonId);
    final srcLit = jsonEncode(code);

    final wrapped = '''
(function () {
  var module = { exports: {} };
  var exports = module.exports;
  try {
    delete globalThis.getStreams;
    var __src = $srcLit;
    eval(__src);
    var __exp = module.exports;
    if (__exp && __exp.default && typeof __exp.default === 'object') __exp = __exp.default;

    var __has = !!__exp && (typeof __exp === 'function' ||
      typeof __exp.getStreams === 'function' || typeof __exp.stream === 'function' ||
      (__exp.default && typeof __exp.default === 'function'));
    if (!__has) {
      if (typeof globalThis.getStreams === 'function') {
        __exp = { getStreams: globalThis.getStreams };
      } else if (typeof getStreams === 'function') {
        __exp = { getStreams: getStreams };
      }
    }
    delete globalThis.getStreams;
    globalThis.__addons[$idLit] = __exp;
    return typeof __exp;
  } catch (err) {
    var msg = String(err && err.message ? err.message : err);
    globalThis.__addons[$idLit] = { __loadError: msg };
    throw err;
  }
})();
''';

    final result = _rt!.evaluate(wrapped);
    if (result.isError) {
      throw Exception('No se pudo cargar el addon JS: ${result.stringResult}');
    }

    final errCheck = _run(
      'globalThis.__addons[$idLit] && globalThis.__addons[$idLit].__loadError',
    );
    if (errCheck.isNotEmpty && errCheck != 'null' && errCheck != 'undefined' && errCheck != 'false') {
      throw Exception('Addon JS falló al iniciar: $errCheck');
    }

    _loaded.add(addonId);
    _codeHash[addonId] = code.hashCode;
    debugPrint('[JsRuntime] Addon cargado: $addonId');
  }

  bool isLoaded(String addonId) => _loaded.contains(addonId);

  Future<List<StreamItem>> callGetStreams({
    required String addonId,
    required String tmdbId,
    required String type,
    int? season,
    int? episode,
    String? addonName,
  }) async {
    await ensureReady();
    final rt = _rt!;
    if (!_loaded.contains(addonId)) {
      debugPrint('[JsRuntime] Addon no cargado: $addonId');
      return [];
    }

    final idLit = jsonEncode(addonId);
    final tmdbLit = jsonEncode(tmdbId);
    final typeLit = jsonEncode(type);
    final seasonLit = season == null ? 'null' : '$season';
    final episodeLit = episode == null ? 'null' : '$episode';

    final script = '''
(async function() {
  var addon = globalThis.__addons[$idLit];
  if (!addon) return JSON.stringify({ error: 'addon missing' });
  if (addon.__loadError) return JSON.stringify({ error: addon.__loadError });

  var fn = null;
  if (typeof addon.getStreams === 'function') fn = addon.getStreams;
  else if (typeof addon.stream === 'function') fn = addon.stream;
  else if (addon.default && typeof addon.default.getStreams === 'function') fn = addon.default.getStreams;
  else if (addon.default && typeof addon.default === 'function') fn = addon.default;
  else if (typeof addon === 'function') fn = addon;

  if (!fn) {
    var keys = [];
    try { keys = Object.keys(addon); } catch(e) {}
    return JSON.stringify({ error: 'getStreams not found / not a function', keys: keys });
  }

  try {
    var result = await fn.call(addon, $tmdbLit, $typeLit, $seasonLit, $episodeLit);
    return JSON.stringify({ ok: true, data: result });
  } catch (e) {
    return JSON.stringify({ error: String(e && e.message ? e.message : e) });
  }
})()
''';

    try {
      final asyncEval = await rt.evaluateAsync(script);
      try {
        rt.executePendingJob();
      } catch (_) {}

      final resolved = await rt
          .handlePromise(asyncEval)
          .timeout(const Duration(seconds: 30));

      if (resolved.isError) {
        debugPrint('[JsRuntime] $addonId promise error: ${resolved.stringResult}');
        return [];
      }
      return _parseResult(resolved.stringResult, addonId, addonName);
    } on TimeoutException {
      debugPrint('[JsRuntime] $addonId: getStreams timeout (30s)');
      return [];
    } catch (e, st) {
      debugPrint('[JsRuntime] callGetStreams($addonId): $e\n$st');
      return [];
    }
  }

  // ---------------------------------------------------------------- parse

  String _clean(String s) =>
      s.replaceAll('[object Promise]', '').replaceAll('[object Object]', '').trim();

  List<StreamItem> _parseResult(String raw, String addonId, String? addonName) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      try {
        decoded = jsonDecode(jsonDecode(raw) as String);
      } catch (_) {
        debugPrint('[JsRuntime] no JSON: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
        return [];
      }
    }

    if (decoded is Map && decoded['error'] != null) {
      debugPrint('[JsRuntime] $addonId error: ${decoded['error']} keys=${decoded['keys']}');
      return [];
    }

    dynamic data = decoded;
    if (decoded is Map && decoded.containsKey('data')) data = decoded['data'];

    final list = <dynamic>[];
    if (data is List) {
      list.addAll(data);
    } else if (data is Map) {
      if (data['streams'] is List) {
        list.addAll(data['streams'] as List);
      } else if (data['url'] != null) {
        list.add(data);
      }
    }

    final out = <StreamItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v)));
      final infoHash = (m['infoHash'] ?? m['info_hash'])?.toString();
      var url = (m['url'] ?? m['file'] ?? m['src'] ?? m['magnet'] ?? '').toString().trim();
      if (url.isEmpty && infoHash != null && infoHash.isNotEmpty) {
        url = 'magnet:?xt=urn:btih:$infoHash';
      }
      if (url.isEmpty) continue;
      if (url.startsWith('//')) url = 'https:$url';

      final headers = <String, String>{};
      final h = m['headers'];
      if (h is Map) {
        h.forEach((k, v) {
          if (k != null && v != null) headers['$k'] = '$v';
        });
      }
      final hints = m['behaviorHints'];
      if (hints is Map) {
        final proxy = hints['proxyHeaders'];
        if (proxy is Map) {
          final req = proxy['request'];
          if (req is Map) {
            req.forEach((k, v) {
              if (k != null && v != null) headers['$k'] = '$v';
            });
          }
        }
      }

      final quality = _clean((m['quality'] ?? '').toString());
      final title = _clean((m['title'] ?? m['name'] ?? quality).toString());
      final provider = (m['provider'] ?? m['name'] ?? addonName ?? addonId).toString();
      final isTorrent = url.startsWith('magnet:') || (infoHash != null && infoHash.isNotEmpty);
      final isHls = !isTorrent && url.contains('.m3u8');

      out.add(StreamItem(
        url: url,
        title: title.isEmpty ? provider : title,
        quality: quality.isEmpty ? null : quality,
        provider: provider,
        addonId: addonId,
        headers: headers,
        isHls: isHls,
        infoHash: infoHash,
      ));
    }
    debugPrint('[JsRuntime] $addonId → ${out.length} streams');
    return out;
  }

  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    try {
      _rt?.dispose();
    } catch (_) {}
    _rt = null;
    _ready = false;
    _loaded.clear();
    _codeHash.clear();
    _cryptoReady = false;
    _cheerioReady = false;
    _cryptoFuture = null;
    _cheerioFuture = null;
  }


  /// Llama getHome / search / discover / getMeta del JS del addon.
  Future<dynamic> callCatalogMethod({
    required String addonId,
    required String code,
    required String method,
    Map<String, dynamic> args = const {},
    Map<String, String> config = const {},
  }) async {
    await ensureReady();
    await ensureAddonLoaded(addonId, code);
    final rt = _rt!;

    final idLit = jsonEncode(addonId);
    final methodLit = jsonEncode(method);
    final argsLit = jsonEncode(args);
    final configLit = jsonEncode(config);

    final script = '''
(async function() {
  var addon = (globalThis.__nuvioAddons && globalThis.__nuvioAddons[$idLit])
    || (globalThis.__addons && globalThis.__addons[$idLit])
    || globalThis.__lastAddonExports
    || {};
  var fn = addon[$methodLit];
  if (typeof fn !== 'function' && addon.default) fn = addon.default[$methodLit];
  if (typeof fn !== 'function' && typeof globalThis[$methodLit] === 'function') {
    fn = globalThis[$methodLit];
  }
  if (typeof fn !== 'function') {
    var keys = [];
    try { keys = Object.keys(addon); } catch (e) {}
    return JSON.stringify({ error: 'method not found: ' + $methodLit, keys: keys });
  }
  try {
    var result = await fn.call(addon, $argsLit, $configLit);
    return JSON.stringify({ ok: true, data: result });
  } catch (e) {
    return JSON.stringify({ error: String(e && e.message ? e.message : e) });
  }
})()
''';

    try {
      final asyncEval = await rt.evaluateAsync(script);
      try {
        rt.executePendingJob();
      } catch (_) {}
      final resolved = await rt
          .handlePromise(asyncEval)
          .timeout(const Duration(seconds: 25));
      if (resolved.isError) {
        throw Exception(resolved.stringResult);
      }
      final text = resolved.stringResult;
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        throw Exception(decoded['error'].toString());
      }
      if (decoded is Map && decoded['ok'] == true) return decoded['data'];
      return decoded;
    } on TimeoutException {
      throw Exception('Timeout catalogo ($method)');
    }
  }

  /// Llama extract(embedUrl) del addon si existe.
  Future<Map<String, dynamic>?> callExtract({
    required String addonId,
    required String embedUrl,
  }) async {
    await ensureReady();
    final rt = _rt!;
    if (!_loaded.contains(addonId)) return null;

    final idLit = jsonEncode(addonId);
    final urlLit = jsonEncode(embedUrl);

    final script = '''
(async function() {
  var addon = globalThis.__addons[$idLit]
    || (globalThis.__nuvioAddons && globalThis.__nuvioAddons[$idLit])
    || {};
  var fn = addon.extract || (addon.default && addon.default.extract);
  if (typeof fn !== 'function') {
    return JSON.stringify({ ok: true, data: null, noExtract: true });
  }
  try {
    var result = await fn.call(addon, $urlLit);
    return JSON.stringify({ ok: true, data: result });
  } catch (e) {
    return JSON.stringify({ error: String(e && e.message ? e.message : e) });
  }
})()
''';

    try {
      final asyncEval = await rt.evaluateAsync(script);
      try {
        rt.executePendingJob();
      } catch (_) {}
      final resolved = await rt
          .handlePromise(asyncEval)
          .timeout(const Duration(seconds: 15));
      if (resolved.isError) return null;
      final text = resolved.stringResult;
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) return null;
      if (decoded is Map && decoded['ok'] == true) {
        final data = decoded['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('[JsRuntime] extract($addonId): $e');
      return null;
    }
  }

  JavascriptRuntime? get debugRuntime => _rt;

  Future<void> ensureAddonLoaded(String addonId, String code) async {
    await ensureReady();
    final hash = code.hashCode;
    if (_codeHash[addonId] == hash && _loaded.contains(addonId)) return;

    final idLit = jsonEncode(addonId);
    final sb = StringBuffer();
    sb.writeln('(function(){');
    sb.writeln('var module={exports:{}}; var exports=module.exports;');
    sb.writeln(code);
    sb.writeln('globalThis.__nuvioAddons=globalThis.__nuvioAddons||{};');
    sb.writeln('globalThis.__nuvioAddons[' + idLit + ']=module.exports;');
    sb.writeln('globalThis.__lastAddonExports=module.exports;');
    sb.writeln('return true;})()');
    final r = _rt!.evaluate(sb.toString());
    if (r.isError) {
      debugPrint('[JsRuntime] load addon error: ' + r.stringResult);
    }
    _codeHash[addonId] = hash;
    _loaded.add(addonId);
  }

  /// Evalúa un script async y devuelve el string resultante (puente Kino).
  Future<String?> evaluateAsyncPublic(String script) async {
    await ensureReady();
    final rt = _rt;
    if (rt == null) throw StateError('JS runtime no listo');
    try {
      final asyncEval = await rt.evaluateAsync(script);
      try {
        rt.executePendingJob();
      } catch (_) {}
      final resolved = await rt
          .handlePromise(asyncEval)
          .timeout(const Duration(seconds: 45));
      if (resolved.isError) {
        throw Exception(resolved.stringResult);
      }
      final text = resolved.stringResult;
      if (text.isEmpty) return null;
      // Evitar devolver el toString de un Future no resuelto
      if (text.startsWith('Instance of')) {
        debugPrint('[JS] evaluateAsyncPublic: resultado no resuelto: $text');
        return null;
      }
      return text;
    } catch (e) {
      debugPrint('[JS] evaluateAsyncPublic: $e');
      rethrow;
    }
  }

}

// ignore: constant_identifier_names
const String _polyfillsJs = r'''
(function () {
  var G = globalThis;
  function noop() {}
  function hasH(h, n) { for (var k in h) { if (String(k).toLowerCase() === n) return true; } return false; }

  if (typeof G.self === 'undefined') G.self = G;
  if (typeof G.window === 'undefined') G.window = G;
  if (typeof G.global === 'undefined') G.global = G;
  if (typeof G.console === 'undefined') {
    G.console = { log: noop, warn: noop, error: noop, info: noop, debug: noop, trace: noop };
  }
  if (typeof G.performance === 'undefined') {
    G.performance = { now: function () { return Date.now(); } };
  }
  if (typeof G.process === 'undefined') {
    G.process = {
      env: { NODE_ENV: 'production' }, browser: true, version: 'v18.0.0',
      versions: { node: '18.0.0' }, platform: 'browser',
      nextTick: function (fn) {
        var a = Array.prototype.slice.call(arguments, 1);
        Promise.resolve().then(function () { fn.apply(null, a); });
      },
      cwd: function () { return '/'; }, emitWarning: noop, on: noop
    };
  }

  // ---------- ES extras (por si el QuickJS embebido es viejo) ----------
  if (!String.prototype.replaceAll) {
    Object.defineProperty(String.prototype, 'replaceAll', {
      value: function (s, r) {
        if (s instanceof RegExp) {
          if (!s.global) throw new TypeError('replaceAll must be called with a global RegExp');
          return this.replace(s, r);
        }
        var esc = String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        return this.replace(new RegExp(esc, 'g'), r);
      }, writable: true, configurable: true
    });
  }
  if (!Array.prototype.at) {
    Object.defineProperty(Array.prototype, 'at', {
      value: function (i) { i = Math.trunc(i) || 0; if (i < 0) i += this.length; return this[i]; },
      writable: true, configurable: true
    });
  }
  if (!Object.fromEntries) {
    Object.fromEntries = function (it) {
      var o = {};
      for (var e of it) o[e[0]] = e[1];
      return o;
    };
  }
  if (!Promise.allSettled) {
    Promise.allSettled = function (list) {
      return Promise.all(Array.prototype.map.call(list, function (p) {
        return Promise.resolve(p).then(
          function (v) { return { status: 'fulfilled', value: v }; },
          function (e) { return { status: 'rejected', reason: e }; }
        );
      }));
    };
  }

  // ---------- Timers reales (puente a Dart) ----------
  var timers = {};
  var seq = 1;
  function schedule(id, ms) {
    var p = sendMessage('jsTimer', JSON.stringify({ id: id, ms: ms }));
    if (p && typeof p.catch === 'function') p.catch(noop);
  }
  G.__fireTimer = function (id) {
    var t = timers[id];
    if (!t) return;
    if (t.interval) schedule(id, t.ms); else delete timers[id];
    try { t.fn.apply(null, t.args); } catch (e) {}
  };
  function addTimer(fn, ms, args, interval) {
    if (typeof fn !== 'function') return 0;
    var id = seq++;
    var m = Math.max(0, Number(ms) || 0);
    timers[id] = { fn: fn, ms: m, args: args, interval: interval };
    schedule(id, m);
    return id;
  }
  G.setTimeout = function (fn, ms) { return addTimer(fn, ms, Array.prototype.slice.call(arguments, 2), false); };
  G.setInterval = function (fn, ms) { return addTimer(fn, Math.max(4, Number(ms) || 0), Array.prototype.slice.call(arguments, 2), true); };
  G.setImmediate = function (fn) { return addTimer(fn, 0, Array.prototype.slice.call(arguments, 1), false); };
  G.clearTimeout = G.clearInterval = G.clearImmediate = function (id) { delete timers[id]; };

  // ---------- crypto.getRandomValues ----------
  if (typeof G.crypto === 'undefined' || typeof G.crypto.getRandomValues !== 'function') {
    G.crypto = G.crypto || {};
    G.crypto.getRandomValues = function (arr) {
      if (!arr || typeof arr.length !== 'number') throw new TypeError('Expected typed array');
      for (var i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
      return arr;
    };
  }

  // ---------- atob / btoa ----------
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  if (typeof G.btoa === 'undefined') {
    G.btoa = function (input) {
      var str = String(input), out = '', i = 0;
      while (i < str.length) {
        var c1 = str.charCodeAt(i++), c2 = str.charCodeAt(i++), c3 = str.charCodeAt(i++);
        if (c1 > 255 || c2 > 255 || c3 > 255) throw new Error('btoa: invalid character');
        var e1 = c1 >> 2, e2 = ((c1 & 3) << 4) | (c2 >> 4);
        var e3 = ((c2 & 15) << 2) | (c3 >> 6), e4 = c3 & 63;
        if (isNaN(c2)) { e3 = 64; e4 = 64; } else if (isNaN(c3)) { e4 = 64; }
        out += B64.charAt(e1) + B64.charAt(e2) + B64.charAt(e3) + B64.charAt(e4);
      }
      return out;
    };
  }
  if (typeof G.atob === 'undefined') {
    G.atob = function (input) {
      var str = String(input).replace(/[\s=]+/g, '');
      var out = '', bits = 0, acc = 0;
      for (var i = 0; i < str.length; i++) {
        var idx = B64.indexOf(str.charAt(i));
        if (idx < 0 || idx >= 64) throw new Error('atob: invalid character');
        acc = (acc << 6) | idx; bits += 6;
        if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 255); acc &= (1 << bits) - 1; }
      }
      return out;
    };
  }

  // ---------- TextEncoder / TextDecoder ----------
  if (typeof G.TextEncoder === 'undefined') {
    G.TextEncoder = function () { this.encoding = 'utf-8'; };
    G.TextEncoder.prototype.encode = function (s) {
      var bin = unescape(encodeURIComponent(String(s == null ? '' : s)));
      var u = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
      return u;
    };
  }
  if (typeof G.TextDecoder === 'undefined') {
    G.TextDecoder = function (enc) { this.encoding = enc || 'utf-8'; };
    G.TextDecoder.prototype.decode = function (u) {
      if (!u) return '';
      var a = (u instanceof ArrayBuffer) ? new Uint8Array(u) : u;
      var bin = '';
      for (var i = 0; i < a.length; i++) bin += String.fromCharCode(a[i] & 255);
      try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
    };
  }

  // ---------- Buffer ----------
  if (typeof G.Buffer === 'undefined') {
    var utf8enc = function (s) { return unescape(encodeURIComponent(s)); };
    var utf8dec = function (b) { try { return decodeURIComponent(escape(b)); } catch (e) { return b; } };
    var bytesToBin = function (u) { var s = ''; for (var i = 0; i < u.length; i++) s += String.fromCharCode(u[i] & 255); return s; };
    var binToBytes = function (b) { var u = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) u[i] = b.charCodeAt(i) & 255; return u; };
    var wrap = function (u) {
      Object.defineProperty(u, 'toString', {
        configurable: true,
        value: function (enc) {
          var b = bytesToBin(u);
          enc = String(enc || 'utf8').toLowerCase();
          if (enc === 'base64') return G.btoa(b);
          if (enc === 'hex') {
            var h = '';
            for (var i = 0; i < u.length; i++) h += (u[i] < 16 ? '0' : '') + u[i].toString(16);
            return h;
          }
          if (enc === 'latin1' || enc === 'binary' || enc === 'ascii') return b;
          return utf8dec(b);
        }
      });
      Object.defineProperty(u, 'toJSON', {
        configurable: true,
        value: function () { return { type: 'Buffer', data: Array.prototype.slice.call(u) }; }
      });
      return u;
    };
    G.Buffer = {
      from: function (data, enc) {
        if (typeof data === 'string') {
          enc = String(enc || 'utf8').toLowerCase();
          if (enc === 'base64' || enc === 'base64url') {
            var s = data.replace(/-/g, '+').replace(/_/g, '/');
            while (s.length % 4) s += '=';
            return wrap(binToBytes(G.atob(s)));
          }
          if (enc === 'hex') {
            var u = new Uint8Array(data.length >> 1);
            for (var i = 0; i < u.length; i++) u[i] = parseInt(data.substr(i * 2, 2), 16);
            return wrap(u);
          }
          if (enc === 'latin1' || enc === 'binary' || enc === 'ascii') return wrap(binToBytes(data));
          return wrap(binToBytes(utf8enc(data)));
        }
        if (data instanceof ArrayBuffer) return wrap(new Uint8Array(data.slice(0)));
        if (data && data.length != null) return wrap(new Uint8Array(Array.prototype.slice.call(data)));
        return wrap(new Uint8Array(0));
      },
      alloc: function (n, fill) { var u = new Uint8Array(n | 0); if (fill) u.fill(fill); return wrap(u); },
      isBuffer: function (o) { return !!o && o instanceof Uint8Array && typeof o.toJSON === 'function'; },
      concat: function (list) {
        var t = 0, i;
        for (i = 0; i < list.length; i++) t += list[i].length;
        var u = new Uint8Array(t), off = 0;
        for (i = 0; i < list.length; i++) { u.set(list[i], off); off += list[i].length; }
        return wrap(u);
      },
      byteLength: function (s) { return typeof s === 'string' ? utf8enc(s).length : (s ? s.length : 0); }
    };
  }

  // ---------- URLSearchParams ----------
  if (typeof G.URLSearchParams === 'undefined') {
    var dec = function (s) { try { return decodeURIComponent(String(s).replace(/\+/g, ' ')); } catch (e) { return String(s); } };
    var USP = function (init) {
      var self = this;
      this._list = [];
      if (typeof init === 'string') {
        var s = init.charAt(0) === '?' ? init.slice(1) : init;
        if (s) {
          var parts = s.split('&');
          for (var i = 0; i < parts.length; i++) {
            if (!parts[i]) continue;
            var k = parts[i].indexOf('=');
            if (k < 0) this._list.push([dec(parts[i]), '']);
            else this._list.push([dec(parts[i].slice(0, k)), dec(parts[i].slice(k + 1))]);
          }
        }
      } else if (init && typeof init === 'object') {
        if (init._list) {
          this._list = init._list.map(function (p) { return [p[0], p[1]]; });
        } else if (Array.isArray(init)) {
          init.forEach(function (p) { self._list.push([String(p[0]), String(p[1])]); });
        } else {
          Object.keys(init).forEach(function (k) { self._list.push([k, init[k] == null ? '' : String(init[k])]); });
        }
      }
    };
    USP.prototype.append = function (k, v) { this._list.push([String(k), v == null ? '' : String(v)]); };
    USP.prototype.set = function (k, v) {
      var key = String(k), found = false, out = [];
      for (var i = 0; i < this._list.length; i++) {
        if (this._list[i][0] === key) { if (!found) { out.push([key, v == null ? '' : String(v)]); found = true; } }
        else out.push(this._list[i]);
      }
      if (!found) out.push([key, v == null ? '' : String(v)]);
      this._list = out;
    };
    USP.prototype.get = function (k) {
      var key = String(k);
      for (var i = 0; i < this._list.length; i++) if (this._list[i][0] === key) return this._list[i][1];
      return null;
    };
    USP.prototype.getAll = function (k) {
      var key = String(k);
      return this._list.filter(function (p) { return p[0] === key; }).map(function (p) { return p[1]; });
    };
    USP.prototype.has = function (k) { return this.get(k) !== null; };
    USP.prototype['delete'] = function (k) { var key = String(k); this._list = this._list.filter(function (p) { return p[0] !== key; }); };
    USP.prototype.forEach = function (cb, thisArg) { this._list.forEach(function (p) { cb.call(thisArg, p[1], p[0]); }); };
    USP.prototype.keys = function () { return this._list.map(function (p) { return p[0]; })[Symbol.iterator](); };
    USP.prototype.values = function () { return this._list.map(function (p) { return p[1]; })[Symbol.iterator](); };
    USP.prototype.entries = function () { return this._list.map(function (p) { return [p[0], p[1]]; })[Symbol.iterator](); };
    USP.prototype[Symbol.iterator] = USP.prototype.entries;
    USP.prototype.toString = function () {
      return this._list.map(function (p) { return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]); }).join('&');
    };
    G.URLSearchParams = USP;
  }

  // ---------- URL ----------
  if (typeof G.URL === 'undefined') {
    G.URL = function URL(url, base) {
      var full = String(url);
      if (!/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(full) && base) {
        var b = String(base);
        var bm = b.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*:)\/\/([^\/?#]*)([^?#]*)/);
        if (bm) {
          var origin = bm[1] + '//' + bm[2];
          if (full.indexOf('//') === 0) full = bm[1] + full;
          else if (full.charAt(0) === '/') full = origin + full;
          else if (full.charAt(0) === '?' || full.charAt(0) === '#') full = origin + bm[3] + full;
          else full = origin + bm[3].replace(/[^\/]*$/, '') + full;
        }
      }
      var m = full.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*:)\/\/(?:([^@\/?#]*)@)?([^\/?#:]*)(?::(\d+))?([^?#]*)(\?[^#]*)?(#.*)?$/);
      if (m) {
        this.protocol = m[1].toLowerCase();
        this.username = m[2] ? m[2].split(':')[0] : '';
        this.password = m[2] && m[2].indexOf(':') >= 0 ? m[2].slice(m[2].indexOf(':') + 1) : '';
        this.hostname = m[3].toLowerCase();
        this.port = m[4] || '';
        this.host = this.hostname + (this.port ? ':' + this.port : '');
        this.pathname = m[5] || '/';
        this.search = m[6] && m[6] !== '?' ? m[6] : '';
        this.hash = m[7] && m[7] !== '#' ? m[7] : '';
        this.origin = this.protocol + '//' + this.host;
        this.href = this.protocol + '//' + (m[2] ? m[2] + '@' : '') + this.host + this.pathname + this.search + this.hash;
      } else {
        var o = full.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*:)(.*)$/);
        if (!o) throw new TypeError('Invalid URL: ' + full);
        this.protocol = o[1].toLowerCase(); this.username = ''; this.password = '';
        this.hostname = ''; this.port = ''; this.host = ''; this.pathname = o[2];
        this.search = ''; this.hash = ''; this.origin = 'null'; this.href = full;
      }
      this.searchParams = new G.URLSearchParams(this.search);
    };
    G.URL.prototype.toString = function () { return this.href; };
    G.URL.prototype.toJSON = function () { return this.href; };
  }

  // ---------- AbortController ----------
  if (typeof G.AbortController === 'undefined') {
    G.AbortSignal = function () { this.aborted = false; this.reason = undefined; this._l = []; };
    G.AbortSignal.prototype.addEventListener = function (t, f) { if (t === 'abort') this._l.push(f); };
    G.AbortSignal.prototype.removeEventListener = function (t, f) { this._l = this._l.filter(function (x) { return x !== f; }); };
    G.AbortSignal.prototype.throwIfAborted = function () { if (this.aborted) throw this.reason; };
    G.AbortSignal.timeout = function (ms) {
      var c = new G.AbortController();
      G.setTimeout(function () { c.abort(); }, ms);
      return c.signal;
    };
    G.AbortController = function () { this.signal = new G.AbortSignal(); };
    G.AbortController.prototype.abort = function (reason) {
      var s = this.signal;
      if (s.aborted) return;
      s.aborted = true; s.reason = reason;
      var ev = { type: 'abort', target: s };
      if (typeof s.onabort === 'function') { try { s.onabort(ev); } catch (e) {} }
      s._l.forEach(function (f) { try { f(ev); } catch (e) {} });
    };
  }

  // ---------- fetch ----------
  function makeResponse(data, url) {
    var raw = data.headers || {};
    var lower = {};
    Object.keys(raw).forEach(function (k) { lower[String(k).toLowerCase()] = raw[k]; });
    var hdrs = {
      _raw: lower,
      get: function (n) { var v = lower[String(n).toLowerCase()]; return v === undefined ? null : v; },
      has: function (n) { return lower[String(n).toLowerCase()] !== undefined; },
      forEach: function (cb) { Object.keys(lower).forEach(function (k) { cb(lower[k], k); }); }
    };
    var body = data.body == null ? '' : String(data.body);
    var status = data.status | 0;
    return {
      ok: !!data.ok, status: status, statusText: status === 200 ? 'OK' : '',
      url: data.url || String(url), redirected: !!data.redirected, type: 'basic',
      bodyUsed: false, headers: hdrs,
      text: function () { return Promise.resolve(body); },
      json: function () {
        var t = body.trim();
        if (t.charAt(0) === '<') {
          var snip = t.slice(0, 80).replace(/\s+/g, ' ');
          return Promise.reject(new Error('Response is HTML, not JSON (status ' + status + ', url ' + (data.url || url) + ', starts: ' + snip + ')'));
        }
        try { return Promise.resolve(JSON.parse(t || 'null')); } catch (e) { return Promise.reject(e); }
      },
      arrayBuffer: function () { return Promise.resolve(new G.TextEncoder().encode(body).buffer); },
      clone: function () { return makeResponse(data, url); }
    };
  }
  function abortError() { var e = new Error('The operation was aborted'); e.name = 'AbortError'; return e; }

  G.fetch = function fetch(url, options) {
    options = options || {};
    var method = String(options.method || 'GET').toUpperCase();
    var headers = {};
    var h = options.headers;
    if (h) {
      if (Array.isArray(h)) h.forEach(function (p) { headers[p[0]] = p[1]; });
      else if (typeof h.forEach === 'function' && !h._raw && typeof h.get === 'function') h.forEach(function (v, k) { headers[k] = v; });
      else if (h._raw) { Object.keys(h._raw).forEach(function (k) { headers[k] = h._raw[k]; }); }
      else Object.keys(h).forEach(function (k) { headers[k] = h[k]; });
    }
    var body = options.body;
    if (body != null && typeof body === 'object') {
      if (body instanceof G.URLSearchParams) {
        body = body.toString();
        if (!hasH(headers, 'content-type')) headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
      } else {
        body = String(body);
      }
    }
    var sig = options.signal;
    if (sig && sig.aborted) return Promise.reject(abortError());
    var payload = JSON.stringify({
      url: String(url), method: method, headers: headers,
      body: body == null ? null : body, redirect: options.redirect || 'follow'
    });
    var p = sendMessage('httpFetch', payload).then(function (raw) {
      var data = (typeof raw === 'string') ? JSON.parse(raw) : raw;
      if (!data) return Promise.reject(new TypeError('fetch failed'));
      if (data.error && !data.status) return Promise.reject(new TypeError('fetch failed: ' + data.error));
      return makeResponse(data, url);
    });
    if (!sig) return p;
    return new Promise(function (resolve, reject) {
      var done = false;
      sig.addEventListener('abort', function () { if (!done) { done = true; reject(abortError()); } });
      p.then(function (v) { if (!done) { done = true; resolve(v); } },
             function (e) { if (!done) { done = true; reject(e); } });
    });
  };

  // ---------- axios mínimo ----------
  function buildUrl(url, params) {
    if (!params) return url;
    var q = new G.URLSearchParams();
    Object.keys(params).forEach(function (k) { if (params[k] != null) q.append(k, params[k]); });
    var s = q.toString();
    return s ? url + (url.indexOf('?') < 0 ? '?' : '&') + s : url;
  }
  function axiosReq(cfg) {
    var method = String(cfg.method || 'get').toUpperCase();
    var headers = Object.assign({}, cfg.headers || {});
    var body = cfg.data;
    var url = String(cfg.url || '');
    if (cfg.baseURL && !/^https?:/i.test(url)) url = String(cfg.baseURL).replace(/\/$/, '') + '/' + url.replace(/^\//, '');
    url = buildUrl(url, cfg.params);
    if (body != null && typeof body === 'object' && !(body instanceof G.URLSearchParams)) {
      body = JSON.stringify(body);
      if (!hasH(headers, 'content-type')) headers['Content-Type'] = 'application/json';
    }
    return G.fetch(url, { method: method, headers: headers, body: body, signal: cfg.signal }).then(function (r) {
      return r.text().then(function (t) {
        var data = t;
        if (cfg.responseType !== 'text') {
          var tt = t.trim(), c = tt.charAt(0);
          if (c === '{' || c === '[') { try { data = JSON.parse(tt); } catch (e) {} }
        }
        var res = { data: data, status: r.status, statusText: r.statusText, headers: r.headers._raw || {}, config: cfg, request: {} };
        var ok = cfg.validateStatus ? cfg.validateStatus(r.status) : (r.status >= 200 && r.status < 300);
        if (!ok) {
          var err = new Error('Request failed with status code ' + r.status);
          err.response = res; err.config = cfg; err.isAxiosError = true; err.code = 'ERR_BAD_RESPONSE';
          return Promise.reject(err);
        }
        return res;
      });
    });
  }
  function makeAxios(defs) {
    defs = defs || {};
    function merge(cfg) {
      var o = Object.assign({}, defs, cfg || {});
      o.headers = Object.assign({}, defs.headers || {}, (cfg && cfg.headers) || {});
      return o;
    }
    var inst = function (cfg, cfg2) {
      return typeof cfg === 'string' ? axiosReq(merge(Object.assign({ url: cfg }, cfg2))) : axiosReq(merge(cfg));
    };
    inst.request = function (cfg) { return axiosReq(merge(cfg)); };
    ['get', 'delete', 'head', 'options'].forEach(function (m) {
      inst[m] = function (url, cfg) { return axiosReq(merge(Object.assign({}, cfg, { url: url, method: m }))); };
    });
    ['post', 'put', 'patch'].forEach(function (m) {
      inst[m] = function (url, data, cfg) { return axiosReq(merge(Object.assign({}, cfg, { url: url, data: data, method: m }))); };
    });
    inst.create = function (d) { return makeAxios(Object.assign({}, defs, d)); };
    inst.defaults = { headers: {} };
    inst.isAxiosError = function (e) { return !!(e && e.isAxiosError); };
    return inst;
  }
  G.__axios = makeAxios({});
  G.__axios['default'] = G.__axios;

  // ---------- require ----------
  G.require = function require(name) {
    name = String(name || '').replace(/^node:/, '');
    if (name === 'crypto-js' || name === 'crypto') {
      if (G.CryptoJS) return G.CryptoJS;
      throw new Error('crypto-js not loaded yet');
    }
    if (name.indexOf('cheerio') === 0) {
      if (G.__cheerio) return G.__cheerio;
      // Carga perezosa: el addon inicia y solo falla si realmente usa cheerio.
      var lazy = {
        load: function () {
          var c = G.__cheerio;
          if (!c) throw new Error('cheerio no esta cargado (falta assets/js/cheerio.bundle.js)');
          return c.load.apply(c, arguments);
        }
      };
      lazy['default'] = lazy;
      return lazy;
    }
    if (name === 'axios') return G.__axios;
    if (name === 'url') return { URL: G.URL, URLSearchParams: G.URLSearchParams };
    if (name === 'buffer') return { Buffer: G.Buffer };
    if (name === 'querystring') {
      return {
        parse: function (s) { var o = {}; new G.URLSearchParams(s).forEach(function (v, k) { o[k] = v; }); return o; },
        stringify: function (o) { return new G.URLSearchParams(o).toString(); }
      };
    }
    throw new Error("Module '" + name + "' is not available");
  };

  G.__addons = G.__addons || {};

})();
''';
