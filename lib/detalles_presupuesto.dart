/// Pantalla principal de detalle de un presupuesto.
///
/// Es la pantalla más compleja de la app. Muestra el estado del período activo:
///   - Balance: presupuesto total, gastado, disponible/excedido
///   - Stats por tipo: fijo / variable / ahorro
///   - Progreso de pagos (circular)
///   - Lista de movimientos del período con estado de pago
///
/// Acciones principales:
///   - **Agregar**: bottom sheet con todos los gastos del presupuesto + opción crear nuevo.
///   - **Reanudar fijos**: re-crea movimientos de gastos fijos que no están en el período.
///   - **Editar**: navega a [EditarPresupuesto].
///   - **Pagar**: bottom sheet para registrar el monto real pagado.
///
/// ## Flujo de gastos con fecha fija
/// Al agregar un gasto con `tipo_fecha = 'fija'`, el modal muestra campos extra:
///   - Frecuencia: único / mensual / quincenal / anual
///   - Día del mes o fecha exacta (si es único)
///   - Opción de notificación con días de anticipación
///
/// El backend crea automáticamente eventos en `calendario_eventos`
/// cuando recibe un gasto con `tipo_fecha = 'fija'`.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:printing/printing.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/pdf_service.dart';
import 'services/gustitos_service.dart';
import 'services/income_service.dart';
import 'editar_presupuesto.dart';
import 'cierre_periodo_screen.dart';
import 'widgets/presupuestos/balance_card.dart';
import 'widgets/presupuestos/pago_form_sheet.dart';
import 'widgets/presupuestos/gasto_form_sheet.dart';
import 'widgets/presupuestos/income_form_sheet.dart';
import 'widgets/presupuestos/capacidad_card.dart';
import 'widgets/presupuestos/fondo_seguridad_card.dart';
import 'widgets/presupuestos/patrones_gustitos_banner.dart';
import 'widgets/presupuestos/clasificacion_card.dart';
import 'widgets/presupuestos/alertas_banner.dart';
import 'widgets/presupuestos/recomendacion_porcentajes_card.dart';
import 'widgets/presupuestos/analisis_financiero_section.dart';
import 'widgets/presupuestos/proyeccion_mes_card.dart';
import 'gustitos/crear_gustito_sheet.dart';
import 'gustitos/gustitos_screen.dart';
import 'simulador_decisiones_screen.dart';
import 'ahorro_meta.dart';

/// Pantalla de detalle de un presupuesto con movimientos del período activo.
class DetallesPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;
  const DetallesPresupuesto({Key? key, required this.presupuesto, required this.firebaseUid}) : super(key: key);

  @override
  _DetallesPresupuestoState createState() => _DetallesPresupuestoState();
}

class _DetallesPresupuestoState extends State<DetallesPresupuesto> with SingleTickerProviderStateMixin {
  List<dynamic> movimientos = [];
  Map<String, dynamic>? periodo;

  double totalFijo = 0, totalNoFijo = 0, totalAhorro = 0, totalGustitos = 0;
  double montoTotal = 0;
  double porcentajePagados = 0;
  bool isLoading = true;
  bool _bannerNuevoPeriodoVisible = false;

  // Métricas financieras P1-P5 + nuevas #4/#6/#7
  Map<String, dynamic>? _income;
  Map<String, dynamic>? _capacidad;
  Map<String, dynamic>? _fondo;
  Map<String, dynamic>? _patrones;
  Map<String, dynamic>? _distribucionClasif;
  Map<String, dynamic>? _alertas;
  Map<String, dynamic>? _recomendacion;
  bool _loadingExtras = true;

  // Historial de períodos (tab Historial)
  late TabController _tabController;
  List<dynamic> _historico = [];
  double _montoTotalHistorico = 0;
  bool _loadingHistorico = false;
  bool _historicoLoaded = false;

