import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes rgb0 alpha before publishing software-rendered frames', () {
    final source = File(
      'packages/media_kit_video/windows/video_output.cc',
    ).readAsStringSync();
    final softwareFormat = source.indexOf('MPV_RENDER_PARAM_SW_FORMAT, "rgb0"');
    expect(softwareFormat, greaterThanOrEqualTo(0));

    final render = source.indexOf(
      'mpv_render_context_render(render_context_, params);',
      softwareFormat,
    );
    final alphaNormalization = source.indexOf(
      'pixel_buffer_[pixel * 4 + 3] = 0xFF;',
      render,
    );
    final publish = source.indexOf(
      'MarkTextureFrameAvailable(texture_id_);',
      render,
    );

    expect(render, greaterThan(softwareFormat));
    expect(alphaNormalization, greaterThan(render));
    expect(publish, greaterThan(alphaNormalization));
    expect(
      source,
      contains('for (size_t pixel = 0; pixel < pixel_count; ++pixel)'),
    );
  });
}
