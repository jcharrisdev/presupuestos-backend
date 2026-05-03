/// Pantalla de detalle de una venta con gráfica de rentabilidad.
///
/// Muestra:
///   1. **Gráfica de rentabilidad**: barras comparativas de Invertido / Cobrado / Esperado.
///      - Invertido = costo de insumos del presupuesto de producción vinculado.
///      - Cobrado   = suma de cobros marcados como 'cobrado'.
///      - Esperado  = suma de todos los cobros (cobrados + pendientes).
///      - Ganancia  = cobrado − invertido (puede ser negativa = pérdida).
///      - Margen    = (ganancia / invertido) × 100 %.
///
///   2. **Lista de clientes** con su monto acordado y estado (pendiente / cobrado).
///      Acciones por cliente: cobrar (bottom sheet con monto editable) o eliminar.
///
/// Cuando se agrega un cliente con `condicion_pago = 'plazo'`, el backend
/// genera automáticamente un evento en `calendario_eventos` para recordar
/// la fecha de cobro.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'lista_compras_screen.dart';
import 'main.dart' show routeObserver;

/// Detalle de venta con rentabilidad y lista de cobros a clientes.
class VentaDetalle extends StatefulWidget {
  final int ventaId;
  final String firebaseUid;
  const VentaDetalle({Key? key, required this.ventaId, required this.firebaseUid}) : super(key: key);

  @override
  _VentaDetalleState createState() => _VentaDetalleState();
}

class _VentaDetalleState extends State<VentaDetalle> with RouteAware {
  Map<String, dynamic>? _venta;
  List<dynamic> _cobros = [];

  /// Fase 2: presupuestos de producción vinculados a esta venta.
  List<dynamic> _presupuestos = [];

  /// Resumen financiero retornado por el backend (Fase 7 — ampliado):
  /// total_invertido, total_cobrado, total_esperado, total_pendiente,
  /// ganancia, margen, margen_esperado, porcentaje_cobrado,
  /// cobros_realizados, cobros_pendientes.
  Map<String, dynamic> _resumen = {};
  bool _loading = true;
  // true mientras se refresca en background — muestra barra delgada sin reemplazar la UI
  bool _refreshing = false;
  // Margen objetivo para la sección de planificación (local, no persiste en DB)
  double _margenObjetivo = 0.25;

  @override
  void initState() { super.initState(); _cargar(); }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Al volver desde otra pantalla refrescar en background para no interrumpir la UI.
  @override
  void didPopNext() { _cargar(silencioso: true); }

