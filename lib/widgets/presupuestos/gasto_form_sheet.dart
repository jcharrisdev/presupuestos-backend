import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

const _subcategorias = [
  'supermercado', 'gasolina', 'educación', 'entretenimiento',
  'salud', 'restaurantes', 'ropa', 'transporte',
  'mantenimiento', 'tecnología', 'hogar', 'otros',
];

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
      String? subcategoria,
      String? clasificacion,
      bool tipoDeuda,
      bool descuentoDirecto,
      DateTime? fechaFin,
      int? numCuotas,
    }) onGuardado,
  }) {
    final descCtrl    = TextEditingController();
    final montoCtrl   = TextEditingController();
    final cuotasCtrl  = TextEditingController();
    String tipo             = 'fijo';
    String tipoFecha        = 'flexible';
    int diaPago             = 1;
    String frecuencia       = 'mensual';
    DateTime? fechaExacta;
    bool notif              = false;
    int diasAnticipacion    = 3;
    String? subcategoria;
    String? clasificacion;
    bool descuentoDirecto   = false;
    DateTime? fechaFin;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
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
            Wrap(spacing: 8, children: ['fijo', 'no fijo', 'ahorro', 'deuda'].map((t) => GestureDetector(
              onTap: () => setS(() { tipo = t; if (t != 'deuda') descuentoDirecto = false; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tipo == t ? AppTheme.gastoColor(t).withValues(alpha: 0.15) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.border),
                ),
                child: Text(AppTheme.gastoLabel(t), style: TextStyle(
                  color: tipo == t ? AppTheme.gastoColor(t) : AppTheme.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ),
            )).toList()),

            // Campos específicos de deuda
            if (tipo == 'deuda') ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Descuento directo del salario',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Text('Se descuenta automáticamente de tu ingreso',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ]),
                  Switch(
                    value: descuentoDirecto,
                    activeColor: AppTheme.colorDeuda,
                    onChanged: (v) => setS(() => descuentoDirecto = v),
                  ),
                ],
              ),
            ],

            // Fecha de fin (deuda y variable: opcional)
            if (tipo == 'deuda' || tipo == 'no fijo') ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primary, surface: AppTheme.surfaceAlt,
                      )),
                      child: child!,
                    ),
                  );
                  if (picked != null) setS(() => fechaFin = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: fechaFin != null ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.event_available_outlined,
                        color: fechaFin != null ? AppTheme.primary : AppTheme.textSecondary,
                        size: 16),
                    const SizedBox(width: 10),
                    Text(
                      fechaFin != null
                          ? 'Vence: ${fechaFin!.year}-${fechaFin!.month.toString().padLeft(2,"0")}-${fechaFin!.day.toString().padLeft(2,"0")}'
                          : tipo == 'deuda' ? 'Fecha de pago final (opcional)' : 'Fecha de fin (opcional)',
                      style: TextStyle(
                        color: fechaFin != null ? AppTheme.textPrimary : AppTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    if (fechaFin != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setS(() => fechaFin = null),
                        child: const Icon(Icons.close, color: AppTheme.textMuted, size: 16),
                      ),
                    ],
                  ]),
                ),
              ),
            ],

            // Cuotas (variable: opcional)
            if (tipo == 'no fijo') ...[
              const SizedBox(height: 10),
              TextField(
                controller: cuotasCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Número de cuotas (opcional)',
                  prefixIcon: Icon(Icons.format_list_numbered, color: AppTheme.textSecondary, size: 18),
                ),
              ),
            ],

            // ── CLASIFICACIÓN FINANCIERA ─────────────────────────────────────
            const SizedBox(height: 16),
            const Text('Clasificación financiera (opcional)',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              _ClasifBtn('Esencial', 'esencial', const Color(0xFF1890FF), clasificacion,
                  (v) => setS(() => clasificacion = clasificacion == v ? null : v)),
              _ClasifBtn('Importante', 'importante', AppTheme.primary, clasificacion,
                  (v) => setS(() => clasificacion = clasificacion == v ? null : v)),
              _ClasifBtn('Flexible', 'flexible', AppTheme.success, clasificacion,
                  (v) => setS(() => clasificacion = clasificacion == v ? null : v)),
            ]),

            // ── SUBCATEGORÍA ────────────────────────────────────────────────
            const SizedBox(height: 16),
            const Text('Subcategoría (opcional)',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ..._subcategorias.map((s) => GestureDetector(
                onTap: () => setS(() => subcategoria = subcategoria == s ? null : s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: subcategoria == s
                        ? AppTheme.primary.withOpacity(0.15)
                        : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: subcategoria == s ? AppTheme.primary : AppTheme.border,
                    ),
                  ),
                  child: Text(s, style: TextStyle(
                    color: subcategoria == s ? AppTheme.primary : AppTheme.textMuted,
                    fontSize: 11, fontWeight: FontWeight.w500,
                  )),
                ),
              )),
            ]),

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
                final tipoReal = tipo == 'deuda' ? 'fijo' : tipo;
                await onGuardado(
                  descCtrl.text,
                  double.tryParse(montoCtrl.text) ?? 0,
                  tipoReal,
                  tipoFecha: tipoFecha,
                  diaPago: tipoFecha == 'fija' && frecuencia != 'unico' ? diaPago : null,
                  frecuenciaPago: tipoFecha == 'fija' ? frecuencia : null,
                  fechaPagoExacta: tipoFecha == 'fija' && frecuencia == 'unico' && fechaExacta != null
                      ? '${fechaExacta!.year}-${fechaExacta!.month.toString().padLeft(2, "0")}-${fechaExacta!.day.toString().padLeft(2, "0")}'
                      : null,
                  generaNotificacion: notif,
                  diasAnticipacion: diasAnticipacion,
                  subcategoria: subcategoria,
                  clasificacion: clasificacion,
                  tipoDeuda: tipo == 'deuda',
                  descuentoDirecto: descuentoDirecto,
                  fechaFin: fechaFin,
                  numCuotas: int.tryParse(cuotasCtrl.text.trim()),
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

class _ClasifBtn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? selected;
  final void Function(String) onTap;
  const _ClasifBtn(this.label, this.value, this.color, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? color : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? color : AppTheme.textSecondary,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ),
    );
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
