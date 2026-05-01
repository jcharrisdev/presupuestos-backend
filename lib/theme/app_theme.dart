import 'package:flutter/material.dart';

class AppTheme {
  // Colores base
  static const Color background   = Color(0xFF0B0E11);
  static const Color surface      = Color(0xFF1E2026);
  static const Color surfaceAlt   = Color(0xFF2B3139);
  static const Color border       = Color(0xFF2B3139);

  // Acento principal
  static const Color primary      = Color(0xFFF0B90B);
  static const Color primaryDark  = Color(0xFFCF9A09);

  // Texto
  static const Color textPrimary   = Color(0xFFEAECEF);
  static const Color textSecondary = Color(0xFF848E9C);
  static const Color textMuted     = Color(0xFF5E6673);

  // Estados
  static const Color success = Color(0xFF0ECB81);
  static const Color danger  = Color(0xFFF6465D);
  static const Color warning = Color(0xFFF0B90B);
  static const Color info    = Color(0xFF1890FF);

  // Tipos de gasto
  static const Color colorFijo     = Color(0xFF1890FF);
  static const Color colorNoFijo   = Color(0xFFF0B90B);
  static const Color colorAhorro   = Color(0xFF0ECB81);

  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primary,
      surface: surface,
      background: background,
      error: danger,
      onPrimary: background,
      onSecondary: background,
      onSurface: textPrimary,
      onBackground: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: textSecondary),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      prefixStyle: const TextStyle(color: textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: background,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.selected) ? primary : Colors.transparent),
      checkColor: MaterialStateProperty.all(background),
      side: const BorderSide(color: textSecondary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: primary,
      thumbColor: primary,
      inactiveTrackColor: surfaceAlt,
      overlayColor: Color(0x22F0B90B),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: const TextTheme(
      bodyLarge:  TextStyle(color: textPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: textPrimary, fontSize: 13),
      bodySmall:  TextStyle(color: textSecondary, fontSize: 12),
      titleLarge: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium:TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(color: textSecondary, fontSize: 11, letterSpacing: 0.4),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: surfaceAlt,
      circularTrackColor: surfaceAlt,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceAlt,
      contentTextStyle: const TextStyle(color: textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      behavior: SnackBarBehavior.floating,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: textPrimary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: background,
      elevation: 2,
    ),
  );

  // Helpers
  static Color gastoColor(String tipo) {
    switch (tipo) {
      case 'fijo':         return colorFijo;
      case 'fijo_x_periodo': return colorFijo;
      case 'no fijo':     return colorNoFijo;
      case 'ahorro':      return colorAhorro;
      default:            return textSecondary;
    }
  }

  static String gastoLabel(String tipo) {
    switch (tipo) {
      case 'fijo':            return 'Fijo';
      case 'fijo_x_periodo':  return 'Fijo x período';
      case 'no fijo':         return 'Variable';
      case 'ahorro':          return 'Ahorro';
      default:                return tipo;
    }
  }
}

// Widget reutilizable: etiqueta de tipo de gasto
class TipoChip extends StatelessWidget {
  final String tipo;
  const TipoChip(this.tipo, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.gastoColor(tipo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        AppTheme.gastoLabel(tipo),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    );
  }
}

// Divider con etiqueta
class LabelDivider extends StatelessWidget {
  final String label;
  const LabelDivider(this.label, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        const Expanded(child: Divider(color: AppTheme.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
        ),
        const Expanded(child: Divider(color: AppTheme.border)),
      ]),
    );
  }
}
