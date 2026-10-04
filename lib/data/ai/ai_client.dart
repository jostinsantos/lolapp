import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model_memory.dart';
import 'ai_usage_tracker.dart';

/// Respuesta de Kilo: texto del modelo o Unable.
sealed class AiResponse {
  const AiResponse();
}

class AiText extends AiResponse {
  final String text;
  final String model;
  const AiText(this.text, this.model);
}

class AiUnable extends AiResponse {
  const AiUnable();
}

class ChatMessage {
  final String role; // system | user | assistant
  final String content;
  const ChatMessage(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Cliente hacia la API gratuita de Kilo (sin API key, sin Authorization).
/// Misma lógica que AiClient de Kino: descubre modelos, prueba en orden de
/// ModelMemory, máximo MAX_ATTEMPTS, timeout 45s.
class AiClient {
  static const String baseUrl = 'https://api.kilo.ai/api/gateway';
  static const String autoId = 'kilo-auto/free';
  static const int maxAttempts = 4;
  static const Duration timeout = Duration(seconds: 45);
  static const Duration catalogTtl = Duration(hours: 6);

  final ModelMemory memory;
  final http.Client _http;

  List<_KiloModel> _catalog = [];
  DateTime? _catalogFetchedAt;

  AiClient({ModelMemory? memory, http.Client? httpClient})
      : memory = memory ?? ModelMemory(),
        _http = httpClient ?? http.Client();

  /// Completar (no streaming). Devuelve AiText o AiUnable.
  Future<AiResponse> complete(
    String prompt, {
    String usageKind = 'other',
  }) async {
    final messages = [ChatMessage('user', prompt)];
    final buf = StringBuffer();
    try {
      await for (final delta in streamChat(messages, usageKind: usageKind)) {
        buf.write(delta);
      }
      final text = buf.toString().trim();
      if (text.isEmpty) return const AiUnable();
      return AiText(text, autoId);
    } catch (_) {
      return const AiUnable();
    }
  }

  /// Streaming de chat. Emite deltas de texto.
  /// [usageKind] se registra en AiUsageTracker: chat | foryou | other
  Stream<String> streamChat(
    List<ChatMessage> messages, {
    String usageKind = 'chat',
  }) async* {
    final models = await _orderedModels();
    if (models.isEmpty) return;

    final promptText = messages.map((m) => m.content).join('\n');
    final promptTok = AiUsageTracker.estimateTokens(promptText);

    int attempts = 0;
    for (final model in models) {
      if (attempts >= maxAttempts) break;
      attempts++;
      try {
        final body = jsonEncode({
          'model': model.id,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': true,
          // Temperatura más baja = respuestas más rápidas y estables
          'temperature': 0.5,
          'max_tokens': 800,
        });
        final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
        req.headers['Content-Type'] = 'application/json; charset=utf-8';
        req.headers['Accept'] = 'text/event-stream';
        // NUNCA enviar Authorization: el tier anónimo de Kilo depende de eso.
        req.body = body;

        final streamed = await _http.send(req).timeout(timeout);
        if (streamed.statusCode == 429) {
          memory.failure(model.id, ModelFailure.rateLimited());
          continue;
        }
        if (streamed.statusCode >= 500) {
          memory.failure(model.id, ModelFailure.server);
          continue;
        }
        if (streamed.statusCode != 200) {
          memory.failure(model.id, ModelFailure.server);
          continue;
        }

        var anyDelta = false;
        final completionBuf = StringBuffer();
        // Buffer de bytes para no romper caracteres UTF-8 (ñ, tildes) a mitad de secuencia
        final byteBuf = <int>[];
        await for (final bytes in streamed.stream) {
          byteBuf.addAll(bytes);
          // Decodificar solo líneas completas (terminadas en \n)
          while (true) {
            final nl = byteBuf.indexOf(0x0A); // \n
            if (nl < 0) break;
            final lineBytes = byteBuf.sublist(0, nl);
            byteBuf.removeRange(0, nl + 1);
            // Quitar \r si viene de \r\n
            if (lineBytes.isNotEmpty && lineBytes.last == 0x0D) {
              lineBytes.removeLast();
            }
            String line;
            try {
              line = utf8.decode(lineBytes, allowMalformed: false).trim();
            } catch (_) {
              // Secuencia inválida: intentar con allowMalformed
              line = utf8.decode(lineBytes, allowMalformed: true).trim();
            }
            if (line.isEmpty || !line.startsWith('data:')) continue;
            final data = line.substring(5).trim();
            if (data == '[DONE]') break;
            try {
              final obj = jsonDecode(data) as Map<String, dynamic>;
              final choices = obj['choices'] as List?;
              if (choices == null || choices.isEmpty) continue;
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content']?.toString();
              if (content != null && content.isNotEmpty) {
                anyDelta = true;
                completionBuf.write(content);
                yield content;
              }
            } catch (_) {
              // JSON parcial o malformado: ignorar
            }
          }
        }
        if (anyDelta) {
          memory.success(model.id);
          await AiUsageTracker.instance.record(
            kind: usageKind,
            model: model.id,
            promptTokens: promptTok,
            completionTokens:
                AiUsageTracker.estimateTokens(completionBuf.toString()),
            success: true,
          );
          return;
        }
        memory.failure(model.id, ModelFailure.unreadable);
        await AiUsageTracker.instance.record(
          kind: usageKind,
          model: model.id,
          promptTokens: promptTok,
          success: false,
        );
      } on TimeoutException {
        memory.failure(model.id, ModelFailure.server);
      } catch (_) {
        memory.failure(model.id, ModelFailure.server);
      }
    }
  }

  Future<List<_KiloModel>> _orderedModels() async {
    final catalog = await _currentCatalog();
    if (catalog.isEmpty) {
      return [_KiloModel(autoId, 'Kilo Auto')];
    }
    return memory.order(catalog);
  }

  Future<List<_KiloModel>> _currentCatalog() async {
    final now = DateTime.now();
    if (_catalogFetchedAt != null &&
        now.difference(_catalogFetchedAt!) < catalogTtl &&
        _catalog.isNotEmpty) {
      return _catalog;
    }
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/models'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return _catalog;
      final data = jsonDecode(res.body);
      final list = <_KiloModel>[];
      if (data is Map && data['data'] is List) {
        for (final m in data['data'] as List) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          if (id == null || id.isEmpty) continue;
          // Solo modelos free / auto
          final free = (m['free'] == true) ||
              id.contains('free') ||
              id.contains('auto');
          if (free) list.add(_KiloModel(id, m['name']?.toString() ?? id));
        }
      }
      if (list.isNotEmpty) {
        _catalog = list;
        _catalogFetchedAt = now;
      }
    } catch (_) {}
    if (_catalog.isEmpty) _catalog = [_KiloModel(autoId, 'Kilo Auto')];
    return _catalog;
  }
}

class _KiloModel {
  final String id;
  final String name;
  const _KiloModel(this.id, this.name);
}