  /// Carga (o refresca) la venta desde el servidor.
  ///
  /// [silencioso] = false (defecto): muestra pantalla de carga completa — solo
  ///   en la carga inicial cuando aún no hay datos.
  /// [silencioso] = true: muestra solo una barra delgada en la parte superior,
  ///   manteniendo la UI actual visible (refresh en background tras cobrar, etc.)
  Future<void> _cargar({bool silencioso = false}) async {
    if (silencioso) {
      if (mounted) setState(() => _refreshing = true);
    } else {
      setState(() { _loading = true; _refreshing = false; });
    }
    try {
      final res = await ApiClient.get('/ventas/${widget.ventaId}?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _venta        = data['venta'];
          _cobros       = data['cobros'] ?? [];
          _presupuestos = data['presupuestos'] ?? [];
          _resumen      = data['resumen'] ?? {};
          _loading      = false;
          _refreshing   = false;
        });
      } else {
        setState(() { _loading = false; _refreshing = false; });
      }
    } catch (e) {
      setState(() { _loading = false; _refreshing = false; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar venta: $e')),
      );
    }
  }

  /// Abre el bottom sheet para agregar un nuevo cliente a la venta.
  ///
  /// Dos modos:
  ///   - **Simple** (default): nombre + monto manual (compatible con flujo anterior).
  ///   - **Catálogo**: selecciona variantes del catálogo de productos; el total
  ///     se calcula automáticamente. El backend crea los pedido_items y recalcula
  ///     cobros_clientes.monto con monto_manual=0.
  ///
  /// Condición de pago (Fase 3):
  ///   - Contra entrega → sin fecha
  ///   - A plazo        → fecha = hoy + días (slider)
  ///   - Fecha exacta   → date picker → crea evento en calendario
  void _modalAgregarCliente() {
    final nombreCtrl = TextEditingController();
    final montoCtrl  = TextEditingController();
    String condicion = 'contra_entrega';
    int diasPlazo = 7;
    DateTime? fechaEspecifica;
    bool usarCatalogo = false;

    // Estado del catálogo (carga lazy cuando el usuario activa el toggle)
    List<Map<String, dynamic>> productos = [];
    bool loadingCatalogo = false;
    // Items seleccionados: { variante_id, descripcion, precio, cantidad }
    final List<Map<String, dynamic>> itemsSel = [];

    Future<void> cargarCatalogo(Function setS) async {
      setS(() => loadingCatalogo = true);
      try {
        final res = await ApiClient.get('/productos?firebase_uid=${widget.firebaseUid}');
        if (res.statusCode == 200) {
          final prods = List<Map<String, dynamic>>.from(json.decode(res.body));
          // Cargar variantes de cada producto en paralelo
          await Future.wait(prods.map((p) async {
            final vRes = await ApiClient.get(
              '/productos/${p['id']}/variantes?firebase_uid=${widget.firebaseUid}',
            );
            p['variantes'] = vRes.statusCode == 200
                ? (json.decode(vRes.body) as List)
                    .where((v) => v['activo'] == 1 || v['activo'] == true)
                    .toList()
                : <dynamic>[];
          }));
          setS(() { productos = prods.where((p) => (p['variantes'] as List).isNotEmpty).toList(); loadingCatalogo = false; });
        } else { setS(() => loadingCatalogo = false); }
      } catch (_) { setS(() => loadingCatalogo = false); }
    }

    double calcTotal() => itemsSel.fold(0.0, (s, i) =>
        s + (double.tryParse(i['precio'].toString()) ?? 0) * (double.tryParse(i['cantidad'].toString()) ?? 0));

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.65, maxChildSize: 0.95, minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Agregar cliente', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Nombre del cliente
            TextField(controller: nombreCtrl, style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Nombre del cliente')),
            const SizedBox(height: 16),

            // Toggle modo catálogo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: usarCatalogo ? AppTheme.primary.withOpacity(0.08) : AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: usarCatalogo ? AppTheme.primary.withOpacity(0.3) : AppTheme.border),
              ),
              child: Row(children: [
                const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Usar catálogo de productos',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                Switch(
                  value: usarCatalogo,
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    setS(() => usarCatalogo = v);
                    if (v && productos.isEmpty) cargarCatalogo(setS);
                  },
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ── MODO SIMPLE: monto manual ─────────────────────────────────────
            if (!usarCatalogo)
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  prefixText: '\$ ', hintText: '0.00',
                  prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),

            // ── MODO CATÁLOGO: selección de variantes ─────────────────────────
            if (usarCatalogo) ...[
              if (loadingCatalogo)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              else if (productos.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Sin productos en el catálogo. Ve a Cobros → Productos para agregar.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
                )
              else ...[
                // Lista de variantes agrupadas por producto
                ...productos.map((prod) {
                  final variantes = (prod['variantes'] as List).cast<Map<String, dynamic>>();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(prod['nombre']?.toString() ?? '', style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                    ),
                    ...variantes.map((v) {
                      final varId = v['id'] is int ? v['id'] as int : int.tryParse(v['id'].toString()) ?? 0;
                      final precio = double.tryParse(v['precio']?.toString() ?? '0') ?? 0;
                      final idx = itemsSel.indexWhere((i) => i['variante_id'] == varId);
                      final cantidad = idx >= 0 ? (double.tryParse(itemsSel[idx]['cantidad'].toString()) ?? 0) : 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cantidad > 0 ? AppTheme.primary.withOpacity(0.07) : AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cantidad > 0 ? AppTheme.primary.withOpacity(0.3) : AppTheme.border),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              [
                                v['nombre']?.toString() ?? '',
                                if ((v['tamano']?.toString() ?? '').isNotEmpty) v['tamano'].toString(),
                              ].join(' · '),
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text('\$${precio.toStringAsFixed(2)} / ${v['unidad'] ?? 'unidad'}',
                                style: const TextStyle(color: AppTheme.primary, fontSize: 12)),
                          ])),
                          // Controles +/-
                          Row(children: [
                            GestureDetector(
                              onTap: () => setS(() {
                                if (idx >= 0 && (itemsSel[idx]['cantidad'] as double) > 1) {
                                  itemsSel[idx]['cantidad'] = (itemsSel[idx]['cantidad'] as double) - 1;
                                } else if (idx >= 0) {
                                  itemsSel.removeAt(idx);
                                }
                              }),
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
                                child: const Icon(Icons.remove, size: 14, color: AppTheme.textSecondary),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text('${cantidad.toInt()}', style: TextStyle(
                                color: cantidad > 0 ? AppTheme.primary : AppTheme.textMuted,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                            GestureDetector(
                              onTap: () => setS(() {
                                if (idx >= 0) {
                                  itemsSel[idx]['cantidad'] = (itemsSel[idx]['cantidad'] as double) + 1;
                                } else {
                                  itemsSel.add({
                                    'variante_id': varId,
                                    'descripcion': [
                                      prod['nombre']?.toString() ?? '',
                                      if ((v['tamano']?.toString() ?? '').isNotEmpty) v['tamano'].toString(),
                                      v['nombre']?.toString() ?? '',
                                    ].join(' - '),
                                    'precio': precio,
                                    'cantidad': 1.0,
                                  });
                                }
                              }),
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
                                child: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                              ),
                            ),
                          ]),
                        ]),
                      );
                    }),
                  ]);
                }),
                // Total en tiempo real
                if (itemsSel.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: AppTheme.colorAhorro.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.colorAhorro.withOpacity(0.25))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total del pedido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      Text('\$${calcTotal().toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.colorAhorro, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
              ],
            ],

            // ── CONDICIÓN DE PAGO ─────────────────────────────────────────────
            const SizedBox(height: 20),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            const Text('Condición de pago', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              _condBtn('contra_entrega', 'Contra entrega', condicion, (v) => setS(() => condicion = v)),
              _condBtn('plazo', 'A plazo', condicion, (v) => setS(() => condicion = v)),
              _condBtn('fecha_especifica', 'Fecha exacta', condicion, (v) => setS(() => condicion = v)),
            ]),
            // A plazo: slider de días
            if (condicion == 'plazo') ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Días para cobrar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Text('$diasPlazo días', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
              ]),
              Slider(value: diasPlazo.toDouble(), min: 1, max: 60, divisions: 59,
                  label: '$diasPlazo días', onChanged: (v) => setS(() => diasPlazo = v.toInt())),
            ],
            // Fecha exacta: date picker (Fase 3)
            if (condicion == 'fecha_especifica') ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary, surface: AppTheme.surfaceAlt)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setS(() => fechaEspecifica = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: fechaEspecifica != null ? AppTheme.primary : AppTheme.border)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 10),
                    Text(
                      fechaEspecifica != null
                          ? '${fechaEspecifica!.year}-${fechaEspecifica!.month.toString().padLeft(2, '0')}-${fechaEspecifica!.day.toString().padLeft(2, '0')}'
                          : 'Seleccionar fecha de cobro',
                      style: TextStyle(color: fechaEspecifica != null ? AppTheme.textPrimary : AppTheme.textMuted),
                    ),
                    if (fechaEspecifica != null) ...[
                      const Spacer(),
                      const Icon(Icons.event_available, color: AppTheme.primary, size: 16),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              const Text('Se creará un recordatorio automático en el Calendario.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ],

            // ── BOTÓN CONFIRMAR ───────────────────────────────────────────────
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty) return;

                // Validación según modo
                if (!usarCatalogo) {
                  final monto = double.tryParse(montoCtrl.text) ?? 0;
                  if (monto <= 0) return;
                } else {
                  if (itemsSel.isEmpty) return;
                }
                if (condicion == 'fecha_especifica' && fechaEspecifica == null) return;

                Navigator.pop(context);

                // Monto inicial: 0 si usa catálogo (se recalculará desde los items)
                final montoInicial = usarCatalogo ? 0.0 : (double.tryParse(montoCtrl.text) ?? 0);
                final body = <String, dynamic>{
                  'nombre_cliente': nombre,
                  'monto': montoInicial,
                  'condicion_pago': condicion,
                  'firebase_uid': widget.firebaseUid,
                };
                if (condicion == 'plazo') body['dias_plazo'] = diasPlazo;
                if (condicion == 'fecha_especifica' && fechaEspecifica != null) {
                  body['fecha_pago_especifica'] =
                      '${fechaEspecifica!.year}-${fechaEspecifica!.month.toString().padLeft(2, '0')}-${fechaEspecifica!.day.toString().padLeft(2, '0')}';
                }

                final res = await ApiClient.post('/ventas/${widget.ventaId}/cobros', body);
                if (res.statusCode != 201) { _cargar(); return; }

                // Si usa catálogo: agregar items al cobro recién creado
                if (usarCatalogo && itemsSel.isNotEmpty) {
                  final cobroId = json.decode(res.body)['id'] as int?;
                  if (cobroId != null) {
                    await Future.wait(itemsSel.map((item) => ApiClient.post('/cobros/$cobroId/items', {
                      'variante_id': item['variante_id'],
                      'descripcion': item['descripcion'],
                      'cantidad': item['cantidad'],
                      'precio_unitario': item['precio'],
                      'firebase_uid': widget.firebaseUid,
                    })));
                  }
                }
                _cargar();
              },
              child: const Text('Agregar cliente'),
            )),
          ]),
        ),
      )),
    );
  }

  /// Abre el bottom sheet para registrar el cobro de un cliente.
  ///
  /// Pre-rellena el monto acordado pero permite editarlo si el cliente pagó
  /// un monto diferente (ej: pagó parcial o con propina).
  void _modalCobrar(Map<String, dynamic> cobro) {
    final montoCtrl = TextEditingController(
        text: (double.tryParse(cobro['monto']?.toString() ?? '0') ?? 0).toStringAsFixed(2));

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Cobrar a ${cobro['nombre_cliente']}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Confirma el monto cobrado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          // Campo de monto con autofocus para edición rápida
          TextField(
            controller: montoCtrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.success, fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final monto = double.tryParse(montoCtrl.text) ?? 0;
              if (monto <= 0) return;
              Navigator.pop(context);
              final res = await ApiClient.put('/cobros/${cobro['id']}/cobrar',
                  {'monto_cobrado': monto, 'firebase_uid': widget.firebaseUid});
              // Optimistic update: actualizar UI de inmediato sin esperar _cargar().
              // Evita que un cold start de Render deje los totales desactualizados.
              if (res.statusCode == 200 && mounted) {
                final cobroId = cobro['id'] is int
                    ? cobro['id'] as int
                    : int.tryParse(cobro['id'].toString()) ?? 0;
                setState(() {
                  for (int i = 0; i < _cobros.length; i++) {
                    final id = _cobros[i]['id'] is int
                        ? _cobros[i]['id'] as int
                        : int.tryParse(_cobros[i]['id'].toString()) ?? 0;
                    if (id == cobroId) {
                      _cobros[i] = Map<String, dynamic>.from(_cobros[i] as Map)
                        ..['estado'] = 'cobrado'
                        ..['monto_cobrado'] = monto;
                      break;
                    }
                  }
                  // Recalcular resumen localmente con los nuevos cobros
                  final cobrados  = _cobros.where((c) => c['estado'] == 'cobrado').toList();
                  final pendts    = _cobros.where((c) => c['estado'] == 'pendiente').toList();
                  final tCobrado  = cobrados.fold(0.0, (s, c) => s +
                      (double.tryParse(c['monto_cobrado']?.toString() ?? c['monto']?.toString() ?? '0') ?? 0));
                  final tEsperado = _cobros.fold(0.0, (s, c) => s +
                      (double.tryParse(c['monto']?.toString() ?? '0') ?? 0));
                  final tPend     = pendts.fold(0.0, (s, c) => s +
                      (double.tryParse(c['monto']?.toString() ?? '0') ?? 0));
                  final inv    = double.tryParse(_resumen['total_invertido']?.toString() ?? '0') ?? 0;
                  final gan    = tCobrado - inv;
                  final mrg    = tCobrado > 0 ? (gan / tCobrado * 100) : 0.0;
                  final pct    = tEsperado > 0 ? (tCobrado / tEsperado * 100) : 0.0;
                  final mrgEsp = tEsperado > 0 ? ((tEsperado - inv) / tEsperado * 100) : 0.0;
                  _resumen = {
                    ..._resumen,
                    'total_cobrado':    tCobrado,
                    'total_pendiente':  tPend,
                    'total_esperado':   tEsperado,
                    'ganancia':         gan,
                    'margen':           mrg,
                    'margen_esperado':  mrgEsp,
                    'porcentaje_cobrado': pct,
                    'cobros_realizados': cobrados.length,
                    'cobros_pendientes': pendts.length,
                  };
                });
              }
              _cargar(silencioso: true); // sincroniza con servidor sin reemplazar la UI
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success, foregroundColor: AppTheme.background),
            child: const Text('Confirmar cobro'),
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Spinner mientras carga — incluye texto para que no parezca pantalla en blanco
    if (_loading) return Scaffold(
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: AppTheme.primary),
        const SizedBox(height: 16),
        const Text('Cargando venta...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ])),
    );

    // FIX: si _venta es null tras cargar (error de red, 404, timeout),
    // mostrar pantalla de error con botón Reintentar en lugar de renderizar
    // datos vacíos que parecen una pantalla en blanco.
    if (_venta == null) return Scaffold(
      appBar: AppBar(title: const Text('Venta')),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 16),
        const Text('No se pudo cargar la venta', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Verifica tu conexión e intenta de nuevo', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
        ),
      ])),
    );

    final nombre         = _venta!['nombre'] ?? 'Venta';
    final invertido      = double.tryParse(_resumen['total_invertido']?.toString()    ?? '0') ?? 0;
    final cobrado        = double.tryParse(_resumen['total_cobrado']?.toString()      ?? '0') ?? 0;
    final esperado       = double.tryParse(_resumen['total_esperado']?.toString()     ?? '0') ?? 0;
    final pendienteAmt   = double.tryParse(_resumen['total_pendiente']?.toString()    ?? '0') ?? 0;
    final ganancia       = double.tryParse(_resumen['ganancia']?.toString()           ?? '0') ?? 0;
    final margen     = double.tryParse(_resumen['margen']?.toString()             ?? '0') ?? 0;
    final pctCobrado = double.tryParse(_resumen['porcentaje_cobrado']?.toString() ?? '0') ?? 0;
    final realizados     = int.tryParse(_resumen['cobros_realizados']?.toString() ?? '0') ?? 0;
    final pendientes     = int.tryParse(_resumen['cobros_pendientes']?.toString()  ?? '0') ?? 0;
    // Fase 6: costo estimado desde recetas (null si no hay precios definidos en los insumos)
    final costoEstimado   = _resumen['costo_estimado'] != null
        ? double.tryParse(_resumen['costo_estimado'].toString()) : null;
    final diferenciaCosto = _resumen['diferencia_costo'] != null
        ? double.tryParse(_resumen['diferencia_costo'].toString()) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(nombre, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Detalle de venta',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Muestra la rentabilidad de una venta y el estado de cobro de cada cliente.\n\n'
                  'Gráfica de rentabilidad:\n'
                  '  • Invertido → costo total de los insumos vinculados.\n'
                  '  • Cobrado → suma de los cobros ya realizados.\n'
                  '  • Esperado → total de todos los cobros (realizados + pendientes).\n'
                  '  • Ganancia = Cobrado − Invertido.\n\n'
                  'Lista de clientes:\n'
                  '  1. Toca "Cliente" para agregar un cobro.\n'
                  '  2. Contra entrega → se cobra en el momento de la entrega.\n'
                  '  3. A plazo → se programa un recordatorio en el Calendario.\n'
                  '  4. Toca "Cobrar" para registrar el monto recibido.\n\n'
                  'Si no vinculaste un presupuesto de producción, '
                  'la barra de "Invertido" no aparece.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined, size: 20),
            tooltip: 'Reporte de producción',
            onPressed: _modalReporteProduccion,
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, size: 20),
            tooltip: 'Lista de compras',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ListaComprasScreen(
                ventaId: widget.ventaId,
                ventaNombre: nombre,
                firebaseUid: widget.firebaseUid,
              ),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => _cargar(silencioso: true)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _modalAgregarCliente,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Cliente'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.background,
      ),
      body: Column(children: [
        // Barra delgada de refresh en background (no interrumpe la UI)
        if (_refreshing)
          const LinearProgressIndicator(
            backgroundColor: AppTheme.surfaceAlt,
            color: AppTheme.primary,
            minHeight: 3,
          ),
        Expanded(child: RefreshIndicator(
        color: AppTheme.primary, backgroundColor: AppTheme.surface,
        onRefresh: () => _cargar(silencioso: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── GRÁFICA DE RENTABILIDAD (Fase 7 — ampliada) ───────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('RENTABILIDAD',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ganancia >= 0
                          ? AppTheme.success.withOpacity(0.1)
                          : AppTheme.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      ganancia >= 0 ? '↑ Ganancia' : '↓ Pérdida',
                      style: TextStyle(
                        color: ganancia >= 0 ? AppTheme.success : AppTheme.danger,
                        fontSize: 11, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Barras comparativas (Invertido / Cobrado / Esperado)
                if (invertido > 0) ...[
                  _barraComparativa('Invertido', invertido,
                      max(max(invertido, cobrado), max(esperado, 0.01)), AppTheme.colorFijo),
                  const SizedBox(height: 10),
                ],
                _barraComparativa('Cobrado', cobrado,
                    max(max(invertido, cobrado), max(esperado, 0.01)), AppTheme.success),
                if (esperado > cobrado) ...[
                  const SizedBox(height: 10),
                  _barraComparativa('Esperado', esperado,
                      max(max(invertido, esperado), 0.01), AppTheme.primary, dashed: true),
                ],

                const SizedBox(height: 20),
                const Divider(color: AppTheme.border, height: 1),
                const SizedBox(height: 16),

                // Inversión — siempre visible, editable.
                // Distingue entre "nunca registrada" (null en venta.inversion)
                // y "registrada en 0" o "calculada desde presupuestos".
                GestureDetector(
                  onTap: _modalEditarInversion,
                  child: Builder(builder: (ctx) {
                    final inversionRaw = _venta!['inversion'];
                    final inversionEsManual = inversionRaw != null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: inversionEsManual
                            ? AppTheme.colorFijo.withOpacity(0.07)
                            : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: inversionEsManual
                            ? AppTheme.colorFijo.withOpacity(0.25)
                            : AppTheme.border),
                      ),
                      child: Row(children: [
                        Icon(Icons.savings_outlined,
                            color: inversionEsManual ? AppTheme.colorFijo : AppTheme.textMuted,
                            size: 16),
                        const SizedBox(width: 10),
                        const Text('Inversión:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(width: 6),
                        inversionEsManual
                            ? Text('\$${invertido.toStringAsFixed(2)}',
                                style: const TextStyle(color: AppTheme.colorFijo,
                                    fontWeight: FontWeight.w800, fontSize: 15))
                            : const Text('Sin registrar · toca para agregar',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        const Spacer(),
                        const Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 14),
                      ]),
                    );
                  }),
                ),

                // Fila 1: Ganancia / Margen / Cobrados
                // FIX: ganancia y margen muestran $0/— cuando cobrado=0.
                // Antes mostraba el invertido como pérdida sin haber vendido nada.
                Row(children: [
                  _statBox(
                    'Ganancia',
                    cobrado > 0 ? '\$${ganancia.abs().toStringAsFixed(2)}' : '\$0.00',
                    cobrado > 0
                        ? (ganancia >= 0 ? AppTheme.success : AppTheme.danger)
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  _statBox(
                    'Margen',
                    cobrado > 0 ? '${margen.toStringAsFixed(1)}%' : '—',
                    cobrado > 0
                        ? (margen >= 0 ? AppTheme.success : AppTheme.danger)
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  _statBox('Cobrados', '$realizados / ${realizados + pendientes}', AppTheme.primary),
                ]),

                // Barra visual de progreso de cobros (% cobrado)
                if (esperado > 0) ...[
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('% Cobrado',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    Text(
                      '${pctCobrado.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: pctCobrado >= 100
                            ? AppTheme.success
                            : pctCobrado > 0
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pctCobrado / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppTheme.surfaceAlt,
                      color: pctCobrado >= 100 ? AppTheme.success : AppTheme.primary,
                    ),
                  ),
                ],

                // Fila 2: Por cobrar + pendientes (solo cuando hay saldo pendiente)
                if (pendienteAmt > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    _statBox('Por cobrar', '\$${pendienteAmt.toStringAsFixed(2)}', AppTheme.warning),
                    const SizedBox(width: 8),
                    _statBox('Pendientes', '$pendientes cobro${pendientes != 1 ? "s" : ""}',
                        AppTheme.warning),
                  ]),
                ],
              ]),
            ),

            // ── OBJETIVO DE MARGEN ─────────────────────────────────────────
            const SizedBox(height: 16),
            const LabelDivider('OBJETIVO DE MARGEN'),
            _seccionObjetivo(invertido, esperado),

            // ── PRESUPUESTOS DE PRODUCCIÓN VINCULADOS (Fase 2) ────────────
            if (_presupuestos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const LabelDivider('COSTOS DE PRODUCCIÓN'),
              ..._presupuestos.map((pp) {
                final ppTotal = double.tryParse(pp['total_invertido']?.toString() ?? '0') ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.colorFijo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.colorFijo, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(pp['nombre']?.toString() ?? '',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                    Text('\$${ppTotal.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.colorFijo, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                );
              }),
              if (_presupuestos.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.colorFijo.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.colorFijo.withOpacity(0.2)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total invertido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text('\$${invertido.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.colorFijo, fontWeight: FontWeight.w800, fontSize: 14)),
                  ]),
                ),
            ],

            // ── COMPARACIÓN ESTIMADO vs REAL (Fase 6) ─────────────────────
            // Solo visible cuando hay costo_estimado calculado desde recetas.
            if (costoEstimado != null && costoEstimado > 0) ...[
              const SizedBox(height: 16),
              const LabelDivider('PRESUPUESTO: ESTIMADO vs REAL'),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Barra costo estimado (desde recetas)
                  _barraComparativa(
                    'Costo estimado (recetas)',
                    costoEstimado,
                    max(costoEstimado, invertido > 0 ? invertido : costoEstimado),
                    AppTheme.colorAhorro,
                    dashed: true,
                  ),
                  if (invertido > 0) ...[
                    const SizedBox(height: 10),
                    _barraComparativa(
                      'Costo real (presupuesto)',
                      invertido,
                      max(costoEstimado, invertido),
                      AppTheme.colorFijo,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.border, height: 1),
                  const SizedBox(height: 14),
                  // Diferencia y badge de estado
                  Row(children: [
                    if (diferenciaCosto != null) ...[
                      _statBox(
                        diferenciaCosto >= 0 ? 'Sobre presupuesto' : 'Bajo presupuesto',
                        '\$${diferenciaCosto.abs().toStringAsFixed(2)}',
                        diferenciaCosto > 0 ? AppTheme.danger : AppTheme.success,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _statBox('Estimado\n(recetas)', '\$${costoEstimado.toStringAsFixed(2)}',
                        AppTheme.colorAhorro),
                    if (invertido > 0) ...[
                      const SizedBox(width: 8),
                      _statBox('Real\n(presupuesto)', '\$${invertido.toStringAsFixed(2)}',
                          AppTheme.colorFijo),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.colorAhorro.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: AppTheme.colorAhorro, size: 12),
                      const SizedBox(width: 7),
                      const Expanded(child: Text(
                        'El estimado se calcula con los precios definidos en las recetas de cada variante.',
                        style: TextStyle(color: AppTheme.colorAhorro, fontSize: 10),
                      )),
                    ]),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 16),
            const LabelDivider('CLIENTES'),

            // ── LISTA DE COBROS ────────────────────────────────────────────
            if (_cobros.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Column(children: [
                  Icon(Icons.person_outline, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  const Text('Sin clientes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text('Toca "Cliente" para agregar', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ])),
              )
            else
              ...(_cobros.map((c) => _ClienteTile(
                cobro: c,
                onCobrar: () => _modalCobrar(c),
                onEliminar: () => _eliminarCobro(c['id']),
              ))),

            const SizedBox(height: 80), // espacio para el FAB
          ]),
        ),
      )),  // cierra Expanded + RefreshIndicator
      ]),  // cierra Column del body
    );
  }

  /// Modal de reporte de producción (Mejora 2).
  /// Agrupa todos los pedido_items de la venta por descripción + precio,
  /// suma cantidades y muestra el consolidado ordenado alfabéticamente.
  void _modalReporteProduccion() {
    // Agregar todos los items de todos los cobros
    final Map<String, Map<String, dynamic>> agrupado = {};
    for (final cobro in _cobros) {
      final items = (cobro['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final item in items) {
        final desc  = item['descripcion']?.toString() ?? '';
        final precio = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
        final cant   = double.tryParse(item['cantidad']?.toString() ?? '0') ?? 0;
        final key    = '$desc||${precio.toStringAsFixed(2)}';
        if (agrupado.containsKey(key)) {
          agrupado[key]!['cantidad'] = (agrupado[key]!['cantidad'] as double) + cant;
        } else {
          agrupado[key] = {'descripcion': desc, 'precio': precio, 'cantidad': cant};
        }
      }
    }

    final lista = agrupado.values.toList()
      ..sort((a, b) => (a['descripcion'] as String).compareTo(b['descripcion'] as String));

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.92, minChildSize: 0.4, expand: false,
        builder: (_, sc) => Column(children: [
          // Handle + título fijo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.summarize_outlined, color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
                const Text('Reporte de Producción',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${lista.length} producto${lista.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              const Divider(color: AppTheme.border, height: 1),
            ]),
          ),
          // Lista scrollable
          Expanded(child: lista.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Ningún cliente tiene productos del catálogo.\nAgrega clientes con pedidos del catálogo para ver el reporte.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ))
              : ListView.separated(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                  itemBuilder: (_, i) {
                    final item  = lista[i];
                    final cant  = item['cantidad'] as double;
                    final precio = item['precio'] as double;
                    final cantStr = cant % 1 == 0 ? cant.toInt().toString() : cant.toStringAsFixed(1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['descripcion'].toString(),
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          Text('\$${precio.toStringAsFixed(2)} c/u',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$cantStr uds',
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text('\$${(cant * precio).toStringAsFixed(2)}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ]),
                      ]),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }

  /// Bottom sheet para registrar o editar la inversión de la venta.
  ///
  /// FIX 1: Lee el campo `inversion` del objeto `_venta` directamente
  ///        (no de `_resumen['total_invertido']` que podría venir de presupuestos).
  /// FIX 2: Campo vacío → envía null (borra la inversión) en lugar de 0.
  ///        0 en DB bloquea COALESCE(0,...) y oculta cálculo de presupuestos.
  /// FIX 3: Optimistic update inmediato, sin esperar cold start de Render.
  /// FIX 4: Muestra SnackBar si el PUT falla.
  void _modalEditarInversion() {
    // Leer el valor guardado en la BD (puede ser null si nunca se registró)
    final inversionGuardada = _venta != null && _venta!['inversion'] != null
        ? double.tryParse(_venta!['inversion'].toString()) : null;
    final ctrl = TextEditingController(
      text: inversionGuardada != null ? inversionGuardada.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Inversión de producción',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('¿Cuánto gastaste para producir esta venta? (deja vacío para borrar)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Aceptar dígitos, punto y coma (la coma se normaliza a punto al guardar)
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.colorFijo, fontSize: 26, fontWeight: FontWeight.w800),
              hintText: '0.00',
              helperText: 'Acepta punto o coma como decimal (ej: 45.50 o 45,50)',
              helperStyle: TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              // Normalizar separador decimal: el teclado numérico de algunos
              // dispositivos Android latinoamericanos envía "45,50" en lugar
              // de "45.50". double.tryParse solo acepta punto.
              final texto = ctrl.text.trim().replaceAll(',', '.');
              final inversion = texto.isEmpty ? null : double.tryParse(texto);

              // Validación: si hay texto pero no parsea → campo inválido
              if (texto.isNotEmpty && inversion == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingresa un número válido (ej: 45.50)')),
                );
                return;
              }

              Navigator.pop(context);

              // Optimistic update: actualizar UI antes de que responda Render
              if (mounted) {
                final newInv = inversion ?? 0.0;
                setState(() {
                  if (_venta != null) {
                    _venta = Map<String, dynamic>.from(_venta!)..['inversion'] = inversion;
                  }
                  final tCobrado = double.tryParse(_resumen['total_cobrado']?.toString() ?? '0') ?? 0;
                  final tEsperado = double.tryParse(_resumen['total_esperado']?.toString() ?? '0') ?? 0;
                  final gan = tCobrado - newInv;
                  final mrg = tCobrado > 0 ? (gan / tCobrado * 100) : 0.0;
                  final mrgEsp = tEsperado > 0 ? ((tEsperado - newInv) / tEsperado * 100) : 0.0;
                  _resumen = {
                    ..._resumen,
                    'total_invertido': newInv,
                    'ganancia':        gan,
                    'margen':          mrg,
                    'margen_esperado': mrgEsp,
                  };
                });
              }

              final res = await ApiClient.put('/ventas/${widget.ventaId}',
                  {'inversion': inversion, 'firebase_uid': widget.firebaseUid});

              if (!mounted) return;
              if (res.statusCode != 200) {
                String msg;
                try {
                  msg = json.decode(res.body)['error']?.toString() ?? 'Error al guardar';
                } catch (_) {
                  msg = 'Error ${res.statusCode} al guardar la inversión';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              }
              _cargar(silencioso: true); // sincronizar con servidor en background
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.colorFijo,
                foregroundColor: AppTheme.background),
            child: const Text('Guardar inversión'),
          )),
        ]),
      ),
    );
  }

  /// Elimina un cobro tras confirmación con optimistic update inmediato.
  Future<void> _eliminarCobro(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar cliente', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar este cobro?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Optimistic update: quitar el cobro de la lista y recalcular resumen localmente
    setState(() {
      _cobros = _cobros.where((c) {
        final cid = c['id'] is int ? c['id'] as int : int.tryParse(c['id'].toString()) ?? 0;
        return cid != id;
      }).toList();
      final cobrados  = _cobros.where((c) => c['estado'] == 'cobrado').toList();
      final pendts    = _cobros.where((c) => c['estado'] == 'pendiente').toList();
      final tCobrado  = cobrados.fold(0.0, (s, c) => s +
          (double.tryParse(c['monto_cobrado']?.toString() ?? c['monto']?.toString() ?? '0') ?? 0));
      final tEsperado = _cobros.fold(0.0, (s, c) => s +
          (double.tryParse(c['monto']?.toString() ?? '0') ?? 0));
      final tPend     = pendts.fold(0.0, (s, c) => s +
          (double.tryParse(c['monto']?.toString() ?? '0') ?? 0));
      final inv    = double.tryParse(_resumen['total_invertido']?.toString() ?? '0') ?? 0;
      final gan    = tCobrado - inv;
      final mrg    = tCobrado > 0 ? (gan / tCobrado * 100) : 0.0;
      final pct    = tEsperado > 0 ? (tCobrado / tEsperado * 100) : 0.0;
      final mrgEsp = tEsperado > 0 ? ((tEsperado - inv) / tEsperado * 100) : 0.0;
      _resumen = {
        ..._resumen,
        'total_cobrado': tCobrado, 'total_pendiente': tPend, 'total_esperado': tEsperado,
        'ganancia': gan, 'margen': mrg, 'margen_esperado': mrgEsp,
        'porcentaje_cobrado': pct,
        'cobros_realizados': cobrados.length, 'cobros_pendientes': pendts.length,
      };
    });

    await ApiClient.delete('/cobros/$id?firebase_uid=${widget.firebaseUid}');
    _cargar(silencioso: true);
  }

  /// Sección de planificación: el usuario elige un margen objetivo y la app
  /// calcula cuánto necesita vender para alcanzarlo, comparándolo con las
  /// ventas proyectadas actuales.
  ///
  /// Fórmula: ventas_necesarias = invertido / (1 − margen_objetivo)
  /// Ejemplo: invertido=$100, objetivo=25% → necesitas vender $133.33
  Widget _seccionObjetivo(double invertido, double esperado) {
    const mrgValues = [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60];
    const mrgLabels = [
      '10% – Mínimo', '15% – Básico', '20% – Razonable',
      '25% – Sólido', '30% – Bueno', '35% – Muy bueno',
      '40% – Excelente', '50% – Óptimo', '60% – Premium',
    ];

    final ventasNecesarias = invertido > 0 && _margenObjetivo < 1.0
        ? invertido / (1.0 - _margenObjetivo)
        : 0.0;
    final brecha = ventasNecesarias > 0 ? (esperado - ventasNecesarias) : 0.0;
    final pctAvance = ventasNecesarias > 0
        ? (esperado / ventasNecesarias).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selector de margen objetivo
        Row(children: [
          const Icon(Icons.flag_outlined, color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          const Text('Meta de margen',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const Spacer(),
          DropdownButton<double>(
            value: _margenObjetivo,
            dropdownColor: AppTheme.surfaceAlt,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(
                color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
            items: List.generate(
              mrgValues.length,
              (i) => DropdownMenuItem(
                value: mrgValues[i],
                child: Text(mrgLabels[i],
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ),
            ),
            onChanged: (v) { if (v != null) setState(() => _margenObjetivo = v); },
          ),
        ]),

        if (invertido <= 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.textMuted, size: 14),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Registra la inversión para calcular el objetivo de ventas.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              )),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          // Ventas necesarias para el margen objetivo
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(
              'Ventas para ${(_margenObjetivo * 100).toStringAsFixed(0)}% de margen',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )),
            const SizedBox(width: 8),
            Text('\$${ventasNecesarias.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),

          if (esperado > 0) ...[
            const SizedBox(height: 10),
            // Progreso hacia el objetivo
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Ventas proyectadas: \$${esperado.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              Text(
                '${(pctAvance * 100).toStringAsFixed(0)}% del objetivo',
                style: TextStyle(
                  color: pctAvance >= 1.0 ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 11, fontWeight: FontWeight.w600,
                ),
              ),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pctAvance,
                minHeight: 7,
                backgroundColor: AppTheme.surfaceAlt,
                color: pctAvance >= 1.0 ? AppTheme.success : AppTheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            // Badge de brecha
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: brecha >= 0
                    ? AppTheme.success.withOpacity(0.08)
                    : AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: brecha >= 0
                      ? AppTheme.success.withOpacity(0.2)
                      : AppTheme.danger.withOpacity(0.2),
                ),
              ),
              child: Row(children: [
                Icon(
                  brecha >= 0
                      ? Icons.check_circle_outline
                      : Icons.arrow_upward_outlined,
                  color: brecha >= 0 ? AppTheme.success : AppTheme.danger,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  brecha >= 0
                      ? 'Superarás el objetivo en \$${brecha.abs().toStringAsFixed(2)}'
                      : 'Faltan \$${brecha.abs().toStringAsFixed(2)} en ventas para el objetivo',
                  style: TextStyle(
                    color: brecha >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                )),
              ]),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Agrega clientes para comparar con el objetivo.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ],
      ]),
    );
  }

  /// Barra horizontal comparativa para la gráfica de rentabilidad.
  ///
  /// [valor] es el monto de esta métrica.
  /// [maxVal] es el máximo entre todas las métricas (para escalar proporcional).
  /// [dashed] muestra borde en lugar de relleno sólido → indica valor proyectado.
  Widget _barraComparativa(String label, double valor, double maxVal, Color color, {bool dashed = false}) {
    final pct = maxVal > 0 ? (valor / maxVal).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text('\$${valor.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      Stack(children: [
        // Fondo de la barra
        Container(height: 10, decoration: BoxDecoration(
            color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(5))),
        // Relleno proporcional al porcentaje
        FractionallySizedBox(
          widthFactor: pct,
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: dashed ? null : color,
              borderRadius: BorderRadius.circular(5),
              // Borde punteado para "Esperado" (valor proyectado)
              border: dashed ? Border.all(color: color, width: 1.5) : null,
              // Gradiente suave de izquierda a derecha para barras sólidas
              gradient: dashed ? null : LinearGradient(colors: [color.withOpacity(0.7), color]),
            ),
          ),
        ),
      ]),
    ]);
  }

  /// Caja de estadística usada en la fila de resumen (Ganancia / Margen / Cobrados).
  Widget _statBox(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10), textAlign: TextAlign.center),
      ]),
    ),
  );

  /// Botón de toggle para seleccionar condición de pago en el modal de cliente.
  /// Ahora devuelve un widget flexible (no Expanded) para usarse en Wrap.
  Widget _condBtn(String value, String label, String selected, void Function(String) onTap) =>
    GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
        decoration: BoxDecoration(
          color: selected == value ? AppTheme.primary.withOpacity(0.1) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected == value ? AppTheme.primary : AppTheme.border,
            width: selected == value ? 1.5 : 1,
          ),
        ),
        child: Text(label, style: TextStyle(
          color: selected == value ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 12, fontWeight: selected == value ? FontWeight.w700 : FontWeight.normal,
        )),
      ),
    );
}

