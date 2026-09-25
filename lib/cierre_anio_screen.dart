import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';
import 'services/gastos_variables_service.dart';
import 'utils/money.dart';

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

  final Set<String> _sugerenciasAplicando = {};
  final Set<String> _sugerenciasAplicadas = {};
  final Set<String> _sugerenciasDescartadas = {};

  Future<void> _aplicarSugerencia(Map<String, dynamic> sug) async {
    final categoria = sug['categoria'] as String;
    final actual = _d(sug['presupuesto_actual']);
    final sugerido = _d(sug['presupuesto_sugerido']);
    if (actual <= 0) return;
    final factor = sugerido / actual;
    setState(() => _sugerenciasAplicando.add(categoria));
    try {
      final items = (sug['items'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final item in items) {
        final nuevoMonto = _d(item['monto_estimado']) * factor;
        await GastosVariablesService.editar(
          widget.firebaseUid, item['id'] as int,
          {'monto_estimado': double.parse(nuevoMonto.toStringAsFixed(2))},
        );
      }
      if (!mounted) return;
      setState(() {
        _sugerenciasAplicando.remove(categoria);
        _sugerenciasAplicadas.add(categoria);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sugerenciasAplicando.remove(categoria));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ajustar: $e'), backgroundColor: AppTheme.danger));
    }
  }

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
        title: Text('Confirmar cierre anual',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          '¿Cerrar el año ${widget.anio} y generar el resumen histórico?\n\n'
          'Los datos quedan preservados. Esta acción puede repetirse si necesitas actualizar.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
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
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        iconTheme: IconThemeData(color: AppTheme.textSecondary),
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
    final sugerencias = (r['sugerencias_presupuesto'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((s) => !_sugerenciasDescartadas.contains(s['categoria']))
        .toList();

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
            _bannerPrevio(sugerencias.length),

          const SizedBox(height: 16),

          // Resumen anual (solo si ya se cerró)
          if (resumenAnual != null) ...[
            _seccion('RESUMEN ${widget.anio}'),
            const SizedBox(height: 8),
            _resumenCard(resumenAnual),
            const SizedBox(height: 20),
          ],

          // Sugerencias de ajuste (nunca se auto-aplican)
          if (sugerencias.isNotEmpty) ...[
            _seccion('PRESUPUESTO SUGERIDO PARA ${widget.anio + 1}'),
            const SizedBox(height: 8),
            ...sugerencias.map((sug) => _sugerenciaCard(sug)),
            const SizedBox(height: 16),
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
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Botón de cierre
          if (!_cerrado) ...[
            Divider(color: AppTheme.border),
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
            Text(
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
                  side: BorderSide(color: AppTheme.border),
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
              Text('Snapshot guardado en el historial.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _bannerPrevio(int ajustes) => Container(
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
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              Text(ajustes > 0
                  ? '$ajustes categoría(s) con ajuste de presupuesto sugerido'
                  : 'Tu presupuesto se mantuvo alineado con lo real',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
          Divider(color: AppTheme.border, height: 16),
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
        Text('${Money.fmt(valor)}', style: TextStyle(
            color: color, fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
      ],
    ),
  );

  /// FIN-04 — mismo patrón visual que _sugerenciaCard de CierreMesSheet:
  /// nunca se auto-aplica, el usuario decide con Ajustar / No, gracias.
  Widget _sugerenciaCard(Map<String, dynamic> sug) {
    final categoria = sug['categoria'] as String? ?? '';
    final nombre = categoria.isNotEmpty ? '${categoria[0].toUpperCase()}${categoria.substring(1)}' : categoria;
    final subir = sug['direccion'] == 'subir';
    final color = subir ? AppTheme.warning : AppTheme.success;
    final actual = _d(sug['presupuesto_actual']);
    final sugerido = _d(sug['presupuesto_sugerido']);
    final aplicando = _sugerenciasAplicando.contains(categoria);
    final aplicada = _sugerenciasAplicadas.contains(categoria);

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
              Icon(subir ? Icons.trending_up : Icons.trending_down, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Ajustar presupuesto de $nombre',
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(sug['razon'] as String? ?? '',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
          const SizedBox(height: 8),
          Row(children: [
            Text(Money.fmt(actual), style: TextStyle(
                color: AppTheme.textMuted, fontSize: 13, decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward, size: 12, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(Money.fmt(sugerido),
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          if (aplicada)
            Row(children: [
              const Icon(Icons.check_circle, color: AppTheme.success, size: 14),
              const SizedBox(width: 6),
              Text('Ajustado para ${widget.anio + 1}',
                  style: TextStyle(color: AppTheme.success, fontSize: 12)),
            ])
          else
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: aplicando ? null : () => setState(() => _sugerenciasDescartadas.add(categoria)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text('No, gracias', style: TextStyle(fontSize: 12)),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                onPressed: aplicando ? null : () => _aplicarSugerencia(sug),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: aplicando
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Ajustar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              )),
            ]),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Text(t,
      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8));
}
