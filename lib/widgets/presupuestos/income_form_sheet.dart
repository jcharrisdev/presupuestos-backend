import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/income_service.dart';

const _tiposIngreso = ['salario', 'informal', 'ocasional', 'prestamo', 'otro'];
const _labelTipo = {
  'salario':   'Salario',
  'informal':  'Informal',
  'ocasional': 'Ocasional',
  'prestamo':  'Préstamo devuelto',
  'otro':      'Otro',
};

class IncomeFormSheet {
  static void show(
    BuildContext context, {
    required int presupuestoId,
    required String firebaseUid,
    Map<String, dynamic>? incomeActual,
    required void Function(Map<String, dynamic> income) onGuardado,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IncomeFormContent(
        presupuestoId: presupuestoId,
        firebaseUid: firebaseUid,
        incomeActual: incomeActual,
        onGuardado: onGuardado,
      ),
    );
  }
}

class _IncomeFormContent extends StatefulWidget {
  final int presupuestoId;
  final String firebaseUid;
  final Map<String, dynamic>? incomeActual;
  final void Function(Map<String, dynamic>) onGuardado;

  const _IncomeFormContent({
    required this.presupuestoId,
    required this.firebaseUid,
    required this.incomeActual,
    required this.onGuardado,
  });

  @override
  State<_IncomeFormContent> createState() => _IncomeFormContentState();
}

class _IncomeFormContentState extends State<_IncomeFormContent> {
  String _tipo = 'salario';
  final _brutoCtrl     = TextEditingController();
  final _seguroCtrl    = TextEditingController(text: '0');
  final _pensionCtrl   = TextEditingController(text: '0');
  final _impuestoCtrl  = TextEditingController(text: '0');
  final _otrosCtrl     = TextEditingController(text: '0');
  final _netoCtrl      = TextEditingController();
  final _notaCtrl      = TextEditingController();
  bool _guardando = false;
  bool _calcularAutomatico = false;

  double get _netoCalculado {
    if (_tipo != 'salario') return 0;
    final bruto    = double.tryParse(_brutoCtrl.text.replaceAll(',', '.'))    ?? 0;
    final seguro   = double.tryParse(_seguroCtrl.text.replaceAll(',', '.'))   ?? 0;
    final pension  = double.tryParse(_pensionCtrl.text.replaceAll(',', '.'))  ?? 0;
    final impuesto = double.tryParse(_impuestoCtrl.text.replaceAll(',', '.')) ?? 0;
    final otros    = double.tryParse(_otrosCtrl.text.replaceAll(',', '.'))    ?? 0;
    return bruto - seguro - pension - impuesto - otros;
  }

