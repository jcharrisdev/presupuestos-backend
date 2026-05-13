import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import 'invoice_scanner_screen.dart';
import 'invoice_detail_screen.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  final String firebaseUid;
  const InvoiceHistoryScreen({super.key, required this.firebaseUid});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  List<dynamic> _invoices    = [];
  bool          _loading     = true;
  String?       _filterStatus; // null=todas, 'assigned', 'partially_assigned', 'unassigned', 'pending'
  final _fmt     = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  // MySQL DECIMAL vuelve como String en JSON — parseamos defensivamente
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
      final list = await InvoiceScannerService.listInvoices(
        widget.firebaseUid,
        status: _filterStatus,
      );
      if (mounted) setState(() => _invoices = list);
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
    try { return _dateFmt.format(DateTime.parse(d.toString())); } catch (_) { return '-'; }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'assigned':           return AppTheme.success;
      case 'partially_assigned': return Colors.orange;
      case 'unassigned':         return AppTheme.danger;
      default:                   return AppTheme.textSecondary;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'assigned':           return 'Asignada';
      case 'partially_assigned': return 'Parcial';
      case 'unassigned':         return 'Sin asignar';
      default:                   return 'Pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Mis Facturas QR',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list, color: AppTheme.textSecondary),
            onPressed: _mostrarFiltros,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
          ));
          _cargar(silencioso: true);
        },
        child: const Icon(Icons.qr_code_scanner, color: Colors.black),
      ),
      body: Column(
        children: [
          // Chips de filtro rápido
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip('Todas',      null),
                  _Chip('Asignadas',  'assigned'),
                  _Chip('Parciales',  'partially_assigned'),
                  _Chip('Sin asignar','unassigned'),
                  _Chip('Pendientes', 'pending'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _invoices.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        color: AppTheme.primary,
                        onRefresh: () => _cargar(silencioso: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _invoices.length,
                          itemBuilder: (_, i) => _buildTile(_invoices[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _Chip(String label, String? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label, style: TextStyle(
        color: _filterStatus == value ? Colors.black : AppTheme.textSecondary,
        fontSize: 12,
      )),
      selected: _filterStatus == value,
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onSelected: (_) {
        setState(() => _filterStatus = value);
        _cargar();
      },
    ),
  );

  Widget _buildTile(Map<String, dynamic> inv) => GestureDetector(
    onTap: () async {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(invoiceId: inv['id'] as int, firebaseUid: widget.firebaseUid),
      ));
      _cargar(silencioso: true);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.receipt_long, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inv['merchant_name'] ?? 'Factura',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(_fmtDate(inv['invoice_date']),
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('B/. ${_fmt.format(_d(inv['total_amount']))}',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(inv['status']).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(inv['status']),
                    style: TextStyle(color: _statusColor(inv['status']), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.qr_code, size: 64, color: AppTheme.textSecondary.withOpacity(0.4)),
        const SizedBox(height: 16),
        Text('No tienes facturas escaneadas',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        const SizedBox(height: 8),
        Text('Usa el botón + para escanear tu primera factura QR',
            style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6), fontSize: 13)),
      ],
    ),
  );

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtrar facturas',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                _Chip('Todas',       null),
                _Chip('Asignadas',   'assigned'),
                _Chip('Parciales',   'partially_assigned'),
                _Chip('Sin asignar', 'unassigned'),
                _Chip('Pendientes',  'pending'),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
