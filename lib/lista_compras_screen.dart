/// Pantalla de lista de compras automática para una venta (Fase 5).
///
/// Calcula cuánto insumo comprar para cubrir todos los pedidos de la venta
/// usando las recetas de cada variante vendida.
///
/// Fórmula por insumo:
///   cantidad_necesaria = cantidad_base_receta × unidades_vendidas / rendimiento
///
/// Ejemplo: receta de "Cheesecake fresa regular" tiene rendimiento=12 y
/// necesita 500 g de queso crema por tanda. Si se vendieron 36 unidades:
///   500 g × 36 / 12 = 1,500 g de queso crema.
///
/// Secciones:
///   1. Insumos con receta agrupados y sumados.
///   2. Variantes vendidas sin receta (requieren definición manual).
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class ListaComprasScreen extends StatefulWidget {
  final int ventaId;
  final String ventaNombre;
  final String firebaseUid;

  const ListaComprasScreen({
    Key? key,
    required this.ventaId,
    required this.ventaNombre,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _ListaComprasScreenState createState() => _ListaComprasScreenState();
}

class _ListaComprasScreenState extends State<ListaComprasScreen> {
  List<dynamic> _insumos    = [];
  List<dynamic> _sinReceta  = [];
  Map<String, dynamic> _resumen = {};
  bool _loading = true;
  // Estado de items "ya comprado" (solo en memoria, no se persiste)
  final Set<int> _comprados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/ventas/${widget.ventaId}/lista-compras?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _insumos   = data['insumos']    ?? [];
          _sinReceta = data['sin_receta'] ?? [];
          _resumen   = data['resumen']    ?? {};
          _loading   = false;
        });
      } else {
        setState(() => _loading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ${res.statusCode}: ${res.body}')),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar lista de compras: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lista de compras', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Lista de compras',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                content: const Text(
                  'Calculada automáticamente desde las recetas de cada variante vendida.\n\n'
                  'Fórmula:\n'
                  '  insumo_necesario = cantidad_receta × unidades_vendidas ÷ rendimiento_tanda\n\n'
                  'Toca un insumo para marcarlo como comprado (solo visual, no se guarda).\n\n'
                  'Si una variante no aparece aquí, es porque no tiene receta definida. '
                  'Agrégala desde Cobros → Productos → Receta.',
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
      body: Container(
        color: AppTheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _insumos.isEmpty && _sinReceta.isEmpty
                ? _vistaVacia()
                : _vistaLista(),
      ),
    );
  }

  Widget _vistaVacia() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('Sin datos para calcular',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const Text(
          'Para generar la lista de compras necesitas:\n'
          '1. Clientes con pedidos usando el catálogo de productos.\n'
          '2. Recetas definidas para las variantes vendidas.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );

  Widget _vistaLista() {
    final totalInsumos = int.tryParse(_resumen['total_insumos']?.toString() ?? '0') ?? 0;
    final costoTotal   = _resumen['costo_estimado_total'];
    final pendientesCount = _insumos.length - _comprados.length;

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── RESUMEN ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary, size: 18),
                const SizedBox(width: 10),
                Text('${widget.ventaNombre}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _resumenStat('$totalInsumos', 'insumos\ntotales', AppTheme.primary),
                const SizedBox(width: 8),
                _resumenStat('$pendientesCount', 'por\ncomprar',
                    pendientesCount > 0 ? AppTheme.warning : AppTheme.success),
                const SizedBox(width: 8),
                if (costoTotal != null)
                  _resumenStat('\$${(double.tryParse(costoTotal.toString()) ?? 0).toStringAsFixed(2)}',
                      'costo\nestimado', AppTheme.colorFijo)
                else
                  _resumenStat('—', 'sin\nprecios', AppTheme.textMuted),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          // ── INSUMOS CON RECETA ─────────────────────────────────────────
          if (_insumos.isNotEmpty) ...[
            _labelDivider('INSUMOS A COMPRAR · $_totalInsumos'),
            ..._insumos.asMap().entries.map((entry) {
              final idx    = entry.key;
              final insumo = entry.value as Map<String, dynamic>;
              final comprado = _comprados.contains(idx);
              final cant     = double.tryParse(insumo['cantidad_total']?.toString() ?? '0') ?? 0;
              final cantStr  = cant % 1 == 0 ? cant.toInt().toString() : cant.toStringAsFixed(3);
              final precio   = insumo['precio_unitario'] != null
                  ? double.tryParse(insumo['precio_unitario'].toString()) : null;
              final costoEst = insumo['costo_estimado'] != null
                  ? double.tryParse(insumo['costo_estimado'].toString()) : null;

              return GestureDetector(
                onTap: () => setState(() {
                  if (comprado) _comprados.remove(idx); else _comprados.add(idx);
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: comprado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: comprado ? AppTheme.success.withOpacity(0.3) : AppTheme.border,
                    ),
                  ),
                  child: Row(children: [
                    // Checkbox visual
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: comprado ? AppTheme.success : Colors.transparent,
                        border: Border.all(
                          color: comprado ? AppTheme.success : AppTheme.textMuted,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: comprado
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(insumo['nombre']?.toString() ?? '',
                          style: TextStyle(
                            color: comprado ? AppTheme.textMuted : AppTheme.textPrimary,
                            fontWeight: FontWeight.w700, fontSize: 14,
                            decoration: comprado ? TextDecoration.lineThrough : null,
                          )),
                      if ((insumo['fuentes']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(insumo['fuentes'].toString(),
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      if (precio != null) ...[
                        const SizedBox(height: 3),
                        Text('\$${precio.toStringAsFixed(2)} / ${insumo['unidad'] ?? ''}',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      ],
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$cantStr ${insumo['unidad'] ?? ''}',
                          style: TextStyle(
                            color: comprado ? AppTheme.textMuted : AppTheme.primary,
                            fontWeight: FontWeight.w800, fontSize: 15,
                          )),
                      if (costoEst != null)
                        Text('\$${costoEst.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: comprado ? AppTheme.textMuted : AppTheme.colorFijo,
                              fontSize: 11, fontWeight: FontWeight.w600,
                            )),
                    ]),
                  ]),
                ),
              );
            }),
          ],

          // ── VARIANTES SIN RECETA ───────────────────────────────────────
          if (_sinReceta.isNotEmpty) ...[
            const SizedBox(height: 16),
            _labelDivider('SIN RECETA DEFINIDA · ${_sinReceta.length}'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 16),
                  const SizedBox(width: 8),
                  const Text('Estas variantes no tienen receta',
                      style: TextStyle(color: AppTheme.warning, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                ..._sinReceta.map((sr) {
                  final cant = double.tryParse(sr['cantidad_total']?.toString() ?? '0') ?? 0;
                  final cantStr = cant % 1 == 0 ? cant.toInt().toString() : cant.toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 5, color: AppTheme.warning),
                      const SizedBox(width: 10),
                      Expanded(child: Text(sr['descripcion']?.toString() ?? '',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                      Text('$cantStr uds',
                          style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ]),
                  );
                }),
                const SizedBox(height: 10),
                const Text('Ve a Cobros → Productos → Receta para definirlas.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ),
          ],

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Cuenta los insumos con formato "N insumo(s)"
  String get _totalInsumos {
    final n = _insumos.length;
    return '$n insumo${n != 1 ? 's' : ''}';
  }

  Widget _resumenStat(String value, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
            textAlign: TextAlign.center),
      ]),
    ),
  );

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
}
