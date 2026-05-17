import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/registros_service.dart';
import '../../services/gastos_variables_service.dart';
import 'mes_rango_selector.dart';
import 'categoria_selector.dart';

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

  String _tipo           = 'variable';
  String _categoria      = 'alimentacion';
  String? _categoriaCustom;
  late DateTime _fecha;
  bool _guardando        = false;
  bool _guardarComoBase  = false;
  // Período para gastos variables (solo si guardarComoBase = true)
  int _mesInicio = 1;
  int _mesFin    = 12;

  static const _tipos = [
    {'value': 'fijo',             'label': 'Gasto fijo',       'icon': Icons.lock_clock,       'color': AppTheme.colorFijo},
    {'value': 'variable',         'label': 'Variable',          'icon': Icons.shopping_bag,     'color': AppTheme.warning},
    {'value': 'no_presupuestado', 'label': 'No presupuestado', 'icon': Icons.add_shopping_cart, 'color': AppTheme.danger},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = (widget.anio == now.year && widget.mes == now.month)
        ? now
        : DateTime(widget.anio, widget.mes, 1);
    _mesInicio = widget.mes;
    _mesFin    = 12;
  }

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
            const Text('Agregar gasto',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // ── Tipo ─────────────────────────────────────────────────────────
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
                    color: sel ? color.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
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

            // ── Nombre ───────────────────────────────────────────────────────
            TextFormField(
              controller: _nombre,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre del gasto'),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),

            // ── Monto ────────────────────────────────────────────────────────
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
            const SizedBox(height: 16),

            // ── Categoría con "Otro" personalizable ───────────────────────
            CategoriaSelector(
              firebaseUid: widget.firebaseUid,
              categoriaActual: _categoria,
              color: _tipo == 'fijo' ? AppTheme.colorFijo
                   : _tipo == 'no_presupuestado' ? AppTheme.danger
                   : AppTheme.warning,
              onChanged: (cat, custom) => setState(() {
                _categoria      = cat;
                _categoriaCustom = custom;
              }),
            ),
            const SizedBox(height: 16),

            // ── Fecha (dentro del mes visualizado) ────────────────────────
            GestureDetector(
              onTap: _seleccionarFecha,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6),
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

            // ── Notas ────────────────────────────────────────────────────
            TextFormField(
              controller: _notas,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 16),

            // ── Guardar como variable base (solo para variable/no-presup) ─
            if (_tipo != 'fijo') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Checkbox(
                      value: _guardarComoBase,
                      onChanged: (v) => setState(() => _guardarComoBase = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'Agregar a mi presupuesto variable base',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ]),
                  // Período: solo visible si va a guardar como base
                  if (_guardarComoBase) ...[
                    const SizedBox(height: 12),
                    MesRangoSelector(
                      mesInicio: _mesInicio,
                      mesFin: _mesFin,
                      onChange: (i, f) => setState(() { _mesInicio = i; _mesFin = f; }),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Botón guardar ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background))
                    : const Text('Guardar gasto'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final lastDay = DateTime(widget.anio, widget.mes + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(widget.anio, widget.mes, 1),
      lastDate: lastDay,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    // Si "Otro" sin texto personalizado, pedir que escriban
    if (_categoria == 'otro' && (_categoriaCustom == null || _categoriaCustom!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el nombre de la categoría personalizada')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final categoriaFinal = (_categoria == 'otro' && _categoriaCustom != null)
          ? _categoriaCustom!
          : _categoria;
      await RegistrosService.crear(
        uid: widget.firebaseUid, anio: widget.anio, mes: widget.mes,
        tipo: _tipo, categoria: categoriaFinal,
        nombre: _nombre.text.trim(),
        monto: double.parse(_monto.text),
        fecha: DateFormat('yyyy-MM-dd').format(_fecha),
        notas: _notas.text.isEmpty ? null : _notas.text.trim(),
      );
      if (_guardarComoBase && _tipo != 'fijo') {
        await GastosVariablesService.crear(
          uid: widget.firebaseUid, nombre: _nombre.text.trim(),
          categoria: categoriaFinal,
          montoEstimado: double.parse(_monto.text),
          mesInicio: _mesInicio, mesFin: _mesFin,
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
