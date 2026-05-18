import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import '../services/productos_catalogo_service.dart';
import 'select_target_screen.dart';
import 'productos_catalogo_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final int    invoiceId;
  final String firebaseUid;
  const InvoiceDetailScreen({super.key, required this.invoiceId, required this.firebaseUid});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading       = true;
  bool _showItems     = false;
  bool _removiendo    = false;
  bool _registrando   = false;
  bool _yaRegistrado  = false;
  final _fmt     = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _dateFmtShort = DateFormat('dd/MM/yyyy');

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    try {
      final data = await InvoiceScannerService.getInvoiceDetail(widget.invoiceId, widget.firebaseUid);
      if (mounted) setState(() {
        _invoice = data;
        // Si ya hay un registros_gasto vinculado a esta factura lo marcamos
        _yaRegistrado = (data['ya_registrado_en_mes'] as bool?) ?? false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '-';
    try { return _dateFmtShort.format(DateTime.parse(d.toString())); } catch (_) { return '-'; }
  }

  String _fmtTs(dynamic d) {
    if (d == null) return '-';
    try { return _dateFmt.format(DateTime.parse(d.toString())); } catch (_) { return '-'; }
  }

  String _tipoLabel(String? t) {
    switch (t) {
      case 'gasto_existente':          return 'Gasto existente';
      case 'gasto_nuevo':              return 'Gasto nuevo';
      case 'gustito':                  return 'Gustito';
      case 'presupuesto_compartido':   return 'Presupuesto compartido';
      case 'gasto_operativo_servicio': return 'Gasto operativo';
      case 'gasto_empresarial':        return 'Gasto empresarial';
      case 'compra_inventario':        return 'Compra inventario';
      case 'sin_asignar':              return 'Sin asignar';
      default: return t ?? '-';
    }
  }

  Future<void> _eliminarAsignacion(int assignmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('¿Eliminar asignación?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Esta acción no puede deshacerse.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _removiendo = true);
    try {
      await InvoiceScannerService.removeAssignment(widget.invoiceId, assignmentId, widget.firebaseUid);
      await _cargar(silencioso: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
      ));
    } finally {
      if (mounted) setState(() => _removiendo = false);
    }
  }

  Future<void> _eliminarFactura() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('¿Eliminar factura?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Solo se pueden eliminar facturas sin asignar.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await InvoiceScannerService.deleteInvoice(widget.invoiceId, widget.firebaseUid);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
      ));
    }
  }

  Future<void> _registrarEnMes() async {
    final invoice = _invoice!;
    final total = _d(invoice['total_amount']);
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta factura no tiene monto total')));
      return;
    }
    final cats = ['Compras', 'Alimentación', 'Salud', 'Hogar', 'Transporte', 'Tecnología', 'Otro'];
    String catSel = 'Compras';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Registrar en estado financiero',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se agregará B/. ${NumberFormat('#,##0.00', 'en_US').format(total)} a tus gastos del mes actual.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          const Text('Categoría', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: catSel,
                isExpanded: true,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setD(() => catSel = v!),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      )),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _registrando = true);
    try {
      await ProductosCatalogoService.registrarEnMes(
        widget.invoiceId, widget.firebaseUid, categoria: catSel,
      );
      if (mounted) {
        setState(() { _registrando = false; _yaRegistrado = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Factura registrada en tu estado financiero'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _registrando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_invoice == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(backgroundColor: AppTheme.surface, iconTheme: IconThemeData(color: AppTheme.textPrimary)),
        body: Center(child: Text('Factura no encontrada', style: TextStyle(color: AppTheme.textSecondary))),
      );
    }

    final items       = (_invoice!['items']       as List?) ?? [];
    final assignments = (_invoice!['assignments'] as List?) ?? [];
    final total       = _d(_invoice!['total_amount']);
    final assigned    = _d(_invoice!['total_assigned']);
    final remaining   = _d(_invoice!['remaining']);
    final status      = _invoice!['status'];

    final canDelete   = status == 'unassigned' || status == 'pending';
    final canAssign   = remaining > 0;
    final progress    = total > 0 ? (assigned / total).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Detalle de Factura',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          if (canDelete)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: _eliminarFactura,
            ),
        ],
      ),
      floatingActionButton: canAssign
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SelectTargetScreen(invoice: _invoice!, firebaseUid: widget.firebaseUid),
                ));
                _cargar(silencioso: true);
              },
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Nueva asignación', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera fiscal
            _Section(title: 'Datos fiscales', children: [
              _Row('Comercio',    _invoice!['merchant_name']  ?? '-'),
              _Row('RUC',         _invoice!['merchant_ruc']   ?? '-'),
              _Row('N° Factura',  _invoice!['numero_factura'] ?? '-'),
              _Row('Fecha',       _fmtDate(_invoice!['invoice_date'])),
              _Row('DGI', _invoice!['dgi_validated'].toString() == '1' ? '✓ Validado' : '— No validado',
                   color: _invoice!['dgi_validated'].toString() == '1' ? AppTheme.success : Colors.orange),
            ]),
            const SizedBox(height: 12),

            // Montos y progreso
            _Section(title: 'Montos', children: [
              _Row('Subtotal', _invoice!['subtotal_amount'] != null ? 'B/. ${_fmt.format(_d(_invoice!['subtotal_amount']))}' : '-'),
              _Row('ITBMS',    _invoice!['tax_amount']      != null ? 'B/. ${_fmt.format(_d(_invoice!['tax_amount']))}' : '-'),
              _Row('Total',    total > 0 ? 'B/. ${_fmt.format(total)}' : '-', bold: true, color: AppTheme.primary),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress, minHeight: 6,
                  backgroundColor: AppTheme.background,
                  valueColor: AlwaysStoppedAnimation(
                    progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Asignado: B/. ${_fmt.format(assigned)}',
                    style: TextStyle(color: AppTheme.success, fontSize: 11)),
                Text('Pendiente: B/. ${_fmt.format(remaining)}',
                    style: TextStyle(
                      color: remaining < 0 ? AppTheme.danger : AppTheme.textSecondary,
                      fontSize: 11,
                    )),
              ]),
            ]),
            const SizedBox(height: 12),

            // Botón registrar en estado financiero
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: _yaRegistrado
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
                        SizedBox(width: 8),
                        Text('Registrada en estado financiero',
                            style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    )
                  : ElevatedButton.icon(
                      icon: _registrando
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Registrar en mi estado financiero',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _registrando ? null : _registrarEnMes,
                    ),
            ),
            const SizedBox(height: 12),

            // Ítems
            if (items.isNotEmpty) ...[
              GestureDetector(
                onTap: () => setState(() => _showItems = !_showItems),
                child: _Section(title: 'Ítems (${items.length})', trailing: Icon(
                  _showItems ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.textSecondary,
                ), children: [
                  if (_showItems) ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it['descripcion'] ?? '-',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('B/. ${_fmt.format(_d(it['subtotal']))}',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        GestureDetector(
                          onTap: () async {
                            final nombreNorm = (it['descripcion'] as String? ?? '').trim().toLowerCase();
                            if (nombreNorm.isEmpty) return;
                            final catalogo = await ProductosCatalogoService.getAll(widget.firebaseUid, q: nombreNorm);
                            if (!mounted) return;
                            if (catalogo.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Sin historial de precio para este producto')));
                              return;
                            }
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ProductoHistorialScreen(
                                productoId: catalogo[0]['id'] as int,
                                nombre: catalogo[0]['nombre'] as String,
                                firebaseUid: widget.firebaseUid,
                              ),
                            ));
                          },
                          child: const Text('📊 historial',
                              style: TextStyle(color: AppTheme.info, fontSize: 10)),
                        ),
                      ]),
                    ]),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // Asignaciones
            _Section(title: 'Asignaciones (${assignments.length})', children: [
              if (assignments.isEmpty)
                Text('Sin asignaciones aún',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
              else
                ...assignments.map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tipoLabel(a['assignment_type']),
                            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(_fmtTs(a['created_at']),
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        if (a['notes'] != null)
                          Text(a['notes'].toString(),
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                    )),
                    Text('B/. ${_fmt.format(_d(a['amount_assigned']))}',
                        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    _removiendo
                        ? SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: AppTheme.danger, strokeWidth: 2))
                        : IconButton(
                            icon: Icon(Icons.close, color: AppTheme.danger, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _eliminarAsignacion(a['id'] as int),
                          ),
                  ]),
                )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const _Section({required this.title, required this.children, this.trailing});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
        if (trailing != null) trailing!,
      ]),
      if (children.isNotEmpty) const SizedBox(height: 8),
      ...children,
    ]),
  );
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      Text(value, style: TextStyle(
        color: color ?? AppTheme.textPrimary, fontSize: 13,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      )),
    ]),
  );
}
