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
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'editar_presupuesto.dart';

/// Pantalla de detalle de un presupuesto con movimientos del período activo.
class DetallesPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;
  const DetallesPresupuesto({Key? key, required this.presupuesto, required this.firebaseUid}) : super(key: key);

  @override
  _DetallesPresupuestoState createState() => _DetallesPresupuestoState();
}

class _DetallesPresupuestoState extends State<DetallesPresupuesto> {
  List<dynamic> movimientos = [];
  Map<String, dynamic>? periodo;

  /// Totales por tipo para las stat cards.
  double totalFijo = 0, totalNoFijo = 0, totalAhorro = 0;

  /// Monto límite del presupuesto (viene del widget.presupuesto).
  double montoTotal = 0;

  /// Fracción de movimientos pagados (0.0 – 1.0) para el indicador circular.
  double porcentajePagados = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    montoTotal = _d(widget.presupuesto['monto_total']);
    _cargar();
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
          porcentajePagados = _d(data['resumen']['porcentajePagados']);
          isLoading         = false;
        });
      } else { throw Exception(); }
    } catch (_) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar detalle')));
    }
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
  }) async {
    if (desc.trim().isEmpty || monto <= 0) return;
    final body = {
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

    final res = await ApiClient.post('/gastos', body);
    if (res.statusCode != 201) return;

    // Para gastos recurrentes, crear también el movimiento del período actual
    if (tipo == 'fijo' || tipo == 'fijo_x_periodo' || tipo == 'ahorro') {
      final id = json.decode(res.body)['id'];
      await ApiClient.post('/presupuestos/${widget.presupuesto['id']}/movimientos', {
        'firebase_uid': widget.firebaseUid,
        'items': [{'gasto_id': id, 'monto': monto}],
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
  /// Pre-rellena el monto presupuestado. El usuario puede cambiarlo si
  /// pagó un monto diferente (gasto variable o con ajuste).
  void _modalPago(int mid, double sugerido) {
    final ctrl = TextEditingController(text: sugerido.toStringAsFixed(2));
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Registrar pago',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          const Text('Ingresa el monto real pagado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              final m = double.tryParse(ctrl.text) ?? 0;
              if (m <= 0) return;
              Navigator.pop(context);
              _pagar(mid, m);
            },
            child: const Text('Confirmar pago'),
          )),
        ]),
      ),
    );
  }

  /// Modal para crear un gasto nuevo directamente desde el detalle del presupuesto.
  ///
  /// Incluye el selector de fecha fija/flexible con todas las opciones:
  /// frecuencia, día del mes, fecha exacta y notificación anticipada.
  void _modalNuevoGasto() {
    final descCtrl  = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo       = 'fijo';
    String tipoFecha  = 'flexible';
    int diaPago       = 1;
    String frecuencia = 'mensual';
    DateTime? fechaExacta;
    bool notif        = false;
    int diasAnticipacion = 3;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle del bottom sheet
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Nuevo gasto',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Descripción y monto
            TextField(controller: descCtrl, style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Descripción')),
            const SizedBox(height: 12),
            TextField(controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00')),

            // Selector de tipo (fijo / variable / ahorro)
            const SizedBox(height: 16),
            const Text('Tipo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: ['fijo', 'no fijo', 'ahorro'].map((t) => GestureDetector(
              onTap: () => setS(() => tipo = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tipo == t ? AppTheme.gastoColor(t).withOpacity(0.15) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.border),
                ),
                child: Text(AppTheme.gastoLabel(t), style: TextStyle(
                  color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ),
            )).toList()),

            // ── SECCIÓN FECHA ──────────────────────────────────────────────
            const SizedBox(height: 20),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            const Text('¿Cuándo pagas este gasto?',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            // Toggle Flexible / Fecha fija
            Row(children: [
              _ToggleBtn('Flexible', tipoFecha == 'flexible', () => setS(() => tipoFecha = 'flexible')),
              const SizedBox(width: 10),
              _ToggleBtn('Fecha fija', tipoFecha == 'fija', () => setS(() => tipoFecha = 'fija'),
                  color: AppTheme.primary),
            ]),

            // Opciones extra cuando el usuario elige "Fecha fija"
            if (tipoFecha == 'fija') ...[
              const SizedBox(height: 16),
              const Text('Frecuencia', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              // Selector de frecuencia: único / mensual / quincenal / anual
              Wrap(spacing: 8, children: ['unico','mensual','quincenal','anual'].map((f) => GestureDetector(
                onTap: () => setS(() => frecuencia = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: frecuencia == f ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: frecuencia == f ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Text(_labelFrecuencia(f), style: TextStyle(
                    color: frecuencia == f ? AppTheme.primary : AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  )),
                ),
              )).toList()),

              const SizedBox(height: 14),
              // Día del mes para frecuencias recurrentes
              if (frecuencia != 'unico') ...[
                const Text('Día del mes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: diaPago,
                  dropdownColor: AppTheme.surfaceAlt,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: List.generate(31, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
                  )),
                  onChanged: (v) => setS(() => diaPago = v!),
                ),
              ] else ...[
                // Date picker para evento único
                const Text('Fecha exacta', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
                          primary: AppTheme.primary, surface: AppTheme.surfaceAlt,
                        )),
                        child: child!,
                      ),
                    );
                    if (picked != null) setS(() => fechaExacta = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                      const SizedBox(width: 10),
                      Text(
                        fechaExacta != null
                            ? '${fechaExacta!.year}-${fechaExacta!.month.toString().padLeft(2, "0")}-${fechaExacta!.day.toString().padLeft(2, "0")}'
                            : 'Seleccionar fecha',
                        style: TextStyle(
                          color: fechaExacta != null ? AppTheme.textPrimary : AppTheme.textMuted,
                        ),
                      ),
                    ]),
                  ),
                ),
              ],

              // Checkbox de notificación anticipada
              const SizedBox(height: 16),
              Row(children: [
                Checkbox(value: notif, onChanged: (v) => setS(() => notif = v ?? false)),
                const Text('Recordarme antes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                if (notif) ...[
                  const Spacer(),
                  // Selector de días de anticipación (visible solo si notif = true)
                  DropdownButton<int>(
                    value: diasAnticipacion,
                    dropdownColor: AppTheme.surfaceAlt,
                    style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                    underline: const SizedBox(),
                    items: [1,2,3,5,7].map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('$d ${d == 1 ? "día" : "días"} antes'),
                    )).toList(),
                    onChanged: (v) => setS(() => diasAnticipacion = v!),
                  ),
                ],
              ]),
            ],

            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _agregarGasto(
                  descCtrl.text,
                  double.tryParse(montoCtrl.text) ?? 0,
                  tipo,
                  tipoFecha: tipoFecha,
                  diaPago: tipoFecha == 'fija' && frecuencia != 'unico' ? diaPago : null,
                  frecuenciaPago: tipoFecha == 'fija' ? frecuencia : null,
                  fechaPagoExacta: tipoFecha == 'fija' && frecuencia == 'unico' && fechaExacta != null
                      ? '${fechaExacta!.year}-${fechaExacta!.month.toString().padLeft(2, "0")}-${fechaExacta!.day.toString().padLeft(2, "0")}'
                      : null,
                  generaNotificacion: notif,
                  diasAnticipacion: diasAnticipacion,
                );
              },
              child: const Text('Agregar gasto'),
            )),
          ]),
        ),
      )),
    );
  }

  /// Etiqueta legible para la frecuencia de pago.
  String _labelFrecuencia(String f) {
    switch (f) {
      case 'unico':     return 'Único';
      case 'mensual':   return 'Mensual';
      case 'quincenal': return 'Quincenal';
      case 'anual':     return 'Anual';
      default:          return f;
    }
  }

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
    final totalGastado = totalFijo + totalNoFijo + totalAhorro;
    final pctGasto     = montoTotal > 0 ? (totalGastado / montoTotal).clamp(0.0, 1.0) : 0.0;
    final disponible   = montoTotal - totalGastado;

    // Color de la barra de progreso según el nivel de gasto
    Color barColor;
    if (totalGastado > montoTotal) barColor = AppTheme.danger;       // excedido
    else if (pctGasto >= 0.85)     barColor = AppTheme.warning;      // cerca del límite
    else                           barColor = AppTheme.success;       // bajo control

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.presupuesto['nombre'], overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditarPresupuesto(
                  presupuesto: widget.presupuesto,
                  firebaseUid: widget.firebaseUid,
                ),
              ));
              _cargar(); // recargar por si cambió el monto total
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: _cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

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

                  const SizedBox(height: 20),

                  // ── BALANCE PRINCIPAL ─────────────────────────────────────
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Presupuesto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('\$${montoTotal.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 32,
                              fontWeight: FontWeight.w800, letterSpacing: -1)),
                      const SizedBox(height: 20),
                      // Barra de progreso del gasto (cambia de color según nivel)
                      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
                        value: pctGasto, minHeight: 8,
                        backgroundColor: AppTheme.surfaceAlt, color: barColor,
                      )),
                      const SizedBox(height: 10),
                      Row(children: [
                        Text('Gastado \$${totalGastado.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        const Spacer(),
                        Text(
                          disponible >= 0
                              ? 'Disponible \$${disponible.toStringAsFixed(2)}'
                              : 'Excedido \$${(-disponible).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: disponible >= 0 ? AppTheme.success : AppTheme.danger,
                            fontSize: 12, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // ── STAT CARDS POR TIPO ───────────────────────────────────
                  Row(children: [
                    _StatCard('Fijos',    totalFijo,   AppTheme.colorFijo),
                    const SizedBox(width: 8),
                    _StatCard('Variables', totalNoFijo, AppTheme.colorNoFijo),
                    const SizedBox(width: 8),
                    _StatCard('Ahorro',   totalAhorro, AppTheme.colorAhorro),
                  ]),

                  const SizedBox(height: 14),

                  // ── INDICADOR CIRCULAR DE PAGOS ───────────────────────────
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

                  const SizedBox(height: 20),

                  // ── BOTONES DE ACCIÓN ─────────────────────────────────────
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
                      onPressed: _reanudar,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reanudar fijos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                  ]),

                  const SizedBox(height: 20),
                  const LabelDivider('MOVIMIENTOS'),

                  // ── LISTA DE MOVIMIENTOS ──────────────────────────────────
                  if (movimientos.isEmpty)
                    _emptyMovimientos()
                  else
                    ...movimientos.map((m) => _MovimientoTile(
                      m: m,
                      onPagar: () => _modalPago(m['id'], _d(m['monto'])),
                    )),

                  const SizedBox(height: 30),
                ]),
              ),
            ),
    );
  }

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
