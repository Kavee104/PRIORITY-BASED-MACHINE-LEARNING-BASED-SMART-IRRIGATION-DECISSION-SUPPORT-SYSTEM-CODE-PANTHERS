import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette - Smart Irrigation / AI AgTech
  static const Color primaryDarkGreen = Color(0xFF075B3A);
  static const Color darkEmerald = Color(0xFF0B6B45);
  static const Color primaryGreen = Color(0xFF10B981);
  static const Color brightGreen = Color(0xFF22C55E);
  static const Color teal = Color(0xFF0EA5A4);
  static const Color lightGreen = Color(0xFFDCFCE7);

  // Background & Surface
  static const Color background = Color(0xFFF7FAF8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color inputBackground = Color(0xFFF8FAFC);

  // Text Colors
  static const Color primaryText = Color(0xFF17211D);
  static const Color secondaryText = Color(0xFF64748B);
  static const Color mutedText = Color(0xFF94A3B8);

  // Aliases for compatibility
  static const Color deepGreen = primaryDarkGreen;
  static const Color emerald = primaryGreen;
  static const Color freshGreen = brightGreen;
  static const Color darkForest = darkEmerald;
  static const Color aquaBlue = teal;
  static const Color lightBlue = lightGreen;
  static const Color skyBlue = Color(0xFF38BDF8);

  static const Color textDark = primaryText;
  static const Color textSecondary = secondaryText;
  static const Color textLight = mutedText;

  // Borders & Dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderFocused = primaryGreen;

  // Feedback Colors
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGreen, primaryDarkGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [primaryDarkGreen, darkEmerald, Color(0xFF084C32)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient waterGradient = LinearGradient(
    colors: [primaryGreen, teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        secondary: AppColors.teal,
        surface: AppColors.surface,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.primaryText),
        titleTextStyle: TextStyle(
          color: AppColors.primaryText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        labelStyle: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.mutedText, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
