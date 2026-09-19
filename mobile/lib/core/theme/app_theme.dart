import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const background = Color(0xFF030817);
  static const surface = Color(0xFF071022);
  static const purple = Color(0xFF8B3DFF);
  static const violet = Color(0xFF6331E8);
  static const text = Color(0xFFF7F5FA);
  static const muted = Color(0xFFB7B2C1);
  static const divider = Color(0xFF41465A);
}

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.purple),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFF080D28),
        displayColor: const Color(0xFF080D28),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Color(0xFF4B5368)),
        floatingLabelStyle: const TextStyle(color: AppColors.violet),
        hintStyle: const TextStyle(color: Color(0xFF8A91A2)),
        helperStyle: const TextStyle(color: Color(0xFF687086)),
        prefixIconColor: AppColors.violet,
        suffixIconColor: const Color(0xFF080D28),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.violet,
        selectionColor: Color(0x336331E8),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.purple,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      );
}
