import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lol/features/player/presentation/tv/tv_player_page.dart';

void main() {
  testWidgets('Windows hover reveals controls and pointer exit hides them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(const _HoverHarness());

      expect(find.text('controls'), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final playerRect = tester.getRect(find.byType(TvPlayerHoverRegion));
      await mouse.addPointer(location: playerRect.center);
      await mouse.moveTo(playerRect.center + const Offset(1, 0));
      await tester.pump();
      expect(find.text('controls'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.text('controls'), findsNothing);
      await mouse.removePointer();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hover controls remain disabled on non-Windows platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(const _HoverHarness());

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final playerRect = tester.getRect(find.byType(TvPlayerHoverRegion));
      await mouse.addPointer(location: playerRect.center);
      await mouse.moveTo(playerRect.center + const Offset(1, 0));
      await tester.pump();
      expect(find.text('controls'), findsNothing);
      await mouse.removePointer();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _HoverHarness extends StatefulWidget {
  const _HoverHarness();

  @override
  State<_HoverHarness> createState() => _HoverHarnessState();
}

class _HoverHarnessState extends State<_HoverHarness> {
  bool _controlsVisible = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 240,
          child: TvPlayerHoverRegion(
            enabled: true,
            onHoverChanged: (hovering) {
              setState(() => _controlsVisible = hovering);
            },
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: _controlsVisible
                    ? const Text('controls')
                    : const Text('video'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
