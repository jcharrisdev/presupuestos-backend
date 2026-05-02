import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class ProduccionDetalle extends StatefulWidget {
  final int presupuestoId;
  final String nombre;
  final String firebaseUid;
  const ProduccionDetalle({Key? key, required this.presupuestoId, required this.nombre, required this.firebaseUid}) : super(key: key);

  @override
  _ProduccionDetalleState createState() => _ProduccionDetalleState();
}

class _ProduccionDetalleState extends State<ProduccionDetalle> {
  List<dynamic> _items = [];
  double _total = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/produccion/${widget.presupuestoId}?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _items = data['items'] ?? [];
          _total = double.tryParse(data['total_invertido']?.toString() ?? '0') ?? 0;
          _loading = false;
        });
      } else setState(() => _loading = false);
    } catch (_) { setState(() => _loading = false); }
  }

  void _modalAgregarItem() {
    final nombreCtrl    = TextEditingController();
    final cantidadCtrl  = TextEditingController(text: '1');
    final precioCtrl    = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Agregar ítem', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(controller: nombreCtrl, style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Nombre del insumo (ej: Harina)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: cantidadCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Cantidad', prefixIcon: Icon(Icons.numbers, size: 16, color: AppTheme.textSecondary)),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: precioCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Precio unitario', prefixText: '\$ ', prefixStyle: TextStyle(color: AppTheme.primary)),
            )),
          ]),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final nombre   = nombreCtrl.text.trim();
              final cantidad = double.tryParse(cantidadCtrl.text) ?? 0;
              final precio   = double.tryParse(precioCtrl.text) ?? 0;
              if (nombre.isEmpty || cantidad <= 0 || precio <= 0) return;
              Navigator.pop(context);
              final res = await ApiClient.post('/produccion/${widget.presupuestoId}/items', {
                'nombre': nombre, 'cantidad': cantidad, 'precio_unitario': precio,
                'firebase_uid': widget.firebaseUid,
              });
              if (res.statusCode == 201) _cargar();
            },
            child: const Text('Agregar ítem'),
          )),
        ]),
      ),
    );
  }

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
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombre, overflow: TextOverflow.ellipsis),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _modalAgregarItem,
        icon: const Icon(Icons.add),
        label: const Text('Ítem'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Header total
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: AppTheme.surface, border: Border(bottom: BorderSide(color: AppTheme.border))),
                child: Row(children: [
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('COSTO TOTAL', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                    SizedBox(height: 4),
                  ]),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('\$${_total.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    Text('${_items.length} ítems', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                ]),
              ),

              // Lista de ítems
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
                        final item   = _items[i];
                        final cant   = double.tryParse(item['cantidad']?.toString() ?? '1') ?? 1;
                        final precio = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
                        final sub    = cant * precio;

                        return Dismissible(
                          key: Key('item_${item['id']}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
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
                                Text(item['nombre'], style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 3),
                                Text('${_fmtNum(cant)} × \$${_fmtNum(precio)}',
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('\$${sub.toStringAsFixed(2)}',
                                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                                const Text('subtotal', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
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

  String _fmtNum(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
}
