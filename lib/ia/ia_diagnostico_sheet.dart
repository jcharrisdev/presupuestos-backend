import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/ia_service.dart';

class IaDiagnosticoSheet extends StatefulWidget {
  final String firebaseUid;
  final int? presupuestoId;

  const IaDiagnosticoSheet({
    super.key,
    required this.firebaseUid,
    this.presupuestoId,
  });

  static Future<void> show(BuildContext context, String uid, {int? presupuestoId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IaDiagnosticoSheet(firebaseUid: uid, presupuestoId: presupuestoId),
    );
  }

  @override
  State<IaDiagnosticoSheet> createState() => _IaDiagnosticoSheetState();
}

class _IaDiagnosticoSheetState extends State<IaDiagnosticoSheet> {
  String? _diagnostico;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final r = await IaService.diagnostico(widget.firebaseUid, presupuestoId: widget.presupuestoId);
      if (mounted) setState(() { _diagnostico = r['diagnostico'] as String?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(children: [
          Center(child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Text('Diagnóstico IA',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!_loading)
                IconButton(
                  icon: Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
                  onPressed: _cargar,
                  tooltip: 'Regenerar',
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Analizo tu perfil y te digo qué te falta para entender tus finanzas con claridad.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Divider(color: AppTheme.border, height: 1),
          Expanded(
            child: _loading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _buildResultado(ctrl),
          ),
        ]),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 40, height: 40,
            child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5)),
        const SizedBox(height: 20),
        Text('Analizando tu situación financiera…',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Claude consulta tus datos reales. Puede tomar unos segundos.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.wifi_off_outlined, color: AppTheme.textMuted, size: 40),
        const SizedBox(height: 16),
        Text('No se pudo conectar',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_error ?? '', style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reintentar'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
        ),
      ]),
    );
  }

  Widget _buildResultado(ScrollController ctrl) {
    return ListView(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Text(
            _diagnostico ?? '',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.65),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.verified_outlined, color: AppTheme.textMuted, size: 12),
          const SizedBox(width: 6),
          Text('Generado por Claude AI · Anthropic',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
      ],
    );
  }
}
