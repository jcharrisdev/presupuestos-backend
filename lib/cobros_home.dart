/// Pantalla principal del módulo de Cobros.
///
/// Organizada en 3 pestañas:
///   - **Productos**: catálogo de productos y variantes vendibles.
///   - **Producción**: presupuestos de insumos. Al tocar abre [ProduccionDetalle].
///   - **Ventas**: ventas con cobros. Al tocar abre [VentaDetalle].
///
/// El FAB es CONTEXTUAL: cambia según la pestaña activa.
///   - Pestaña 0 (Productos) → navega a [ProductosScreen]
///   - Pestaña 1 (Producción) → modal crear presupuesto de producción
///   - Pestaña 2 (Ventas) → modal crear venta
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'produccion_detalle.dart';
import 'venta_detalle.dart';
import 'productos_screen.dart';

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

  // Labels e íconos de las 3 pestañas
  static const _tabs = [
    Tab(icon: Icon(Icons.storefront_outlined, size: 18), text: 'Productos'),
    Tab(icon: Icon(Icons.inventory_2_outlined, size: 18), text: 'Producción'),
    Tab(icon: Icon(Icons.receipt_long_outlined, size: 18), text: 'Ventas'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() { if (mounted) setState(() {}); });
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
      if (res.statusCode == 200) {
        setState(() { _producciones = json.decode(res.body); _loadProd = false; });
      } else {
        setState(() => _loadProd = false);
      }
    } catch (e) {
      // FIX: catch silencioso mostraba lista vacía sin avisar al usuario.
      setState(() => _loadProd = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar producción: $e')),
      );
    }
  }

  /// Carga las ventas del usuario con resumen de cobros.
  Future<void> _cargarVentas() async {
    setState(() => _loadVentas = true);
    try {
      final res = await ApiClient.get('/ventas?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        setState(() { _ventas = json.decode(res.body); _loadVentas = false; });
      } else {
        setState(() => _loadVentas = false);
      }
    } catch (e) {
      // FIX: igual que arriba — ahora notifica al usuario en lugar de silenciar el error.
      setState(() => _loadVentas = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar ventas: $e')),
      );
    }
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
  /// Bug 2: el usuario ingresa manualmente el monto de inversión (opcional).
  /// Campos:
  ///   - Nombre de la venta (requerido)
  ///   - Inversión total (opcional, ej: $45.00 gastados en insumos)
  void _crearVenta() {
    final nombreCtrl   = TextEditingController();
    final inversionCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Nueva venta',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(
            controller: nombreCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Ej: Venta mayo semana 1'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: inversionCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Inversión total (opcional)',
              prefixText: '\$ ',
              helperText: 'Cuánto gastaste para producir esta venta',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final inversion = double.tryParse(inversionCtrl.text);
              final body = <String, dynamic>{
                'nombre': nombreCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              };
              if (inversion != null && inversion >= 0) body['inversion'] = inversion;
              final res = await ApiClient.post('/ventas', body);
              if (res.statusCode == 201) _cargarVentas();
            },
            child: const Text('Crear venta'),
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Módulo de Cobros',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Gestiona tu negocio en tres pasos:\n\n'
                  'Pestaña Productos:\n'
                  '  Define tu catálogo: productos y variantes con precio. '
                  'Ej: Cheesecake → Fresa regular \$3.75, Fresa grande \$5.50.\n\n'
                  'Pestaña Producción:\n'
                  '  Registra los insumos que usas para producir (ej: ingredientes). '
                  'El sistema calcula automáticamente el costo total invertido.\n\n'
                  'Pestaña Ventas:\n'
                  '  Crea ventas, agrega clientes y selecciona productos del catálogo. '
                  'El total se calcula automáticamente.\n\n'
                  'Flujo recomendado:\n'
                  '  1. Define productos y variantes en Productos.\n'
                  '  2. Crea un presupuesto de producción con tus insumos.\n'
                  '  3. Crea una venta, agrega clientes y sus productos.\n'
                  '  4. Marca los cobros cuando los recibas.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_tabProductos(), _tabProducciones(), _tabVentas()],
      ),
      // FAB contextual según pestaña: Productos navega, Producción/Ventas abren modal
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tab.index == 0) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProductosScreen(firebaseUid: widget.firebaseUid),
            ));
          } else if (_tab.index == 1) {
            _crearProduccion();
          } else {
            _crearVenta();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tab.index == 0 ? 'Catálogo' : _tab.index == 1 ? 'Producción' : 'Venta'),
      ),
    );
  }

  /// Pestaña de acceso directo al catálogo de productos.
  Widget _tabProductos() {
    return Container(
      color: AppTheme.background,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 36),
        ),
        const SizedBox(height: 20),
        const Text('Catálogo de Productos',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Define productos y variantes con precio para usar en los pedidos de tus clientes.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ProductosScreen(firebaseUid: widget.firebaseUid),
          )),
          icon: const Icon(Icons.storefront_outlined, size: 18),
          label: const Text('Abrir catálogo'),
        ),
      ])),
    );
  }

  /// Pestaña de presupuestos de producción.
  Widget _tabProducciones() {
    // FIX: fondo explícito en todos los estados para evitar fondo gris de Android
    if (_loadProd) return Container(
      color: AppTheme.background,
      child: const Center(child: CircularProgressIndicator()),
    );
    if (_producciones.isEmpty) return Container(
      color: AppTheme.background,
      child: _empty('Sin presupuestos de producción', 'Crea uno para registrar tus insumos', Icons.inventory_2_outlined),
    );
    return Container(
      color: AppTheme.background,
      child: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onRefresh: _cargarProducciones,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _producciones.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final p     = _producciones[i] as Map<String, dynamic>? ?? {};
            final total = double.tryParse(p['total_invertido']?.toString() ?? '0') ?? 0.0;
            final nombre = p['nombre']?.toString() ?? 'Sin nombre';
            return GestureDetector(
              onTap: () async {
                final prodId = p['id'] is int ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                if (prodId == 0) return;
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ProduccionDetalle(
                    presupuestoId: prodId,
                    nombre: nombre,
                    firebaseUid: widget.firebaseUid,
                  ),
                ));
                _cargarProducciones();
              },
              child: _card(
                icon: Icons.inventory_2_outlined,
                color: AppTheme.colorFijo,
                title: nombre,
                subtitle: p['descripcion']?.toString() ?? '',
                trailing: '\$${total.toStringAsFixed(2)}',
                trailingLabel: 'Costo total',
              ),
            );
          },
        ),
      ),
    );
  }

  /// Pestaña de ventas con barra de progreso de cobros.
  Widget _tabVentas() {
    // FIX: todos los estados tienen fondo explícito (AppTheme.background).
    // Sin esto, en release mode un error en el itemBuilder deja el tab gris
    // (Android background visible a través del ErrorWidget de tamaño cero).
    if (_loadVentas) return Container(
      color: AppTheme.background,
      child: const Center(child: CircularProgressIndicator()),
    );
    if (_ventas.isEmpty) return Container(
      color: AppTheme.background,
      child: _empty('Sin ventas registradas', 'Crea una venta para gestionar cobros', Icons.receipt_long_outlined),
    );
    return Container(
      color: AppTheme.background,
      child: RefreshIndicator(
        color: AppTheme.primary, backgroundColor: AppTheme.surface,
        onRefresh: _cargarVentas,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _ventas.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final v = _ventas[i] as Map<String, dynamic>? ?? {};

            // FIX: parsear todos los campos numéricos de forma robusta.
            // MySQL puede retornar DECIMAL como String y SUM como null en LEFT JOIN sin COALESCE.
            // Antes: `v['cobros_pendientes'] ?? 0` era dynamic y `pendientes > 0`
            //        lanzaba NoSuchMethodError en release si el valor era null o String.
            final cobrado    = double.tryParse(v['total_cobrado']?.toString()   ?? '0') ?? 0.0;
            final esperado   = double.tryParse(v['total_esperado']?.toString()  ?? '0') ?? 0.0;
            final pendientes = int.tryParse(v['cobros_pendientes']?.toString()  ?? '0') ?? 0;
            final nombre     = v['nombre']?.toString() ?? 'Venta sin nombre';
            final ventaId    = v['id'] is int ? v['id'] as int : int.tryParse(v['id']?.toString() ?? '') ?? 0;

            return GestureDetector(
              onTap: () async {
                if (ventaId == 0) return; // guardia por si id es inválido
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VentaDetalle(ventaId: ventaId, firebaseUid: widget.firebaseUid),
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
                    Expanded(child: Text(nombre,
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15))),
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
                  if (esperado > 0.0) ...[
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
