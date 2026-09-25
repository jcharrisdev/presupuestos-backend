import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/ingreso_extra_service.dart';

/// S1/U6 — tercera opción en la landing de Ventas para un ingreso suelto
/// (venta usada, trabajo puntual, regalo) sin catálogo ni inventario.
/// Reusa el mismo mecanismo que Ingresos Extra: se guarda en
/// registros_ingreso y suma directo al ingreso_real del mes.
class IngresoPuntualSheet extends StatefulWidget {
  final String firebaseUid;
  const IngresoPuntualSheet({Key? key, required this.firebaseUid}) : super(key: key);

  static Future<bool?> show(BuildContext context, String firebaseUid) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IngresoPuntualSheet(firebaseUid: firebaseUid),
    );
  }

  @override
  State<IngresoPuntualSheet> createState() => _IngresoPuntualSheetState();
}

class _IngresoPuntualSheetState extends State<IngresoPuntualSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  final _monto = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _monto.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await IngresoExtraService.crear(
        widget.firebaseUid,
        monto: double.parse(_monto.text.replaceAll(',', '.')),
        fuenteNombre: 'Ingreso puntual',
        fecha: DateFormat('yyyy-MM-dd').format(_fecha),
        descripcion: _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.payments_outlined, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Ingreso puntual',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Para una venta suelta, un trabajo extra o un regalo — sin catálogo ni inventario. '
                  'Se suma directo a tu ingreso real de este mes.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 20),
                Text('¿De qué se trata?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descripcion,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Ej. Vendí la bicicleta usada',
                    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppTheme.surfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Monto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _monto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    prefixText: 'B/. ',
                    prefixStyle: TextStyle(color: AppTheme.textSecondary),
                    hintText: '0.00',
                    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppTheme.surfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (n == null || n <= 0) return 'Ingresa un monto válido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text('Fecha', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _elegirFecha,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                      const SizedBox(width: 8),
                      Text(DateFormat('d MMM yyyy', 'es').format(_fecha),
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    ]),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Guardar ingreso', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
