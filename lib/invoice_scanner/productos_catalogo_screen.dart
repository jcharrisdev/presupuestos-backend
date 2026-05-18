import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/productos_catalogo_service.dart';

class ProductosCatalogoScreen extends StatefulWidget {
  final String firebaseUid;
  const ProductosCatalogoScreen({super.key, required this.firebaseUid});

  @override
  State<ProductosCatalogoScreen> createState() => _ProductosCatalogoScreenState();
}

class _ProductosCatalogoScreenState extends State<ProductosCatalogoScreen> {
  List<dynamic> _productos = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({String? q}) async {
    setState(() => _loading = true);
    final data = await ProductosCatalogoService.getAll(widget.firebaseUid, q: q);
    if (mounted) setState(() { _productos = data; _loading = false; });
  }

  double _d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Mis Productos', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 18),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                        onPressed: () { _searchCtrl.clear(); _cargar(); },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                if (v.length >= 2 || v.isEmpty) _cargar(q: v.isEmpty ? null : v);
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _productos.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _productos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _productoCard(_productos[i]),
                  ),
                ),
    );
  }

  Widget _productoCard(dynamic p) {
    final tendencia = p['tendencia'] as String? ?? 'igual';
    final pctCambio = p['pct_cambio'];
    final ultimoPrecio = _d(p['ultimo_precio']);
    final veces = (p['veces_comprado'] as int?) ?? 1;
    final merchant = p['merchant_name_habitual'] as String? ?? '';
    final ultimaCompra = p['ultima_compra'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductoHistorialScreen(
          productoId: p['id'] as int,
          nombre: p['nombre'] as String,
          firebaseUid: widget.firebaseUid,
        ),
      )).then((_) => _cargar(q: _searchCtrl.text.isEmpty ? null : _searchCtrl.text)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['nombre'] as String, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Row(children: [
              if (merchant.isNotEmpty) ...[
                const Icon(Icons.store_outlined, size: 11, color: AppTheme.textMuted),
                const SizedBox(width: 3),
                Text(merchant, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.shopping_bag_outlined, size: 11, color: AppTheme.textMuted),
              const SizedBox(width: 3),
              Text('$veces vez${veces > 1 ? "es" : ""}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              if (ultimaCompra.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(ultimaCompra.length >= 10 ? ultimaCompra.substring(0, 10) : ultimaCompra,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ]),
            if (p['categoria'] != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.info.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(p['categoria'] as String, style: const TextStyle(color: AppTheme.info, fontSize: 10)),
              ),
            ],
          ])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${_fmt.format(ultimoPrecio)}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            _tendenciaChip(tendencia, pctCambio),
          ]),
        ]),
      ),
    );
  }

  Widget _tendenciaChip(String tendencia, dynamic pct) {
    if (tendencia == 'igual' || pct == null) {
      return const Text('Sin cambio', style: TextStyle(color: AppTheme.textMuted, fontSize: 11));
    }
    final sube = tendencia == 'sube';
    final color = sube ? AppTheme.danger : AppTheme.success;
    final icon = sube ? '↑' : '↓';
    final pctVal = (pct as num).abs();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(width: 2),
      Text('${pctVal.toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.inventory_2_outlined, color: AppTheme.textSecondary, size: 56),
      const SizedBox(height: 12),
      const Text('Sin productos aún', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Escanea una factura QR para\nconstruir tu catálogo automáticamente',
          textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ]),
  );
}

// ── Pantalla de historial de precios de un producto ──────────────────────────

class ProductoHistorialScreen extends StatefulWidget {
  final int productoId;
  final String nombre;
  final String firebaseUid;
  const ProductoHistorialScreen({super.key, required this.productoId, required this.nombre, required this.firebaseUid});

  @override
  State<ProductoHistorialScreen> createState() => _ProductoHistorialScreenState();
}

