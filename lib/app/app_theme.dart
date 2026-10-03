import 'package:flutter/material.dart';
import 'app_constants.dart';
ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppConstants.scaffoldBackground,
  );
}