  // Panamá: CSS 9.75%, Educativo (IFARHU) 1.25%, ISR solo si bruto > 916.67
  void _autoCalcular() {
    if (!_calcularAutomatico || _tipo != 'salario') return;
    final bruto = double.tryParse(_brutoCtrl.text.replaceAll(',', '.')) ?? 0;
    final css       = bruto * 0.0975;
    final educativo = bruto * 0.0125;
    final isr       = bruto > 916.67 ? (bruto - 916.67) * 0.15 : 0.0;
    _seguroCtrl.text   = css.toStringAsFixed(2);
    _pensionCtrl.text  = educativo.toStringAsFixed(2);
    _impuestoCtrl.text = isr.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    final inc = widget.incomeActual;
    if (inc != null) {
      _tipo = inc['tipo_ingreso'] ?? 'salario';
      _calcularAutomatico = (inc['calcular_automatico'] == 1 || inc['calcular_automatico'] == true);
      if (_tipo == 'salario') {
        _brutoCtrl.text    = _fmt(inc['ingreso_bruto']);
        _seguroCtrl.text   = _fmt(inc['desc_seguro']);
        _pensionCtrl.text  = _fmt(inc['desc_pension']);
        _impuestoCtrl.text = _fmt(inc['desc_impuesto']);
        _otrosCtrl.text    = _fmt(inc['desc_otros']);
      } else {
        _netoCtrl.text = _fmt(inc['ingreso_neto']);
      }
      _notaCtrl.text = inc['nota'] ?? '';
    }
    _brutoCtrl.addListener(() {
      _autoCalcular();
      setState(() {});
    });
    for (final c in [_seguroCtrl, _pensionCtrl, _impuestoCtrl, _otrosCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final d = double.tryParse(v.toString()) ?? 0;
    return d == 0 ? '0' : d.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in [_brutoCtrl, _seguroCtrl, _pensionCtrl, _impuestoCtrl, _otrosCtrl, _netoCtrl, _notaCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final body = <String, dynamic>{
      'firebase_uid': widget.firebaseUid,
      'tipo_ingreso': _tipo,
      'nota': _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
    };

    if (_tipo == 'salario') {
      final bruto = double.tryParse(_brutoCtrl.text.replaceAll(',', '.')) ?? 0;
      if (bruto <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un ingreso bruto válido')));
        return;
      }
      body['ingreso_bruto']         = bruto;
      body['desc_seguro']           = double.tryParse(_seguroCtrl.text.replaceAll(',', '.'))   ?? 0;
      body['desc_pension']          = double.tryParse(_pensionCtrl.text.replaceAll(',', '.'))  ?? 0;
      body['desc_impuesto']         = double.tryParse(_impuestoCtrl.text.replaceAll(',', '.')) ?? 0;
      body['desc_otros']            = double.tryParse(_otrosCtrl.text.replaceAll(',', '.'))    ?? 0;
      body['calcular_automatico']   = _calcularAutomatico ? 1 : 0;
      body['ingreso_bruto_mensual'] = bruto;
    } else {
      final neto = double.tryParse(_netoCtrl.text.replaceAll(',', '.')) ?? 0;
      if (neto <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un monto válido')));
        return;
      }
      body['ingreso_neto'] = neto;
    }

    setState(() => _guardando = true);
    try {
      final saved = await IncomeService.upsertIncome(widget.presupuestoId, body);
      if (mounted) Navigator.pop(context);
      widget.onGuardado(saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Configurar ingreso',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // Tipo de ingreso
                  const Text('Tipo de ingreso',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _tiposIngreso.map((t) {
                      final sel = t == _tipo;
                      return ChoiceChip(
                        label: Text(_labelTipo[t]!),
                        selected: sel,
                        onSelected: (_) => setState(() => _tipo = t),
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.surfaceAlt,
                        labelStyle: TextStyle(
                          color: sel ? Colors.black : AppTheme.textPrimary,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  if (_tipo == 'salario') ...[
                    _buildMontoField('Ingreso bruto', _brutoCtrl),
                    const SizedBox(height: 12),
                    const Divider(color: AppTheme.border),
                    const SizedBox(height: 8),
                    // Toggle auto-cálculo Panamá
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Calcular deducciones (Panamá)',
                                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text('CSS 9.75% · Educativo 1.25% · ISR automático',
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _calcularAutomatico,
                          activeColor: AppTheme.primary,
                          onChanged: (v) {
                            setState(() => _calcularAutomatico = v);
                            if (v) _autoCalcular();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildMontoField('Seguro Social (CSS)', _seguroCtrl,
                        readOnly: _calcularAutomatico),
                    const SizedBox(height: 10),
                    _buildMontoField('Educativo (IFARHU)', _pensionCtrl,
                        readOnly: _calcularAutomatico),
                    const SizedBox(height: 10),
                    _buildMontoField('Impuesto sobre renta', _impuestoCtrl,
                        readOnly: _calcularAutomatico),
                    const SizedBox(height: 10),
                    _buildMontoField('Otros descuentos', _otrosCtrl),
                    const SizedBox(height: 16),
                    // Preview neto
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ingreso neto disponible',
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          Text(
                            '\$${_netoCalculado.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _netoCalculado >= 0 ? AppTheme.success : AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _buildMontoField('Monto que recibes', _netoCtrl),
                  ],

                  const SizedBox(height: 16),
                  TextField(
                    controller: _notaCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Nota (opcional)',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.surfaceAlt,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _guardando
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Guardar ingreso',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMontoField(String label, TextEditingController ctrl,
      {bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      style: TextStyle(
          color: readOnly ? AppTheme.textMuted : AppTheme.textPrimary),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixText: '\$ ',
        prefixStyle: const TextStyle(color: AppTheme.textSecondary),
        filled: true,
        fillColor: readOnly
            ? AppTheme.surfaceAlt.withValues(alpha: 0.6)
            : AppTheme.surfaceAlt,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
        suffixIcon: readOnly
            ? const Icon(Icons.calculate_outlined,
                color: AppTheme.textMuted, size: 16)
            : null,
      ),
    );
  }
}
