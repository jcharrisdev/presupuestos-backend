import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class FondoSeguridadCard extends StatelessWidget {
  final Map<String, dynamic> fondo;

  const FondoSeguridadCard({super.key, required this.fondo});

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final ahorrado   = _d(fondo['total_ahorrado_actual']);
    final nivel1     = _d(fondo['objetivo_nivel1']);
    final nivel2     = _d(fondo['objetivo_nivel2']);
    final nivel3     = _d(fondo['objetivo_nivel3']);
    final nivelActual = (fondo['nivel_actual'] as num?)?.toInt() ?? 0;
    final pct        = (_d(fondo['pct_nivel1'])).clamp(0.0, 1.0);

    if (nivel1 <= 0) return const SizedBox.shrink();

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
                Icon(Icons.shield_outlined, color: AppTheme.info, size: 16),
                SizedBox(width: 6),
                Text('Fondo de seguridad',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${ahorrado.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('ahorrado',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppTheme.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.info),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                _NivelFila(
                  num: 1,
                  label: '1 período de gastos fijos',
                  monto: nivel1,
                  alcanzado: nivelActual >= 1,
                ),
                const SizedBox(height: 6),
                _NivelFila(
                  num: 2,
                  label: '1 mes completo',
                  monto: nivel2,
                  alcanzado: nivelActual >= 2,
                ),
                const SizedBox(height: 6),
                _NivelFila(
                  num: 3,
                  label: '3 meses (colchón fuerte)',
                  monto: nivel3,
                  alcanzado: nivelActual >= 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NivelFila extends StatelessWidget {
  final int num;
  final String label;
  final double monto;
  final bool alcanzado;

  const _NivelFila({
    required this.num,
    required this.label,
    required this.monto,
    required this.alcanzado,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          alcanzado ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: alcanzado ? AppTheme.success : AppTheme.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Nivel $num — $label',
              style: TextStyle(
                  fontSize: 12,
                  color: alcanzado ? AppTheme.textPrimary : AppTheme.textSecondary)),
        ),
        Text('\$${monto.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: alcanzado ? AppTheme.success : AppTheme.textMuted)),
      ],
    );
  }
}
