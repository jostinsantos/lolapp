import 'package:flutter_test/flutter_test.dart';
import 'package:lol/features/player/presentation/player_page.dart';

void main() {
  group('esAudioEnEspanol (regla de subtítulos)', () {
    test('audio en español → subtítulos desactivados', () {
      const espanoles = [
        'latino',
        'Latino',
        'LATINO',
        'castellano',
        'es',
        'ES',
        'es_MX',
        'es-mx',
        'es_ES',
        'es_LA',
        'audio Latino dublado',
      ];

      for (final idioma in espanoles) {
        expect(
          esAudioEnEspanol(idioma),
          isTrue,
          reason: '"$idioma" debe considerarse español',
        );
      }
    });

    test('idioma extranjero → subtítulos activados', () {
      const extranjeros = [
        'en',
        'en_US',
        'ja',
        'ja_JA',
        'vo',
        'sub',
        'ingles',
        'pt_BR',
        'fr',
        'de',
      ];

      for (final idioma in extranjeros) {
        expect(
          esAudioEnEspanol(idioma),
          isFalse,
          reason: '"$idioma" no debe considerarse español',
        );
      }
    });

    test('sin información no se asume español', () {
      expect(esAudioEnEspanol(null), isFalse);
      expect(esAudioEnEspanol(''), isFalse);
      expect(esAudioEnEspanol('   '), isFalse);
    });

    test('no hay falsos positivos por coincidencia parcial ("es")', () {
      // "ingles" contiene "es" pero NO es español
      expect(esAudioEnEspanol('ingles'), isFalse);
      expect(esAudioEnEspanol('test'), isFalse);
      expect(esAudioEnEspanol('yes'), isFalse);
    });
  });
}
