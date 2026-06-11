/// Tarjeta de objetivo de ganancia en la pantalla de detalle de venta.
///
/// El usuario selecciona un porcentaje de ganancia deseado y la tarjeta
/// calcula cuánto necesita vender para alcanzarlo usando markup sobre costo.
///
/// Fórmula: precio_objetivo = invertido × (1 + markup)
/// Ej: $12 invertido con 50% markup → necesita vender $18.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/money.dart';

class MargenObjetivoCard extends StatelessWidget {
  final double invertido;
  final double totalCobrado;
  final double margenObjetivo;
  final void Function(double) onMargenChanged;

  const MargenObjetivoCard({
    Key? key,
    required this.invertido,
    required this.totalCobrado,
    required this.margenObjetivo,
    required this.onMargenChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const mrgValues = [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.75, 1.00];
    const mrgLabels = [
      '10% – Mínimo', '15% – Básico', '20% – Razonable',
      '25% – Sólido', '30% – Bueno', '35% – Muy bueno',
      '40% – Excelente', '50% – Óptimo', '60% – Muy bueno',
      '75% – Excelente', '100% – Premium',
    ];

    // esperado = totalCobrado (suma de todos los cobros: cobrados + pendientes)
    final esperado = totalCobrado;

    // Markup: precio_objetivo = invertido × (1 + markup). Ganancia sobre el costo.
    final ventasNecesarias = invertido > 0
        ? invertido * (1.0 + margenObjetivo)
        : 0.0;
    final brecha = ventasNecesarias > 0 ? (esperado - ventasNecesarias) : 0.0;
    final pctAvance = ventasNecesarias > 0
        ? (esperado / ventasNecesarias).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selector de margen objetivo
        Row(children: [
          const Icon(Icons.flag_outlined, color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          const Text('% de ganancia sobre costo',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          DropdownButton<double>(
            value: margenObjetivo,
            dropdownColor: AppTheme.surfaceAlt,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(
                color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
            items: List.generate(
              mrgValues.length,
              (i) => DropdownMenuItem(
                value: mrgValues[i],
                child: Text(mrgLabels[i],
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ),
            ),
            onChanged: (v) { if (v != null) onMargenChanged(v); },
          ),
        ]),

        if (invertido <= 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.textMuted, size: 14),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Registra la inversión para calcular el objetivo de ventas.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              )),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          // Ventas necesarias para el margen objetivo
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(
              'Ventas para ${(margenObjetivo * 100).toStringAsFixed(0)}% de ganancia',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )),
            const SizedBox(width: 8),
            Text('${Money.fmt(ventasNecesarias)}',
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),

          if (esperado > 0) ...[
            const SizedBox(height: 10),
            // Progreso hacia el objetivo
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Ventas proyectadas: ${Money.fmt(esperado)}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              Text(
                '${(pctAvance * 100).toStringAsFixed(0)}% del objetivo',
                style: TextStyle(
                  color: pctAvance >= 1.0 ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 11, fontWeight: FontWeight.w600,
                ),
              ),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pctAvance,
                minHeight: 7,
                backgroundColor: AppTheme.surfaceAlt,
                color: pctAvance >= 1.0 ? AppTheme.success : AppTheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            // Badge de brecha
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: brecha >= 0
                    ? AppTheme.success.withOpacity(0.08)
                    : AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: brecha >= 0
                      ? AppTheme.success.withOpacity(0.2)
                      : AppTheme.danger.withOpacity(0.2),
                ),
              ),
              child: Row(children: [
                Icon(
                  brecha >= 0
                      ? Icons.check_circle_outline
                      : Icons.arrow_upward_outlined,
                  color: brecha >= 0 ? AppTheme.success : AppTheme.danger,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  brecha >= 0
                      ? 'Superarás el objetivo en ${Money.fmt(brecha.abs())}'
                      : 'Faltan ${Money.fmt(brecha.abs())} en ventas para el objetivo',
                  style: TextStyle(
                    color: brecha >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                )),
              ]),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Agrega clientes para comparar con el objetivo.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ],
      ]),
    );
  }
}
