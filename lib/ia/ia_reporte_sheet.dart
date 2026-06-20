import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../services/ia_service.dart';
import '../services/api_client.dart';

class IaReporteSheet extends StatefulWidget {
  final String firebaseUid;

  const IaReporteSheet({super.key, required this.firebaseUid});

  static Future<void> show(BuildContext context, String uid) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IaReporteSheet(firebaseUid: uid),
    );
  }

  @override
  State<IaReporteSheet> createState() => _IaReporteSheetState();
}

class _IaReporteSheetState extends State<IaReporteSheet> {
  String? _reporte;
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
      final r = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (r.statusCode != 200) throw Exception('Error al obtener presupuestos');
      final body = jsonDecode(r.body);
      final lista = (body is List ? body : (body['presupuestos'] ?? [])) as List;
      if (lista.isEmpty) {
        throw Exception('No tienes ningún presupuesto activo todavía.');
      }
      final presupuestoId = lista.first['id'] as int;
      final rr = await IaService.reporte(widget.firebaseUid, presupuestoId: presupuestoId);
      if (mounted) setState(() { _reporte = rr['reporte'] as String?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
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
              Text('Reporte IA',
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
              'Narrativa financiera de tu período activo en lenguaje claro.',
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
        Text('Generando tu reporte…',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Claude revisa tus gastos, deudas y tendencia histórica.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline, color: AppTheme.textMuted, size: 40),
        const SizedBox(height: 16),
        Text('No se pudo generar el reporte',
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
          child: MarkdownBody(
            data: _reporte ?? '',
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.65),
              strong: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
              h2: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 15),
              h3: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              listBullet: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            shrinkWrap: true,
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
