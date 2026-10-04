import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/ai/ai_client.dart';
import '../../../data/ai/lolbot_client.dart';
import '../../../data/recommendations/user_taste_profile.dart';
import '../../content/presentation/content_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Chat Lolbot (solo móvil). Misma UX que Kinobot de Kino.
class LolbotPage extends StatefulWidget {
  const LolbotPage({super.key});

  @override
  State<LolbotPage> createState() => _LolbotPageState();
}

class _LolbotPageState extends State<LolbotPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _ai = AiClient();
  late final LolbotClient _bot;
  final List<_Bubble> _messages = [];
  final List<ChatMessage> _history = [];
  bool _busy = false;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _bot = LolbotClient(_ai);
    _messages.add(const _Bubble(
      role: 'assistant',
      text:
          '¡Hola! Soy **Lolbot** 🎬 Tu amigo cinéfilo. ¿Qué te apetece ver? Puedo recomendarte pelis, series o anime según lo que te gusta.',
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _suggestions = [];
      _messages.add(_Bubble(role: 'user', text: text));
      _history.add(ChatMessage('user', text));
      _messages.add(const _Bubble(role: 'assistant', text: '', streaming: true));
    });
    _scrollToEnd();

    final buf = StringBuffer();
    try {
      await for (final chunk in _bot.reply(List.from(_history))) {
        if (chunk is LolbotDelta) {
          buf.write(chunk.text);
          setState(() {
            _messages[_messages.length - 1] =
                _Bubble(role: 'assistant', text: buf.toString(), streaming: true);
          });
          _scrollToEnd();
        } else if (chunk is LolbotDone) {
          setState(() {
            _messages[_messages.length - 1] =
                _Bubble(role: 'assistant', text: buf.toString());
            _suggestions = chunk.suggestions;
            _busy = false;
          });
          _history.add(ChatMessage('assistant', buf.toString()));
          _scrollToEnd();
        } else if (chunk is LolbotRefusal) {
          setState(() {
            _messages[_messages.length - 1] =
                _Bubble(role: 'assistant', text: chunk.text);
            _busy = false;
          });
          _scrollToEnd();
        } else if (chunk is LolbotFailed) {
          setState(() {
            _messages[_messages.length - 1] = const _Bubble(
              role: 'assistant',
              text: 'No pude responder ahora. Prueba de nuevo en un momento 🎬',
            );
            _busy = false;
          });
        }
      }
    } catch (_) {
      setState(() {
        _messages[_messages.length - 1] = const _Bubble(
          role: 'assistant',
          text: 'Error de conexión. Intenta otra vez.',
        );
        _busy = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openSuggestion(String title) async {
    // Buscar en TMDB (multi) para respetar movie vs tv
    try {
      const key = 'a2d9bbed370d9f678e34006f8750a5a5';
      // 1) multi search — el resultado trae media_type
      final multiUri = Uri.parse(
        'https://api.themoviedb.org/3/search/multi'
        '?api_key=$key&language=es-MX&query=${Uri.encodeQueryComponent(title)}&page=1',
      );
      final multiRes =
          await http.get(multiUri).timeout(const Duration(seconds: 10));
      if (multiRes.statusCode == 200) {
        final data = jsonDecode(multiRes.body) as Map;
        final results = data['results'] as List? ?? [];
        Map? best;
        for (final r in results) {
          if (r is! Map) continue;
          final mt = r['media_type']?.toString();
          if (mt != 'movie' && mt != 'tv') continue;
          best = r;
          break;
        }
        if (best != null) {
          final id = (best['id'] as num?)?.toInt();
          final mt = best['media_type']?.toString() ?? 'movie';
          if (id != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PageContenido(
                  idcontenido: id,
                  tmdbId: id,
                  mediaType: mt,
                ),
              ),
            );
            return;
          }
        }
      }
      // 2) Fallback: movie y tv en paralelo, elige el de mayor popularidad
      final results = await Future.wait([
        http
            .get(Uri.parse(
                'https://api.themoviedb.org/3/search/movie?api_key=$key&language=es-MX&query=${Uri.encodeQueryComponent(title)}&page=1'))
            .timeout(const Duration(seconds: 8)),
        http
            .get(Uri.parse(
                'https://api.themoviedb.org/3/search/tv?api_key=$key&language=es-MX&query=${Uri.encodeQueryComponent(title)}&page=1'))
            .timeout(const Duration(seconds: 8)),
      ]);
      double bestPop = -1;
      int? bestId;
      String bestMt = 'movie';
      for (var i = 0; i < 2; i++) {
        final res = results[i];
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map;
        final list = data['results'] as List? ?? [];
        if (list.isEmpty) continue;
        final first = list.first as Map;
        final pop = (first['popularity'] as num?)?.toDouble() ?? 0;
        final id = (first['id'] as num?)?.toInt();
        if (id != null && pop > bestPop) {
          bestPop = pop;
          bestId = id;
          bestMt = i == 0 ? 'movie' : 'tv';
        }
      }
      if (bestId != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PageContenido(
              idcontenido: bestId!,
              tmdbId: bestId,
              mediaType: bestMt,
            ),
          ),
        );
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No encontré "$title" en el catálogo')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al buscar el título')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 28,
              errorBuilder: (_, __, ___) => const Text(
                'L',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Lolbot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.purpleAccent.withOpacity(0.85)
                          : const Color(0xFF1a1a2e),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: Text(
                      m.text.isEmpty && m.streaming ? '…' : m.text.replaceAll('**', ''),
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_suggestions.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ActionChip(
                    label: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    backgroundColor: const Color(0xFF2a2a4a),
                    side: BorderSide(color: Colors.purpleAccent.withOpacity(0.5)),
                    onPressed: () => _openSuggestion(s),
                  );
                },
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Pregúntame por una peli, serie…',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                        filled: true,
                        fillColor: const Color(0xFF1a1a2e),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _busy ? null : () => _send(),
                    icon: Icon(
                      Icons.send_rounded,
                      color: _busy ? Colors.grey : Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble {
  final String role;
  final String text;
  final bool streaming;
  const _Bubble({
    required this.role,
    required this.text,
    this.streaming = false,
  });
}
