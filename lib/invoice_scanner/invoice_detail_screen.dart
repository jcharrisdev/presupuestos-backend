import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import 'select_target_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final int    invoiceId;
  final String firebaseUid;
  const InvoiceDetailScreen({super.key, required this.invoiceId, required this.firebaseUid});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading    = true;
  bool _showItems  = false;
  bool _removiendo = false;
  final _fmt     = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _dateFmtShort = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    try {
      final data = await InvoiceScannerService.getInvoiceDetail(widget.invoiceId, widget.firebaseUid);
      if (mounted) setState(() => _invoice = data);
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
    final total       = _invoice!['total_amount']   ?? 0;
    final assigned    = _invoice!['total_assigned']  ?? 0;
    final remaining   = _invoice!['remaining']       ?? 0;
    final status      = _invoice!['status'];

    final canDelete   = status == 'unassigned' || status == 'pending';
    final canAssign   = remaining > 0;
    final progress    = total > 0 ? (assigned / total).clamp(0.0, 1.0) as double : 0.0;

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
              _Row('DGI',         (_invoice!['dgi_validated'] as int? ?? 0) == 1 ? '✓ Validado' : '— No validado',
                   color: (_invoice!['dgi_validated'] as int? ?? 0) == 1 ? AppTheme.success : Colors.orange),
            ]),
            const SizedBox(height: 12),

            // Montos y progreso
            _Section(title: 'Montos', children: [
              _Row('Subtotal',  _invoice!['subtotal_amount'] != null ? 'B/. ${_fmt.format(_invoice!['subtotal_amount'])}' : '-'),
              _Row('ITBMS',     _invoice!['tax_amount'] != null ? 'B/. ${_fmt.format(_invoice!['tax_amount'])}' : '-'),
              _Row('Total',     'B/. ${_fmt.format(total)}', bold: true, color: AppTheme.primary),
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
                      Expanded(child: Text(it['descripcion'] ?? '-',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                      Text('B/. ${_fmt.format(it['subtotal'] ?? 0)}',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
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
                    Text('B/. ${_fmt.format(a['amount_assigned'] ?? 0)}',
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
