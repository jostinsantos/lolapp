import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubtitlePrefs {
  static const sizeKey = 'subtitulo_tamano';
  static const boldKey = 'subtitulos_negrita';
  static const offsetKey = 'player_vertical_offset';

  final double fontSize;
  final FontWeight fontWeight;
  final double verticalOffset;

  const SubtitlePrefs({
    required this.fontSize,
    required this.fontWeight,
    required this.verticalOffset,
  });

  static const defaults = SubtitlePrefs(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    verticalOffset: 0,
  );

  static double sizeFromCode(String? code) {
    switch (code) {
      case 'pequeno':
        return 16;
      case 'grande':
        return 28;
      case 'mediano':
      default:
        return 22;
    }
  }

  static Future<SubtitlePrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = sizeFromCode(prefs.getString(sizeKey));
      final bold = prefs.getBool(boldKey) ?? false;
      final offset =
          (prefs.getDouble(offsetKey) ?? 0).clamp(-80.0, 80.0);
      return SubtitlePrefs(
        fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        verticalOffset: offset,
      );
    } catch (_) {
      return defaults;
    }
  }
}

class SubtitleWidget extends StatelessWidget {
  final String text;
  final bool isActive;
  final double bottomPadding;
  final double fontSize;
  final Color textColor;
  final Color strokeColor;
  final double strokeWidth;
  final double shadowBlur;
  final Offset shadowOffset;
  final double horizontalPadding;
  final double verticalPadding;
  final FontWeight fontWeight;
  final bool showBackground;
  final double maxWidth;
  final Color backgroundColor;
  final double borderRadius;
  final double verticalOffset;

  const SubtitleWidget({
    super.key,
    required this.text,
    required this.isActive,
    this.bottomPadding = 25.0,
    this.fontSize = 22.0,
    this.textColor = Colors.white,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.5,
    this.shadowBlur = 0.0,
    this.shadowOffset = Offset.zero,
    this.horizontalPadding = 20.0,
    this.verticalPadding = 6.0,
    this.fontWeight = FontWeight.w600,
    this.showBackground = false,
    this.maxWidth = 700,
    this.backgroundColor = Colors.black,
    this.borderRadius = 8.0,
    this.verticalOffset = 0,
  });

  factory SubtitleWidget.fromPrefs({
    Key? key,
    required String text,
    required bool isActive,
    required SubtitlePrefs prefs,
    double baseBottomPadding = 40.0,
    double maxWidth = 780,
    Color textColor = Colors.white,
    Color strokeColor = Colors.black,
    double strokeWidth = 2.5,
  }) {
    return SubtitleWidget(
      key: key,
      text: text,
      isActive: isActive,
      bottomPadding: baseBottomPadding,
      fontSize: prefs.fontSize,
      fontWeight: prefs.fontWeight,
      verticalOffset: prefs.verticalOffset,
      textColor: textColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      maxWidth: maxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isActive || text.isEmpty) return const SizedBox.shrink();

    final bottom = (bottomPadding + verticalOffset).clamp(8.0, 320.0);

    return Positioned(
      bottom: bottom,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: showBackground
              ? BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                )
              : null,
          child: _buildText(),
        ),
      ),
    );
  }

  Widget _buildText() {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: 'Roboto',
      height: 1.3,
    );

    if (strokeWidth <= 0) {
      return Text(
        text,
        textAlign: TextAlign.center,
        style: base.copyWith(
          color: textColor,
          shadows: shadowBlur > 0
              ? [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: shadowBlur,
                    offset: shadowOffset,
                  ),
                ]
              : null,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            color: textColor,
            shadows: shadowBlur > 0
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: shadowBlur,
                      offset: shadowOffset,
                    ),
                  ]
                : null,
          ),
        ),
      ],
    );
  }
}