import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ClasificacionCard extends StatelessWidget {
  final Map<String, dynamic>? distribucion;
  const ClasificacionCard({Key? key, required this.distribucion}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (distribucion == null) return const SizedBox.shrink();
    final dist = distribucion!['distribucion'] as Map<String, dynamic>? ?? {};
    if (dist.isEmpty) return const SizedBox.shrink();

    final esencial  = _parse(dist['esencial']);
    final importante = _parse(dist['importante']);
    final flexible  = _parse(dist['flexible']);
    final sinClasif = _parse(dist['sin_clasificar']);
    final montoTotal = _d(distribucion!['monto_total']);

    final total = esencial + importante + flexible + sinClasif;
    if (total <= 0) return const SizedBox.shrink();

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
          const Icon(Icons.pie_chart_outline, color: AppTheme.textSecondary, size: 16),
          const SizedBox(width: 8),
          const Text('Distribución por clasificación',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 14),
        if (esencial > 0)
          _ClasifRow('Esencial', esencial, montoTotal, const Color(0xFF1890FF)),
        if (importante > 0)
          _ClasifRow('Importante', importante, montoTotal, AppTheme.primary),
        if (flexible > 0)
          _ClasifRow('Flexible', flexible, montoTotal, AppTheme.success),
        if (sinClasif > 0)
          _ClasifRow('Sin clasificar', sinClasif, montoTotal, AppTheme.textMuted),
      ]),
    );
  }

  double _parse(dynamic v) {
    if (v == null) return 0;
    if (v is Map) return _d(v['total']);
    return _d(v);
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _ClasifRow extends StatelessWidget {
  final String label;
  final double monto;
  final double total;
  final Color color;
  const _ClasifRow(this.label, this.monto, this.total, this.color);

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (monto / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
          Text('\$${monto.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('(${(pct * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 5,
          ),
        ),
      ]),
    );
  }
}
