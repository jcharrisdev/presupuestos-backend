import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/servicios_service.dart';

class RegistroPagoClienteScreen extends StatefulWidget {
  final String firebaseUid;
  final int jobId;
  const RegistroPagoClienteScreen({Key? key, required this.firebaseUid, required this.jobId}) : super(key: key);

  @override
  _RegistroPagoClienteScreenState createState() => _RegistroPagoClienteScreenState();
}

class _RegistroPagoClienteScreenState extends State<RegistroPagoClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  String _tipo = 'pago_parcial';
  bool _loading = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Registrar pago del cliente',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Registra un pago recibido del cliente:\n\n'
          '• Anticipo — pago inicial antes de iniciar el trabajo.\n'
          '• Pago parcial — abono durante el desarrollo del trabajo.\n'
          '• Pago final — liquidación total del saldo pendiente.\n\n'
          'Cada pago actualiza automáticamente el estado de cobro y la utilidad neta.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ServiciosService.addCustomerPayment(widget.jobId, {
        'firebase_uid': widget.firebaseUid,
        'monto': double.tryParse(_montoCtrl.text.trim()) ?? 0,
        'tipo': _tipo,
        'nota': _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar pago'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Tipo de pago'),
              DropdownButtonFormField<String>(
                value: _tipo,
                dropdownColor: AppTheme.surface,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: _deco(''),
                items: const [
                  DropdownMenuItem(value: 'anticipo', child: Text('Anticipo')),
                  DropdownMenuItem(value: 'pago_parcial', child: Text('Pago parcial')),
                  DropdownMenuItem(value: 'pago_final', child: Text('Pago final')),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? 'pago_parcial'),
              ),
              const SizedBox(height: 16),
              _label('Monto recibido *'),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: _deco('Ej. 1500.00'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Campo requerido';
                  if (double.tryParse(v.trim()) == null) return 'Ingresa un número válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _label('Nota (opcional)'),
              TextFormField(
                controller: _notaCtrl,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: _deco('Ej. Anticipo vía transferencia'),
                maxLines: 2,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _registrar,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Registrar pago', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary)),
      );
}
