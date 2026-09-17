/// Tema visual global. Soporta modo OSCURO (Binance-style, por defecto) y CLARO.
///
/// Solo los colores de "lienzo" (fondo, superficie, bordes, texto) cambian entre
/// modos. Los acentos (amarillo de marca) y el semáforo (verde/rojo/naranja/azul)
/// son iguales en ambos temas, por eso siguen siendo `const`.
import 'package:flutter/material.dart';

class AppTheme {
  // ── Estado del tema ───────────────────────────────────────────────────────
  static bool _isDark = true;
  static bool get isDark => _isDark;

  /// Cambia al notificar → el root reconstruye MaterialApp y todo el árbol.
  static final ValueNotifier<bool> modeNotifier = ValueNotifier<bool>(true);

  // ── COLORES QUE CAMBIAN entre oscuro/claro (mutables) ─────────────────────
  static Color background    = const Color(0xFF0B0E11);
  static Color surface       = const Color(0xFF1E2026);
  static Color surfaceAlt    = const Color(0xFF2B3139);
  static Color border        = const Color(0xFF2B3139);
  static Color textPrimary   = const Color(0xFFEAECEF);
  static Color textSecondary = const Color(0xFF848E9C);
  static Color textMuted     = const Color(0xFF5E6673);

  // ── ACENTO + SEMÁFORO: iguales en ambos temas (const) ─────────────────────
  static const Color primary     = Color(0xFFF0B90B);
  static const Color primaryDark = Color(0xFFCF9A09);
  /// Texto/íconos encima del amarillo (botones primarios). Siempre oscuro.
  static const Color onPrimary   = Color(0xFF181A20);
  static const Color success = Color(0xFF0ECB81);
  static const Color danger  = Color(0xFFF6465D);
  static const Color warning = Color(0xFFF7931A);
  static const Color info    = Color(0xFF1890FF);
  static const Color colorFijo   = Color(0xFF1890FF);
  static const Color colorNoFijo = Color(0xFFF0B90B);
  static const Color colorAhorro = Color(0xFF0ECB81);
  static const Color colorDeuda  = Color(0xFFF6465D);

  /// Cambia el tema y reasigna los colores de lienzo.
  static void setMode(bool dark) {
    _isDark = dark;
    if (dark) {
      background    = const Color(0xFF0B0E11);
      surface       = const Color(0xFF1E2026);
      surfaceAlt    = const Color(0xFF2B3139);
      border        = const Color(0xFF2B3139);
      textPrimary   = const Color(0xFFEAECEF);
      textSecondary = const Color(0xFF848E9C);
      textMuted     = const Color(0xFF5E6673);
    } else {
      background    = const Color(0xFFF4F6F8); // gris muy claro
      surface       = const Color(0xFFFFFFFF); // tarjetas blancas
      surfaceAlt    = const Color(0xFFEDF0F3); // inputs/dropdowns
      border        = const Color(0xFFDDE1E7);
      textPrimary   = const Color(0xFF14161A); // texto oscuro
      textSecondary = const Color(0xFF5E6673);
      textMuted     = const Color(0xFF98A1AE);
    }
    modeNotifier.value = dark;
  }

  // ── TEMA GLOBAL ───────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    brightness: _isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme: (_isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: primary,
      secondary: primary,
      surface: surface,
      error: danger,
      onPrimary: onPrimary,
      onSecondary: onPrimary,
      onSurface: textPrimary,
    ),
    appBarTheme: AppBarTheme(
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
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      labelStyle: TextStyle(color: textSecondary, fontSize: 13),
      hintStyle: TextStyle(color: textMuted, fontSize: 14),
      prefixStyle: TextStyle(color: textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
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
        foregroundColor: onPrimary,
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
      checkColor: MaterialStateProperty.all(onPrimary),
      side: BorderSide(color: textSecondary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      thumbColor: primary,
      inactiveTrackColor: surfaceAlt,
      overlayColor: const Color(0x22F0B90B),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: TextTheme(
      bodyLarge:   TextStyle(color: textPrimary,   fontSize: 15),
      bodyMedium:  TextStyle(color: textPrimary,   fontSize: 13),
      bodySmall:   TextStyle(color: textSecondary, fontSize: 12),
      titleLarge:  TextStyle(color: textPrimary,   fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: textPrimary,   fontSize: 16, fontWeight: FontWeight.w600),
      labelSmall:  TextStyle(color: textSecondary, fontSize: 11, letterSpacing: 0.4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: surfaceAlt,
      circularTrackColor: surfaceAlt,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceAlt,
      contentTextStyle: TextStyle(color: textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      behavior: SnackBarBehavior.floating,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: textPrimary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 2,
    ),
  );

  // ── HELPERS ───────────────────────────────────────────────────────────────
  static Color gastoColor(String tipo) {
    switch (tipo) {
      case 'fijo':            return colorFijo;
      case 'fijo_x_periodo':  return colorFijo;
      case 'no fijo':         return colorNoFijo;
      case 'ahorro':          return colorAhorro;
      case 'deuda':           return colorDeuda;
      default:                return textSecondary;
    }
  }

  static String gastoLabel(String tipo) {
    switch (tipo) {
      case 'fijo':            return 'Fijo';
      case 'fijo_x_periodo':  return 'Fijo x período';
      case 'no fijo':         return 'Variable';
      case 'ahorro':          return 'Ahorro';
      case 'deuda':           return 'Deuda';
      default:                return tipo;
    }
  }
}

/// Widget reutilizable: etiqueta con color según el tipo de gasto.
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

/// Widget reutilizable: línea divisoria con una etiqueta centrada.
class LabelDivider extends StatelessWidget {
  final String label;
  const LabelDivider(this.label, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: AppTheme.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
        ),
        Expanded(child: Divider(color: AppTheme.border)),
      ]),
    );
  }
}
