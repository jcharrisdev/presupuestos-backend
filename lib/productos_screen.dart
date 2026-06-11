/// Pantalla de gestión del catálogo de productos y sus variantes.
///
/// Un PRODUCTO es lo que se vende (Cheesecake, Tornillo, Camisa, Servicio).
/// Una VARIANTE es una versión vendible con precio propio:
///   - Cheesecake fresa regular → $3.75
///   - Cheesecake fresa grande  → $5.50
///
/// El catálogo es reutilizable entre ventas. Al crear un pedido de cliente
/// dentro de una venta, el usuario elige variantes de aquí en lugar de
/// escribir el total manualmente.
///
/// Estructura de la pantalla:
///   - Lista de productos con ExpansionTile
///   - Al expandir: muestra variantes del producto con precio y unidad
///   - FAB: crear nuevo producto
///   - Botón "+" dentro del tile expandido: agregar variante
///   - Swipe / botón eliminar para producto y variante
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'receta_screen.dart';
import 'widgets/widgets.dart';
import 'utils/money.dart';

class ProductosScreen extends StatefulWidget {
  final String firebaseUid;
  const ProductosScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _ProductosScreenState createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  List<Map<String, dynamic>> _productos = [];
  // Variantes cargadas por producto (key = producto_id)
  final Map<int, List<Map<String, dynamic>>> _variantes = {};
  // Qué productos tienen el tile expandido
  final Set<int> _expandidos = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga la lista de productos del usuario.
  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/productos?firebase_uid=${widget.firebaseUid}');
      setState(() {
        _productos = res.statusCode == 200
            ? List<Map<String, dynamic>>.from(json.decode(res.body))
            : [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar productos: $e')),
      );
    }
  }

