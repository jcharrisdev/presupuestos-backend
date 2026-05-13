import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/invoice_scanner_service.dart';
import 'invoice_history_screen.dart';

class AssignToBudgetScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const AssignToBudgetScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<AssignToBudgetScreen> createState() => _AssignToBudgetScreenState();
}

class _AssignToBudgetScreenState extends State<AssignToBudgetScreen> {
  List<dynamic> _presupuestos = [];
  List<dynamic> _movimientos  = [];
  dynamic _selectedPresupuesto;
  dynamic _selectedMovimiento;
  bool _loading  = false;
  bool _saving   = false;

  final _amountCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _fmt        = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = (widget.invoice['total_amount'] ?? '').toString();
    _cargarPresupuestos();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPresupuestos() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (resp.statusCode == 200) {
        setState(() => _presupuestos = json.decode(resp.body));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarMovimientos(int presupuestoId) async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/presupuestos/$presupuestoId/gastos?firebase_uid=${widget.firebaseUid}');
      if (resp.statusCode == 200) {
        final gastos = json.decode(resp.body) as List;
        setState(() => _movimientos = gastos.where((g) => g['tipo'] != 'ahorro').toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _asignar() async {
    if (_selectedMovimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Selecciona un gasto'),
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
      final result = await InvoiceScannerService.assignInvoice(
        widget.invoice['id'] as int,
        {
          'assignment_type': 'gasto_existente',
          'target_id':       _selectedMovimiento['id'],
          'amount_assigned': amount,
          'notes':           _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        },
        widget.firebaseUid,
      );

      if (!mounted) return;
      if (result['overpaid'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Asignado con sobrepago de B/. ${_fmt.format(result['excess'])}'),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Factura asignada al gasto'),
          backgroundColor: AppTheme.success,
        ));
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => InvoiceHistoryScreen(firebaseUid: widget.firebaseUid)),
        (r) => r.isFirst,
      );
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
        title: Text('Asignar a gasto existente',
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
                  Text('Factura: ${widget.invoice['merchant_name'] ?? '-'}  •  B/. ${_fmt.format(widget.invoice['total_amount'] ?? 0)}',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 20),

                  Text('Presupuesto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
                    onChanged: (p) {
                      setState(() { _selectedPresupuesto = p; _selectedMovimiento = null; _movimientos = []; });
                      if (p != null) _cargarMovimientos(p['id'] as int);
                    },
                  ),
                  const SizedBox(height: 16),

                  if (_movimientos.isNotEmpty) ...[
                    Text('Gasto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedMovimiento,
                      dropdownColor: AppTheme.surface,
                      style: TextStyle(color: AppTheme.textPrimary),
                      decoration: _deco('Selecciona el gasto'),
                      items: _movimientos.map((g) {
                        final monto = g['monto'] ?? 0;
                        return DropdownMenuItem(
                          value: g,
                          child: Text('${g['descripcion'] ?? '-'}  (B/. ${_fmt.format(monto)})',
                              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (g) => setState(() => _selectedMovimiento = g),
                    ),
                    if (_selectedMovimiento != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Stat('Planificado', 'B/. ${_fmt.format(_selectedMovimiento['monto'] ?? 0)}', AppTheme.textSecondary),
                            _Stat('Pagado', 'B/. ${_fmt.format(_selectedMovimiento['monto_pagado_real'] ?? 0)}', AppTheme.success),
                            _Stat('Pendiente',
                              'B/. ${_fmt.format((_selectedMovimiento['monto'] ?? 0) - (_selectedMovimiento['monto_pagado_real'] ?? 0))}',
                              AppTheme.primary),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  Text('Monto a asignar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
                    decoration: _deco('Ej: Pago parcial del mes'),
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
                          : const Text('Confirmar asignación',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    ],
  );
}
