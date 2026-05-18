import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';

class CierreAnioScreen extends StatefulWidget {
  final String firebaseUid;
  final int anio;

  const CierreAnioScreen({
    Key? key,
    required this.firebaseUid,
    required this.anio,
  }) : super(key: key);

  @override
  State<CierreAnioScreen> createState() => _CierreAnioScreenState();
}

class _CierreAnioScreenState extends State<CierreAnioScreen> {
  bool _cargando = true;
  bool _cerrando = false;
  bool _cerrado = false;
  String? _error;
  Map<String, dynamic>? _resultado;

  @override
  void initState() {
    super.initState();
    _cargarProyeccion();
  }

  Future<void> _cargarProyeccion() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final data = await EstadoAnualService.getProyeccionSiguienteAnio(
          widget.firebaseUid, widget.anio);
      if (!mounted) return;
      setState(() { _resultado = data; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _cargando = false; });
    }
  }

  Future<void> _confirmarCierre() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Confirmar cierre anual',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          '¿Cerrar el año ${widget.anio} y generar el resumen histórico?\n\n'
          'Los datos quedan preservados. Esta acción puede repetirse si necesitas actualizar.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _cerrando = true);
    try {
      final res = await EstadoAnualService.cerrarAnio(widget.firebaseUid, widget.anio);
      if (!mounted) return;
      setState(() { _resultado = res; _cerrado = true; _cerrando = false; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
      setState(() => _cerrando = false);
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Cierre ${widget.anio}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _cargarProyeccion,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );

  Widget _buildContent() {
    final r = _resultado!;
    final recomendaciones = (r['recomendaciones'] as List? ?? []).cast<Map<String, dynamic>>();
    final ajustes = recomendaciones.where((x) => x['accion'] != 'mantener').toList();
    final mantener = recomendaciones.where((x) => x['accion'] == 'mantener').toList();

    // Si ya fue cerrado, mostrar el resumen anual
    final resumenAnual = r['resumen_anual'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner estado
          if (_cerrado)
            _bannerCerrado()
          else
            _bannerPrevio(recomendaciones.length, ajustes.length),

          const SizedBox(height: 16),

          // Resumen anual (solo si ya se cerró)
          if (resumenAnual != null) ...[
            _seccion('RESUMEN ${widget.anio}'),
            const SizedBox(height: 8),
            _resumenCard(resumenAnual),
            const SizedBox(height: 20),
          ],

          // Recomendaciones con ajuste
          if (ajustes.isNotEmpty) ...[
            _seccion('AJUSTES SUGERIDOS PARA ${widget.anio + 1}'),
            const SizedBox(height: 8),
            ...ajustes.map((rec) => _recCard(rec)),
            const SizedBox(height: 16),
          ],

          // Sin cambios
          if (mantener.isNotEmpty) ...[
            _seccion('SIN CAMBIOS (${mantener.length} categorías)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: mantener.map((rec) => Chip(
                label: Text(rec['categoria'] as String? ?? '',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                backgroundColor: AppTheme.surfaceAlt,
                side: const BorderSide(color: AppTheme.border),
                padding: EdgeInsets.zero,
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Nota del resumen
          if (r['resumen'] != null || r['mensaje'] != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppTheme.primary, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (r['mensaje'] ?? r['resumen'] ?? '') as String,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Botón de cierre
          if (!_cerrado) ...[
            const Divider(color: AppTheme.border),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cerrando ? null : _confirmarCierre,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _cerrando
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text('Cerrar año ${widget.anio}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se guarda un snapshot del año. Puedes volver a ejecutarlo para actualizar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Listo'),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bannerCerrado() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.success.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.success.withOpacity(0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Año ${widget.anio} cerrado',
                  style: const TextStyle(
                      color: AppTheme.success, fontSize: 15, fontWeight: FontWeight.bold)),
              const Text('Snapshot guardado en el historial.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _bannerPrevio(int total, int ajustes) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.analytics_outlined, color: AppTheme.primary, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Análisis del año ${widget.anio}',
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              Text('$total categorías analizadas · $ajustes con ajuste sugerido',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _resumenCard(Map<String, dynamic> res) {
    final ing   = _d(res['ingreso_total']);
    final fijos = _d(res['fijos_total']);
    final vars  = _d(res['variables_total']);
    final noPres = _d(res['no_presupuestados_total']);
    final rem   = _d(res['remanente_real']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _filaStat('Ingreso total', ing, AppTheme.success),
          _filaStat('Gastos fijos', fijos, AppTheme.colorFijo),
          _filaStat('Gastos variables', vars, AppTheme.warning),
          _filaStat('No presupuestados', noPres, AppTheme.danger),
          const Divider(color: AppTheme.border, height: 16),
          _filaStat('Remanente real', rem, rem >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
        ],
      ),
    );
  }

  Widget _filaStat(String label, double valor, Color color, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
            color: AppTheme.textSecondary, fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text('\$${valor.toStringAsFixed(2)}', style: TextStyle(
            color: color, fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
      ],
    ),
  );

  Widget _recCard(Map<String, dynamic> rec) {
    final accion = rec['accion'] as String? ?? '';
    final color  = accion == 'aumentar' ? AppTheme.danger : AppTheme.success;
    final icon   = accion == 'aumentar' ? Icons.trending_up : Icons.trending_down;
    final presup = _d(rec['presupuesto_actual']);
    final avg    = _d(rec['promedio_real_mensual']);
    final noPresupMes = _d(rec['promedio_no_presupuestado']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(rec['categoria'] as String? ?? '',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(rec['recomendacion'] as String? ?? '',
              style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip('Presup. actual \$${presup.toStringAsFixed(0)}/mes', AppTheme.textMuted),
              const SizedBox(width: 6),
              _chip('Promedio real \$${avg.toStringAsFixed(0)}/mes', color),
              if (noPresupMes > 0) ...[
                const SizedBox(width: 6),
                _chip('No presup. \$${noPresupMes.toStringAsFixed(0)}', AppTheme.warning),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(texto, style: TextStyle(color: color, fontSize: 10)),
  );

  Widget _seccion(String t) => Text(t,
      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8));
}