class _ProductoHistorialScreenState extends State<ProductoHistorialScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final d = await ProductosCatalogoService.getHistorial(widget.productoId, widget.firebaseUid);
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  double _d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  @override
  Widget build(BuildContext context) {
    final historial = (_data?['historial'] as List?) ?? [];
    final producto = _data?['producto'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(widget.nombre, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          if (producto != null)
            IconButton(
              icon: const Icon(Icons.label_outline, color: AppTheme.textSecondary),
              tooltip: 'Asignar categoría',
              onPressed: () => _showCategoria(producto),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : historial.isEmpty
              ? const Center(child: Text('Sin historial', style: TextStyle(color: AppTheme.textSecondary)))
              : Column(children: [
                  _buildResumen(historial),
                  Expanded(child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: historial.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _historialRow(historial[i], i < historial.length - 1 ? historial[i + 1] : null),
                  )),
                ]),
    );
  }

  Widget _buildResumen(List historial) {
    if (historial.length < 2) return const SizedBox.shrink();
    final precios = historial.map((h) => _d(h['precio_unitario'])).toList();
    final minPrecio = precios.reduce((a, b) => a < b ? a : b);
    final maxPrecio = precios.reduce((a, b) => a > b ? a : b);
    final primero = precios.last;
    final ultimo = precios.first;
    final cambioTotal = primero > 0 ? ((ultimo - primero) / primero * 100) : 0.0;
    final sube = cambioTotal > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Expanded(child: _statCol('Mínimo', '\$${_fmt.format(minPrecio)}', AppTheme.success)),
        Expanded(child: _statCol('Máximo', '\$${_fmt.format(maxPrecio)}', AppTheme.danger)),
        Expanded(child: _statCol('Compras', '${historial.length}', AppTheme.primary)),
        Expanded(child: _statCol(
          'Variación',
          '${sube ? "+" : ""}${cambioTotal.toStringAsFixed(1)}%',
          sube ? AppTheme.danger : AppTheme.success,
        )),
      ]),
    );
  }

  Widget _statCol(String label, String value, Color color) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
  ]);

  Widget _historialRow(dynamic h, dynamic anterior) {
    final precio = _d(h['precio_unitario']);
    final precioAnt = anterior != null ? _d(anterior['precio_unitario']) : null;
    final fecha = (h['fecha_compra'] as String?)?.substring(0, 10) ?? '';
    final merchant = h['merchant_name'] as String? ?? h['factura_merchant'] as String? ?? '';
    final numFactura = h['numero_factura'] as String? ?? '';

    Color? tendColor;
    String? tendIcon;
    if (precioAnt != null && precio != precioAnt) {
      final sube = precio > precioAnt;
      tendColor = sube ? AppTheme.danger : AppTheme.success;
      tendIcon = sube ? '↑' : '↓';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fecha, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          if (merchant.isNotEmpty)
            Text(merchant, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          if (numFactura.isNotEmpty)
            Text('Factura #$numFactura', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ])),
        Row(children: [
          if (tendIcon != null) ...[
            Text(tendIcon, style: TextStyle(color: tendColor, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
          ],
          Text('\$${_fmt.format(precio)}',
              style: TextStyle(
                color: tendColor ?? AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              )),
        ]),
      ]),
    );
  }

  void _showCategoria(dynamic producto) {
    final cats = ['Alimentos', 'Bebidas', 'Limpieza', 'Higiene', 'Salud', 'Electrodomésticos', 'Ropa', 'Tecnología', 'Otro'];
    final current = producto['categoria'] as String?;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Asignar categoría', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: cats.map((c) {
            final sel = c == current;
            return GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await ProductosCatalogoService.setCategoria(widget.productoId, widget.firebaseUid, c);
                _cargar();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? AppTheme.primary : Colors.transparent),
                ),
                child: Text(c, style: TextStyle(
                  color: sel ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                )),
              ),
            );
          }).toList()),
        ]),
      ),
    );
  }
}
