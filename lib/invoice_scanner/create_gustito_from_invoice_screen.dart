import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/gustitos_service.dart';
import 'invoice_history_screen.dart';

class CreateGustitoFromInvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const CreateGustitoFromInvoiceScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<CreateGustitoFromInvoiceScreen> createState() => _CreateGustitoFromInvoiceScreenState();
}

class _CreateGustitoFromInvoiceScreenState extends State<CreateGustitoFromInvoiceScreen> {
  String _emocion = 'antojo';
  bool   _saving  = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _amountCtrl;
  late DateTime _fecha;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  static const _emociones = ['antojo', 'premio', 'social', 'impulso', 'estres', 'otro'];

  @override
  void initState() {
    super.initState();
    _nameCtrl   = TextEditingController(text: widget.invoice['merchant_name'] ?? 'Gustito');
    _amountCtrl = TextEditingController(text: (widget.invoice['total_amount'] ?? '').toString());
    final rawDate = widget.invoice['invoice_date'] as String?;
    _fecha = rawDate != null ? DateTime.tryParse(rawDate) ?? DateTime.now() : DateTime.now();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Monto inválido'), backgroundColor: AppTheme.danger,
      ));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa un nombre'), backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await GustitosService.crear({
        'user_id':            widget.firebaseUid,
        'name':               name,
        'amount':             amount,
        'spent_at':           '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}',
        'emotion_tag':        _emocion,
        'source':             'qr',
        'scanned_invoice_id': widget.invoice['id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gustito registrado'), backgroundColor: AppTheme.success,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Registrar como gustito',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Resumen de la factura
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              const Icon(Icons.receipt_outlined, color: AppTheme.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                widget.invoice['merchant_name'] ?? 'Factura QR',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              )),
              Text('B/. ${_fmt.format(widget.invoice['total_amount'] ?? 0)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 20),

          const Text('Nombre', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          _field(_nameCtrl, '¿Qué compraste?'),
          const SizedBox(height: 16),

          const Text('Monto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          _field(_amountCtrl, '0.00', numeric: true),
          const SizedBox(height: 16),

          const Text('Fecha', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primary, surface: AppTheme.surfaceAlt,
                  )),
                  child: child!,
                ),
              );
              if (p != null) setState(() => _fecha = p);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                const SizedBox(width: 10),
                Text(
                  '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          const Text('¿Cómo te sentiste?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _emociones.map((e) => GestureDetector(
              onTap: () => setState(() => _emocion = e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _emocion == e ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _emocion == e ? AppTheme.primary : AppTheme.border,
                    width: _emocion == e ? 1.5 : 1,
                  ),
                ),
                child: Text(e, style: TextStyle(
                  color: _emocion == e ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: _emocion == e ? FontWeight.w600 : FontWeight.normal,
                )),
              ),
            )).toList(),
          ),
          const SizedBox(height: 32),

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
                  : const Text('Guardar gustito',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {bool numeric = false}) =>
      TextField(
        controller: ctrl,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
