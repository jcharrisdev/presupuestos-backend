import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class PatronesGustitosBanner extends StatefulWidget {
  final Map<String, dynamic>? patrones;
  final void Function(String categoria) onAgregarGasto;

  const PatronesGustitosBanner({
    super.key,
    required this.patrones,
    required this.onAgregarGasto,
  });

  @override
  State<PatronesGustitosBanner> createState() => _PatronesGustitosBannerState();
}

class _PatronesGustitosBannerState extends State<PatronesGustitosBanner> {
  bool _ignorado = false;

  @override
  Widget build(BuildContext context) {
    if (_ignorado) return const SizedBox.shrink();
    if (widget.patrones == null) return const SizedBox.shrink();
    if (widget.patrones!['tiene_patrones'] != true) return const SizedBox.shrink();

    final lista = widget.patrones!['patrones'] as List<dynamic>? ?? [];
    if (lista.isEmpty) return const SizedBox.shrink();

    final top = lista.first as Map<String, dynamic>;
    final categoria = top['category'] as String? ?? '';
    final periodos  = (top['periodos_con_gasto'] as num?)?.toInt() ?? 2;
    final promedio  = double.tryParse(top['monto_promedio']?.toString() ?? '0') ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gastas regularmente en "$categoria"',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aparece en $periodos períodos · promedio \$${promedio.toStringAsFixed(2)} por Gustito',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => widget.onAgregarGasto(categoria),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Agregar como gasto',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _ignorado = true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Ignorar',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
