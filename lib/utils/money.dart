import 'package:intl/intl.dart';

/// Formateador único de montos para toda la app (F3 + W3).
///
/// Estándar Panamá: símbolo `B/.` + separador de miles + 2 decimales.
/// Ej: Money.fmt(1200) → "B/. 1,200.00"
///
/// Uso recomendado en lugar de `'\$${v.toStringAsFixed(2)}'` suelto.
/// El símbolo se controla SOLO aquí: cambiar `_sym` migra toda la app.
class Money {
  static const String _sym = 'B/. ';
  static final NumberFormat _f = NumberFormat('#,##0.00', 'en_US');

  /// "B/. 1,200.00" — con separador de miles.
  static String fmt(num? v) => '$_sym${_f.format(v ?? 0)}';

  /// "B/. 1,200" — sin decimales (para metas/totales redondeados).
  static String fmt0(num? v) => '$_sym${NumberFormat('#,##0', 'en_US').format(v ?? 0)}';

  /// "1,200.00" — sin símbolo, para componer textos.
  static String plain(num? v) => _f.format(v ?? 0);
}
