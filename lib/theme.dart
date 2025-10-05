import 'package:flutter/material.dart';
//import 'package:google_fonts/google_fonts.dart';

var appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  
  // Material Design 3 expressive color scheme
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4), // Purple primary
    brightness: Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.expressive,
  ),
  
  // Enhanced Material 3 components
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  ),
  
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 3,
  ),
);
