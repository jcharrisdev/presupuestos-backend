import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/estado_anual_service.dart';
import '../../services/registros_service.dart';
import '../../services/gastos_variables_service.dart';
import '../../utils/money.dart';

/// Wizard de cierre mensual.
/// Recibe los datos ya cargados del mes (data de getMes) y las alertas.
/// Muestra: resumen estimado vs real → pagos pendientes → alertas → confirmación.
class CierreMesSheet extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final int mes;
  final String labelMes;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> alertas;

  const CierreMesSheet({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    required this.mes,
    required this.labelMes,
    required this.data,
    required this.alertas,
  }) : super(key: key);

  @override
  State<CierreMesSheet> createState() => _CierreMesSheetState();
}

class _CierreMesSheetState extends State<CierreMesSheet> {
  int _paso = 0; // 0=resumen, 1=pendientes, 2=alertas, 3=confirmar
  bool _cerrando = false;
  late List<Map<String, dynamic>> _pendientes;

  // FIN-03: motor rico de FIN-02 (insights + sugerencias de ajuste de
  // presupuesto). Si falla o sigue cargando, el resumen usa el insight
  // simple de siempre como respaldo — nunca deja al usuario sin nada.
  Map<String, dynamic>? _variaciones;
  final Set<String> _sugerenciasAplicando = {};
  final Set<String> _sugerenciasAplicadas = {};
  final Set<String> _sugerenciasDescartadas = {};

