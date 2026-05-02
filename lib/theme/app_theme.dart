/// Tema visual global inspirado en la interfaz de Binance.
///
/// Paleta oscura con fondo casi negro (#0B0E11), superficie elevada (#1E2026),
/// acento amarillo (#F0B90B), verde éxito (#0ECB81) y rojo peligro (#F6465D).
/// Toda la app usa exclusivamente estas constantes para mantener coherencia visual.
import 'package:flutter/material.dart';

/// Contiene todos los colores, el [ThemeData] y helpers visuales de la app.
///
/// NUNCA usar `Colors.xxx` directamente en los widgets — siempre usar las
/// constantes de [AppTheme] para que el cambio a tema claro (si se desea
/// en el futuro) sea un cambio de un solo archivo.
class AppTheme {
  // ─── COLORES BASE ─────────────────────────────────────────────────────────

  /// Fondo principal de todas las pantallas. Negro profundo estilo Binance.
  static const Color background   = Color(0xFF0B0E11);

  /// Superficie de tarjetas, modales y AppBar. Ligeramente más claro que el fondo.
  static const Color surface      = Color(0xFF1E2026);

  /// Superficie alternativa para inputs, dropdowns y fondos secundarios.
  static const Color surfaceAlt   = Color(0xFF2B3139);

  /// Color de bordes de tarjetas, divisores y separadores.
  static const Color border       = Color(0xFF2B3139);

  // ─── ACENTO PRINCIPAL ─────────────────────────────────────────────────────

  /// Amarillo dorado Binance — color de marca, botones principales y activos.
  static const Color primary      = Color(0xFFF0B90B);

  /// Versión más oscura del amarillo para estados pressed/hover.
  static const Color primaryDark  = Color(0xFFCF9A09);

  // ─── TEXTO ────────────────────────────────────────────────────────────────

  /// Texto de alta prioridad: títulos, montos grandes, nombres.
  static const Color textPrimary   = Color(0xFFEAECEF);

  /// Texto secundario: subtítulos, etiquetas de campos, descripciones.
  static const Color textSecondary = Color(0xFF848E9C);

  /// Texto de baja prioridad: placeholders, fechas, metadatos.
  static const Color textMuted     = Color(0xFF5E6673);

  // ─── ESTADOS / SEMÁFORO ───────────────────────────────────────────────────

  /// Verde: pagado, completado, disponible, ganancia positiva.
  static const Color success = Color(0xFF0ECB81);

  /// Rojo: excedido, vencido, error, pérdida.
  static const Color danger  = Color(0xFFF6465D);

  /// Amarillo: alerta, próximo a vencer (≤3 días), casi al límite (≥85%).
  static const Color warning = Color(0xFFF0B90B);

  /// Azul informativo (reservado para uso futuro o cobros pendientes).
  static const Color info    = Color(0xFF1890FF);

  // ─── COLORES POR TIPO DE GASTO ────────────────────────────────────────────

  /// Azul para gastos fijos (alquiler, servicios recurrentes).
  static const Color colorFijo     = Color(0xFF1890FF);

  /// Amarillo para gastos variables/no fijos (supermercado, restaurantes).
  static const Color colorNoFijo   = Color(0xFFF0B90B);

  /// Verde para gastos de ahorro (metas, reservas).
  static const Color colorAhorro   = Color(0xFF0ECB81);

  // ─── TEMA GLOBAL ──────────────────────────────────────────────────────────

  /// [ThemeData] completo para inyectar en [MaterialApp.theme].
  ///
  /// Configura: AppBar, Card, TextField, ElevatedButton, TextButton,
  /// Checkbox, Slider, Divider, Text, ProgressIndicator, SnackBar,
  /// DropdownMenu y FAB con los colores de [AppTheme].
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primary,
      surface: surface,
      background: background,
      error: danger,
      onPrimary: background,      // texto encima de botones amarillos → negro
      onSecondary: background,
      onSurface: textPrimary,
      onBackground: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,               // sin sombra → apariencia flat
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
      // Borde amarillo cuando el campo está enfocado
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: background,   // texto negro sobre botón amarillo
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
      // Relleno amarillo solo cuando está seleccionado; transparente si no
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
      overlayColor: Color(0x22F0B90B),  // halo semi-transparente al arrastrar
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: const TextTheme(
      bodyLarge:   TextStyle(color: textPrimary,   fontSize: 15),
      bodyMedium:  TextStyle(color: textPrimary,   fontSize: 13),
      bodySmall:   TextStyle(color: textSecondary, fontSize: 12),
      titleLarge:  TextStyle(color: textPrimary,   fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: textPrimary,   fontSize: 16, fontWeight: FontWeight.w600),
      labelSmall:  TextStyle(color: textSecondary, fontSize: 11, letterSpacing: 0.4),
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

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  /// Devuelve el color asociado a un tipo de gasto.
  ///
  /// Útil para puntitos del calendario, bordes de chips y barras de progreso.
  static Color gastoColor(String tipo) {
    switch (tipo) {
      case 'fijo':            return colorFijo;
      case 'fijo_x_periodo':  return colorFijo;   // mismo color que fijo
      case 'no fijo':         return colorNoFijo;
      case 'ahorro':          return colorAhorro;
      default:                return textSecondary;
    }
  }

  /// Devuelve la etiqueta legible para el tipo de gasto.
  ///
  /// `'fijo_x_periodo'` → `'Fijo x período'`, etc.
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

/// Widget reutilizable: etiqueta con color según el tipo de gasto.
///
/// Muestra una pequeña pastilla coloreada con el nombre del tipo.
/// Ejemplo de uso:
/// ```dart
/// TipoChip('fijo')      // → pastilla azul "Fijo"
/// TipoChip('no fijo')   // → pastilla amarilla "Variable"
/// TipoChip('ahorro')    // → pastilla verde "Ahorro"
/// ```
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
///
/// Se usa para separar secciones dentro de pantallas de detalle.
/// Ejemplo: `LabelDivider('MOVIMIENTOS')` produce:
/// ──────────── MOVIMIENTOS ────────────
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
