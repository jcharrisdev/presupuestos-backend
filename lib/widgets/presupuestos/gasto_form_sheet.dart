import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class GastoFormSheet {
  static void show(
    BuildContext context, {
    required Future<void> Function(
      String desc,
      double monto,
      String tipo, {
      String tipoFecha,
      int? diaPago,
      String? frecuenciaPago,
      String? fechaPagoExacta,
      bool generaNotificacion,
      int diasAnticipacion,
    }) onGuardado,
  }) {
    final descCtrl  = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo       = 'fijo';
    String tipoFecha  = 'flexible';
    int diaPago       = 1;
    String frecuencia = 'mensual';
    DateTime? fechaExacta;
    bool notif        = false;
    int diasAnticipacion = 3;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Nuevo gasto',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            TextField(controller: descCtrl, style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Descripción')),
            const SizedBox(height: 12),
            TextField(controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00')),

            const SizedBox(height: 16),
            const Text('Tipo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: ['fijo', 'no fijo', 'ahorro'].map((t) => GestureDetector(
              onTap: () => setS(() => tipo = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tipo == t ? AppTheme.gastoColor(t).withOpacity(0.15) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.border),
                ),
                child: Text(AppTheme.gastoLabel(t), style: TextStyle(
                  color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ),
            )).toList()),

            const SizedBox(height: 20),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            const Text('¿Cuándo pagas este gasto?',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              _ToggleBtn('Flexible', tipoFecha == 'flexible', () => setS(() => tipoFecha = 'flexible')),
              const SizedBox(width: 10),
              _ToggleBtn('Fecha fija', tipoFecha == 'fija', () => setS(() => tipoFecha = 'fija'),
                  color: AppTheme.primary),
            ]),

            if (tipoFecha == 'fija') ...[
              const SizedBox(height: 16),
              const Text('Frecuencia', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: ['unico','mensual','quincenal','anual'].map((f) => GestureDetector(
                onTap: () => setS(() => frecuencia = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: frecuencia == f ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: frecuencia == f ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Text(_labelFrecuencia(f), style: TextStyle(
                    color: frecuencia == f ? AppTheme.primary : AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  )),
                ),
              )).toList()),

              const SizedBox(height: 14),
              if (frecuencia != 'unico') ...[
                const Text('Día del mes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: diaPago,
                  dropdownColor: AppTheme.surfaceAlt,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: List.generate(31, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
                  )),
                  onChanged: (v) => setS(() => diaPago = v!),
                ),
              ] else ...[
                const Text('Fecha exacta', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
                          primary: AppTheme.primary, surface: AppTheme.surfaceAlt,
                        )),
                        child: child!,
                      ),
                    );
                    if (picked != null) setS(() => fechaExacta = picked);
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
                        fechaExacta != null
                            ? '${fechaExacta!.year}-${fechaExacta!.month.toString().padLeft(2, "0")}-${fechaExacta!.day.toString().padLeft(2, "0")}'
                            : 'Seleccionar fecha',
                        style: TextStyle(
                          color: fechaExacta != null ? AppTheme.textPrimary : AppTheme.textMuted,
                        ),
                      ),
                    ]),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(children: [
                Checkbox(value: notif, onChanged: (v) => setS(() => notif = v ?? false)),
                const Text('Recordarme antes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                if (notif) ...[
                  const Spacer(),
                  DropdownButton<int>(
                    value: diasAnticipacion,
                    dropdownColor: AppTheme.surfaceAlt,
                    style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                    underline: const SizedBox(),
                    items: [1,2,3,5,7].map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('$d ${d == 1 ? "día" : "días"} antes'),
                    )).toList(),
                    onChanged: (v) => setS(() => diasAnticipacion = v!),
                  ),
                ],
              ]),
            ],

            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await onGuardado(
                  descCtrl.text,
                  double.tryParse(montoCtrl.text) ?? 0,
                  tipo,
                  tipoFecha: tipoFecha,
                  diaPago: tipoFecha == 'fija' && frecuencia != 'unico' ? diaPago : null,
                  frecuenciaPago: tipoFecha == 'fija' ? frecuencia : null,
                  fechaPagoExacta: tipoFecha == 'fija' && frecuencia == 'unico' && fechaExacta != null
                      ? '${fechaExacta!.year}-${fechaExacta!.month.toString().padLeft(2, "0")}-${fechaExacta!.day.toString().padLeft(2, "0")}'
                      : null,
                  generaNotificacion: notif,
                  diasAnticipacion: diasAnticipacion,
                );
              },
              child: const Text('Agregar gasto'),
            )),
          ]),
        ),
      )),
    );
  }
}

String _labelFrecuencia(String f) {
  switch (f) {
    case 'unico':     return 'Único';
    case 'mensual':   return 'Mensual';
    case 'quincenal': return 'Quincenal';
    case 'anual':     return 'Anual';
    default:          return f;
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _ToggleBtn(this.label, this.selected, this.onTap, {this.color = AppTheme.textSecondary});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.12) : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? color : AppTheme.border, width: selected ? 1.5 : 1),
      ),
      child: Text(label, style: TextStyle(
        color: selected ? color : AppTheme.textSecondary,
        fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      )),
    ),
  );
}
