import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/invoice_scanner_service.dart';
import 'invoice_history_screen.dart';

class SplitInvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const SplitInvoiceScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<SplitInvoiceScreen> createState() => _SplitInvoiceScreenState();
}

class _SplitInvoiceScreenState extends State<SplitInvoiceScreen> {
  List<dynamic> _budgets         = [];
  dynamic        _selectedBudget;
  bool           _loading        = false;
  bool           _saving         = false;

  late TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: (widget.invoice['total_amount'] ?? '').toString());
    _cargarSharedBudgets();
  }

  @override
  void dispose() {
    _amountCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarSharedBudgets() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/shared-budgets?firebase_uid=${widget.firebaseUid}');
      if (resp.statusCode == 200) {
        final all = json.decode(resp.body) as List;
        setState(() => _budgets = all.where((b) => b['status'] == 'active').toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _reglaNombre(String? regla) {
    switch (regla) {
      case 'equitativo':    return '50/50 equitativo';
      case 'porcentual':    return 'Por porcentaje';
      case 'proporcional':  return 'Proporcional a ingresos';
      case 'pool_contribucion': return 'Fondo común';
      default: return regla ?? '-';
    }
  }

  Future<void> _asignar() async {
    if (_selectedBudget == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Selecciona un presupuesto compartido'), backgroundColor: AppTheme.danger,
      ));
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Monto inválido'), backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await InvoiceScannerService.assignInvoice(
        widget.invoice['id'] as int,
        {
          'assignment_type': 'presupuesto_compartido',
          'target_id':       _selectedBudget['id'],
          'amount_assigned': amount,
          'notes':           _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        },
        widget.firebaseUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Gasto compartido registrado'), backgroundColor: AppTheme.success,
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
    hintText: hint, hintStyle: TextStyle(color: AppTheme.textSecondary),
    filled: true, fillColor: AppTheme.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Dividir factura', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _budgets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text('No tienes presupuestos compartidos activos',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total factura: B/. ${_fmt.format(widget.invoice['total_amount'] ?? 0)}',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 20),

                      Text('Presupuesto compartido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<dynamic>(
                        value: _selectedBudget,
                        dropdownColor: AppTheme.surface,
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: _deco('Selecciona presupuesto'),
                        items: _budgets.map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(b['nombre'] ?? '', style: TextStyle(color: AppTheme.textPrimary)),
                        )).toList(),
                        onChanged: (b) => setState(() => _selectedBudget = b),
                      ),
                      if (_selectedBudget != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surface, borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.swap_horiz, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Text('Regla: ${_reglaNombre(_selectedBudget['regla_reparto'])}',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      Text('Monto a registrar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: _deco('0.00'),
                      ),
                      const SizedBox(height: 16),

                      Text('Descripción (opcional)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notesCtrl,
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: _deco('Ej: Cena restaurante'),
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
                          onPressed: _saving ? null : _asignar,
                          child: _saving
                              ? const SizedBox(height: 18, width: 18,
                                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                              : const Text('Registrar gasto compartido',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
