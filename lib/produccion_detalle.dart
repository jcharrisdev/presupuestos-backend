/// Pantalla de detalle de un presupuesto de producción.
///
/// Muestra la lista de ítems (insumos) con su costo individual y subtotal,
/// y el COSTO TOTAL de todos los ítems en el encabezado.
///
/// Funcionalidades:
///   - Agregar ítems: bottom sheet con nombre, cantidad y precio unitario.
///   - Eliminar ítems: swipe hacia la izquierda (Dismissible) + confirmación.
///   - Pull-to-refresh y botón de recarga en el AppBar.
///
/// El costo total se recalcula en el backend cada vez que se agregan
/// o eliminan ítems: `total = SUM(cantidad × precio_unitario)`.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'utils/money.dart';

/// Detalle de insumos de un presupuesto de producción.
class ProduccionDetalle extends StatefulWidget {
  final int presupuestoId;
  final String nombre;
  final String firebaseUid;
  const ProduccionDetalle({
    Key? key,
    required this.presupuestoId,
    required this.nombre,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _ProduccionDetalleState createState() => _ProduccionDetalleState();
}

class _ProduccionDetalleState extends State<ProduccionDetalle> {
  List<dynamic> _items = [];
  double _total = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  /// Carga los ítems del presupuesto de producción desde el backend.
  ///
  /// La respuesta incluye `items` (array) y `total_invertido` (suma calculada).
  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/produccion/${widget.presupuestoId}?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _items = data['items'] ?? [];
          _total = double.tryParse(data['total_invertido']?.toString() ?? '0') ?? 0;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      // FIX: catch silencioso ocultaba errores de red; ahora muestra SnackBar.
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar producción: $e')),
      );
    }
  }

  /// Abre el modal para agregar un nuevo ítem de insumo.
  ///
  /// Permite registrar el precio del paquete completo y cuántas unidades
  /// se usaron realmente en esta producción. El sistema calcula el costo
  /// asignado proporcional: precio_paquete × (usadas / total).
  void _modalAgregarItem() {
    final nombreCtrl   = TextEditingController();
    final cantidadCtrl = TextEditingController(text: '1');
    final precioCtrl   = TextEditingController();
    final usadasCtrl   = TextEditingController();
    bool soloUseParte  = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final cantidad     = double.tryParse(cantidadCtrl.text) ?? 0;
          final precioPaq    = double.tryParse(precioCtrl.text) ?? 0;
          final usadas       = soloUseParte ? (double.tryParse(usadasCtrl.text) ?? 0) : cantidad;
          final costoAsignado = (cantidad > 0 && precioPaq > 0)
              ? precioPaq * (usadas / cantidad)
              : 0.0;
          final sobrante = soloUseParte && cantidad > 0 ? cantidad - usadas : 0.0;

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Agregar insumo', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // Nombre
              TextField(
                controller: nombreCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Nombre del insumo (ej: Bolsitas, Harina)'),
              ),
              const SizedBox(height: 12),

              // Unidades en el paquete + precio del paquete
              Row(children: [
                Expanded(child: TextField(
                  controller: cantidadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Unidades compradas',
                    prefixIcon: Icon(Icons.numbers, size: 16, color: AppTheme.textSecondary),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: precioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Precio del paquete',
                    prefixText: 'B/. ',
                    prefixStyle: TextStyle(color: AppTheme.primary),
                  ),
                )),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Ingresa el precio total que pagaste por el paquete.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 14),

              // Toggle: ¿solo usé una parte?
              Row(children: [
                Switch(
                  value: soloUseParte,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setModalState(() { soloUseParte = v; if (!v) usadasCtrl.clear(); }),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text(
                  '¿Solo usé una parte del paquete?',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                )),
              ]),

              if (soloUseParte) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: usadasCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Unidades usadas en esta producción',
                    prefixIcon: Icon(Icons.cut_outlined, size: 16, color: AppTheme.textSecondary),
                  ),
                ),
              ],

              // Preview de costo asignado
              if (costoAsignado > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Costo asignado a esta producción:',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text('${Money.fmt(costoAsignado)}',
                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                    ]),
                    if (soloUseParte && sobrante > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sobrante: ${sobrante % 1 == 0 ? sobrante.toInt() : sobrante.toStringAsFixed(1)} unidades sin usar',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ]),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () async {
                  final nombre  = nombreCtrl.text.trim();
                  final cant    = double.tryParse(cantidadCtrl.text) ?? 0;
                  final precio  = double.tryParse(precioCtrl.text) ?? 0;
                  final usadasV = soloUseParte ? (double.tryParse(usadasCtrl.text) ?? 0) : 0;
                  if (nombre.isEmpty || cant <= 0 || precio <= 0) return;
                  if (soloUseParte && (usadasV <= 0 || usadasV > cant)) return;
                  Navigator.pop(ctx);
                  final body = {
                    'nombre': nombre,
                    'cantidad': cant,
                    'precio_total_paquete': precio,
                    'firebase_uid': widget.firebaseUid,
                    if (soloUseParte) 'cantidad_usada': usadasV,
                  };
                  final res = await ApiClient.post('/produccion/${widget.presupuestoId}/items', body);
                  if (res.statusCode == 201) _cargar();
                },
                child: const Text('Agregar insumo'),
              )),
            ]),
          );
        },
      ),
    );
  }

  /// Elimina un ítem tras confirmación del usuario.
  ///
  /// Se llama desde el `confirmDismiss` del [Dismissible] para que el
  /// swipe no elimine sin preguntar.
  Future<void> _eliminarItem(int itemId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar ítem', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Confirmas eliminar este ítem?', style: TextStyle(color: AppTheme.textSecondary)),
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
    await ApiClient.delete('/produccion/items/$itemId?firebase_uid=${widget.firebaseUid}');
    _cargar(); // recalcular total
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombre, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Presupuesto de producción',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Registra los insumos (materiales, ingredientes, etc.) '
                  'que necesitas para producir tu producto o servicio.\n\n'
                  '1. Toca "Ítem" para agregar un insumo.\n'
                  '2. Ingresa el precio del paquete completo y cuántas unidades compraste.\n'
                  '3. Si solo usaste una parte del paquete, activa el toggle para indicar '
                  'cuántas unidades usaste — el costo asignado se calcula proporcionalmente.\n'
                  '4. El COSTO TOTAL refleja solo lo invertido en esta producción.\n\n'
                  'Ejemplo: compraste 100 bolsitas a \$3.00 y usaste 32 → '
                  'costo asignado = \$0.96.\n\n'
                  'Para eliminar un ítem, desliza la tarjeta hacia la izquierda.',
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
        onPressed: _modalAgregarItem,
        icon: const Icon(Icons.add),
        label: const Text('Ítem'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // ── ENCABEZADO CON COSTO TOTAL ──────────────────────────────
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(children: [
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('COSTO TOTAL', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                    SizedBox(height: 4),
                  ]),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${Money.fmt(_total)}',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    Text('${_items.length} ítems', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                ]),
              ),

              // ── LISTA DE ÍTEMS ───────────────────────────────────────────
              Expanded(child: _items.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.inventory_2_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.35)),
                      const SizedBox(height: 16),
                      const Text('Sin ítems', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Toca "Ítem" para agregar insumos', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    ]))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item        = _items[i];
                        final cant        = double.tryParse(item['cantidad']?.toString() ?? '1') ?? 1;
                        final precio      = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
                        final precioPaq   = item['precio_total_paquete'] != null
                            ? double.tryParse(item['precio_total_paquete'].toString()) : null;
                        final cantUsada   = item['cantidad_usada'] != null
                            ? double.tryParse(item['cantidad_usada'].toString()) : null;
                        final tienePaquete = precioPaq != null && cantUsada != null;
                        final costoAsig   = tienePaquete
                            ? precioPaq! * (cantUsada! / cant)
                            : cant * precio;

                        return Dismissible(
                          key: Key('item_${item['id']}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.delete_outline, color: AppTheme.danger),
                          ),
                          confirmDismiss: (_) => _eliminarItem(item['id']).then((_) => false),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item['nombre'],
                                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 3),
                                if (tienePaquete)
                                  Text(
                                    '${_fmtNum(cantUsada!)} de ${_fmtNum(cant)} usadas · paquete ${Money.fmt(precioPaq!)}',
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  )
                                else
                                  Text('${_fmtNum(cant)} × \$${_fmtNum(precio)}',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${Money.fmt(costoAsig)}',
                                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                                Text(tienePaquete ? 'asignado' : 'subtotal',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
              ),
            ]),
    );
  }

  /// Formatea un número eliminando decimales innecesarios.
  /// Ej: 1.0 → "1", 0.5 → "0.50", 2.5 → "2.5".
  String _fmtNum(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
}
