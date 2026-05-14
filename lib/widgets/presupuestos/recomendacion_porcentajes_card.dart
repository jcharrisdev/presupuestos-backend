import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecomendacionPorcentajesCard extends StatelessWidget {
  final Map<String, dynamic>? recomendacion;
  final VoidCallback onConfigurarIngreso;
  const RecomendacionPorcentajesCard({
    Key? key,
    required this.recomendacion,
    required this.onConfigurarIngreso,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (recomendacion == null) return const SizedBox.shrink();

    final tieneIncome = recomendacion!['tiene_income'] as bool? ?? false;
    final categorias = recomendacion!['categorias'] as List? ?? [];
    final sinClasif = _d(recomendacion!['sin_clasificar']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.percent, color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('Regla 50/30/20',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14))),
          if (!tieneIncome)
            GestureDetector(
              onTap: onConfigurarIngreso,
              child: const Text('+ Ingreso',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
        if (!tieneIncome)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Basado en tu presupuesto total. Configura tu ingreso neto para mayor precisión.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4)),
          ),
        const SizedBox(height: 14),
        ...categorias.map((c) => _CategoriaRow(c as Map<String, dynamic>)),
        if (sinClasif > 0) ...[
          const Divider(color: AppTheme.border, height: 20),
          Row(children: [
            const Icon(Icons.help_outline, color: AppTheme.textMuted, size: 13),
            const SizedBox(width: 6),
            Text('\$${sinClasif.toStringAsFixed(2)} sin clasificar',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ]),
        ],
      ]),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _CategoriaRow extends StatelessWidget {
  final Map<String, dynamic> cat;
  const _CategoriaRow(this.cat);

  @override
  Widget build(BuildContext context) {
    final label          = cat['label'] as String? ?? '';
    final montoRec       = _d(cat['monto_recomendado']);
    final montoReal      = _d(cat['monto_real']);
    final dif            = _d(cat['diferencia']);
    final pctRec         = (_d(cat['pct_recomendado']) * 100).round();
    final clasificacion  = cat['clasificacion'] as String? ?? '';

    Color color;
    switch (clasificacion) {
      case 'esencial':   color = const Color(0xFF1890FF); break;
      case 'importante': color = AppTheme.primary; break;
      case 'flexible':   color = AppTheme.success; break;
      default:           color = AppTheme.textSecondary;
    }

    final pctReal = montoRec > 0 ? (montoReal / montoRec).clamp(0.0, 1.5) : 0.0;
    final enRango = dif.abs() <= montoRec * 0.1;  // dentro de ±10%
    final colorDif = dif > montoRec * 0.1 ? AppTheme.danger : (enRango ? AppTheme.success : AppTheme.warning);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
          Text('$pctRec%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Stack(children: [
          Container(
            height: 6, decoration: BoxDecoration(
              color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(3)),
          ),
          FractionallySizedBox(
            widthFactor: pctReal.clamp(0.0, 1.0),
            child: Container(
              height: 6, decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('Real: \$${montoReal.toStringAsFixed(0)}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(width: 6),
          Text('/ \$${montoRec.toStringAsFixed(0)} rec.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          const Spacer(),
          if (montoReal > 0 || montoRec > 0)
            Text(
              dif > 0 ? '+\$${dif.toStringAsFixed(0)}' : '-\$${dif.abs().toStringAsFixed(0)}',
              style: TextStyle(color: colorDif, fontSize: 11, fontWeight: FontWeight.w600),
            ),
        ]),
      ]),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
