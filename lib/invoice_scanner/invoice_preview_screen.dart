import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import 'select_target_screen.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const InvoicePreviewScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  late Map<String, dynamic> _invoice;
  bool _saving    = false;
  bool _showItems = false;

  final _fmt     = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _invoice = Map<String, dynamic>.from(widget.invoice);
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '-';
    try { return _dateFmt.format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  Future<void> _guardarSinAsignar() async {
    setState(() => _saving = true);
    try {
      await InvoiceScannerService.assignInvoice(
        _invoice['id'] as int,
        {'assignment_type': 'sin_asignar', 'amount_assigned': _d(_invoice['total_amount'])},
        widget.firebaseUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Factura guardada sin asignar'),
        backgroundColor: AppTheme.success,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppTheme.danger,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items       = (_invoice['items'] as List?) ?? [];
    final dgiOk       = (_invoice['dgi_validated'].toString() == '1');
    final total       = _d(_invoice['total_amount']);
    final tax         = _invoice['tax_amount']   != null ? _d(_invoice['tax_amount'])   : null;
    final subtotal    = _invoice['subtotal_amount'] != null ? _d(_invoice['subtotal_amount']) : null;
    final assigned    = _d(_invoice['total_assigned']);
    final remaining   = _d(_invoice['remaining']);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Resumen de Factura',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado DGI
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: dgiOk ? AppTheme.success.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(dgiOk ? Icons.verified : Icons.warning_amber_rounded,
                      color: dgiOk ? AppTheme.success : Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    dgiOk ? 'Validado por DGI' : 'No pudo validarse con DGI — revisa los datos',
                    style: TextStyle(
                        color: dgiOk ? AppTheme.success : Colors.orange, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Datos del comercio
            _Card(children: [
              _Row('Comercio',       _invoice['merchant_name']  ?? '-'),
              _Row('RUC',            _invoice['merchant_ruc']   ?? '-'),
              _Row('N° Factura',     _invoice['numero_factura'] ?? '-'),
              _Row('Fecha',          _fmtDate(_invoice['invoice_date'])),
            ]),
            const SizedBox(height: 12),

            // Montos
            _Card(children: [
              if (subtotal != null) _Row('Subtotal', 'B/. ${_fmt.format(subtotal)}'),
              if (tax != null)      _Row('ITBMS',    'B/. ${_fmt.format(tax)}'),
              _Row('Total',
                total > 0 ? 'B/. ${_fmt.format(total)}' : '-',
                bold: true, color: AppTheme.primary),
              if (assigned > 0) ...[
                _Row('Asignado',  'B/. ${_fmt.format(assigned)}', color: AppTheme.success),
                _Row('Pendiente', 'B/. ${_fmt.format(remaining)}',
                    color: remaining < 0 ? AppTheme.danger : AppTheme.textSecondary),
              ],
            ]),
            const SizedBox(height: 12),

            // Ítems
            if (items.isNotEmpty) ...[
              GestureDetector(
                onTap: () => setState(() => _showItems = !_showItems),
                child: _Card(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ítems (${items.length})',
                          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      Icon(_showItems ? Icons.expand_less : Icons.expand_more,
                          color: AppTheme.textSecondary),
                    ],
                  ),
                  if (_showItems) ...[
                    const SizedBox(height: 8),
                    ...items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(it['descripcion'] ?? '-',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                          Text('B/. ${_fmt.format(_d(it['subtotal']))}',
                              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        ],
                      ),
                    )),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),
            // Botón principal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.black),
                label: const Text('Asignar factura',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SelectTargetScreen(
                      invoice: _invoice,
                      firebaseUid: widget.firebaseUid,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Botón secundario
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _guardarSinAsignar,
                child: _saving
                    ? SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                    : Text('Guardar sin asignar',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            )),
      ],
    ),
  );
}
