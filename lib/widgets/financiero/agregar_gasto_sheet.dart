import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/registros_service.dart';
import '../../services/gastos_variables_service.dart';

class AgregarGastoSheet extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final int mes;

  const AgregarGastoSheet({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    required this.mes,
  }) : super(key: key);

  @override
  State<AgregarGastoSheet> createState() => _AgregarGastoSheetState();
}

class _AgregarGastoSheetState extends State<AgregarGastoSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _nombre   = TextEditingController();
  final _monto    = TextEditingController();
  final _notas    = TextEditingController();

  String _tipo      = 'variable';
  String _categoria = 'alimentacion';
  DateTime _fecha   = DateTime.now();
  bool _guardando   = false;
  bool _guardarComoBase = false;

  static const _tipos = [
    {'value': 'fijo',             'label': 'Gasto fijo',             'icon': Icons.lock_clock,          'color': AppTheme.colorFijo},
    {'value': 'variable',         'label': 'Gasto variable',         'icon': Icons.shopping_bag,         'color': AppTheme.warning},
    {'value': 'no_presupuestado', 'label': 'No presupuestado',       'icon': Icons.add_shopping_cart,    'color': AppTheme.danger},
  ];

  static const _categorias = [
    {'value': 'alimentacion', 'label': 'Alimentación', 'icon': Icons.restaurant},
    {'value': 'transporte',   'label': 'Transporte',   'icon': Icons.directions_car},
    {'value': 'vivienda',     'label': 'Vivienda',     'icon': Icons.home},
    {'value': 'salud',        'label': 'Salud',        'icon': Icons.local_hospital},
    {'value': 'educacion',    'label': 'Educación',    'icon': Icons.school},
    {'value': 'ocio',         'label': 'Ocio',         'icon': Icons.sports_esports},
    {'value': 'deudas',       'label': 'Deudas',       'icon': Icons.account_balance},
    {'value': 'ropa',         'label': 'Ropa',         'icon': Icons.checkroom},
    {'value': 'deportes',     'label': 'Deportes',     'icon': Icons.fitness_center},
    {'value': 'familia',      'label': 'Familia',      'icon': Icons.family_restroom},
    {'value': 'tecnologia',   'label': 'Tecnología',   'icon': Icons.devices},
    {'value': 'emergencias',  'label': 'Emergencias',  'icon': Icons.warning},
    {'value': 'otro',         'label': 'Otro',         'icon': Icons.receipt},
  ];

  @override
  void dispose() {
    _nombre.dispose(); _monto.dispose(); _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            const Text('Agregar gasto', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Tipo
            const Text('TIPO', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: _tipos.map((t) {
              final sel = _tipo == t['value'];
              final color = t['color'] as Color;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _tipo = t['value'] as String),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? color.withOpacity(0.12) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? color : AppTheme.border, width: sel ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(t['icon'] as IconData, color: sel ? color : AppTheme.textMuted, size: 18),
                    const SizedBox(height: 4),
                    Text(t['label'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: sel ? color : AppTheme.textMuted,
                            fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                  ]),
                ),
              ));
            }).toList()),
            const SizedBox(height: 16),

            // Nombre
            TextFormField(
              controller: _nombre,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre del gasto'),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),

            // Monto
            TextFormField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Monto (\$)', prefixText: '\$ '),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requerido';
                if (double.tryParse(v) == null) return 'Número inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Categoría
            const Text('CATEGORÍA', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _categorias.map((c) {
                  final sel = _categoria == c['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _categoria = c['value'] as String),
                    child: Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? AppTheme.primary : AppTheme.border, width: sel ? 1.5 : 1),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(c['icon'] as IconData,
                            color: sel ? AppTheme.primary : AppTheme.textMuted, size: 20),
                        const SizedBox(height: 4),
                        Text(c['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: sel ? AppTheme.primary : AppTheme.textMuted,
                                fontSize: 9, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Fecha
            GestureDetector(
              onTap: _seleccionarFecha,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 10),
                  Text(DateFormat('dd MMM yyyy', 'es').format(_fecha),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // Notas
            TextFormField(
              controller: _notas,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              maxLines: 1,
            ),
            const SizedBox(height: 12),

            // Guardar como variable base (solo para tipo variable/no-presupuestado)
            if (_tipo != 'fijo')
              Row(children: [
                Checkbox(
                  value: _guardarComoBase,
                  onChanged: (v) => setState(() => _guardarComoBase = v ?? false),
                ),
                const Expanded(
                  child: Text('Agregar a mis gastos variables base\n(aparecerá en futuros presupuestos)',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
              ]),
            const SizedBox(height: 20),

            // Botón guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background))
                    : const Text('Guardar gasto'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(widget.anio, widget.mes, 1),
      lastDate: DateTime(widget.anio, widget.mes + 1, 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await RegistrosService.crear(
        uid: widget.firebaseUid,
        anio: widget.anio,
        mes: widget.mes,
        tipo: _tipo,
        categoria: _categoria,
        nombre: _nombre.text.trim(),
        monto: double.parse(_monto.text),
        fecha: DateFormat('yyyy-MM-dd').format(_fecha),
        notas: _notas.text.isEmpty ? null : _notas.text.trim(),
      );

      // Si el usuario quiere guardar como base
      if (_guardarComoBase && _tipo != 'fijo') {
        await GastosVariablesService.crear(
          uid: widget.firebaseUid,
          nombre: _nombre.text.trim(),
          categoria: _categoria,
          montoEstimado: double.parse(_monto.text),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}