  /// Carga las variantes de un producto específico (lazy: solo cuando expande).
  Future<void> _cargarVariantes(int productoId) async {
    try {
      final res = await ApiClient.get(
        '/productos/$productoId/variantes?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        setState(() {
          _variantes[productoId] = List<Map<String, dynamic>>.from(json.decode(res.body));
        });
      }
    } catch (_) {}
  }

  // ─── CRUD PRODUCTOS ─────────────────────────────────────────────────────────

  /// Modal para crear un nuevo producto.
  void _modalCrearProducto() {
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
          const Text('Nuevo producto', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(
            controller: nombreCtrl, autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Nombre del producto (ej: Cheesecake)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Descripción (opcional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(context);
              final res = await ApiClient.post('/productos', {
                'nombre': nombre,
                'descripcion': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              });
              if (res.statusCode == 201) _cargar();
            },
            child: const Text('Crear producto'),
          )),
        ]),
      ),
    );
  }

  Future<void> _eliminarProducto(int id, String nombre) async {
    final ok = await showConfirmDialog(context, title: 'Eliminar producto', content: '¿Eliminar "$nombre" y todas sus variantes?');
    if (!ok) return;
    await ApiClient.delete('/productos/$id?firebase_uid=${widget.firebaseUid}');
    setState(() { _variantes.remove(id); _expandidos.remove(id); });
    _cargar();
  }

  // ─── CRUD VARIANTES ──────────────────────────────────────────────────────────

  /// Modal para crear una variante de un producto.
  void _modalCrearVariante(int productoId) {
    final nombreCtrl = TextEditingController();
    final tamanoCtrl = TextEditingController();
    final precioCtrl = TextEditingController();
    final unidadCtrl = TextEditingController(text: 'unidad');
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Nueva variante', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Ej: sabor "Fresa", tamaño "Pequeño"',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(
              controller: nombreCtrl, autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre / Sabor'),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: tamanoCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Tamaño (opcional)',
                hintText: 'Pequeño, Grande…',
              ),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: precioCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Precio de venta',
                prefixText: 'B/. ',
                prefixStyle: TextStyle(color: AppTheme.primary),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: unidadCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Unidad'),
            )),
          ]),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final precio = double.tryParse(precioCtrl.text);
              if (nombre.isEmpty || precio == null || precio <= 0) return;
              Navigator.pop(context);
              final body = <String, dynamic>{
                'nombre': nombre,
                'precio': precio,
                'unidad': unidadCtrl.text.trim().isEmpty ? 'unidad' : unidadCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              };
              if (tamanoCtrl.text.trim().isNotEmpty) body['tamano'] = tamanoCtrl.text.trim();
              final res = await ApiClient.post('/productos/$productoId/variantes', body);
              if (res.statusCode == 201) _cargarVariantes(productoId);
            },
            child: const Text('Agregar variante'),
          )),
        ]),
      ),
    );
  }

  /// Modal para editar el precio de una variante.
  void _modalEditarVariante(int productoId, Map<String, dynamic> variante) {
    final nombreCtrl = TextEditingController(text: variante['nombre']?.toString() ?? '');
    final tamanoCtrl = TextEditingController(text: variante['tamano']?.toString() ?? '');
    final precioCtrl = TextEditingController(
      text: (double.tryParse(variante['precio']?.toString() ?? '0') ?? 0).toStringAsFixed(2),
    );
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Editar variante', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre / Sabor'),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: tamanoCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Tamaño (opcional)',
                hintText: 'Pequeño, Grande…',
              ),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: precioCtrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Precio de venta',
              prefixText: 'B/. ',
              prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final precio = double.tryParse(precioCtrl.text);
              if (precio == null || precio <= 0) return;
              Navigator.pop(context);
              await ApiClient.put('/variantes/${variante['id']}', {
                'nombre': nombreCtrl.text.trim(),
                'tamano': tamanoCtrl.text.trim().isEmpty ? null : tamanoCtrl.text.trim(),
                'precio': precio,
                'firebase_uid': widget.firebaseUid,
              });
              _cargarVariantes(productoId);
            },
            child: const Text('Guardar cambios'),
          )),
        ]),
      ),
    );
  }

  Future<void> _eliminarVariante(int productoId, int varianteId, String nombre) async {
    final ok = await showConfirmDialog(context, title: 'Eliminar variante', content: '¿Eliminar "$nombre"?');
    if (!ok) return;
    await ApiClient.delete('/variantes/$varianteId?firebase_uid=${widget.firebaseUid}');
    _cargarVariantes(productoId);
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de Productos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Catálogo de productos',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Define aquí lo que vendes.\n\n'
                  '• Producto → lo que vendes (ej: Cheesecake).\n'
                  '• Variante → versión con precio propio (ej: Fresa regular \$3.75).\n'
                  '• Receta → insumos necesarios para producir una tanda de la variante.\n\n'
                  '1. Toca "Producto" para crear uno nuevo.\n'
                  '2. Toca el producto para ver sus variantes.\n'
                  '3. Toca "+" para agregar variantes.\n'
                  '4. Toca una variante para editar su precio.\n'
                  '5. Toca "Receta" junto a la variante para definir sus insumos.\n\n'
                  'Al crear el pedido de un cliente dentro de una venta, '
                  'podrás seleccionar variantes del catálogo y el total '
                  'se calculará automáticamente.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _modalCrearProducto,
        icon: const Icon(Icons.add),
        label: const Text('Producto'),
      ),
      body: Container(
        color: AppTheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _productos.isEmpty
                ? _empty()
                : RefreshIndicator(
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surface,
                    onRefresh: _cargar,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _productos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = _productos[i];
                        final id = p['id'] is int ? p['id'] as int : int.tryParse(p['id'].toString()) ?? 0;
                        final variantesActivas = int.tryParse(p['variantes_activas']?.toString() ?? '0') ?? 0;
                        final expandido = _expandidos.contains(id);
                        return _ProductoCard(
                          producto: p,
                          variantes: _variantes[id] ?? [],
                          expandido: expandido,
                          onExpand: () {
                            setState(() {
                              if (expandido) {
                                _expandidos.remove(id);
                              } else {
                                _expandidos.add(id);
                                if (!_variantes.containsKey(id)) _cargarVariantes(id);
                              }
                            });
                          },
                          onEliminarProducto: () => _eliminarProducto(id, p['nombre']?.toString() ?? ''),
                          onAgregarVariante: () => _modalCrearVariante(id),
                          onEditarVariante: (v) => _modalEditarVariante(id, v),
                          onEliminarVariante: (v) => _eliminarVariante(
                            id,
                            v['id'] is int ? v['id'] as int : int.tryParse(v['id'].toString()) ?? 0,
                            v['nombre']?.toString() ?? '',
                          ),
                          onVerReceta: (v) {
                            final varId = v['id'] is int ? v['id'] as int : int.tryParse(v['id'].toString()) ?? 0;
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => RecetaScreen(
                                varianteId: varId,
                                varianteNombre: v['nombre']?.toString() ?? '',
                                firebaseUid: widget.firebaseUid,
                              ),
                            ));
                          },
                          onVerHistorialPrecios: (v) => _mostrarHistorialPrecios(v),
                          variantesActivas: variantesActivas,
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  void _mostrarHistorialPrecios(Map<String, dynamic> variante) {
    final varId = variante['id'] is int ? variante['id'] as int : int.tryParse(variante['id'].toString()) ?? 0;
    final nombre = variante['nombre']?.toString() ?? 'Variante';
    final precioActual = double.tryParse(variante['precio']?.toString() ?? '0') ?? 0;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          Text('Historial de precios — $nombre',
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Precio actual: ${Money.fmt(precioActual)}',
            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          FutureBuilder(
            future: ApiClient.get('/variantes/$varId/historial-precios?firebase_uid=${widget.firebaseUid}'),
            builder: (ctx, snap) {
              if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
              final body = json.decode(snap.data!.body) as Map<String, dynamic>;
              final historial = (body['historial'] as List? ?? []).cast<Map<String, dynamic>>();
              if (historial.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Sin cambios de precio registrados', style: TextStyle(color: AppTheme.textSecondary))),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: historial.length,
                  separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                  itemBuilder: (_, i) {
                    final h = historial[i];
                    final antes = double.tryParse(h['precio_anterior'].toString()) ?? 0;
                    final nuevo = double.tryParse(h['precio_nuevo'].toString()) ?? 0;
                    final variacion = antes > 0 ? ((nuevo - antes) / antes * 100) : 0.0;
                    final subio = nuevo >= antes;
                    final fecha = h['changed_at']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(fecha.length >= 16 ? fecha.substring(0, 16) : fecha,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          const SizedBox(height: 3),
                          Text('${Money.fmt(antes)} → ${Money.fmt(nuevo)}',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: (subio ? AppTheme.success : AppTheme.danger).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${subio ? '+' : ''}${variacion.toStringAsFixed(1)}%',
                            style: TextStyle(color: subio ? AppTheme.success : AppTheme.danger, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _empty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.storefront_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.4)),
    const SizedBox(height: 16),
    const Text('Sin productos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    const Text('Toca "Producto" para agregar uno al catálogo', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
  ]));

  Widget _handle() => Center(child: Container(
    width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
  ));
}

/// Tarjeta expandible de producto con lista de variantes.
class _ProductoCard extends StatelessWidget {
  final Map<String, dynamic> producto;
  final List<Map<String, dynamic>> variantes;
  final bool expandido;
  final int variantesActivas;
  final VoidCallback onExpand, onEliminarProducto, onAgregarVariante;
  final void Function(Map<String, dynamic>) onEditarVariante, onEliminarVariante, onVerReceta, onVerHistorialPrecios;

  const _ProductoCard({
    required this.producto, required this.variantes, required this.expandido,
    required this.variantesActivas, required this.onExpand,
    required this.onEliminarProducto, required this.onAgregarVariante,
    required this.onEditarVariante, required this.onEliminarVariante,
    required this.onVerReceta, required this.onVerHistorialPrecios,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── HEADER PRODUCTO ──────────────────────────────────────────────────
        InkWell(
          onTap: onExpand,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(producto['nombre']?.toString() ?? '', style: const TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                if ((producto['descripcion']?.toString() ?? '').isNotEmpty)
                  Text(producto['descripcion'].toString(), style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              // Badge de variantes activas
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.colorAhorro.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$variantesActivas variantes',
                    style: const TextStyle(color: AppTheme.colorAhorro, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                onPressed: onEliminarProducto,
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Icon(expandido ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.textMuted, size: 20),
            ]),
          ),
        ),

        // ── VARIANTES (expandido) ─────────────────────────────────────────────
        if (expandido) ...[
          const Divider(color: AppTheme.border, height: 1),
          if (variantes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppTheme.textMuted, size: 14),
                const SizedBox(width: 8),
                const Text('Sin variantes. Agrega la primera.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAgregarVariante,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Agregar', style: TextStyle(fontSize: 12)),
                ),
              ]),
            )
          else ...[
            ...variantes.map((v) {
              final precio = double.tryParse(v['precio']?.toString() ?? '0') ?? 0;
              final activo = v['activo'] == 1 || v['activo'] == true;
              return InkWell(
                onTap: () => onEditarVariante(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const SizedBox(width: 8),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: activo ? AppTheme.success : AppTheme.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v['nombre']?.toString() ?? '', style: TextStyle(
                        color: activo ? AppTheme.textPrimary : AppTheme.textMuted,
                        fontSize: 14, fontWeight: FontWeight.w600,
                      )),
                      Text(
                        [
                          if ((v['tamano']?.toString() ?? '').isNotEmpty) v['tamano'].toString(),
                          v['unidad']?.toString() ?? 'unidad',
                        ].join(' · '),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ])),
                    Text('${Money.fmt(precio)}', style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(width: 10),
                    // Botón Receta: navega a RecetaScreen para esta variante
                    GestureDetector(
                      onTap: () => onVerReceta(v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.colorAhorro.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppTheme.colorAhorro.withOpacity(0.3)),
                        ),
                        child: const Text('Receta',
                            style: TextStyle(color: AppTheme.colorAhorro, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onVerHistorialPrecios(v),
                      child: const Icon(Icons.history, color: AppTheme.textMuted, size: 16),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => onEliminarVariante(v),
                      child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 16),
                    ),
                  ]),
                ),
              );
            }),
            // Botón agregar variante dentro del tile expandido
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextButton.icon(
                onPressed: onAgregarVariante,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Agregar variante', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ]),
    );
  }
}