/// Tarjeta de un cliente dentro de la lista de cobros de una venta.
///
/// Si el cobro tiene `items[]` (pedido con catálogo), muestra el detalle de
/// productos debajo del nombre. Si no, muestra solo el monto manual.
///
/// Compatibilidad: cobros sin items[] funcionan igual que antes.
class _ClienteTile extends StatelessWidget {
  final Map<String, dynamic> cobro;
  final VoidCallback onCobrar, onEliminar;
  const _ClienteTile({required this.cobro, required this.onCobrar, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final cobrado      = cobro['estado'] == 'cobrado';
    final monto        = double.tryParse(cobro['monto']?.toString() ?? '0') ?? 0;
    final montoCobrado = cobro['monto_cobrado'] != null
        ? double.tryParse(cobro['monto_cobrado'].toString()) : null;
    final items = (cobro['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Etiqueta de condición de pago con fecha si aplica
    String condicion;
    final fechaCobro = cobro['fecha_cobro']?.toString();
    switch (cobro['condicion_pago']) {
      case 'plazo':
        condicion = fechaCobro != null
            ? 'Plazo · $fechaCobro'
            : 'A plazo · ${cobro['dias_plazo'] ?? '?'}d';
        break;
      case 'fecha_especifica':
        condicion = fechaCobro != null ? 'Fecha · $fechaCobro' : 'Fecha exacta';
        break;
      default:
        condicion = 'Contra entrega';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cobrado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cobrado ? AppTheme.success.withOpacity(0.25) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── FILA PRINCIPAL ─────────────────────────────────────────────────
        Row(children: [
        // Avatar con la inicial del nombre del cliente
        CircleAvatar(
          backgroundColor: cobrado
              ? AppTheme.success.withOpacity(0.15) : AppTheme.primary.withOpacity(0.1),
          radius: 20,
          child: Text(
            (cobro['nombre_cliente'] as String? ?? '?').isNotEmpty
                ? (cobro['nombre_cliente'] as String)[0].toUpperCase() : '?',
            style: TextStyle(
              color: cobrado ? AppTheme.success : AppTheme.primary,
              fontWeight: FontWeight.w800, fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Info del cliente
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cobro['nombre_cliente'] ?? '', style: TextStyle(
            color: cobrado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
          )),
          const SizedBox(height: 3),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(4)),
              child: Text(condicion, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            ),
            if (cobrado && montoCobrado != null) ...[
              const SizedBox(width: 6),
              Text('\$${montoCobrado.toStringAsFixed(2)} cobrado',
                  style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
        ])),

        // Monto y acciones
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: cobrado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
          )),
          const SizedBox(height: 6),
          if (!cobrado)
            Row(children: [
              GestureDetector(onTap: onEliminar,
                  child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCobrar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                  ),
                  child: const Text('Cobrar',
                      style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ])
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),  // cierra Row principal

        // ── DETALLE DE ITEMS (solo si hay pedido con catálogo) ───────────────
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 8),
          ...items.map((item) {
            final cant   = double.tryParse(item['cantidad']?.toString() ?? '1') ?? 1;
            final precio = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
            final sub    = double.tryParse(item['subtotal']?.toString() ?? '0') ?? (cant * precio);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(children: [
                const Icon(Icons.circle, size: 5, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${cant % 1 == 0 ? cant.toInt() : cant} × ${item['descripcion'] ?? ''}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                )),
                Text('\$${sub.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ]),  // cierra Column principal
    );
  }
}

/// Divider con etiqueta centrada (definido localmente para evitar
/// importar app_theme.dart directamente en este archivo).
class LabelDivider extends StatelessWidget {
  final String label;
  const LabelDivider(this.label, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      const Expanded(child: Divider(color: AppTheme.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
      ),
      const Expanded(child: Divider(color: AppTheme.border)),
    ]),
  );
}
