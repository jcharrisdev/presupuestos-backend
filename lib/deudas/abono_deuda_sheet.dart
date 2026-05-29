import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';
import '../services/registros_service.dart';

class AbonoDeudaSheet {
  static void show(
    BuildContext context, {
    required Map<String, dynamic> deuda,
    required String firebaseUid,
    required VoidCallback onAbonado,
  }) {
    final montoCtrl = TextEditingController();
    DateTime? fechaProximoPago;
    bool _guardando = false;

    final montoPendiente = _d(deuda['monto_pendiente']);
    final pagoMinimo     = _d(deuda['pago_minimo']);
    if (pagoMinimo > 0) montoCtrl.text = pagoMinimo.toStringAsFixed(2);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Registrar abono — ${deuda['nombre']}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Saldo pendiente: \$${montoPendiente.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          const SizedBox(height: 16),

          TextField(
            controller: montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
            autofocus: true,
          ),
          const SizedBox(height: 12),

          // Fecha próximo pago
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: DateTime.now().add(const Duration(days: 30)),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      : 'Actualizar fecha próximo pago (opcional)',
                  style: TextStyle(
                    color: fechaProximoPago != null ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _guardando ? null : () async {
              final monto = double.tryParse(montoCtrl.text) ?? 0;
              if (monto <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresa el monto del abono')));
                return;
              }
              setS(() => _guardando = true);
              try {
                await DeudasService.registrarAbono(
                  deuda['id'] as int, firebaseUid, monto,
                  fechaProximoPago: fechaProximoPago?.toIso8601String().substring(0, 10),
                );
                final hoy = DateTime.now();
                final fecha = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
                await RegistrosService.crear(
                  uid: firebaseUid,
                  anio: hoy.year,
                  mes: hoy.month,
                  tipo: 'fijo',
                  categoria: 'deudas',
                  nombre: deuda['nombre'] as String? ?? 'Abono deuda',
                  monto: monto,
                  fecha: fecha,
                  origenDeudaId: deuda['id'] as int,
                  pagado: 1,
                ).catchError((_) => <String, dynamic>{});
                Navigator.pop(ctx);
                onAbonado();
              } catch (e) {
                setS(() => _guardando = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.black),
            child: _guardando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Confirmar abono'),
          )),
        ]),
      )),
    );
  }

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
