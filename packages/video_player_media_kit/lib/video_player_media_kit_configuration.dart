import 'package:media_kit_video/media_kit_video.dart';

/// Builds the video output configuration used by the video_player adapter.
///
/// Windows uses software-backed video output to avoid the zero-sized hardware
/// texture reported by some Windows rendering paths. Other platforms keep the
/// MediaKit default hardware acceleration behavior.
VideoControllerConfiguration videoControllerConfigurationForPlatform({
  required bool isWindows,
}) {
  return VideoControllerConfiguration(
    enableHardwareAcceleration: !isWindows,
  );
}
