import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/invoice_scanner_service.dart';
import 'invoice_history_screen.dart';

class AssignServiceExpenseScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  final String tipo; // 'gasto_operativo_servicio' | 'gasto_empresarial' | 'compra_inventario'
  const AssignServiceExpenseScreen({super.key, required this.invoice, required this.firebaseUid, required this.tipo});

  @override
  State<AssignServiceExpenseScreen> createState() => _AssignServiceExpenseScreenState();
}

class _AssignServiceExpenseScreenState extends State<AssignServiceExpenseScreen> {
  List<dynamic> _jobs    = [];
  dynamic        _selectedJob;
  bool           _loading = false;
  bool           _saving  = false;
  bool           _requireJob = false;

  late TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  String get _titulo {
    switch (widget.tipo) {
      case 'gasto_operativo_servicio': return 'Gasto operativo de servicio';
      case 'gasto_empresarial':        return 'Gasto empresarial';
      case 'compra_inventario':        return 'Compra de inventario';
      default: return 'Asignar gasto';
    }
  }

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: (widget.invoice['total_amount'] ?? '').toString());
    _requireJob = widget.tipo == 'gasto_operativo_servicio';
    if (_requireJob) _cargarJobs();
  }

  @override
  void dispose() {
    _amountCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarJobs() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/jobs?firebase_uid=${widget.firebaseUid}');
      if (resp.statusCode == 200) {
        final all = json.decode(resp.body) as List;
        setState(() => _jobs = all.where((j) => j['status'] != 'completed' && j['status'] != 'cancelled').toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _asignar() async {
    if (_requireJob && _selectedJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Selecciona un trabajo'), backgroundColor: AppTheme.danger,
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
          'assignment_type': widget.tipo,
          if (_selectedJob != null) 'target_id': _selectedJob['id'],
          'amount_assigned': amount,
          'notes':           _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        },
        widget.firebaseUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Gasto registrado'), backgroundColor: AppTheme.success,
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
        title: Text(_titulo, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
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

                  if (_requireJob) ...[
                    Text('Trabajo / Servicio', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 6),
                    _jobs.isEmpty
                        ? Text('No tienes trabajos activos', style: TextStyle(color: AppTheme.textSecondary))
                        : DropdownButtonFormField<dynamic>(
                            value: _selectedJob,
                            dropdownColor: AppTheme.surface,
                            style: TextStyle(color: AppTheme.textPrimary),
                            decoration: _deco('Selecciona el trabajo'),
                            items: _jobs.map((j) => DropdownMenuItem(
                              value: j,
                              child: Text(j['title'] ?? j['nombre'] ?? '-',
                                  style: TextStyle(color: AppTheme.textPrimary)),
                            )).toList(),
                            onChanged: (j) => setState(() => _selectedJob = j),
                          ),
                    const SizedBox(height: 16),
                  ],

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
                    decoration: _deco('Descripción del gasto'),
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
                          : const Text('Registrar gasto',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