  @override
  void initState() {
    super.initState();
    final registros = (widget.data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    _pendientes = registros.where((r) => r['pagado'] == 0 || r['pagado'] == false).toList();
    // Si no hay pendientes ni alertas, saltar directo a confirmar
    if (_pendientes.isEmpty && widget.alertas.isEmpty) _paso = 3;
    _cargarVariaciones();
  }

  Future<void> _cargarVariaciones() async {
    try {
      final data = await EstadoAnualService.getAnalisisVariaciones(
        widget.firebaseUid, widget.anio, widget.mes);
      if (mounted) setState(() => _variaciones = data);
    } catch (_) {
      // Sin conexión al motor nuevo: el resumen sigue con el insight simple.
    }
  }

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

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  Future<void> _marcarPagado(Map<String, dynamic> registro) async {
    try {
      await RegistrosService.marcarPagado(
        widget.firebaseUid, registro['id'] as int, true);
      if (!mounted) return;
      setState(() {
        registro['pagado'] = 1;
        _pendientes = _pendientes.where((r) => r['pagado'] == 0 || r['pagado'] == false).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _confirmarCierre() async {
    setState(() => _cerrando = true);
    try {
      await EstadoAnualService.cerrarMes(widget.firebaseUid, widget.anio, widget.mes);
      if (!mounted) return;
      Navigator.pop(context, true); // true = cerrado exitosamente
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar: $e'), backgroundColor: AppTheme.danger));
      setState(() => _cerrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.insights_outlined, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Cómo te fue en ${widget.labelMes}',
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Indicador de paso
                if (_paso < 3)
                  Text('${_paso + 1}/3',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Línea separadora
          Divider(color: AppTheme.border, height: 1),
          // Contenido por paso
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildPaso(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaso() {
    switch (_paso) {
      case 0:  return _buildResumen();
      case 1:  return _buildPendientes();
      case 2:  return _buildAlertas();
      default: return _buildConfirmacion();
    }
  }

  // ─── PASO 0: RESUMEN ────────────────────────────────────────────────────────

  Widget _buildResumen() {
    final r = widget.data['resumen'] as Map<String, dynamic>? ?? {};
    final ingEst = _d(r['ingreso_estimado']);
    final ingReal = _d(r['ingreso_real']);
    final fijEst  = _d(r['fijos_estimados']);
    final fijReal = _d(r['fijos_reales']);
    final varEst  = _d(r['variables_estimados']);
    final varReal = _d(r['variables_reales']);
    final noPres  = _d(r['no_presupuestados']);
    final remEst  = _d(r['remanente_estimado']);
    final remReal = _d(r['remanente_real']);

    final sano = remReal >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tabla estimado vs real
        _seccion('Resumen del mes'),
        const SizedBox(height: 10),
        _tablaEstVsReal([
          {'label': 'Ingreso',          'est': ingEst, 'real': ingReal, 'invert': false},
          {'label': 'Gastos fijos',     'est': fijEst, 'real': fijReal, 'invert': true},
          {'label': 'Gastos variables', 'est': varEst, 'real': varReal, 'invert': true},
          {'label': 'No presupuestados','est': 0.0,    'real': noPres,  'invert': true},
        ]),
        const SizedBox(height: 10),
        // Remanente destacado
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sano ? AppTheme.success.withOpacity(0.12) : AppTheme.danger.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sano ? AppTheme.success : AppTheme.danger, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remanente estimado',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text('${Money.fmt(remEst)}',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Remanente real',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text('${Money.fmt(remReal)}',
                      style: TextStyle(
                          color: sano ? AppTheme.success : AppTheme.danger,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        // P3 — explicar POR QUÉ gastó de más, no solo el número
        ..._buildInsightDesviacion(remEst, remReal),
        // FIN-03 — si algún patrón se repite mes a mes, ofrecer ajustar el
        // presupuesto para el próximo mes (nunca se auto-aplica).
        ..._buildSugerenciasPresupuesto(),
        const SizedBox(height: 20),
        _botonSiguiente(
          label: _pendientes.isEmpty && widget.alertas.isEmpty ? 'Ir a confirmar' : 'Siguiente',
          onTap: () => setState(() => _paso = _pendientes.isNotEmpty ? 1 : widget.alertas.isNotEmpty ? 2 : 3),
        ),
      ],
    );
  }

  /// P3/FIN-03 — bajo la tabla: por qué gastó más o menos de lo planeado.
  /// Usa los insights ricos de FIN-02 (alza vs mes anterior, variabilidad,
  /// oportunidad de ahorro) cuando ya cargaron; si no, cae al cálculo simple
  /// de siempre para no dejar la pantalla sin nada mientras carga o si falla.
  List<Widget> _buildInsightDesviacion(double remEst, double remReal) {
    final insightsRicos = (_variaciones?['insights'] as List? ?? []).cast<Map<String, dynamic>>();
    if (insightsRicos.isNotEmpty) {
      return [
        const SizedBox(height: 12),
        ...insightsRicos.map((i) => _insightRicoBox(i)),
      ];
    }

    final cats = (widget.data['analisis_categorias'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((c) => _d(c['desviacion']) > 0.5)
        .toList()
      ..sort((a, b) => _d(b['desviacion']).compareTo(_d(a['desviacion'])));
    if (cats.isEmpty) return [];
    final diferencia = remEst - remReal; // cuánto menos te quedó vs lo planeado
    final top = cats.take(2).map((c) {
      final cat = (c['categoria'] as String? ?? '');
      final nombre = cat.isNotEmpty ? '${cat[0].toUpperCase()}${cat.substring(1)}' : cat;
      return '$nombre +${Money.fmt0(_d(c['desviacion']))}';
    }).join(', ');
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warning.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline, color: AppTheme.warning, size: 15),
            const SizedBox(width: 6),
            Text(diferencia > 0.5
                ? 'Te quedó ${Money.fmt0(diferencia)} menos de lo planeado'
                : 'Dónde te pasaste del plan',
                style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('Fue principalmente en: $top. El próximo mes podrías ajustar esas categorías.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
        ]),
      ),
    ];
  }

  Widget _insightRicoBox(Map<String, dynamic> insight) {
    final tipo = insight['tipo'] as String? ?? '';
    final (icon, color) = switch (tipo) {
      'alza_vs_mes_anterior' => (Icons.trending_up, AppTheme.warning),
      'variabilidad' => (Icons.show_chart, AppTheme.info),
      'oportunidad_ahorro' => (Icons.savings_outlined, AppTheme.success),
      _ => (Icons.lightbulb_outline, AppTheme.warning),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(insight['mensaje'] as String? ?? '',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3))),
      ]),
    );
  }

  /// FIN-03 — si una categoría se desvió de forma consistente (no solo este
  /// mes), ofrecer ajustar su presupuesto para el mes siguiente. Nunca se
  /// auto-aplica: el usuario decide con "Ajustar" o "No, gracias".
  List<Widget> _buildSugerenciasPresupuesto() {
    final sugerencias = (_variaciones?['sugerencias_presupuesto'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((s) => !_sugerenciasDescartadas.contains(s['categoria']))
        .toList();
    if (sugerencias.isEmpty) return [];
    return [
      const SizedBox(height: 12),
      Text('PRESUPUESTO PARA EL PRÓXIMO MES',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      ...sugerencias.map((s) => _sugerenciaCard(s)),
    ];
  }

  Widget _sugerenciaCard(Map<String, dynamic> sug) {
    final categoria = sug['categoria'] as String;
    final nombre = categoria.isNotEmpty ? '${categoria[0].toUpperCase()}${categoria.substring(1)}' : categoria;
    final subir = sug['direccion'] == 'subir';
    final color = subir ? AppTheme.warning : AppTheme.success;
    final actual = _d(sug['presupuesto_actual']);
    final sugerido = _d(sug['presupuesto_sugerido']);
    final aplicando = _sugerenciasAplicando.contains(categoria);
    final aplicada = _sugerenciasAplicadas.contains(categoria);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(subir ? Icons.trending_up : Icons.trending_down, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text('Ajustar presupuesto de $nombre',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
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
            Text('Ajustado para el próximo mes',
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
      ]),
    );
  }

  // ─── PASO 1: PENDIENTES ──────────────────────────────────────────────────────

  Widget _buildPendientes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seccion('Gastos por confirmar (${_pendientes.length})'),
        const SizedBox(height: 4),
        Text('¿Ya pagaste estos? Confírmalos para que tu resumen sea exacto. Los que no, déjalos así.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        if (_pendientes.isEmpty)
          _infoBox('Todos los pagos están al día.', AppTheme.success)
        else
          ..._pendientes.map((r) => _pendienteCard(r)),
        const SizedBox(height: 20),
        _botonSiguiente(
          label: 'Siguiente',
          onTap: () => setState(() => _paso = widget.alertas.isNotEmpty ? 2 : 3),
        ),
      ],
    );
  }

  Widget _pendienteCard(Map<String, dynamic> r) {
    final tipo = r['tipo'] as String? ?? '';
    final color = tipo == 'fijo' ? AppTheme.colorFijo
        : tipo == 'variable' ? AppTheme.success
        : AppTheme.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['nombre']?.toString() ?? '',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                Text(tipo,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text('${Money.fmt(_d(r['monto']))}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _marcarPagado(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success.withOpacity(0.4)),
              ),
              child: const Text('Sí, lo pagué',
                  style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PASO 2: ALERTAS ─────────────────────────────────────────────────────────

  Widget _buildAlertas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seccion('Alertas del mes (${widget.alertas.length})'),
        const SizedBox(height: 4),
        Text('Revisa estas situaciones antes de cerrar el mes.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        if (widget.alertas.isEmpty)
          _infoBox('Sin alertas activas.', AppTheme.success)
        else
          ...widget.alertas.map((a) => _alertaCard(a)),
        const SizedBox(height: 20),
        _botonSiguiente(
          label: 'Ir a confirmar',
          onTap: () => setState(() => _paso = 3),
        ),
      ],
    );
  }

  Widget _alertaCard(Map<String, dynamic> a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a['mensaje']?.toString() ?? '',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ─── PASO 3: CONFIRMACIÓN ────────────────────────────────────────────────────

  Widget _buildConfirmacion() {
    final mesRow = widget.data['mes'] as Map<String, dynamic>? ?? {};
    final estado = mesRow['estado']?.toString() ?? '';

    if (estado == 'cerrado') {
      return Column(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
          const SizedBox(height: 12),
          const Text('Este mes ya fue cerrado.',
              style: TextStyle(color: AppTheme.success, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _botonSiguiente(label: 'Cerrar', onTap: () => Navigator.pop(context, false)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seccion('Guardar resumen del mes'),
        const SizedBox(height: 10),
        _infoBox(
          'Se guarda una foto de cómo te fue este mes. Tu historial queda preservado '
          'y puedes seguir consultándolo después — no pierdes acceso a nada.',
          AppTheme.info,
        ),
        if (_pendientes.isNotEmpty) ...[
          const SizedBox(height: 8),
          _infoBox(
            '${_pendientes.length} pago(s) quedan pendientes. '
            'Puedes cerrar igual, pero considera marcarlos primero.',
            AppTheme.warning,
          ),
        ],
        const SizedBox(height: 20),
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
                : const Text('Guardar y ver mi resumen',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _cerrando ? null : () => Navigator.pop(context, false),
            child: Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────

  Widget _seccion(String texto) => Text(
    texto,
    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
  );

  Widget _botonSiguiente({required String label, required VoidCallback onTap}) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.surfaceAlt,
        foregroundColor: AppTheme.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ),
  );

  Widget _infoBox(String texto, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: color, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: TextStyle(color: color, fontSize: 12))),
      ],
    ),
  );

  Widget _tablaEstVsReal(List<Map<String, dynamic>> filas) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text('', style: TextStyle(fontSize: 11))),
                SizedBox(width: 80,
                    child: Text('Estimado', textAlign: TextAlign.right,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11))),
                SizedBox(width: 80,
                    child: Text('Real', textAlign: TextAlign.right,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11))),
              ],
            ),
          ),
          Divider(color: AppTheme.border, height: 1),
          ...filas.map((f) {
            final est    = f['est'] as double;
            final real   = f['real'] as double;
            final invert = f['invert'] as bool;
            Color realColor = AppTheme.textPrimary;
            if (est > 0 || real > 0) {
              // verde si ahorró, rojo si gastó de más (según contexto)
              if (!invert) {
                realColor = real >= est ? AppTheme.success : AppTheme.warning;
              } else {
                realColor = real <= est ? AppTheme.success : AppTheme.danger;
              }
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(f['label'] as String,
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(est > 0 ? '${Money.fmt(est)}' : '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text('${Money.fmt(real)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: realColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                Divider(color: AppTheme.border, height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}
