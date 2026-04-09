import 'package:flutter/material.dart';

/// Premium gradient presets for the Circuit Detector App.
/// Use these across buttons, backgrounds, cards, and overlays.
class AppGradients {
  AppGradients._();

  // ── Primary action gradients ────────────────────────────────────────────
  static const LinearGradient cyanBlue = LinearGradient(
    colors: [Color(0xFF00D4FF), Color(0xFF0080FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetPurple = LinearGradient(
    colors: [Color(0xFFAB47BC), Color(0xFF6A1B9A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldTeal = LinearGradient(
    colors: [Color(0xFF00E5A0), Color(0xFF009688)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmOrange = LinearGradient(
    colors: [Color(0xFFFF6E40), Color(0xFFFF3D00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldPremium = LinearGradient(
    colors: [Color(0xFFFFD54F), Color(0xFFE65100)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Background gradients ────────────────────────────────────────────────
  static const LinearGradient darkBackground = LinearGradient(
    colors: [Color(0xFF0D0D1A), Color(0xFF0A1628)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient surfaceDark = LinearGradient(
    colors: [Color(0xFF141428), Color(0xFF0E1A2E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceLight = LinearGradient(
    colors: [Color(0xFFF5F7FA), Color(0xFFE8EDF5)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Card overlays ──────────────────────────────────────────────────────
  static LinearGradient glassDark({double opacity = 0.12}) => LinearGradient(
    colors: [
      Colors.white.withOpacity(opacity),
      Colors.white.withOpacity(opacity * 0.3),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient glassLight({double opacity = 0.6}) => LinearGradient(
    colors: [
      Colors.white.withOpacity(opacity),
      Colors.white.withOpacity(opacity * 0.7),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Premium color palette.
class AppColors {
  AppColors._();

  // Primary
  static const Color primaryCyan = Color(0xFF00D4FF);
  static const Color primaryBlue = Color(0xFF0080FF);
  static const Color primaryViolet = Color(0xFF7C4DFF);

  // Accent
  static const Color accentEmerald = Color(0xFF00E5A0);
  static const Color accentAmber = Color(0xFFFFAB00);
  static const Color accentOrange = Color(0xFFFF6E40);
  static const Color accentRose = Color(0xFFFF4081);

  // Surfaces (dark mode)
  static const Color darkBg = Color(0xFF0D0D1A);
  static const Color darkSurface = Color(0xFF141428);
  static const Color darkCard = Color(0xFF1A1A35);
  static const Color darkCardBorder = Color(0xFF2A2A4A);

  // Surfaces (light mode)
  static const Color lightBg = Color(0xFFF5F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFF9E9EB8);
  static const Color textDarkPrimary = Color(0xFF1A1A2E);
  static const Color textDarkSecondary = Color(0xFF6B7280);

  // Status
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF5252);
  static const Color info = Color(0xFF448AFF);
}

/// Spacing tokens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Border radius tokens.
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 100;
}

/// Premium glassmorphism card decoration.
class GlassDecoration {
  GlassDecoration._();

  static BoxDecoration dark({
    double borderRadius = AppRadius.lg,
    double opacity = 0.10,
    Color borderColor = AppColors.darkCardBorder,
  }) =>
      BoxDecoration(
        gradient: AppGradients.glassDark(opacity: opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration light({
    double borderRadius = AppRadius.lg,
    double opacity = 0.7,
  }) =>
      BoxDecoration(
        gradient: AppGradients.glassLight(opacity: opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      );
}
