import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'clasificacion_card.dart';
import 'fondo_seguridad_card.dart';
import 'patrones_gustitos_banner.dart';
import 'recomendacion_porcentajes_card.dart';
import 'alertas_banner.dart';

class AnalisisFinancieroSection extends StatelessWidget {
  final Map<String, dynamic>? distribucionClasif;
  final Map<String, dynamic>? recomendacion;
  final Map<String, dynamic>? fondo;
  final Map<String, dynamic>? patrones;
  final Map<String, dynamic>? alertas;
  final VoidCallback onConfigurarIngreso;
  final VoidCallback onAgregarGasto;
  final bool loading;

  const AnalisisFinancieroSection({
    super.key,
    required this.distribucionClasif,
    required this.recomendacion,
    required this.fondo,
    required this.patrones,
    required this.alertas,
    required this.onConfigurarIngreso,
    required this.onAgregarGasto,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(Icons.analytics_outlined,
              color: AppTheme.textSecondary, size: 18),
          title: const Text('ANÁLISIS FINANCIERO',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.expand_more,
              color: AppTheme.textMuted, size: 20),
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                    backgroundColor: AppTheme.surfaceAlt,
                    color: AppTheme.primary),
              )
            else ...[
              AlertasBanner(alertasData: alertas),
              ClasificacionCard(distribucion: distribucionClasif),
              RecomendacionPorcentajesCard(
                recomendacion: recomendacion,
                onConfigurarIngreso: onConfigurarIngreso,
              ),
              if (fondo != null) FondoSeguridadCard(fondo: fondo!),
              PatronesGustitosBanner(
                patrones: patrones,
                onAgregarGasto: (_) => onAgregarGasto(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
