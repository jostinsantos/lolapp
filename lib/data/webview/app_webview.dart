import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;

/// Navigation decisions exposed by the app's WebView compatibility layer.
enum NavigationDecision { navigate, prevent }

/// Converts the existing WebView navigation decision to the in-app API.
inapp.NavigationActionPolicy toInAppNavigationPolicy(
  NavigationDecision decision,
) => switch (decision) {
  NavigationDecision.navigate => inapp.NavigationActionPolicy.ALLOW,
  NavigationDecision.prevent => inapp.NavigationActionPolicy.CANCEL,
};

class NavigationRequest {
  const NavigationRequest(this.url);

  final String url;
}

class JavaScriptMessage {
  const JavaScriptMessage(this.message);

  final String message;
}

class WebResourceError {
  const WebResourceError({required this.description, this.isForMainFrame});

  final String description;
  final bool? isForMainFrame;
}

class JavaScriptMode {
  const JavaScriptMode._();

  static const unrestricted = JavaScriptMode._();
}

class NavigationDelegate {
  const NavigationDelegate({
    this.onProgress,
    this.onPageStarted,
    this.onPageFinished,
    this.onWebResourceError,
    this.onNavigationRequest,
  });

  final void Function(int progress)? onProgress;
  final FutureOr<void> Function(String url)? onPageStarted;
  final FutureOr<void> Function(String url)? onPageFinished;
  final void Function(WebResourceError error)? onWebResourceError;
  final FutureOr<NavigationDecision> Function(NavigationRequest request)?
  onNavigationRequest;
}

class WebViewController {
  String? _userAgent;
  Color? _backgroundColor;
  String? _initialUrl;
  bool _requiresUserGesture = true;
  NavigationDelegate? _navigationDelegate;
  inapp.InAppWebViewController? _nativeController;
  final Map<String, void Function(JavaScriptMessage)> _channels = {};

  void setJavaScriptMode(JavaScriptMode mode) {}

  void setUserAgent(String userAgent) => _userAgent = userAgent;

  void setBackgroundColor(Color color) => _backgroundColor = color;

  void setMediaPlaybackRequiresUserGesture(bool required) =>
      _requiresUserGesture = required;

  void addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage message) onMessageReceived,
  }) {
    _channels[name] = onMessageReceived;
  }

  void setNavigationDelegate(NavigationDelegate delegate) {
    _navigationDelegate = delegate;
  }

  Future<void> loadRequest(Uri uri) async {
    _initialUrl = uri.toString();
    final controller = _nativeController;
    if (controller != null) {
      await controller.loadUrl(
        urlRequest: inapp.URLRequest(url: inapp.WebUri(_initialUrl!)),
      );
    }
  }

  Future<void> runJavaScript(String javaScript) async {
    final controller = _nativeController;
    if (controller != null) {
      await controller.evaluateJavascript(source: javaScript);
    }
  }

  Future<void> scrollBy(int x, int y) async {
    final controller = _nativeController;
    if (controller != null) {
      await controller.scrollBy(x: x, y: y);
    }
  }

  void _attach(inapp.InAppWebViewController controller) {
    _nativeController = controller;
    for (final channelName in _channels.keys) {
      controller.addJavaScriptHandler(
        handlerName: channelName,
        callback: (arguments) {
          final message = arguments.isEmpty ? '' : arguments.first.toString();
          _channels[channelName]?.call(JavaScriptMessage(message));
          return null;
        },
      );
    }
  }

  Widget _build() {
    final delegate = _navigationDelegate;
    return Container(
      color: _backgroundColor,
      child: inapp.InAppWebView(
        initialUrlRequest: _initialUrl == null
            ? null
            : inapp.URLRequest(url: inapp.WebUri(_initialUrl!)),
        initialSettings: inapp.InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: _userAgent,
          mediaPlaybackRequiresUserGesture: _requiresUserGesture,
          useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: _attach,
        onProgressChanged: (_, progress) =>
            delegate?.onProgress?.call(progress),
        onLoadStart: (_, url) {
          final callback = delegate?.onPageStarted;
          if (callback != null) callback(url?.toString() ?? '');
        },
        onLoadStop: (_, url) {
          final callback = delegate?.onPageFinished;
          if (callback != null) callback(url?.toString() ?? '');
        },
        onReceivedError: (_, request, error) {
          delegate?.onWebResourceError?.call(
            WebResourceError(
              description: error.description,
              isForMainFrame: request.isForMainFrame,
            ),
          );
        },
        shouldOverrideUrlLoading: (_, action) async {
          final callback = delegate?.onNavigationRequest;
          if (callback == null) return inapp.NavigationActionPolicy.ALLOW;
          final url = action.request.url?.toString() ?? '';
          return toInAppNavigationPolicy(
            await callback(NavigationRequest(url)),
          );
        },
      ),
    );
  }
}

class WebViewWidget extends StatelessWidget {
  const WebViewWidget({super.key, required this.controller});

  final WebViewController controller;

  @override
  Widget build(BuildContext context) => controller._build();
}
