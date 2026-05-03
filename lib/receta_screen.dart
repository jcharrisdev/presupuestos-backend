/// Pantalla de gestión de receta de una variante de producto.
///
/// Una RECETA define qué insumos (ingredientes / materiales) se necesitan para
/// producir una tanda de la variante.
///
/// Conceptos clave:
///   - **Rendimiento**: cuántas unidades de la variante produce una tanda.
///     Ej: una tanda produce 12 cheesecakes.
///   - **Insumo**: ingrediente con cantidad por tanda y unidad.
///     Ej: 500 g de queso crema por tanda de 12 cheesecakes.
///   - **Fórmula**: para producir N unidades de la variante →
///     cantidad_insumo = cantidad_base × N / rendimiento
///
/// La receta se usa en Fase 5 (lista de compras automática) para calcular
/// cuánto comprar dado el volumen de ventas de una venta.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class RecetaScreen extends StatefulWidget {
  final int varianteId;
  final String varianteNombre;
  final String firebaseUid;

  const RecetaScreen({
    Key? key,
    required this.varianteId,
    required this.varianteNombre,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _RecetaScreenState createState() => _RecetaScreenState();
}

class _RecetaScreenState extends State<RecetaScreen> {
  Map<String, dynamic>? _receta;
  List<dynamic> _insumos = [];
  bool _loading = true;
  bool _sinReceta = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/variantes/${widget.varianteId}/receta?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _receta  = data;
          _insumos = data['insumos'] ?? [];
          _sinReceta = false;
          _loading = false;
        });
      } else if (res.statusCode == 404) {
        setState(() { _sinReceta = true; _loading = false; });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar receta: $e')),
      );
    }
  }

  /// Abre el bottom sheet para crear o editar la configuración de la receta
  /// (rendimiento, unidad, notas). Si no existe receta, la crea.
  void _modalEditarReceta() {
    final rendCtrl = TextEditingController(
      text: _receta != null
          ? (double.tryParse(_receta!['rendimiento']?.toString() ?? '1') ?? 1).toString()
          : '1',
    );
    final unidadCtrl = TextEditingController(
      text: _receta?['unidad']?.toString() ?? 'tanda',
    );
    final notasCtrl = TextEditingController(
      text: _receta?['notas']?.toString() ?? '',
    );

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          Text(_receta != null ? 'Editar receta' : 'Crear receta',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Para: ${widget.varianteNombre}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: TextField(
              controller: rendCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Rendimiento',
                helperText: 'Unidades por tanda',
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: unidadCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Unidad de tanda',
                helperText: 'Ej: tanda, horneada',
              ),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: notasCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              helperText: 'Ej: Temp. horno 180°C, 45 min',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final rend = double.tryParse(rendCtrl.text);
              if (rend == null || rend <= 0) return;
              Navigator.pop(context);
              final res = await ApiClient.post(
                '/variantes/${widget.varianteId}/receta',
                {
                  'rendimiento': rend,
                  'unidad': unidadCtrl.text.trim().isEmpty ? 'tanda' : unidadCtrl.text.trim(),
                  'notas': notasCtrl.text.trim().isEmpty ? null : notasCtrl.text.trim(),
                  'firebase_uid': widget.firebaseUid,
                },
              );
              if (res.statusCode == 201) _cargar();
              else if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error al guardar la receta')),
              );
            },
            child: Text(_receta != null ? 'Guardar cambios' : 'Crear receta'),
          )),
        ]),
      ),
    );
  }

  /// Abre el bottom sheet para agregar un nuevo insumo a la receta.
  /// precio_unitario es opcional (Fase 6: permite calcular costo estimado).
  void _modalAgregarInsumo() {
    if (_receta == null) return;
    final nombreCtrl   = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final unidadCtrl   = TextEditingController(text: 'g');
    final precioCtrl   = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Nuevo insumo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Cantidad por tanda completa',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 20),
          TextField(
            controller: nombreCtrl, autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Nombre del insumo',
                hintText: 'Ej: Queso crema, Harina'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: cantidadCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Cantidad'),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: unidadCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Unidad',
                hintText: 'g, kg, ml, unidad',
              ),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: precioCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Precio por unidad (opcional)',
              prefixText: '\$ ',
              helperText: 'Permite calcular el costo estimado de producción',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final nombre   = nombreCtrl.text.trim();
              final cantidad = double.tryParse(cantidadCtrl.text);
              if (nombre.isEmpty || cantidad == null || cantidad <= 0) return;
              Navigator.pop(context);
              final recetaId = _receta!['id'] is int
                  ? _receta!['id'] as int
                  : int.tryParse(_receta!['id'].toString()) ?? 0;
              final precio = double.tryParse(precioCtrl.text);
              final body = <String, dynamic>{
                'nombre': nombre,
                'cantidad': cantidad,
                'unidad': unidadCtrl.text.trim().isEmpty ? 'g' : unidadCtrl.text.trim(),
                'firebase_uid': widget.firebaseUid,
              };
              if (precio != null && precio > 0) body['precio_unitario'] = precio;
              final res = await ApiClient.post('/recetas/$recetaId/insumos', body);
              if (res.statusCode == 201) _cargar();
              else if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error al agregar insumo')),
              );
            },
            child: const Text('Agregar insumo'),
          )),
        ]),
      ),
    );
  }

  /// Abre el bottom sheet para editar un insumo existente.
  /// precio_unitario es opcional (Fase 6).
  void _modalEditarInsumo(Map<String, dynamic> insumo) {
    final nombreCtrl   = TextEditingController(text: insumo['nombre']?.toString() ?? '');
    final cantidadCtrl = TextEditingController(
      text: (double.tryParse(insumo['cantidad']?.toString() ?? '0') ?? 0).toString(),
    );
    final unidadCtrl  = TextEditingController(text: insumo['unidad']?.toString() ?? 'g');
    final precioExist = insumo['precio_unitario'] != null
        ? double.tryParse(insumo['precio_unitario'].toString()) : null;
    final precioCtrl  = TextEditingController(
      text: precioExist != null ? precioExist.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const Text('Editar insumo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(
            controller: nombreCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Nombre del insumo'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: cantidadCtrl, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Cantidad'),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: unidadCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Unidad'),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: precioCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Precio por unidad (opcional)',
              prefixText: '\$ ',
              helperText: 'Dejar vacío para quitar el precio',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final nombre   = nombreCtrl.text.trim();
              final cantidad = double.tryParse(cantidadCtrl.text);
              if (nombre.isEmpty || cantidad == null || cantidad <= 0) return;
              Navigator.pop(context);
              final insumoId = insumo['id'] is int
                  ? insumo['id'] as int
                  : int.tryParse(insumo['id'].toString()) ?? 0;
              final precio = double.tryParse(precioCtrl.text);
              await ApiClient.put('/receta-insumos/$insumoId', {
                'nombre': nombre,
                'cantidad': cantidad,
                'unidad': unidadCtrl.text.trim().isEmpty ? 'g' : unidadCtrl.text.trim(),
                // null explícito borra el precio; si viene número > 0 lo actualiza
                'precio_unitario': (precio != null && precio > 0) ? precio : null,
                'firebase_uid': widget.firebaseUid,
              });
              _cargar();
            },
            child: const Text('Guardar cambios'),
          )),
        ]),
      ),
    );
  }

  Future<void> _eliminarInsumo(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar insumo', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar este insumo de la receta?',
            style: TextStyle(color: AppTheme.textSecondary)),
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
    await ApiClient.delete('/receta-insumos/$id?firebase_uid=${widget.firebaseUid}');
    _cargar();
  }

  Future<void> _eliminarReceta() async {
    if (_receta == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar receta', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar la receta completa y todos sus insumos?',
            style: TextStyle(color: AppTheme.textSecondary)),
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
    final recetaId = _receta!['id'] is int
        ? _receta!['id'] as int
        : int.tryParse(_receta!['id'].toString()) ?? 0;
    await ApiClient.delete('/recetas/$recetaId?firebase_uid=${widget.firebaseUid}');
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Receta · ${widget.varianteNombre}',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Receta de producción',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Una receta define cuánto necesitas de cada insumo para producir una tanda.\n\n'
                  '• Rendimiento: cuántas unidades produce una tanda.\n'
                  '  Ej: una tanda produce 12 cheesecakes.\n\n'
                  '• Insumos: ingredientes o materiales por tanda.\n'
                  '  Ej: 500 g de queso crema por tanda.\n\n'
                  '• Fórmula de cálculo:\n'
                  '  Para N unidades vendidas →\n'
                  '  cantidad_insumo = base × N ÷ rendimiento\n\n'
                  'Esto se usa para calcular automáticamente la lista de compras en una venta.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          if (_receta != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
              tooltip: 'Eliminar receta',
              onPressed: _eliminarReceta,
            ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
      ),
      floatingActionButton: _receta != null
          ? FloatingActionButton.extended(
              onPressed: _modalAgregarInsumo,
              icon: const Icon(Icons.add),
              label: const Text('Insumo'),
            )
          : null,
      body: Container(
        color: AppTheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sinReceta
                ? _vistaCrearReceta()
                : _vistaReceta(),
      ),
    );
  }

  /// Vista inicial cuando la variante no tiene receta aún.
  Widget _vistaCrearReceta() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.menu_book_outlined, color: AppTheme.primary, size: 40),
        ),
        const SizedBox(height: 24),
        Text('Sin receta para\n${widget.varianteNombre}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text(
          'Crea una receta para definir cuántos insumos necesitas por tanda y '
          'calcular automáticamente la lista de compras.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _modalEditarReceta,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Crear receta'),
        ),
      ]),
    ),
  );

  /// Vista principal con la receta y sus insumos.
  Widget _vistaReceta() {
    final rendimiento = double.tryParse(_receta!['rendimiento']?.toString() ?? '1') ?? 1;
    final unidad      = _receta!['unidad']?.toString() ?? 'tanda';
    final notas       = _receta!['notas']?.toString() ?? '';

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── HEADER DE RECETA ─────────────────────────────────────────────
          GestureDetector(
            onTap: _modalEditarReceta,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_outlined, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('CONFIGURACIÓN DE TANDA',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 1.1,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${rendimiento % 1 == 0 ? rendimiento.toInt() : rendimiento} '
                        '${widget.varianteNombre} por $unidad',
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ])),
                  const Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 16),
                ]),
                if (notas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.border, height: 1),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.sticky_note_2_outlined, color: AppTheme.textMuted, size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(notas,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
                  ]),
                ],
              ]),
            ),
          ),

          const SizedBox(height: 20),
          _labelDivider('INSUMOS POR TANDA · ${_insumos.length} insumo${_insumos.length != 1 ? 's' : ''}'),

          // ── LISTA DE INSUMOS ─────────────────────────────────────────────
          if (_insumos.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(children: [
                Icon(Icons.science_outlined, size: 40, color: AppTheme.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('Sin insumos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('Toca "Insumo" para agregar el primer ingrediente.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
              ]),
            )
          else
            ...(_insumos.map((ins) {
              final insumoId = ins['id'] is int ? ins['id'] as int : int.tryParse(ins['id'].toString()) ?? 0;
              final cant   = double.tryParse(ins['cantidad']?.toString() ?? '0') ?? 0;
              final cantStr = cant % 1 == 0 ? cant.toInt().toString() : cant.toString();
              final precio = ins['precio_unitario'] != null
                  ? double.tryParse(ins['precio_unitario'].toString()) : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: InkWell(
                  onTap: () => _modalEditarInsumo(ins),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.colorAhorro, shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ins['nombre']?.toString() ?? '',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (precio != null)
                          Text('\$${precio.toStringAsFixed(2)} / ${ins['unidad'] ?? ''}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      ])),
                      Text('$cantStr ${ins['unidad'] ?? ''}',
                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _eliminarInsumo(insumoId),
                        child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                      ),
                    ]),
                  ),
                ),
              );
            })),

          // ── CALCULADORA RÁPIDA ───────────────────────────────────────────
          if (_insumos.isNotEmpty) ...[
            const SizedBox(height: 20),
            _labelDivider('CALCULADORA RÁPIDA'),
            _CalculadoraInsumos(
              insumos: _insumos,
              rendimiento: rendimiento,
              varianteNombre: widget.varianteNombre,
            ),
          ],

          const SizedBox(height: 80), // espacio para FAB
        ],
      ),
    );
  }

  Widget _labelDivider(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      const Expanded(child: Divider(color: AppTheme.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
      ),
      const Expanded(child: Divider(color: AppTheme.border)),
    ]),
  );

  Widget _handle() => Center(child: Container(
    width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
  ));
}

