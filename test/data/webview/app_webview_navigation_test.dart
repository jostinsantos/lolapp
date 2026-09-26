import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lol/data/webview/app_webview.dart';

void main() {
  group('App WebView call sites', () {
    const webViewFiles = [
      'lib/data/extractors/hls/hls_extractor.dart',
      'lib/data/extractors/providers/content/extractor_hls.dart',
      'lib/features/discover/domain/extractor.dart',
      'lib/features/downloads/presentation/extractor_download_page.dart',
      'lib/features/player/data/extractor.dart',
      'lib/features/player/data/extractor_mobil.dart',
      'lib/features/player/presentation/web_player_view.dart',
      'lib/features/player/presentation/tv/tv_player_webview.dart',
    ];

    for (final path in webViewFiles) {
      test('$path uses the Windows-capable app adapter', () {
        final source = File(path).readAsStringSync();

        expect(
          source,
          contains("import 'package:lol/data/webview/app_webview.dart';"),
        );
        expect(source, isNot(contains("import 'package:webview_flutter/")));
      });
    }
  });

  group('AppWebView navigation decisions', () {
    test('allows a navigation explicitly approved by the delegate', () {
      expect(
        toInAppNavigationPolicy(NavigationDecision.navigate),
        NavigationActionPolicy.ALLOW,
      );
    });

    test('cancels a navigation explicitly rejected by the delegate', () {
      expect(
        toInAppNavigationPolicy(NavigationDecision.prevent),
        NavigationActionPolicy.CANCEL,
      );
    });
  });

  group('MediaDetector JavaScript bridge', () {
    const extractorFiles = [
      'lib/data/extractors/hls/hls_extractor.dart',
      'lib/data/extractors/providers/content/extractor_hls.dart',
      'lib/features/discover/domain/extractor.dart',
      'lib/features/downloads/presentation/extractor_download_page.dart',
      'lib/features/player/data/extractor.dart',
      'lib/features/player/data/extractor_mobil.dart',
    ];

    for (final path in extractorFiles) {
      test('$path gates messages on the InAppWebView bridge', () {
        final source = File(path).readAsStringSync();

        expect(
          source.contains('window.MediaDetector.postMessage'),
          isFalse,
          reason:
              'the obsolete MediaDetector postMessage bridge must be absent',
        );
        expect(
          source,
          contains(
            'if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler)',
          ),
        );
        expect(
          source,
          contains(
            "window.flutter_inappwebview.callHandler('MediaDetector', absUrl);",
          ),
        );
      });
    }
  });
}
