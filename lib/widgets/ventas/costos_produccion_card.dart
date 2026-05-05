import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class CostosProduccionCard extends StatelessWidget {
  final List<dynamic> presupuestos;
  final double invertido;

  const CostosProduccionCard({
    Key? key,
    required this.presupuestos,
    required this.invertido,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (presupuestos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...presupuestos.map((pp) {
          final ppTotal = double.tryParse(pp['total_invertido']?.toString() ?? '0') ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.colorFijo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: AppTheme.colorFijo, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(pp['nombre']?.toString() ?? '',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
              Text('\$${ppTotal.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.colorFijo, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          );
        }),
        if (presupuestos.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.colorFijo.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.colorFijo.withOpacity(0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total invertido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('\$${invertido.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.colorFijo, fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
          ),
      ],
    );
  }
}
