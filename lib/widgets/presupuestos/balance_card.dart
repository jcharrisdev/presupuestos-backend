import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class BalanceCard extends StatelessWidget {
  final double montoTotal;
  final double totalGastado;
  final double disponible;
  final double pctGasto;
  final Color barColor;

  const BalanceCard({
    Key? key,
    required this.montoTotal,
    required this.totalGastado,
    required this.disponible,
    required this.pctGasto,
    required this.barColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Presupuesto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        Text('\$${montoTotal.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 32,
                fontWeight: FontWeight.w800, letterSpacing: -1)),
        const SizedBox(height: 20),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
          value: pctGasto, minHeight: 8,
          backgroundColor: AppTheme.surfaceAlt, color: barColor,
        )),
        const SizedBox(height: 10),
        Row(children: [
          Text('Gastado \$${totalGastado.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          Text(
            disponible >= 0
                ? 'Disponible \$${disponible.toStringAsFixed(2)}'
                : 'Excedido \$${(-disponible).toStringAsFixed(2)}',
            style: TextStyle(
              color: disponible >= 0 ? AppTheme.success : AppTheme.danger,
              fontSize: 12, fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ]),
    );
  }
}
