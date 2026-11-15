import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B45)),
    scaffoldBackgroundColor: const Color(0xFFF7F8F5),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
  );
}
