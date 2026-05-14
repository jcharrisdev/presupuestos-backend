import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class ProyeccionMesCard extends StatelessWidget {
  final Map<String, dynamic> mes;
  final VoidCallback? onTap;

  const ProyeccionMesCard({super.key, required this.mes, this.onTap});

  static final _fmt = NumberFormat('#,##0.00', 'es');

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final tipo          = mes['tipo'] as String? ?? 'proyectado';
    final mesLabel      = mes['mes_label'] as String? ?? '';
    final ingreso       = _d(mes['ingreso_proyectado']);
    final gastos        = _d(mes['gastos_proyectados']);
    final saldo         = _d(mes['saldo_estimado']);
    final fijo          = _d(mes['total_fijo']);
    final variable      = _d(mes['total_variable']);
    final ahorro        = _d(mes['total_ahorro']);
    final isProyectado  = tipo == 'proyectado';
    final isActivo      = tipo == 'activo';

    final saldoColor = saldo >= 0 ? AppTheme.success : AppTheme.danger;
    final prefix     = isProyectado ? '~' : '';

    Color badgeColor;
    String badgeLabel;
    switch (tipo) {
      case 'activo':
        badgeColor = AppTheme.primary; badgeLabel = 'Activo'; break;
      case 'real':
        badgeColor = AppTheme.textMuted; badgeLabel = 'Cerrado'; break;
      default:
        badgeColor = AppTheme.textMuted; badgeLabel = 'Proyectado';
    }

    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActivo
            ? AppTheme.primary.withValues(alpha: 0.05)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActivo ? AppTheme.primary : AppTheme.border,
          width: isActivo ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: mes + badge
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(mesLabel, style: TextStyle(
            color: isProyectado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            fontStyle: isProyectado ? FontStyle.italic : FontStyle.normal,
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
            ),
            child: Text(badgeLabel,
                style: TextStyle(color: badgeColor, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),

        // Ingreso
        _Row('Ingreso', ingreso, AppTheme.success, prefix: prefix),
        const SizedBox(height: 4),

        // Breakdown gastos
        if (fijo > 0 || variable > 0 || ahorro > 0) ...[
          _Row('Fijos', fijo, AppTheme.colorFijo, prefix: prefix, small: true),
          if (variable > 0)
            _Row('Variables', variable, AppTheme.colorNoFijo, prefix: prefix, small: true),
          if (ahorro > 0)
            _Row('Ahorro', ahorro, AppTheme.colorAhorro, prefix: prefix, small: true),
        ] else
          _Row('Gastos', gastos, AppTheme.danger, prefix: prefix),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: AppTheme.border, height: 1),
        ),

        // Saldo
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Saldo estimado',
              style: TextStyle(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600, fontSize: 13)),
          Text('$prefix\$${_fmt.format(saldo.abs())}',
              style: TextStyle(
                  color: saldoColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ]),
      ]),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }
    return content;
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double monto;
  final Color color;
  final String prefix;
  final bool small;

  static final _fmt = NumberFormat('#,##0.00', 'es');

  const _Row(this.label, this.monto, this.color,
      {this.prefix = '', this.small = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: small ? 11 : 12)),
      Text('$prefix\$${_fmt.format(monto)}',
          style: TextStyle(
              color: color,
              fontWeight: small ? FontWeight.w500 : FontWeight.w600,
              fontSize: small ? 11 : 12)),
    ]);
  }
}