  // Proyección 12 meses (tab Proyección)
  Map<String, dynamic>? _proyeccion;
  bool _loadingProyeccion = false;
  bool _proyeccionLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_proyeccionLoaded && mounted) {
        _cargarProyeccion();
      }
      if (_tabController.index == 2 && !_historicoLoaded && mounted) {
        _cargarHistorico();
      }
    });
    montoTotal = _d(widget.presupuesto['monto_total']);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorico() async {
    setState(() { _loadingHistorico = true; _historicoLoaded = true; });
    try {
      final res = await ApiClient.get(
        '/presupuestos/${widget.presupuesto['id']}/historico?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        if (mounted) setState(() {
          _historico = body['periodos'] as List? ?? [];
          _montoTotalHistorico = _d(body['monto_total']);
          _loadingHistorico = false;
        });
      } else {
        if (mounted) setState(() => _loadingHistorico = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingHistorico = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar historial: $e')));
      }
    }
  }

  Future<void> _cargarProyeccion() async {
    setState(() { _loadingProyeccion = true; _proyeccionLoaded = true; });
    try {
      final data = await IncomeService.getProyeccion(
          widget.presupuesto['id'] as int, widget.firebaseUid);
      if (mounted) setState(() { _proyeccion = data; _loadingProyeccion = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProyeccion = false);
    }
  }

  /// Carga el detalle del período activo desde GET /presupuestos/:id/detalle.
  ///
  /// La respuesta incluye: movimientos[], periodo{}, resumen{totalFijo, totalNoFijo, ...}.
  /// El backend crea el período automáticamente si no existe uno activo.
  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiClient.get(
        '/presupuestos/${widget.presupuesto['id']}/detalle?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          movimientos       = data['movimientos'];
          periodo           = data['periodo'];
          totalFijo         = _d(data['resumen']['totalFijo']);
          totalNoFijo       = _d(data['resumen']['totalNoFijo']);
          totalAhorro       = _d(data['resumen']['totalAhorro']);
          totalGustitos     = _d(data['resumen']['totalGustitos']);
          porcentajePagados = _d(data['resumen']['porcentajePagados']);
          isLoading         = false;
          _bannerNuevoPeriodoVisible = _detectarPeriodoNuevo(data['periodo']);
        });
      } else { throw Exception(); }
    } catch (_) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar detalle')));
    }
    _cargarExtras();
  }

  // Carga métricas financieras adicionales sin bloquear la UI principal
  Future<void> _cargarExtras() async {
    if (mounted) setState(() => _loadingExtras = true);
    final id  = widget.presupuesto['id'] as int;
    final uid = widget.firebaseUid;
    try {
      final results = await Future.wait([
        IncomeService.getIncome(id, uid),
        IncomeService.getCapacidad(id, uid),
        IncomeService.getFondoSeguridad(id, uid),
        IncomeService.getPatronesGustitos(id, uid),
        IncomeService.getDistribucionClasificacion(id, uid),
        IncomeService.getAlertas(id, uid),
        IncomeService.getRecomendacionPorcentajes(id, uid),
      ]);
      if (!mounted) return;
      setState(() {
        _income             = results[0];
        _capacidad          = results[1];
        _fondo              = results[2];
        _patrones           = results[3];
        _distribucionClasif = results[4];
        _alertas            = results[5];
        _recomendacion      = results[6];
        _loadingExtras      = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  void _abrirIncomeForm() {
    IncomeFormSheet.show(
      context,
      presupuestoId: widget.presupuesto['id'] as int,
      firebaseUid: widget.firebaseUid,
      incomeActual: _income,
      onGuardado: (inc) {
        if (mounted) setState(() => _income = inc);
        _cargarExtras();
      },
    );
  }

  bool _detectarPeriodoNuevo(dynamic p) {
    if (p == null) return false;
    try {
      final inicioStr = p['fecha_inicio']?.toString() ?? '';
      if (inicioStr.isEmpty) return false;
      final inicio = DateTime.parse(inicioStr);
      final hoy = DateTime.now();
      return hoy.difference(inicio).inDays <= 2;
    } catch (_) { return false; }
  }

  Widget _buildBannerNuevoPeriodo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wb_sunny_outlined, color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('¡Período nuevo!',
                style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          GestureDetector(
            onTap: () => setState(() => _bannerNuevoPeriodoVisible = false),
            child: const Icon(Icons.close, color: AppTheme.textMuted, size: 16),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('¿Tus gastos y metas siguen igual que el período pasado?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => setState(() => _bannerNuevoPeriodoVisible = false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            child: const Text('Sí, mismo plan', style: TextStyle(fontSize: 12)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () {
              setState(() => _bannerNuevoPeriodoVisible = false);
              GastoFormSheet.show(
                context,
                onGuardado: (desc, monto, tipo, {tipoFecha='flexible', diaPago, frecuenciaPago,
                    fechaPagoExacta, generaNotificacion=false, diasAnticipacion=3,
                    subcategoria, clasificacion, tipoDeuda=false, descuentoDirecto=false,
                    fechaFin, numCuotas}) =>
                  _agregarGasto(desc, monto, tipo,
                    tipoFecha: tipoFecha, diaPago: diaPago, frecuenciaPago: frecuenciaPago,
                    fechaPagoExacta: fechaPagoExacta, generaNotificacion: generaNotificacion,
                    diasAnticipacion: diasAnticipacion, subcategoria: subcategoria,
                    clasificacion: clasificacion, tipoDeuda: tipoDeuda,
                    descuentoDirecto: descuentoDirecto, fechaFin: fechaFin, numCuotas: numCuotas),
              );
            },
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
            child: const Text('Quiero ajustar', style: TextStyle(fontSize: 12)),
          )),
        ]),
      ]),
    );
  }

  bool _mostrarBotonCierre() {
    if (periodo == null) return false;
    try {
      final finStr = periodo!['fecha_fin']?.toString() ?? '';
      if (finStr.isEmpty) return false;
      final fin = DateTime.parse(finStr);
      final hoy = DateTime.now();
      final diff = fin.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
      return diff <= 2;
    } catch (_) {
      return false;
    }
  }

  Future<void> _navegarACierre() async {
    if (periodo == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CierrePeriodoScreen(
          presupuesto: widget.presupuesto,
          periodo: periodo!,
          firebaseUid: widget.firebaseUid,
        ),
      ),
    );
    if (result == true && mounted) _cargar();
  }

  /// Llama al endpoint que re-crea movimientos de gastos fijos no presentes en el período.
  ///
  /// Útil cuando el usuario crea un gasto fijo después de que el período ya fue iniciado,
  /// o cuando se marca manualmente un movimiento como pagado y desea "reiniciarlo".
  Future<void> _reanudar() async {
    await ApiClient.put(
      '/presupuestos/${widget.presupuesto['id']}/gastos/reanudar-fijos',
      {'firebase_uid': widget.firebaseUid},
    );
    _cargar();
  }

  /// Obtiene todos los gastos del presupuesto para mostrarlos en el modal de selección.
  Future<List<dynamic>> _todosLosGastos() async {
    final res = await ApiClient.get(
      '/presupuestos/${widget.presupuesto['id']}/gastos?firebase_uid=${widget.firebaseUid}',
    );
    if (res.statusCode != 200) throw Exception();
    return json.decode(res.body);
  }

  /// Crea un gasto nuevo y, si es fijo/ahorro, también su movimiento en el período activo.
  ///
  /// Los gastos de tipo 'fijo', 'fijo_x_periodo' y 'ahorro' generan un movimiento
  /// automáticamente al ser creados (via POST /movimientos).
  /// Los gastos 'no fijo' solo se registran como plantilla y el usuario los
  /// selecciona manualmente cuando quiere incluirlos en el período.
  Future<void> _agregarGasto(String desc, double monto, String tipo, {
    String tipoFecha = 'flexible',
    int? diaPago,
    String? frecuenciaPago,
    String? fechaPagoExacta,
    bool generaNotificacion = false,
    int diasAnticipacion = 3,
    String? subcategoria,
    String? clasificacion,
    bool tipoDeuda = false,
    bool descuentoDirecto = false,
    DateTime? fechaFin,
    int? numCuotas,
  }) async {
    if (desc.trim().isEmpty || monto <= 0) return;
    final body = <String, dynamic>{
      'presupuesto_id': widget.presupuesto['id'],
      'descripcion': desc.trim(), 'monto': monto, 'tipo': tipo,
      'fecha': DateTime.now().toIso8601String().split('T')[0],
      'firebase_uid': widget.firebaseUid,
      'tipo_fecha': tipoFecha,
      'genera_notificacion': generaNotificacion,
      'dias_anticipacion': diasAnticipacion,
    };
    if (diaPago != null) body['dia_pago'] = diaPago;
    if (frecuenciaPago != null) body['frecuencia_pago'] = frecuenciaPago;
    if (fechaPagoExacta != null) body['fecha_pago_exacta'] = fechaPagoExacta;
    if (subcategoria != null) body['subcategoria'] = subcategoria;
    if (clasificacion != null) body['clasificacion'] = clasificacion;
    if (tipoDeuda) {
      body['tipo_deuda'] = 1;
      body['descuento_directo'] = descuentoDirecto ? 1 : 0;
    }
    if (fechaFin != null) {
      body['fecha_fin'] = '${fechaFin.year}-${fechaFin.month.toString().padLeft(2,'0')}-${fechaFin.day.toString().padLeft(2,'0')}';
    }
    if (numCuotas != null) body['num_cuotas'] = numCuotas;

    final res = await ApiClient.post('/gastos', body);
    if (res.statusCode != 201) return;

    // Para gastos recurrentes, crear también el movimiento del período actual
    if (tipo == 'fijo' || tipo == 'fijo_x_periodo' || tipo == 'ahorro') {
      // FIX: validar que el servidor retornó el id antes de crear el movimiento.
      final id = json.decode(res.body)['id'] as int?;
      if (id == null) { _cargar(); return; }
      await ApiClient.post('/presupuestos/${widget.presupuesto['id']}/movimientos', {
        'firebase_uid': widget.firebaseUid,
        'items': [{'gasto_id': id, 'monto': monto, 'subcategoria': subcategoria}],
      });
    }
    _cargar();
  }

  /// Crea movimientos en el período activo desde una lista de gastos seleccionados.
  ///
  /// [items] = [{ 'gasto_id': int, 'monto': double }, ...]
  Future<void> _crearMovimientos(List items) async {
    await ApiClient.post('/presupuestos/${widget.presupuesto['id']}/movimientos',
        {'firebase_uid': widget.firebaseUid, 'items': items});
    _cargar();
  }

  /// Registra el pago de un movimiento con el monto real pagado.
  ///
  /// [mid] = ID del movimiento.
  /// [monto] = monto real pagado (puede diferir del presupuestado).
  /// El backend guarda `monto_pagado_real` para análisis de diferencias.
  Future<void> _pagar(int mid, double monto) async {
    final res = await ApiClient.put('/movimientos/$mid/pagar', {
      'pagado': 1, 'monto_pagado_real': monto, 'firebase_uid': widget.firebaseUid,
    });
    if (res.statusCode == 200) _cargar();
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al registrar pago')));
  }

  /// Modal para confirmar el monto real de un pago.
  ///
  void _modalPago(int mid, double sugerido) => PagoFormSheet.show(
    context,
    sugerido: sugerido,
    onPagar: (m) => _pagar(mid, m),
  );

  void _modalNuevoGasto() => GastoFormSheet.show(
    context,
    onGuardado: (desc, monto, tipo, {
      tipoFecha = 'flexible',
      diaPago,
      frecuenciaPago,
      fechaPagoExacta,
      generaNotificacion = false,
      diasAnticipacion = 3,
      subcategoria,
      clasificacion,
      tipoDeuda = false,
      descuentoDirecto = false,
      fechaFin,
      numCuotas,
    }) => _agregarGasto(
      desc, monto, tipo,
      tipoFecha: tipoFecha,
      diaPago: diaPago,
      frecuenciaPago: frecuenciaPago,
      fechaPagoExacta: fechaPagoExacta,
      generaNotificacion: generaNotificacion,
      diasAnticipacion: diasAnticipacion,
      subcategoria: subcategoria,
      clasificacion: clasificacion,
      tipoDeuda: tipoDeuda,
      descuentoDirecto: descuentoDirecto,
      fechaFin: fechaFin,
      numCuotas: numCuotas,
    ),
  );

  /// Modal que muestra TODOS los gastos del presupuesto para seleccionar
  /// cuáles agregar al período actual como movimientos.
  ///
  /// Muestra checkbox + campo de monto editable por cada gasto.
  /// Botón "Crear nuevo" para ir al modal de nuevo gasto directamente.
  void _modalSeleccionar() async {
    List<dynamic> gastos = [];
    try { gastos = await _todosLosGastos(); } catch (_) { return; }

    if (!mounted) return;
    if (gastos.isEmpty) { _modalNuevoGasto(); return; }

    final sel    = <int, bool>{};
    final montos = <int, TextEditingController>{};

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              const Text('Agregar al período',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _modalNuevoGasto(); },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Crear nuevo'),
              ),
            ]),
          ),
          const Divider(color: AppTheme.border),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            ...gastos.map((g) {
              final id = g['id'] as int;
              sel[id]    ??= false;
              montos[id] ??= TextEditingController(text: g['monto'].toString());
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel[id]! ? AppTheme.primary.withOpacity(0.06) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel[id]! ? AppTheme.primary.withOpacity(0.3) : AppTheme.border,
                  ),
                ),
                child: Row(children: [
                  Checkbox(value: sel[id], onChanged: (v) => setS(() => sel[id] = v ?? false)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g['descripcion'],
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    TipoChip(g['tipo']),
                  ])),
                  // Campo de monto editable individualmente
                  SizedBox(width: 90, child: TextField(
                    controller: montos[id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      prefixText: '\$',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                  )),
                ]),
              );
            }),
          ])),
          // Botón de confirmación
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                final items = gastos
                    .where((g) => sel[g['id']] == true)
                    .map((g) {
                      final m = double.tryParse(montos[g['id']]!.text) ?? 0;
                      return m > 0 ? {'gasto_id': g['id'], 'monto': m} : null;
                    })
                    .where((e) => e != null)
                    .toList();
                if (items.isEmpty) return;
                Navigator.pop(ctx);
                await _crearMovimientos(items);
              },
              child: const Text('Agregar seleccionados'),
            )),
          ),
        ]),
      )),
    );
  }

  /// Convierte cualquier valor numérico del JSON a double de forma segura.
  double _d(dynamic v) {
    if (v is num)    return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalGastado    = totalFijo + totalNoFijo + totalAhorro;
    final totalConGustitos = totalGastado + totalGustitos;
    final pctGasto     = montoTotal > 0 ? (totalConGustitos / montoTotal).clamp(0.0, 1.0) : 0.0;
    final disponible   = montoTotal - totalConGustitos;

    // Color de la barra de progreso según el nivel de gasto
    Color barColor;
    if (totalConGustitos > montoTotal) barColor = AppTheme.danger;   // excedido
    else if (pctGasto >= 0.85)         barColor = AppTheme.warning;  // cerca del límite
    else                               barColor = AppTheme.success;   // bajo control

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.presupuesto['nombre'], overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Detalle del presupuesto',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Muestra el estado del período activo de este presupuesto.\n\n'
                  '• Barra de progreso — compara lo gastado vs el límite. '
                  'Se vuelve amarilla al 85% y roja si se excede.\n'
                  '• Movimientos — cada gasto registrado en el período. '
                  'Toca "Pagar" para registrar el monto real pagado.\n'
                  '• Agregar — selecciona gastos existentes o crea uno nuevo.\n'
                  '• Reanudar fijos — restaura los gastos fijos que ya marcaste como pagados.\n\n'
                  'Tipos de gasto:\n'
                  '  Fijo → se repite cada período (ej: alquiler)\n'
                  '  Variable → lo agregas cuando quieras (ej: supermercado)\n'
                  '  Ahorro → cuota de una meta de ahorro',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditarPresupuesto(
                  presupuesto: widget.presupuesto,
                  firebaseUid: widget.firebaseUid,
                ),
              ));
              _cargar();
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            tooltip: 'Exportar PDF',
            onPressed: () async {
              try {
                final bytes = await PdfService.generarPdfPresupuesto(widget.presupuesto, movimientos);
                await Printing.layoutPdf(onLayout: (_) => bytes);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e')));
              }
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Período'),
            Tab(text: 'Proyección'),
            Tab(text: 'Historial'),
          ],
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TAB 1: Período activo ─────────────────────────────────────────
          isLoading
          ? Container(color: AppTheme.background, child: const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: _cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── BANNER PERÍODO NUEVO ─────────────────────────────────
                  if (_bannerNuevoPeriodoVisible) _buildBannerNuevoPeriodo(),

                  // ── INFO DEL PERÍODO ─────────────────────────────────────
                  if (periodo != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          'Período ${periodo!['numero_periodo']}  ·  '
                          '${_fmtDate(periodo!['fecha_inicio'])}  →  ${_fmtDate(periodo!['fecha_fin'])}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    ),

                  const SizedBox(height: 12),

                  // ── INGRESO Y CAPACIDAD ───────────────────────────────────
                  const LabelDivider('INGRESO Y CAPACIDAD'),
                  const SizedBox(height: 8),
                  CapacidadCard(
                    capacidad: _capacidad,
                    onConfigurar: _abrirIncomeForm,
                  ),

                  // ── ESTE PERÍODO ──────────────────────────────────────────
                  const LabelDivider('ESTE PERÍODO'),
                  const SizedBox(height: 8),

                  // Balance principal
                  BalanceCard(
                    montoTotal: montoTotal,
                    totalGastado: totalConGustitos,
                    disponible: disponible,
                    pctGasto: pctGasto,
                    barColor: barColor,
                  ),

                  const SizedBox(height: 14),

                  // Stat cards por tipo
                  Row(children: [
                    _StatCard('Fijos',    totalFijo,    AppTheme.colorFijo),
                    const SizedBox(width: 8),
                    _StatCard('Variables', totalNoFijo, AppTheme.colorNoFijo),
                    const SizedBox(width: 8),
                    _StatCard('Ahorro',   totalAhorro,  AppTheme.colorAhorro),
                  ]),
                  if (totalGustitos > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [_StatCard('Gustitos', totalGustitos, AppTheme.primary)]),
                  ],

                  const SizedBox(height: 14),

                  // Indicador circular de pagos
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(children: [
                      SizedBox(width: 56, height: 56, child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: porcentajePagados, strokeWidth: 5,
                          backgroundColor: AppTheme.surfaceAlt, color: AppTheme.success,
                        ),
                        Text('${(porcentajePagados * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                      ])),
                      const SizedBox(width: 16),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Progreso de pagos',
                            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(
                          '${movimientos.where((m) => m['pagado'] == 1).length} de '
                          '${movimientos.length} movimientos pagados',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // Botones de acción
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _modalSeleccionar,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Agregar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            title: const Text('Resetear pagos fijos',
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                            content: const Text(
                              'Esto marcará como pendientes todos los gastos fijos del período. '
                              'Los pagos ya registrados se perderán.\n\n¿Continuar?',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar',
                                    style: TextStyle(color: AppTheme.textSecondary)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Resetear',
                                    style: TextStyle(color: AppTheme.danger)),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) _reanudar();
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Resetear fijos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SimuladorDecisionesScreen(
                          montoTotal: montoTotal,
                          gastadoActual: totalConGustitos,
                          ingresoNeto: _d(_income?['ingreso_neto']),
                          totalAhorro: totalAhorro,
                          nombrePresupuesto: widget.presupuesto['nombre'] as String? ?? '',
                        ),
                      )),
                      icon: const Icon(Icons.calculate_outlined, size: 16),
                      label: const Text('Simular decisión'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.info,
                        side: const BorderSide(color: AppTheme.info),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_mostrarBotonCierre()) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _navegarACierre,
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Cerrar período'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.warning,
                          side: const BorderSide(color: AppTheme.warning),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── MOVIMIENTOS ───────────────────────────────────────────
                  const LabelDivider('MOVIMIENTOS'),
                  const SizedBox(height: 8),
                  if (movimientos.isEmpty)
                    _emptyMovimientos()
                  else
                    ...movimientos.map((m) => _MovimientoTile(
                      m: m,
                      onPagar: () => _modalPago(m['id'], _d(m['monto'])),
                    )),

                  const SizedBox(height: 20),

                  // ── ANÁLISIS FINANCIERO (colapsable) ─────────────────────
                  AnalisisFinancieroSection(
                    distribucionClasif: _distribucionClasif,
                    recomendacion: _recomendacion,
                    fondo: _fondo,
                    patrones: _patrones,
                    alertas: _alertas,
                    onConfigurarIngreso: _abrirIncomeForm,
                    onAgregarGasto: _modalNuevoGasto,
                    loading: _loadingExtras,
                  ),

                  const SizedBox(height: 8),

                  // ── GUSTITOS ─────────────────────────────────────────────
                  const LabelDivider('GUSTITOS'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          totalGustitos > 0
                              ? '\$${totalGustitos.toStringAsFixed(2)} en Gustitos'
                              : 'Sin Gustitos este período',
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const Text('Compras espontáneas registradas',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      ])),
                      Row(children: [
                        GestureDetector(
                          onTap: () => CrearGustitoSheet.show(
                            context,
                            budgetId: widget.presupuesto['id'] as int,
                            firebaseUid: widget.firebaseUid,
                            onCreado: _cargar,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.add, color: AppTheme.primary, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => GustitosScreen(
                              budgetId: widget.presupuesto['id'] as int,
                              budgetNombre: widget.presupuesto['nombre'] as String,
                              firebaseUid: widget.firebaseUid,
                            ),
                          )).then((_) => _cargar()),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary, size: 14),
                          ),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 30),
                ]),
              ),
            ),
          // ── TAB 2: Proyección 12 meses ────────────────────────────────────
          _buildProyeccionTab(),
          // ── TAB 3: Historial de períodos ─────────────────────────────────
          _buildHistorialTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AhorroMetaScreen(firebaseUid: widget.firebaseUid),
              )),
              label: const Text('Agregar meta'),
              icon: const Icon(Icons.flag_outlined),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
            )
          : null,
    );
  }

  Widget _buildProyeccionTab() {
    if (_loadingProyeccion) {
      return Container(color: AppTheme.background,
          child: const Center(child: CircularProgressIndicator()));
    }
    if (_proyeccion == null) {
      return Container(
        color: AppTheme.background,
        child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 12),
          Text('Sin datos de proyección', style: TextStyle(color: AppTheme.textSecondary)),
          SizedBox(height: 4),
          Text('Toca "Proyección" para cargar',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ])),
      );
    }
    final meses = (_proyeccion!['meses'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>).toList();
    return Container(
      color: AppTheme.background,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: meses.length,
        itemBuilder: (_, i) => ProyeccionMesCard(
          mes: meses[i],
          onTap: meses[i]['tipo'] != 'proyectado'
              ? () {} // tap en períodos reales — se puede extender a detalle
              : null,
        ),
      ),
    );
  }

  Widget _buildHistorialTab() {
    if (_loadingHistorico) return Container(
      color: AppTheme.background,
      child: const Center(child: CircularProgressIndicator()),
    );
    if (_historico.isEmpty) return Container(
      color: AppTheme.background,
      child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history, size: 48, color: AppTheme.textMuted),
        SizedBox(height: 12),
        Text('Sin períodos anteriores', style: TextStyle(color: AppTheme.textSecondary)),
      ])),
    );
    return Container(
      color: AppTheme.background,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historico.length,
        itemBuilder: (_, i) {
          final p = _historico[i] as Map<String, dynamic>;
          final totalGastado = _d(p['total_gastado']);
          final pct = _montoTotalHistorico > 0 ? (totalGastado / _montoTotalHistorico).clamp(0.0, 1.0) : 0.0;
          final fijo = _d(p['total_fijo']);
          final variable = _d(p['total_no_fijo']);
          final ahorro = _d(p['total_ahorro']);
          final pagados = int.tryParse(p['movimientos_pagados']?.toString() ?? '0') ?? 0;
          final total = int.tryParse(p['movimientos_total']?.toString() ?? '0') ?? 0;
          final activo = p['estado'] == 'activo';
          Color barColor;
          if (totalGastado > _montoTotalHistorico) barColor = AppTheme.danger;
          else if (pct >= 0.80) barColor = AppTheme.primary;
          else barColor = AppTheme.success;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: activo ? AppTheme.primary.withOpacity(0.4) : AppTheme.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(
                  'Período #${p['numero_periodo']}  ·  ${_fmtDate(p['fecha_inicio'])} → ${_fmtDate(p['fecha_fin'])}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: activo ? AppTheme.primary.withOpacity(0.1) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(activo ? 'activo' : 'cerrado',
                    style: TextStyle(color: activo ? AppTheme.primary : AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: pct,
                backgroundColor: AppTheme.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(barColor),
                borderRadius: BorderRadius.circular(3),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('\$${totalGastado.toStringAsFixed(2)} de \$${_montoTotalHistorico.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15))),
                Text('$pagados/$total pagados', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _histChip('Fijo', fijo, AppTheme.colorFijo),
                const SizedBox(width: 6),
                _histChip('Variable', variable, AppTheme.colorNoFijo),
                const SizedBox(width: 6),
                _histChip('Ahorro', ahorro, AppTheme.colorAhorro),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _histChip(String label, double val, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('$label \$${val.toStringAsFixed(0)}',
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  /// Formatea la fecha del backend truncando a "YYYY-MM-DD".
  String _fmtDate(dynamic d) {
    final s = d?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Widget _emptyMovimientos() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(child: Column(children: [
      Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
      const SizedBox(height: 12),
      const Text('Sin movimientos en este período',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      const SizedBox(height: 6),
      const Text('Toca "Agregar" para registrar gastos',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    ])),
  );
}

/// Botón de toggle genérico (Flexible / Fecha fija, etc.).
class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _ToggleBtn(this.label, this.selected, this.onTap, {this.color = AppTheme.textSecondary});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.12) : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? color : AppTheme.border, width: selected ? 1.5 : 1),
      ),
      child: Text(label, style: TextStyle(
        color: selected ? color : AppTheme.textSecondary,
        fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      )),
    ),
  );
}

/// Mini tarjeta de estadística por tipo de gasto (Fijos / Variables / Ahorro).
class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Punto de color del tipo
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ]),
        const SizedBox(height: 6),
        Text('\$${value.toStringAsFixed(0)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

/// Fila de un movimiento en la lista de movimientos del período.
///
/// Muestra: ícono de tipo, descripción, TipoChip, monto presupuestado,
/// monto real pagado (si difiere del presupuestado) y botón Pagar / check.
///
/// Diferencia presupuestado vs real:
///   - Verde (−) si pagó menos de lo presupuestado
///   - Rojo (+) si pagó más de lo presupuestado
class _MovimientoTile extends StatelessWidget {
  final Map<String, dynamic> m;
  final VoidCallback onPagar;
  const _MovimientoTile({required this.m, required this.onPagar});

  @override
  Widget build(BuildContext context) {
    final pagado = m['pagado'] == 1;
    final monto  = double.tryParse(m['monto'].toString()) ?? 0;
    final real   = m['monto_pagado_real'] != null
        ? double.tryParse(m['monto_pagado_real'].toString()) : null;
    final dif  = real != null ? real - monto : null; // positivo = pagó más
    final tipo = m['tipo'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: pagado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: pagado ? AppTheme.success.withOpacity(0.2) : AppTheme.border,
        ),
      ),
      child: Row(children: [
        // Ícono del tipo de gasto con fondo de color
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.gastoColor(tipo).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_tipoIcon(tipo), color: AppTheme.gastoColor(tipo), size: 18),
        ),
        const SizedBox(width: 14),

        // Descripción y badge de tipo
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m['descripcion'], style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
            // Tachado si ya está pagado
            decoration: pagado ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 3),
          Row(children: [
            TipoChip(tipo),
            // Clasificación financiera (si existe)
            if ((m['clasificacion'] as String?) != null) ...[
              const SizedBox(width: 5),
              _ClasifChip(m['clasificacion'] as String),
            ],
            // Subcategoría (si existe)
            if ((m['subcategoria'] as String?) != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(m['subcategoria'] as String,
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ),
            ],
            // Diferencia presupuestado vs real (solo si pagado y hay dato real)
            if (pagado && real != null) ...[
              const SizedBox(width: 6),
              Text(
                '${dif! >= 0 ? '+' : ''}\$${dif.toStringAsFixed(2)}',
                style: TextStyle(
                  color: dif > 0 ? AppTheme.danger : AppTheme.success,
                  fontSize: 10, fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ]),
        ])),

        // Monto y botón de acción
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
            decoration: pagado ? TextDecoration.lineThrough : null,
          )),
          // Monto real pagado (si difiere del presupuestado)
          if (pagado && real != null)
            Text('\$${real.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (!pagado)
            GestureDetector(
              onTap: onPagar,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: const Text('Pagar',
                    style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            )
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),
    );
  }

  /// Ícono del tipo de gasto para el avatar del movimiento.
  IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'fijo':            return Icons.repeat;
      case 'fijo_x_periodo':  return Icons.event_repeat;
      case 'no fijo':         return Icons.shopping_cart_outlined;
      case 'ahorro':          return Icons.savings_outlined;
      default:                return Icons.attach_money;
    }
  }
}

/// Chip de clasificación financiera en movimientos.
class _ClasifChip extends StatelessWidget {
  final String clasificacion;
  const _ClasifChip(this.clasificacion);

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (clasificacion) {
      case 'esencial':
        color = const Color(0xFF1890FF); label = 'Esencial'; break;
      case 'importante':
        color = AppTheme.primary; label = 'Importante'; break;
      case 'flexible':
        color = AppTheme.success; label = 'Flexible'; break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
