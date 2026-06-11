import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/servicios_service.dart';
import 'trabajo_detalle_screen.dart';

class CrearTrabajoScreen extends StatefulWidget {
  final String firebaseUid;
  const CrearTrabajoScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CrearTrabajoScreenState createState() => _CrearTrabajoScreenState();
}

class _CrearTrabajoScreenState extends State<CrearTrabajoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _estado = 'pending';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _loading = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _clienteCtrl.dispose();
    _telefonoCtrl.dispose();
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Crear trabajo',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Completa los datos del nuevo trabajo o proyecto:\n\n'
          '• Nombre: identifica el trabajo (ej. "Boda García mayo").\n'
          '• Cliente: nombre de quien contrata el servicio.\n'
          '• Teléfono: contacto del cliente (opcional).\n'
          '• Descripción: detalle adicional del trabajo (opcional).\n'
          '• Monto total: precio acordado con el cliente.\n'
          '• Estado inicial: define si el trabajo ya comenzó o está en espera.\n'
          '• Fechas: inicio y entrega estimada (opcionales).\n\n'
          'Después de crear el trabajo podrás agregar colaboradores, registrar pagos y gastos.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _pickFecha({required bool esInicio}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (esInicio) _fechaInicio = picked;
        else _fechaFin = picked;
      });
    }
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final job = await ServiciosService.createJob({
        'firebase_uid': widget.firebaseUid,
        'nombre': _nombreCtrl.text.trim(),
        'nombre_cliente': _clienteCtrl.text.trim(),
        'telefono_cliente': _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
        'descripcion': _descripcionCtrl.text.trim().isEmpty ? null : _descripcionCtrl.text.trim(),
        'monto_total': double.tryParse(_montoCtrl.text.trim()) ?? 0,
        'estado': _estado,
        'fecha_inicio': _fechaInicio?.toIso8601String().split('T').first,
        'fecha_fin': _fechaFin?.toIso8601String().split('T').first,
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => TrabajoDetalleScreen(
          firebaseUid: widget.firebaseUid,
          jobId: job['id'] as int,
        )),
      );
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
        title: const Text('Nuevo trabajo'),
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
              _label('Nombre del trabajo *'),
              _field(_nombreCtrl, 'Ej. Boda García mayo 2026',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null),
              const SizedBox(height: 16),
              _label('Nombre del cliente *'),
              _field(_clienteCtrl, 'Ej. María García',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null),
              const SizedBox(height: 16),
              _label('Teléfono del cliente'),
              _field(_telefonoCtrl, 'Ej. +502 5000 0000'),
              const SizedBox(height: 16),
              _label('Descripción'),
              _field(_descripcionCtrl, 'Detalle adicional del trabajo', maxLines: 3),
              const SizedBox(height: 16),
              _label('Monto total acordado *'),
              _field(
                _montoCtrl,
                'Ej. 5000.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Campo requerido';
                  if (double.tryParse(v.trim()) == null) return 'Ingresa un número válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _label('Estado inicial'),
              _dropdownEstado(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _fechaButton(
                    label: 'Fecha inicio',
                    fecha: _fechaInicio,
                    onTap: () => _pickFecha(esInicio: true),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _fechaButton(
                    label: 'Fecha fin',
                    fecha: _fechaFin,
                    onTap: () => _pickFecha(esInicio: false),
                  )),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _crear,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear trabajo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.primary),
          ),
        ),
      );

  Widget _dropdownEstado() => DropdownButtonFormField<String>(
        value: _estado,
        dropdownColor: AppTheme.surface,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(0.2)),
          ),
        ),
        items: const [
          DropdownMenuItem(value: 'draft', child: Text('Borrador')),
          DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
          DropdownMenuItem(value: 'in_progress', child: Text('En progreso')),
        ],
        onChanged: (v) => setState(() => _estado = v ?? 'pending'),
      );

  Widget _fechaButton({required String label, required DateTime? fecha, required VoidCallback onTap}) {
    final texto = fecha != null
        ? '${fecha.day}/${fecha.month}/${fecha.year}'
        : 'Seleccionar';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.textSecondary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                  Text(texto, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
