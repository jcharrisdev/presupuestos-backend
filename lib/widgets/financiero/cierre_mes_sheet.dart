import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/estado_anual_service.dart';
import '../../services/registros_service.dart';

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

  @override
  void initState() {
    super.initState();
    final registros = (widget.data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    _pendientes = registros.where((r) => r['pagado'] == 0 || r['pagado'] == false).toList();
    // Si no hay pendientes ni alertas, saltar directo a confirmar
    if (_pendientes.isEmpty && widget.alertas.isEmpty) _paso = 3;
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
      decoration: const BoxDecoration(
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
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Indicador de paso
                if (_paso < 3)
                  Text('${_paso + 1}/3',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Línea separadora
          const Divider(color: AppTheme.border, height: 1),
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
                  const Text('Remanente estimado',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text('\$${remEst.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Remanente real',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text('\$${remReal.toStringAsFixed(2)}',
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
        const SizedBox(height: 20),
        _botonSiguiente(
          label: _pendientes.isEmpty && widget.alertas.isEmpty ? 'Ir a confirmar' : 'Siguiente',
          onTap: () => setState(() => _paso = _pendientes.isNotEmpty ? 1 : widget.alertas.isNotEmpty ? 2 : 3),
        ),
      ],
    );
  }

  /// P3 — bajo la tabla: si gastó más de lo planeado, decir en qué categorías.
  List<Widget> _buildInsightDesviacion(double remEst, double remReal) {
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
      return '$nombre +\$${_d(c['desviacion']).toStringAsFixed(0)}';
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
                ? 'Te quedó \$${diferencia.toStringAsFixed(0)} menos de lo planeado'
                : 'Dónde te pasaste del plan',
                style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('Fue principalmente en: $top. El próximo mes podrías ajustar esas categorías.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
        ]),
      ),
    ];
  }

  // ─── PASO 1: PENDIENTES ──────────────────────────────────────────────────────

  Widget _buildPendientes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seccion('Gastos por confirmar (${_pendientes.length})'),
        const SizedBox(height: 4),
        const Text('¿Ya pagaste estos? Confírmalos para que tu resumen sea exacto. Los que no, déjalos así.',
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
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                Text(tipo,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text('\$${_d(r['monto']).toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
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
        const Text('Revisa estas situaciones antes de cerrar el mes.',
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
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
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
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────

  Widget _seccion(String texto) => Text(
    texto,
    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
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
              children: const [
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
          const Divider(color: AppTheme.border, height: 1),
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
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(est > 0 ? '\$${est.toStringAsFixed(2)}' : '—',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text('\$${real.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: realColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.border, height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}
