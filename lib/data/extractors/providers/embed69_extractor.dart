import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Servicio que scrapea enlaces desde SeriesKao / Xupalace (Embed69)
class Embed69Service {
  Embed69Service._();

  static const _kBaseUrlSeriesKao = 'https://serieskao.top/vidurl/';
  static const _kBaseUrlXupalace = 'https://xupalace.org/video/';
  static const _kTmdbApiKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _kTmdbBase = 'https://api.themoviedb.org/3';

  // Usado como fallback cuando TMDB no tiene el imdb_id mapeado
  // (muy común en series nuevas o poco populares).
  static const _kOmdbApiKey = '5b0e8a3e';
  static const _kOmdbBase = 'http://www.omdbapi.com/';

  // Ponelo en true si necesitás ver en consola por qué falla la resolución
  // del imdb_id (útil para debug real contra la API, algo que acá no
  // podemos ejecutar).
  static const bool _debug = false;

  static void _log(String msg) {
    if (_debug) {
      // ignore: avoid_print
      print('[Embed69Service] $msg');
    }
  }

  static Stream<Embed69Server> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) {
      throw Exception('tmdb_id inválido');
    }

    final type = isMovie ? 'movie' : 'tv';
    final imdbId = await _getImdbFromTmdb(tmdbId, type);
    if (imdbId == null || imdbId.isEmpty) {
      throw Exception(
        'No se pudo obtener el IMDb ID desde TMDB para el ID: $tmdbId ($type)',
      );
    }

    // Variantes de ID que usan SeriesKao / Xupalace en series
    final idVariants = <String>[];
    if (isMovie) {
      idVariants.add(imdbId);
    } else {
      final s = season;
      final e = episode;
      final e2 = e.toString().padLeft(2, '0');
      final s2 = s.toString().padLeft(2, '0');
      // Formatos más comunes primero
      idVariants.addAll([
        '$imdbId-${s}x$e2', // tt123-1x01
        '$imdbId-${s}x$e', // tt123-1x1
        '$imdbId-$s2' 'x$e2', // tt123-01x01
        '$imdbId-$s-$e2', // tt123-1-01
        '$imdbId-$s-$e', // tt123-1-1
      ]);
    }

    List<Embed69Server>? result;

    for (final idCompleto in idVariants) {
      result = await _fetchFromSeriesKao(
        idCompleto,
        season,
        episode,
        imdbId,
        tmdbId,
      );
      if (result != null && result.isNotEmpty) break;

      result = await _fetchFromXupalace(
        idCompleto,
        season,
        episode,
        imdbId,
        tmdbId,
      );
      if (result != null && result.isNotEmpty) break;
    }

    if (result == null || result.isEmpty) {
      throw Exception('No se encontraron enlaces para el contenido');
    }

    for (final server in result) {
      yield server;
    }
  }

  // ─── Obtener IMDb desde TMDB (robusto para movie y tv) ─────────────────

  static Future<String?> _getImdbFromTmdb(int tmdbId, String type) async {
    // 1) Endpoint oficial external_ids
    var imdb = await _parseImdbFromTmdbResponse(
      '$_kTmdbBase/$type/$tmdbId/external_ids?api_key=$_kTmdbApiKey',
    );
    if (imdb != null) return imdb;

    // 2) Detalle con append_to_response=external_ids
    imdb = await _parseImdbFromTmdbResponse(
      '$_kTmdbBase/$type/$tmdbId?api_key=$_kTmdbApiKey&append_to_response=external_ids',
    );
    if (imdb != null) return imdb;

    // 3) Solo en TV: a veces el imdb está en el detalle sin append
    if (type == 'tv') {
      imdb = await _parseImdbFromTmdbResponse(
        '$_kTmdbBase/tv/$tmdbId?api_key=$_kTmdbApiKey',
      );
      if (imdb != null) return imdb;
    }

    // 4) Fallback final: TMDB no siempre tiene el imdb_id mapeado para
    //    series (pasa bastante seguido, sobre todo en shows nuevos).
    //    Buscamos en OMDB por título + año como último recurso.
    imdb = await _getImdbFromOmdbByTitle(tmdbId, type);
    if (imdb != null) return imdb;

    _log('No se pudo resolver imdb_id para tmdbId=$tmdbId type=$type '
        'ni por TMDB ni por OMDB (título).');

    return null;
  }

  static Future<String?> _parseImdbFromTmdbResponse(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _log('TMDB respondió ${response.statusCode} para $url');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      if (data['success'] == false) {
        _log('TMDB devolvió success=false para $url '
            '(${data['status_message']})');
        return null;
      }

      // imdb_id directo
      final direct = _normalizeImdb(data['imdb_id']);
      if (direct != null) return direct;

      // nested external_ids.imdb_id
      final ext = data['external_ids'];
      if (ext is Map) {
        final nested = _normalizeImdb(ext['imdb_id']);
        if (nested != null) return nested;
      }

      return null;
    } catch (e) {
      _log('Excepción consultando $url: $e');
      return null;
    }
  }

  /// Último recurso: TMDB a veces no tiene el imdb_id mapeado para series.
  /// Buscamos en OMDB por título + año (usando los datos del propio TMDB).
  static Future<String?> _getImdbFromOmdbByTitle(
    int tmdbId,
    String type,
  ) async {
    try {
      final detailUrl = '$_kTmdbBase/$type/$tmdbId?api_key=$_kTmdbApiKey';
      final response = await http
          .get(
            Uri.parse(detailUrl),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      final title =
          (type == 'movie' ? data['title'] : data['name'])?.toString();
      if (title == null || title.trim().isEmpty) return null;

      final dateStr =
          (type == 'movie' ? data['release_date'] : data['first_air_date'])
              ?.toString();
      final year =
          (dateStr != null && dateStr.length >= 4) ? dateStr.substring(0, 4) : null;

      final omdbType = type == 'movie' ? 'movie' : 'series';
      final queryParams = <String, String>{
        'apikey': _kOmdbApiKey,
        't': title,
        'type': omdbType,
        if (year != null) 'y': year,
      };

      final omdbUrl = Uri.parse(_kOmdbBase).replace(queryParameters: queryParams);
      final omdbResponse =
          await http.get(omdbUrl).timeout(const Duration(seconds: 15));

      if (omdbResponse.statusCode != 200) return null;

      final omdbData = jsonDecode(omdbResponse.body);
      if (omdbData is! Map<String, dynamic>) return null;
      if (omdbData['Response'] == 'False') {
        _log('OMDB no encontró "$title" ($year): ${omdbData['Error']}');
        return null;
      }

      return _normalizeImdb(omdbData['imdbID']);
    } catch (e) {
      _log('Excepción buscando en OMDB por título: $e');
      return null;
    }
  }

  /// Acepta solo IDs válidos tipo tt1234567
  static String? _normalizeImdb(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return null;
    // Algunos devuelven solo el número
    if (RegExp(r'^tt\d+$').hasMatch(s)) return s;
    if (RegExp(r'^\d+$').hasMatch(s)) return 'tt$s';
    // Extraer tt... si viene embebido
    final m = RegExp(r'(tt\d+)').firstMatch(s);
    return m?.group(1);
  }

  // ─── SeriesKao ────────────────────────────────────────────────────────────

  static Future<List<Embed69Server>?> _fetchFromSeriesKao(
    String idCompleto,
    int season,
    int episode,
    String imdbId,
    int tmdbId,
  ) async {
    final url = '$_kBaseUrlSeriesKao$idCompleto/';

    final html = await _fetchPage(url, source: 'serieskao');
    if (html == null) return null;

    final dataLink = _extractDataLink(html);
    if (dataLink == null) return null;

    final powConstants = _extractPowConstants(html);
    if (powConstants['challenge'] == null) return null;

    final nonce = _solvePow(
      powConstants['challenge']!,
      powConstants['difficulty'] ?? 3,
    );
    if (nonce == null) return null;

    final aesKey = _generateAesKey(
      powConstants['challenge']!,
      nonce,
      powConstants['salt'] ?? '',
    );

    final servers = _procesarEnlacesSeriesKao(
      dataLink,
      aesKey,
      imdbId,
      tmdbId,
      season,
      episode,
    );

    if (servers.isEmpty) return null;
    return servers;
  }

  // ─── Xupalace ─────────────────────────────────────────────────────────────

  static Future<List<Embed69Server>?> _fetchFromXupalace(
    String idCompleto,
    int season,
    int episode,
    String imdbId,
    int tmdbId,
  ) async {
    final url = '$_kBaseUrlXupalace$idCompleto/';

    final html = await _fetchPage(url, source: 'xupalace');
    if (html == null) return null;

    final enlaces = _extractEnlacesXupalace(html);
    if (enlaces.isEmpty) return null;

    final servers = _procesarEnlacesXupalace(
      enlaces,
      imdbId,
      tmdbId,
      season,
      episode,
    );

    if (servers.isEmpty) return null;
    return servers;
  }

  // ─── Fetch página ────────────────────────────────────────────────────────

  static Future<String?> _fetchPage(
    String url, {
    required String source,
  }) async {
    try {
      final headers = {
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
      };

      if (source == 'serieskao') {
        headers['Referer'] = 'https://serieskao.top/';
        headers['Origin'] = 'https://serieskao.top';
      } else {
        headers['Referer'] = 'https://xupalace.org/';
        headers['Origin'] = 'https://xupalace.org';
      }

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (_) {}

    return null;
  }

  // ─── Extraer dataLink ────────────────────────────────────────────────────

  static List<Map<String, dynamic>>? _extractDataLink(String html) {
    final patterns = [
      r'let\s+dataLink\s*=\s*(\[.*?\]);',
      r'dataLink\s*=\s*(\[.*?\]);',
      r'<script>.*?dataLink\s*=\s*(\[.*?\]);.*?</script>',
    ];

    for (final pattern in patterns) {
      final re = RegExp(pattern, dotAll: true, caseSensitive: false);
      final match = re.firstMatch(html);
      if (match != null) {
        final jsonStr = match.group(1)?.replaceAll(r'\"', '"') ?? '';
        try {
          return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
        } catch (_) {}
      }
    }

    return null;
  }

  // ─── Extraer constantes PoW ─────────────────────────────────────────────

  static Map<String, dynamic> _extractPowConstants(String html) {
    final constants = <String, dynamic>{};

    final challengeRe = RegExp(
      r'''POW_CHALLENGE\s*=\s*['"]?([a-f0-9]+)['"]?''',
    );
    final challengeMatch = challengeRe.firstMatch(html);
    if (challengeMatch != null) {
      constants['challenge'] = challengeMatch.group(1);
    }

    final saltRe = RegExp(
      r'''POW_SALT\s*=\s*['"]?([a-f0-9]+)['"]?''',
    );
    final saltMatch = saltRe.firstMatch(html);
    if (saltMatch != null) {
      constants['salt'] = saltMatch.group(1);
    }

    final difficultyRe = RegExp(r'POW_DIFFICULTY\s*=\s*(\d+)');
    final difficultyMatch = difficultyRe.firstMatch(html);
    if (difficultyMatch != null) {
      constants['difficulty'] =
          int.tryParse(difficultyMatch.group(1) ?? '') ?? 3;
    }

    return constants;
  }

  // ─── Resolver PoW ────────────────────────────────────────────────────────

  static int? _solvePow(String challenge, int difficulty) {
    final prefix = '0' * difficulty;

    for (var nonce = 0; nonce < 1000000; nonce++) {
      final hash = _sha256('$challenge$nonce');
      if (hash.startsWith(prefix)) {
        return nonce;
      }
    }

    return null;
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ─── Generar clave AES ──────────────────────────────────────────────────
  //
  // FIX: el PHP que sí funciona usa hash('sha256', ..., true) → los 32
  // BYTES BINARIOS crudos del digest como clave AES-256. Antes acá se
  // tomaba el string HEXADECIMAL del hash y se cortaban los primeros 32
  // caracteres, lo cual arma una clave totalmente distinta (y más débil).
  // Ahora devolvemos los bytes crudos, igual que el PHP.
  static Uint8List _generateAesKey(String challenge, int nonce, String salt) {
    final digest = sha256.convert(utf8.encode('$challenge$nonce$salt'));
    return Uint8List.fromList(digest.bytes);
  }

  // ─── Descifrar AES ──────────────────────────────────────────────────────
  //
  // FIX: esto antes NO descifraba nada — solo hacía base64Decode y
  // comprobaba si el resultado, leído como texto plano, contenía "http".
  // Como el payload real está cifrado con AES-256-CBC (igual que el PHP
  // con openssl_decrypt(..., 'aes-256-cbc', $aesKey, OPENSSL_RAW_DATA,
  // $iv)), esa condición prácticamente nunca se cumplía. Ahora se hace el
  // descifrado real: los primeros 16 bytes del base64 decodeado son el
  // IV, el resto es el ciphertext (con padding PKCS7, que la librería
  // `encrypt` remueve automáticamente, igual que hace OpenSSL por
  // default).
  static String? _decryptAES(String encryptedBase64, Uint8List aesKey) {
    try {
      final raw = base64Decode(encryptedBase64);
      if (raw.length <= 16) return null;

      final ivBytes = raw.sublist(0, 16);
      final cipherBytes = raw.sublist(16);

      final key = enc.Key(aesKey);
      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final decryptedBytes = encrypter.decryptBytes(
        enc.Encrypted(Uint8List.fromList(cipherBytes)),
        iv: iv,
      );

      final text = utf8.decode(decryptedBytes, allowMalformed: true);
      if (text.contains('http')) {
        return text;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Procesar enlaces SeriesKao ─────────────────────────────────────────

  static List<Embed69Server> _procesarEnlacesSeriesKao(
    List<Map<String, dynamic>> dataLink,
    Uint8List aesKey,
    String imdbId,
    int tmdbId,
    int season,
    int episode,
  ) {
    final results = <Embed69Server>[];
    final servidoresFiltrados = ['voe', 'rapidvideo'];

    for (final item in dataLink) {
      final idioma = item['video_language']?.toString() ?? 'DESCONOCIDO';
      final idiomaNormalizado = _normalizarIdioma(idioma);

      if (item['sortedEmbeds'] != null) {
        final embeds = List<Map<String, dynamic>>.from(item['sortedEmbeds']);
        for (final embed in embeds) {
          final servidor =
              embed['servername']?.toString().toLowerCase() ?? '';

          if (servidoresFiltrados.contains(servidor)) continue;

          final enlaceCifrado = embed['link']?.toString() ?? '';
          if (enlaceCifrado.isEmpty) continue;

          var urlReal = _decryptAES(enlaceCifrado, aesKey);
          if (urlReal == null) continue;

          urlReal = urlReal
              .replaceAll('`', '')
              .replaceAll('hglink.to', 'vibuxer.com')
              .replaceAll('filelions.to', 'callistanise.com');

          results.add(
            Embed69Server(
              serverName: servidor.isNotEmpty ? servidor : 'desconocido',
              url: urlReal,
              calidad: 'Digital',
              idioma: idiomaNormalizado,
              imdbId: imdbId,
              tmdbId: tmdbId,
              season: season,
              episode: episode,
              fuente: 'serieskao',
            ),
          );
        }
      }
    }

    return results;
  }

  // ─── Extraer enlaces Xupalace ───────────────────────────────────────────
  //
  // FIX: antes, cuando la regex principal no matcheaba (por orden de
  // atributos distinto en el <li>), se caía al fallback que hardcodeaba
  // 'es_MX' para TODOS los enlaces sin importar el idioma real. Ahora:
  //  1) Partimos el HTML en bloques <li>...</li> y leemos data-lang, url
  //     y nombre de servidor de forma independiente dentro de cada bloque
  //     (no importa el orden de los atributos).
  //  2) Si ni así se encuentran bloques <li>, buscamos cada
  //     go_to_playerVast(...) y miramos el data-lang más cercano
  //     alrededor de esa posición, en vez de asumir siempre es_MX.

  static List<Map<String, String>> _extractEnlacesXupalace(String html) {
    final enlaces = <Map<String, String>>[];
    final seen = <String>{};

    final mapLang = {
      '0': 'es_MX',
      '1': 'subtitulado',
      '2': 'en_US',
      '3': 'castellano',
    };

    final urlRe = RegExp(r'''go_to_playerVast\(\s*['"]([^'"]+)['"]''');
    final langRe = RegExp(r'''data-lang=["'](\d+)["']''');
    final spanRe = RegExp(r'<span[^>]*>([^<]+)</span>');

    // 1) Intento principal: bloques <li>...</li> completos
    final liBlockRe = RegExp(
      r'<li\b[^>]*>.*?</li>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final liMatch in liBlockRe.allMatches(html)) {
      final block = liMatch.group(0) ?? '';

      final urlMatch = urlRe.firstMatch(block);
      if (urlMatch == null) continue;

      final url = urlMatch.group(1)?.trim() ?? '';
      if (url.isEmpty || seen.contains(url)) continue;

      final dataLang = langRe.firstMatch(block)?.group(1) ?? '0';
      final servidor =
          spanRe.firstMatch(block)?.group(1)?.trim().toLowerCase() ??
              'desconocido';

      seen.add(url);
      enlaces.add({
        'servidor': servidor,
        'url': url,
        'idioma': mapLang[dataLang] ?? 'es_MX',
      });
    }

    // 2) Fallback: no se pudieron delimitar bloques <li>. Buscamos cada
    //    url y el data-lang / servidor más cercanos alrededor de ella.
    if (enlaces.isEmpty) {
      for (final m in urlRe.allMatches(html)) {
        final url = m.group(1)?.trim() ?? '';
        if (url.isEmpty || seen.contains(url)) continue;
        seen.add(url);

        final windowStart = (m.start - 300).clamp(0, html.length);
        final windowEnd = (m.end + 300).clamp(0, html.length);

        final beforeContext = html.substring(windowStart, m.start);
        final afterContext = html.substring(m.end, windowEnd);

        // El data-lang suele venir en el <li> que envuelve el link, así
        // que lo buscamos justo antes de la url (más cercano gana).
        final langMatches = langRe.allMatches(beforeContext).toList();
        final dataLang =
            langMatches.isNotEmpty ? langMatches.last.group(1) : '0';

        var servidor =
            spanRe.firstMatch(afterContext)?.group(1)?.trim().toLowerCase() ??
                '';

        if (servidor.isEmpty) {
          if (url.contains('hglink.to') || url.contains('streamwish')) {
            servidor = 'streamwish';
          } else if (url.contains('filemoon') ||
              url.contains('bysedikamoum')) {
            servidor = 'filemoon';
          } else if (url.contains('vidhide') || url.contains('filelions')) {
            servidor = 'vidhide';
          } else if (url.contains('streamtape')) {
            servidor = 'stape';
          } else if (url.contains('voe.sx')) {
            servidor = 'vox';
          } else if (url.contains('waaw')) {
            servidor = 'waaw';
          } else if (url.contains('1fichier') || url.contains('ggtz')) {
            servidor = '1fichier';
          } else {
            servidor = 'desconocido';
          }
        }

        enlaces.add({
          'servidor': servidor,
          'url': url,
          'idioma': mapLang[dataLang] ?? 'es_MX',
        });
      }
    }

    return enlaces;
  }

  // ─── Procesar enlaces Xupalace ──────────────────────────────────────────

  static List<Embed69Server> _procesarEnlacesXupalace(
    List<Map<String, String>> enlaces,
    String imdbId,
    int tmdbId,
    int season,
    int episode,
  ) {
    final results = <Embed69Server>[];

    for (final enlace in enlaces) {
      var servidor = enlace['servidor']?.toLowerCase() ?? 'desconocido';
      var url = enlace['url'] ?? '';
      final idioma = enlace['idioma'] ?? 'es_MX';

      if (url.isEmpty) continue;

      final esStreamwish = servidor == 'streamwish' ||
          url.contains('hglink.to') ||
          url.contains('streamwish') ||
          url.contains('vibuxer.com');

      final esVidhide = servidor == 'vidhide' ||
          url.contains('vidhide') ||
          url.contains('filelions') ||
          url.contains('callistanise');

      if (!esStreamwish && !esVidhide) continue;

      servidor = esStreamwish ? 'streamwish' : 'vidhide';

      url = url
          .replaceAll('hglink.to', 'vibuxer.com')
          .replaceAll('filelions.to', 'callistanise.com');

      results.add(
        Embed69Server(
          serverName: servidor,
          url: url,
          calidad: 'Digital',
          idioma: _normalizarIdioma(idioma),
          imdbId: imdbId,
          tmdbId: tmdbId,
          season: season,
          episode: episode,
          fuente: 'xupalace',
        ),
      );
    }

    return results;
  }

  // ─── Normalizar idioma ──────────────────────────────────────────────────

  static String _normalizarIdioma(String idioma) {
    final upper = idioma.toUpperCase().trim();

    final mapa = {
      'ESP': 'es_MX',
      'ES': 'es_MX',
      'ESPAÑOL': 'es_MX',
      'SPANISH': 'es_MX',
      'LATINO': 'es_MX',
      'LAT': 'es_MX',
      'MX': 'es_MX',
      'ES_MX': 'es_MX',
      'SUB': 'subtitulado',
      'SUBTITULADO': 'subtitulado',
      'SUB ESPAÑOL': 'subtitulado',
      'SUB LATINO': 'subtitulado',
      'SUB LAT': 'subtitulado',
      'INGLES': 'en_US',
      'EN': 'en_US',
      'ENGLISH': 'en_US',
      'EN_US': 'en_US',
      'ESP SUB': 'es_ES',
      'ES SUB': 'es_ES',
      'ESPAÑOL SUB': 'es_ES',
      'SPANISH SUB': 'es_ES',
      'CASTELLANO': 'castellano',
      'CAST': 'castellano',
      'ES_ES': 'castellano',
    };

    for (final entry in mapa.entries) {
      if (upper.contains(entry.key)) {
        return entry.value;
      }
    }

    return idioma.toLowerCase();
  }
}

class Embed69Server {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma;
  final String imdbId;
  final int tmdbId;
  final int season;
  final int episode;
  final String fuente;

  const Embed69Server({
    required this.serverName,
    required this.url,
    this.calidad = 'Digital',
    this.idioma = 'es_MX',
    required this.imdbId,
    required this.tmdbId,
    required this.season,
    required this.episode,
    this.fuente = 'serieskao',
  });

  Map<String, dynamic> toModalMap() {
    final display =
        'Embed69 · ${serverName[0].toUpperCase()}${serverName.substring(1)}';
    return {
      'servidor_nombre': display,
      'servidor_url': url,
      'calidad': calidad,
      'idioma': idioma,
      'estado': 'activo',
      'es_embed69': true,
      'imdb_id': imdbId,
      'tmdb_id': tmdbId,
      'season': season,
      'episode': episode,
      'fuente': fuente,
    };
  }
}