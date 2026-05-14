import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';

class CrearDeudaSheet {
  static void show(
    BuildContext context, {
    required String firebaseUid,
    required VoidCallback onCreada,
  }) {
    final nombreCtrl    = TextEditingController();
    final totalCtrl     = TextEditingController();
    final pendienteCtrl = TextEditingController();
    final tasaCtrl      = TextEditingController();
    final pagoMinCtrl   = TextEditingController();
    String tipo = 'personal';
    DateTime? fechaProximoPago;
    bool _guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Nueva deuda',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            TextField(controller: nombreCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Nombre (ej: Tarjeta Visa, Préstamo banco)')),
            const SizedBox(height: 16),

            // Tipo
            const Text('Tipo de deuda', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _TipoBtn('Tarjeta',  'tarjeta_credito', tipo, (v) => setS(() => tipo = v)),
              _TipoBtn('Préstamo', 'prestamo',        tipo, (v) => setS(() => tipo = v)),
              _TipoBtn('Hipoteca', 'hipoteca',        tipo, (v) => setS(() => tipo = v)),
              _TipoBtn('Auto',     'auto',            tipo, (v) => setS(() => tipo = v)),
              _TipoBtn('Personal', 'personal',        tipo, (v) => setS(() => tipo = v)),
              _TipoBtn('Otro',     'otro',            tipo, (v) => setS(() => tipo = v)),
            ]),
            const SizedBox(height: 16),

            TextField(controller: totalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Monto total original')),
            const SizedBox(height: 12),
            TextField(controller: pendienteCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Saldo pendiente actual')),
            const SizedBox(height: 12),
            TextField(controller: tasaCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(suffixText: '%/mes', hintText: 'Tasa de interés (opcional)')),
            const SizedBox(height: 12),
            TextField(controller: pagoMinCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Pago mínimo mensual (opcional)')),
            const SizedBox(height: 12),

            // Fecha próximo pago
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
                      primary: AppTheme.primary, surface: AppTheme.surfaceAlt)),
                    child: child!,
                  ),
                );
                if (picked != null) setS(() => fechaProximoPago = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    fechaProximoPago != null
                        ? 'Próximo pago: ${fechaProximoPago!.toIso8601String().substring(0, 10)}'
                        : 'Fecha del próximo pago (opcional)',
                    style: TextStyle(
                      color: fechaProximoPago != null ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _guardando ? null : () async {
                final nombre    = nombreCtrl.text.trim();
                final total     = double.tryParse(totalCtrl.text) ?? 0;
                final pendiente = double.tryParse(pendienteCtrl.text) ?? 0;
                if (nombre.isEmpty || total <= 0 || pendiente <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Completa nombre, monto total y saldo pendiente')));
                  return;
                }
                setS(() => _guardando = true);
                try {
                  final body = <String, dynamic>{
                    'firebase_uid': firebaseUid,
                    'nombre': nombre,
                    'tipo': tipo,
                    'monto_total': total,
                    'monto_pendiente': pendiente,
                  };
                  final tasa = double.tryParse(tasaCtrl.text);
                  if (tasa != null && tasa > 0) body['tasa_interes'] = tasa;
                  final pagoMin = double.tryParse(pagoMinCtrl.text);
                  if (pagoMin != null && pagoMin > 0) body['pago_minimo'] = pagoMin;
                  if (fechaProximoPago != null)
                    body['fecha_proximo_pago'] = fechaProximoPago!.toIso8601String().substring(0, 10);
                  await DeudasService.crear(body);
                  Navigator.pop(ctx);
                  onCreada();
                } catch (e) {
                  setS(() => _guardando = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: _guardando
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar deuda'),
            )),
          ]),
        ),
      )),
    );
  }
}

class _TipoBtn extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final void Function(String) onTap;
  const _TipoBtn(this.label, this.value, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final sel = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? AppTheme.danger.withOpacity(0.12) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? AppTheme.danger : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? AppTheme.danger : AppTheme.textSecondary,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}
