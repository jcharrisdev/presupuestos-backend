import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/gustitos_service.dart';
import '../invoice_scanner/invoice_scanner_screen.dart';
import 'crear_gustito_sheet.dart';

class GustitosScreen extends StatefulWidget {
  final int budgetId;
  final String budgetNombre;
  final String firebaseUid;

  const GustitosScreen({
    Key? key,
    required this.budgetId,
    required this.budgetNombre,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  State<GustitosScreen> createState() => _GustitosScreenState();
}

class _GustitosScreenState extends State<GustitosScreen> {
  List<dynamic> _gustitos = [];
  bool _loading = true;
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final lista = await GustitosService.listarPorPresupuesto(
          widget.budgetId, widget.firebaseUid);
      final total = lista.fold<double>(
          0, (sum, g) => sum + _d(g['amount']));
      setState(() {
        _gustitos = lista;
        _total    = total;
        _loading  = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _eliminar(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar Gustito',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Seguro que quieres eliminarlo?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (confirm != true) return;
    await GustitosService.eliminar(id, widget.firebaseUid);
    _cargar();
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _fmtDate(dynamic d) {
    final s = d?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gustitos', style: TextStyle(fontSize: 18)),
          Text(widget.budgetNombre,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_scanner, size: 22, color: AppTheme.primary),
            tooltip: 'Escanear factura',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
              ));
              _cargar();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // ── Resumen total ──────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bolt,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Total en Gustitos',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    Text('\$${_total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ])),
                  Text('${_gustitos.length} registro${_gustitos.length == 1 ? "" : "s"}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ]),
              ),

              // ── Lista ─────────────────────────────────────────────
              Expanded(child: _gustitos.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      color: AppTheme.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _gustitos.length,
                        itemBuilder: (_, i) => _GustitoTile(
                          g: _gustitos[i],
                          onEliminar: () =>
                              _eliminar(_gustitos[i]['id'] as int),
                          fmtDate: _fmtDate,
                        ),
                      ),
                    )),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Gustito',
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => CrearGustitoSheet.show(
          context,
          budgetId: widget.budgetId,
          firebaseUid: widget.firebaseUid,
          onCreado: _cargar,
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.bolt, size: 56, color: AppTheme.textMuted),
      const SizedBox(height: 16),
      const Text('Sin Gustitos registrados',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Registra tus compras pequeñas\ncon conciencia y sin culpa',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
    ],
  ));
}

class _GustitoTile extends StatelessWidget {
  final Map<String, dynamic> g;
  final VoidCallback onEliminar;
  final String Function(dynamic) fmtDate;

  const _GustitoTile({
    required this.g,
    required this.onEliminar,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    final amount   = double.tryParse(g['amount'].toString()) ?? 0;
    final category = g['category'] as String?;
    final merchant = g['merchant'] as String?;
    final emotion  = g['emotion_tag'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bolt, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g['name'] as String,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 3),
          Row(children: [
            if (category != null) ...[
              _Chip(category, AppTheme.primary),
              const SizedBox(width: 5),
            ],
            if (emotion != null) _Chip(emotion, AppTheme.info),
          ]),
          if (merchant != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(merchant,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11)),
            ),
          const SizedBox(height: 2),
          Text(fmtDate(g['spent_at']),
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onEliminar,
            child: const Icon(Icons.delete_outline,
                color: AppTheme.textMuted, size: 18),
          ),
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
  );
}
