import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const background = Color(0xFFF7F7FB);
  static const surface = Color(0xFF071022);
  static const purple = Color(0xFF6D31FF);
  static const violet = Color(0xFF6331E8);
  static const text = Color(0xFF080D28);
  static const muted = Color(0xFF687086);
  static const divider = Color(0xFFE8E8F0);
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.purple, surface: Colors.white),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: AppColors.text, elevation: 0, scrolledUnderElevation: 1, centerTitle: false, titleTextStyle: TextStyle(color: AppColors.text, fontSize: 19, fontWeight: FontWeight.w700)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: TextStyle(color: Color(0xFF626A80)),
          hintStyle: TextStyle(color: Color(0xFF8A91A3)),
          helperStyle: TextStyle(color: AppColors.muted),
          prefixIconColor: AppColors.purple,
          suffixIconColor: AppColors.muted,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDADCE5))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.purple, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE64A59))),
        ),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.divider))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: AppColors.purple, foregroundColor: Colors.white, minimumSize: const Size(48, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: AppColors.purple, minimumSize: const Size(48, 48), side: const BorderSide(color: Color(0xFFD5C7FF)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
        dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
        snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: AppColors.text, contentTextStyle: const TextStyle(color: Colors.white), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.purple),
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true),
        dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.purple, selectionColor: Color(0x336D31FF), selectionHandleColor: AppColors.purple),
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030817),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.purple,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      );
}
