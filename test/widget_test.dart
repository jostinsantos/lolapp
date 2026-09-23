import 'package:flutter_test/flutter_test.dart';
import 'package:lol/features/player/presentation/player_page.dart';

void main() {
  test('PlayerScreen conserva la configuración recibida', () {
    const player = PlayerScreen(
      idcontenido: 123,
      tmdbId: 123,
      tipo: 'movie',
      titulo: 'Contenido de prueba',
      idioma: 'en_US',
    );

    // Sin URL: el player resuelve con ServerLoader (caché / fuentes)
    expect(player.videoUrl, '');
    expect(player.idioma, 'en_US');
    expect(player.temporada, isNull);
    expect(player.capitulo, isNull);
  });
}
