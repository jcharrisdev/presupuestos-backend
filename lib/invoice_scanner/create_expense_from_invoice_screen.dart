import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import '../widgets/financiero/categoria_selector.dart';
import '../widgets/financiero/split_section.dart';
import '../mes_detalle_screen.dart';

class CreateExpenseFromInvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const CreateExpenseFromInvoiceScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<CreateExpenseFromInvoiceScreen> createState() => _CreateExpenseFromInvoiceScreenState();
}

class _CreateExpenseFromInvoiceScreenState extends State<CreateExpenseFromInvoiceScreen> {
  bool _saving = false;
  String _tipo = 'no_presupuestado';
  String _categoria = 'otro';
  late DateTime _fecha;
  late TextEditingController _nombreCtrl;
  final _splitKey = GlobalKey<SplitSectionState>();
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  static const _tipos = [
    ('no_presupuestado', 'No presupuestado'),
    ('variable',         'Variable'),
    ('fijo',             'Fijo'),
  ];

  @override
  void initState() {
    super.initState();
    final merchant = widget.invoice['merchant_name'] as String? ?? '';
    _nombreCtrl = TextEditingController(
      text: merchant.isNotEmpty ? merchant : 'Gasto factura QR',
    );
    final invoiceDate = widget.invoice['invoice_date'] as String?;
    if (invoiceDate != null) {
      _fecha = DateTime.tryParse(invoiceDate) ?? DateTime.now();
    } else {
      _fecha = DateTime.now();
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  String get _fechaStr =>
      '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}';

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre para el gasto'), backgroundColor: AppTheme.danger),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await InvoiceScannerService.registrarEnMes(
        widget.invoice['id'] as int,
        widget.firebaseUid,
        categoria:    _categoria,
        tipo:         _tipo,
        nombreGasto:  nombre,
        fecha:        _fechaStr,
      );
      final splitState = _splitKey.currentState;
      final monto = (widget.invoice['total_amount'] as num?)?.toDouble() ?? 0;
      if (splitState != null && splitState.activo) {
        await enviarSplitPuntual(
          firebaseUid: widget.firebaseUid,
          descripcion: nombre,
          montoTotal: monto,
          participantes: splitState.participantes,
          tipo: splitState.tipo,
          registroGastoId: result['id'] as int?,
        );
      }
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gasto registrado — visible en la quincena de la fecha'),
        backgroundColor: AppTheme.success,
      ));
      // Navegar al mes de la fecha de la factura, abriendo directo el Tab Quincenas (idx 2)
      const meses = ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => MesDetalleScreen(
          firebaseUid: widget.firebaseUid,
          anio: _fecha.year,
          mes: _fecha.month,
          label: meses[_fecha.month],
          initialTabIndex: 2,
        )),
        (r) => r.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monto = (widget.invoice['total_amount'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Nuevo gasto desde factura',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Invoice summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                Icon(Icons.receipt_outlined, color: AppTheme.textSecondary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.invoice['merchant_name'] ?? 'Factura QR'}  •  B/. ${_fmt.format(monto)}',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Nombre
            Text('Nombre del gasto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _nombreCtrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Nombre del gasto',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                filled: true, fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
            ),
            const SizedBox(height: 16),

            // Tipo
            Text('Tipo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: _tipos.map((t) {
                final selected = _tipo == t.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tipo = t.$1),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(t.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? AppTheme.primary : AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Categoría
            Text('Categoría', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            CategoriaSelector(
              firebaseUid: widget.firebaseUid,
              categoriaActual: _categoria,
              color: AppTheme.primary,
              onChanged: (cat, custom) => setState(() => _categoria = custom ?? cat),
            ),
            const SizedBox(height: 16),

            // Fecha
            Text('Fecha', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: ColorScheme.dark(
                          primary: AppTheme.primary, surface: AppTheme.surfaceAlt),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _fecha = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 10),
                  Text(_fechaStr, style: TextStyle(color: AppTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            SplitSection(
              key: _splitKey,
              getTotal: () => monto,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saving ? null : _guardar,
                child: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Registrar gasto',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
