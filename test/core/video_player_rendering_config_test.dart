import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

void main() {
  group('videoControllerConfigurationForPlatform', () {
    test('disables hardware acceleration on Windows', () {
      final configuration = videoControllerConfigurationForPlatform(
        isWindows: true,
      );

      expect(configuration.enableHardwareAcceleration, isFalse);
    });

    test('keeps hardware acceleration enabled off Windows', () {
      final configuration = videoControllerConfigurationForPlatform(
        isWindows: false,
      );

      expect(configuration.enableHardwareAcceleration, isTrue);
    });
  });
}
