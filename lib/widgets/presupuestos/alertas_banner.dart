import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AlertasBanner extends StatelessWidget {
  final Map<String, dynamic>? alertasData;
  const AlertasBanner({Key? key, required this.alertasData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (alertasData == null) return const SizedBox.shrink();
    final alertas = alertasData!['alertas'] as List? ?? [];
    if (alertas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alertas.map<Widget>((a) => _AlertaTile(a as Map<String, dynamic>)).toList(),
    );
  }
}

class _AlertaTile extends StatelessWidget {
  final Map<String, dynamic> alerta;
  const _AlertaTile(this.alerta);

  @override
  Widget build(BuildContext context) {
    final nivel = alerta['nivel'] as String? ?? 'info';
    Color color;
    IconData icon;
    switch (nivel) {
      case 'danger':
        color = AppTheme.danger; icon = Icons.warning_rounded; break;
      case 'warning':
        color = AppTheme.warning; icon = Icons.info_outline; break;
      default:
        color = AppTheme.info; icon = Icons.notifications_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alerta['titulo'] ?? '',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(alerta['mensaje'] ?? '',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }
}
