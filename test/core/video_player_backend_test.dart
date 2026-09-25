import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/video_player_backend.dart';

void main() {
  group('initializeVideoPlayerBackend', () {
    test('initializes the injected backend on Windows', () {
      var initialized = false;

      initializeVideoPlayerBackend(
        isWindows: true,
        initializeWindowsBackend: () => initialized = true,
      );

      expect(initialized, isTrue);
    });

    test('does not override the platform backend elsewhere', () {
      var initialized = false;

      initializeVideoPlayerBackend(
        isWindows: false,
        initializeWindowsBackend: () => initialized = true,
      );

      expect(initialized, isFalse);
    });
  });
}
