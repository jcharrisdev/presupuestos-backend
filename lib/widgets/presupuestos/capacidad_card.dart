import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class CapacidadCard extends StatelessWidget {
  final Map<String, dynamic>? capacidad;
  final VoidCallback onConfigurar;

  const CapacidadCard({
    super.key,
    required this.capacidad,
    required this.onConfigurar,
  });

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final tieneIncome = capacidad != null && capacidad!['tiene_income'] == true;

    if (!tieneIncome) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: AppTheme.textSecondary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Capacidad real de pago',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  SizedBox(height: 2),
                  Text('Configura tu ingreso para ver cuánto puedes comprometer',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            TextButton(
              onPressed: onConfigurar,
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              child: const Text('Configurar'),
            ),
          ],
        ),
      );
    }

    final ingresoNeto     = _d(capacidad!['ingreso_neto']);
    final fijos           = _d(capacidad!['gastos_fijos_totales']);
    final variables       = _d(capacidad!['promedio_variable_historico']);
    final capacidadR      = _d(capacidad!['capacidad_real']);
    final positivo        = capacidadR >= 0;
    final cuotasDeudas    = _d(capacidad!['cuotas_deudas_periodo']);
    final numDeudas       = (capacidad!['num_deudas_activas'] as num?)?.toInt() ?? 0;
    // Mostrar aviso si las deudas representan una cantidad significativa y podrían no estar en los fijos
    final mostrarAvisoDeudas = numDeudas > 0 && cuotasDeudas > 0 && cuotasDeudas > fijos * 0.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: const [
                Icon(Icons.account_balance_wallet_outlined,
                    color: AppTheme.primary, size: 16),
                SizedBox(width: 6),
                Text('Capacidad real de pago',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          // Número grande
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              '\$${capacidadR.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: positivo ? AppTheme.success : AppTheme.danger,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: AppTheme.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _Fila('Ingreso neto', ingresoNeto, AppTheme.success),
                _Fila('Gastos fijos', -fijos, AppTheme.danger),
                _Fila('Var. promedio histórico', -variables, AppTheme.textSecondary),
                if (mostrarAvisoDeudas) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, color: AppTheme.warning, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        'Tienes cuotas de deuda por \$${cuotasDeudas.toStringAsFixed(2)}/período. '
                        '¿Están incluidas en tus gastos fijos?',
                        style: const TextStyle(color: AppTheme.warning, fontSize: 11, height: 1.4),
                      )),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final double monto;
  final Color color;
  const _Fila(this.label, this.monto, this.color);

  @override
  Widget build(BuildContext context) {
    final sign = monto >= 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
          Text('$sign\$${monto.abs().toStringAsFixed(2)}',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