/// Widget de calculadora: dado un número de unidades a producir,
/// muestra cuánto se necesita de cada insumo.
///
/// Fórmula: cantidad_necesaria = cantidad_base × unidades / rendimiento
class _CalculadoraInsumos extends StatefulWidget {
  final List<dynamic> insumos;
  final double rendimiento;
  final String varianteNombre;

  const _CalculadoraInsumos({
    required this.insumos,
    required this.rendimiento,
    required this.varianteNombre,
  });

  @override
  __CalculadoraInsumosState createState() => __CalculadoraInsumosState();
}

class __CalculadoraInsumosState extends State<_CalculadoraInsumos> {
  double _unidades = 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Selector de unidades
        Row(children: [
          const Icon(Icons.calculate_outlined, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text('¿Cuántas ${widget.varianteNombre} quieres producir?',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
          Text('${_unidades.toInt()}',
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        Slider(
          value: _unidades,
          min: 1,
          max: widget.rendimiento * 10,
          divisions: (widget.rendimiento * 10 - 1).toInt().clamp(1, 999),
          onChanged: (v) => setState(() => _unidades = v.roundToDouble()),
          activeColor: AppTheme.primary,
          inactiveColor: AppTheme.surfaceAlt,
        ),

        const SizedBox(height: 4),
        const Divider(color: AppTheme.border, height: 1),
        const SizedBox(height: 14),

        // Tabla de resultados
        ...widget.insumos.map((ins) {
          final base   = double.tryParse(ins['cantidad']?.toString() ?? '0') ?? 0;
          final needed = base * _unidades / widget.rendimiento;
          final neededStr = needed % 1 == 0 ? needed.toInt().toString()
              : needed.toStringAsFixed(2);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.arrow_right, color: AppTheme.textMuted, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(ins['nombre']?.toString() ?? '',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
              Text('$neededStr ${ins['unidad'] ?? ''}',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          );
        }),

        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppTheme.primary, size: 13),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Tandas necesarias: ${(_unidades / widget.rendimiento).toStringAsFixed(2)} '
              '(rend. ${widget.rendimiento % 1 == 0 ? widget.rendimiento.toInt() : widget.rendimiento} '
              'u/tanda)',
              style: const TextStyle(color: AppTheme.primary, fontSize: 11),
            )),
          ]),
        ),
      ]),
    );
  }
}
