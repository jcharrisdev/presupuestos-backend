/// Pantalla principal del módulo de Cobros.
///
/// Organizada en 2 pestañas:
///   - **Producción**: listado de presupuestos de insumos. Cada uno muestra el
///     costo total invertido. Al tocar abre [ProduccionDetalle].
///   - **Ventas**: listado de ventas con cobros pendientes. Muestra total cobrado
///     vs esperado con barra de progreso. Al tocar abre [VentaDetalle].
///
/// El FAB es CONTEXTUAL: cambia su acción según la pestaña activa.
///   - Pestaña "Producción" → abre modal para crear presupuesto de producción.
///   - Pestaña "Ventas"     → abre modal para crear venta (opcionalmente vinculada
///     a un presupuesto de producción para calcular rentabilidad).
///
/// Flujo completo del módulo:
///   presupuesto_produccion (insumos) → venta → cobros_clientes → calendario
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'produccion_detalle.dart';
import 'venta_detalle.dart';

/// Pantalla con tabs Producción / Ventas y FAB contextual.
class CobrosHome extends StatefulWidget {
  final String firebaseUid;
  const CobrosHome({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CobrosHomeState createState() => _CobrosHomeState();
}

class _CobrosHomeState extends State<CobrosHome> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _producciones = [];
  List<dynamic> _ventas = [];
  bool _loadProd = true, _loadVentas = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // Carga ambas listas en paralelo al inicializar la pantalla
    _cargarProducciones();
    _cargarVentas();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  /// Carga los presupuestos de producción del usuario.
  Future<void> _cargarProducciones() async {
    setState(() => _loadProd = true);
    try {
      final res = await ApiClient.get('/produccion?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) setState(() { _producciones = json.decode(res.body); _loadProd = false; });
      else setState(() => _loadProd = false);
    } catch (_) { setState(() => _loadProd = false); }
  }

  /// Carga las ventas del usuario con resumen de cobros.
  Future<void> _cargarVentas() async {
    setState(() => _loadVentas = true);
    try {
      final res = await ApiClient.get('/ventas?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) setState(() { _ventas = json.decode(res.body); _loadVentas = false; });
      else setState(() => _loadVentas = false);
    } catch (_) { setState(() => _loadVentas = false); }
  }

  /// Abre el bottom sheet para crear un nuevo presupuesto de producción.
  ///
  /// Campos: nombre (requerido), descripción (opcional).
  /// Al confirmar llama POST /produccion y recarga la lista.
  void _crearProduccion() {
    final nombreCtrl = TextEditingController();
    final descCtrl   = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Nuevo presupuesto de producción',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(controller: nombreCtrl, style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Ej: Producción mayo - Cheesecakes')),
          const SizedBox(height: 12),
          TextField(controller: descCtrl, style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Descripción (opcional)'), maxLines: 2),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final res = await ApiClient.post('/produccion', {
                'nombre': nombreCtrl.text.trim(),
                'descripcion': descCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              });
              if (res.statusCode == 201) _cargarProducciones();
            },
            child: const Text('Crear presupuesto'),
          )),
        ]),
      ),
    );
  }

  /// Abre el bottom sheet para crear una nueva venta.
  ///
  /// Campos:
  ///   - Nombre de la venta (requerido)
  ///   - Presupuesto de producción (opcional): si se vincula, el backend
  ///     calculará `ganancia = cobrado - invertido` en [VentaDetalle].
  ///
  /// Al confirmar llama POST /ventas y recarga la lista.
  void _crearVenta() {
    final nombreCtrl = TextEditingController();
    int? prodId; // null si no se vincula a producción

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      // StatefulBuilder necesario porque el dropdown modifica prodId localmente
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Nueva venta',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(controller: nombreCtrl, style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Ej: Venta mayo semana 1')),
          const SizedBox(height: 16),
          const Text('Presupuesto de producción (opcional)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: prodId, dropdownColor: AppTheme.surfaceAlt,
            hint: const Text('Sin presupuesto de insumos', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(),
            items: [
              // Opción para no vincular presupuesto
              const DropdownMenuItem<int>(value: null,
                  child: Text('Sin presupuesto', style: TextStyle(color: AppTheme.textMuted))),
              ..._producciones.map((p) => DropdownMenuItem<int>(
                value: p['id'],
                child: Text(p['nombre'], style: const TextStyle(color: AppTheme.textPrimary)),
              )),
            ],
            onChanged: (v) => setS(() => prodId = v),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final body = <String, dynamic>{
                'nombre': nombreCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              };
              // Solo incluir presupuesto_produccion_id si el usuario eligió uno
              if (prodId != null) body['presupuesto_produccion_id'] = prodId;
              final res = await ApiClient.post('/ventas', body);
              if (res.statusCode == 201) _cargarVentas();
            },
            child: const Text('Crear venta'),
          )),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobros'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined, size: 18), text: 'Producción'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 18), text: 'Ventas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_tabProducciones(), _tabVentas()],
      ),
      // FAB contextual: acción cambia según la pestaña activa
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tab.index == 0 ? _crearProduccion() : _crearVenta(),
        icon: const Icon(Icons.add),
        label: Text(_tab.index == 0 ? 'Producción' : 'Venta'),
      ),
    );
  }

  /// Pestaña de presupuestos de producción.
  Widget _tabProducciones() {
    if (_loadProd) return const Center(child: CircularProgressIndicator());
    if (_producciones.isEmpty) return _empty(
      'Sin presupuestos de producción',
      'Crea uno para registrar tus insumos',
      Icons.inventory_2_outlined,
    );
    return RefreshIndicator(
      color: AppTheme.primary, backgroundColor: AppTheme.surface,
      onRefresh: _cargarProducciones,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _producciones.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p     = _producciones[i];
          final total = double.tryParse(p['total_invertido']?.toString() ?? '0') ?? 0;
          return GestureDetector(
            onTap: () async {
              // Navega al detalle y recarga al regresar (puede haber cambiado el total)
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProduccionDetalle(
                  presupuestoId: p['id'],
                  nombre: p['nombre'],
                  firebaseUid: widget.firebaseUid,
                ),
              ));
              _cargarProducciones();
            },
            child: _card(
              icon: Icons.inventory_2_outlined,
              color: AppTheme.colorFijo,
              title: p['nombre'],
              subtitle: p['descripcion'] ?? '',
              trailing: '\$${total.toStringAsFixed(2)}',
              trailingLabel: 'Costo total',
            ),
          );
        },
      ),
    );
  }

  /// Pestaña de ventas con barra de progreso de cobros.
  Widget _tabVentas() {
    if (_loadVentas) return const Center(child: CircularProgressIndicator());
    if (_ventas.isEmpty) return _empty(
      'Sin ventas registradas',
      'Crea una venta para gestionar cobros',
      Icons.receipt_long_outlined,
    );
    return RefreshIndicator(
      color: AppTheme.primary, backgroundColor: AppTheme.surface,
      onRefresh: _cargarVentas,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _ventas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final v         = _ventas[i];
          final cobrado   = double.tryParse(v['total_cobrado']?.toString() ?? '0') ?? 0;
          final esperado  = double.tryParse(v['total_esperado']?.toString() ?? '0') ?? 0;
          final pendientes = v['cobros_pendientes'] ?? 0;
          return GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => VentaDetalle(ventaId: v['id'], firebaseUid: widget.firebaseUid),
              ));
              _cargarVentas();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.receipt_long_outlined, color: AppTheme.primary, size: 18)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(v['nombre'],
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15))),
                  // Badge de cobros pendientes (solo si hay alguno)
                  if (pendientes > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text('$pendientes pendientes',
                          style: const TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Cobrado', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    Text('\$${cobrado.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w800, fontSize: 16)),
                  ])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Total esperado', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    Text('\$${esperado.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
                  ])),
                ]),
                // Barra de progreso de cobros (solo si hay montos)
                if (esperado > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                    value: (cobrado / esperado).clamp(0.0, 1.0), minHeight: 4,
                    backgroundColor: AppTheme.surfaceAlt, color: AppTheme.success,
                  )),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  /// Tarjeta genérica para ítems de la lista de producción.
  Widget _card({required IconData icon, required Color color, required String title,
      required String subtitle, required String trailing, required String trailingLabel}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(trailing, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 15)),
          Text(trailingLabel, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  /// Pantalla vacía cuando una pestaña no tiene elementos.
  Widget _empty(String t, String s, IconData icon) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, size: 56, color: AppTheme.textMuted.withOpacity(0.35)),
    const SizedBox(height: 16),
    Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    Text(s, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
  ]));

  /// Handle decorativo del bottom sheet (barra gris centrada en la parte superior).
  Widget _handle() => Center(child: Container(
    width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
  ));
}
