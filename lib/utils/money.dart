import 'package:intl/intl.dart';

/// Formateador único de montos para toda la app (F3).
///
/// Estándar: separador de miles + 2 decimales, símbolo `$` por delante.
/// Ej: Money.fmt(1200) → "$1,200.00"
///
/// Uso recomendado en lugar de `'\$${v.toStringAsFixed(2)}'` suelto.
/// La migración del símbolo a `B/.` (mejora W3) se controla desde aquí
/// en un solo lugar el día que se decida.
class Money {
  static final NumberFormat _f = NumberFormat('#,##0.00', 'en_US');

  /// "$1,200.00" — con separador de miles.
  static String fmt(num? v) => '\$${_f.format(v ?? 0)}';

  /// "$1,200" — sin decimales (para metas/totales redondeados).
  static String fmt0(num? v) => '\$${NumberFormat('#,##0', 'en_US').format(v ?? 0)}';

  /// "1,200.00" — sin símbolo, para componer textos.
  static String plain(num? v) => _f.format(v ?? 0);
}
