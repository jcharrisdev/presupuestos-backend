import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/invoice_scanner_service.dart';
import 'invoice_history_screen.dart';

class CreateExpenseFromInvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const CreateExpenseFromInvoiceScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<CreateExpenseFromInvoiceScreen> createState() => _CreateExpenseFromInvoiceScreenState();
}

class _CreateExpenseFromInvoiceScreenState extends State<CreateExpenseFromInvoiceScreen> {
  List<dynamic> _presupuestos = [];
  dynamic _selectedPresupuesto;
  bool _loading = false;
  bool _saving  = false;

  late TextEditingController _descCtrl;
  late TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _descCtrl   = TextEditingController(text: widget.invoice['merchant_name'] ?? 'Gasto factura QR');
    _amountCtrl = TextEditingController(text: (widget.invoice['total_amount'] ?? '').toString());
    _cargarPresupuestos();
  }

  @override
  void dispose() {
    _descCtrl.dispose(); _amountCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPresupuestos() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (resp.statusCode == 200) setState(() => _presupuestos = json.decode(resp.body));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _crear() async {
    if (_selectedPresupuesto == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Selecciona un presupuesto'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Ingresa un monto válido'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await InvoiceScannerService.assignInvoice(
        widget.invoice['id'] as int,
        {
          'assignment_type':  'gasto_nuevo',
          'presupuesto_id':   _selectedPresupuesto['id'],
          'amount_assigned':  amount,
          'notes':            _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        },
        widget.firebaseUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Gasto creado y factura asignada'),
        backgroundColor: AppTheme.success,
      ));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => InvoiceHistoryScreen(firebaseUid: widget.firebaseUid)),
        (r) => r.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppTheme.textSecondary),
    filled: true,
    fillColor: AppTheme.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Crear gasto desde factura',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total factura: B/. ${_fmt.format(widget.invoice['total_amount'] ?? 0)}',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 20),

                  Text('Presupuesto destino', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<dynamic>(
                    value: _selectedPresupuesto,
                    dropdownColor: AppTheme.surface,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco('Selecciona presupuesto'),
                    items: _presupuestos.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p['nombre'] ?? '', style: TextStyle(color: AppTheme.textPrimary)),
                    )).toList(),
                    onChanged: (p) => setState(() => _selectedPresupuesto = p),
                  ),
                  const SizedBox(height: 16),

                  Text('Descripción', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descCtrl,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco('Descripción del gasto'),
                  ),
                  const SizedBox(height: 16),

                  Text('Monto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco('0.00'),
                  ),
                  const SizedBox(height: 16),

                  Text('Notas (opcional)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _notesCtrl,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco('Notas adicionales'),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saving ? null : _crear,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text('Crear gasto y asignar',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
