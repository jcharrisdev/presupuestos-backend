import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/money.dart';

/// Dashboard y Mes muestran el mismo contrato del backend, sin recalcular caja.
class ResumenMensualCard extends StatelessWidget {
  final Map<String, dynamic> resumen;

  const ResumenMensualCard({super.key, required this.resumen});

  // Durante una actualización pueden quedar respuestas del backend anterior
  // en caché. La pantalla conserva su vista anterior hasta tener todo el contrato.
  static bool tieneDatos(Map<String, dynamic> resumen) => const [
        'ingreso_real',
        'gastos_registrados',
        'gastos_pagados',
        'gastos_pendientes',
        'compromisos_pendientes',
        'total_pendiente',
        'disponible_real',
        'disponible_proyectado',
      ].every((campo) {
        final valor = double.tryParse(resumen[campo]?.toString() ?? '');
        return valor != null && valor.isFinite;
      });

  double _monto(String campo) => double.parse(resumen[campo].toString());

  @override
  Widget build(BuildContext context) {
    final real = _monto('disponible_real');
    final proyectado = _monto('disponible_proyectado');
    final color = proyectado < 0 ? AppTheme.danger : AppTheme.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disponible tras pagos',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(Money.fmt(real),
              style: TextStyle(
                  color: real < 0 ? AppTheme.danger : AppTheme.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _fila('Ingreso de referencia', _monto('ingreso_real')),
          if (resumen['ingreso_es_estimado'] == true)
            Text('Se está usando el ingreso estimado del mes.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          _fila('Gastos pagados', _monto('gastos_pagados')),
          _fila('Gastos registrados sin pagar', _monto('gastos_pendientes')),
          _fila('Compromisos aún sin registrar', _monto('compromisos_pendientes')),
          Divider(color: AppTheme.border, height: 22),
          _fila('Total pendiente', _monto('total_pendiente')),
          _fila('Tras pagar los pendientes', proyectado, color: color, bold: true),
          const SizedBox(height: 8),
          Text(
            proyectado < 0
                ? 'Los pagos pendientes superan tu disponible.'
                : 'Los pagos pendientes están cubiertos con este ingreso.',
            style: TextStyle(color: color, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            'El total pendiente incluye gastos sin pagar y compromisos fijos, '
            'deudas y cuotas de eventos del mes. El presupuesto variable '
            'aún sin registrar se consulta en el detalle del plan.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, double monto, {Color? color, bool bold = false}) {
    final estilo = TextStyle(
      color: color ?? AppTheme.textPrimary,
      fontSize: 12,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: estilo)),
          const SizedBox(width: 12),
          Flexible(child: Text(Money.fmt(monto), textAlign: TextAlign.right, style: estilo)),
        ],
      ),
    );
  }
}
