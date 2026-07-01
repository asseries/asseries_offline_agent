import 'package:flutter/material.dart';

// Gemma-chat inspired dark theme — ink-* color palette
class AppColors {
  static const bg = Color(0xFF0f0f11);         // ink-900
  static const surface = Color(0xFF18181b);    // ink-800
  static const surfaceHigh = Color(0xFF27272a); // ink-700
  static const border = Color(0xFF3f3f46);     // ink-600
  static const textDim = Color(0xFF71717a);    // ink-400
  static const text = Color(0xFFe4e4e7);       // ink-100
  static const textBright = Color(0xFFfafafa); // ink-50
  static const accent = Color(0xFF6366f1);     // indigo-500
  static const accentDim = Color(0xFF4f46e5);  // indigo-600
  static const green = Color(0xFF22c55e);
  static const red = Color(0xFFef4444);
  static const yellow = Color(0xFFf59e0b);
  static const userBubble = Color(0xFF1e1e2e); // user message bg
  static const toolBg = Color(0xFF141418);     // tool card bg
  static const sidebarBg = Color(0xFF0d0d10);  // slightly darker
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onSurface: AppColors.text,
      outline: AppColors.border,
    ),
    fontFamily: 'system-ui',
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 0,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.border),
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(2),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text, fontSize: 14, height: 1.6),
      bodySmall: TextStyle(color: AppColors.textDim, fontSize: 12),
      titleMedium: TextStyle(color: AppColors.textBright, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      hintStyle: const TextStyle(color: AppColors.textDim),
    ),
    iconTheme: const IconThemeData(color: AppColors.textDim, size: 18),
    useMaterial3: true,
  );
}
