import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/income_service.dart';
import 'widgets/presupuestos/gasto_form_sheet.dart';

class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;
  const CrearPresupuesto({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CrearPresupuestoState createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final _pageCtrl = PageController();
  int _step = 0;

  // ── Paso 0 — Básicos ─────────────────────────────────────────────────────
  final _nombreCtrl = TextEditingController();
  String _tipoPeriodo = 'mensual';
  int _diaInicio = 1;

  // ── Paso 1 — Ingreso (inline, sin modal) ─────────────────────────────────
  String _tipoIngreso = 'salario';
  final _brutoCtrl     = TextEditingController();
  final _seguroCtrl    = TextEditingController(text: '0');
  final _pensionCtrl   = TextEditingController(text: '0');
  final _impuestoCtrl  = TextEditingController(text: '0');
  final _otrosCtrl     = TextEditingController(text: '0');
  final _netoCtrl      = TextEditingController();
  bool _calcularAutomatico = false;
  bool _incomeConfigurado = false;

  // ── Paso 2 — Gastos ───────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _gastosStep2 = [];

  bool _loading = false;

  // ── Helpers de ingreso ────────────────────────────────────────────────────
  double get _netoCalculado {
    if (_tipoIngreso != 'salario') return 0;
    final bruto    = _parseD(_brutoCtrl.text);
    final seguro   = _parseD(_seguroCtrl.text);
    final pension  = _parseD(_pensionCtrl.text);
    final impuesto = _parseD(_impuestoCtrl.text);
    final otros    = _parseD(_otrosCtrl.text);
    return bruto - seguro - pension - impuesto - otros;
  }

  double _parseD(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  void _autoCalcular() {
    if (!_calcularAutomatico || _tipoIngreso != 'salario') return;
    final bruto = _parseD(_brutoCtrl.text);
    _seguroCtrl.text   = (bruto * 0.0975).toStringAsFixed(2);
    _pensionCtrl.text  = (bruto * 0.0125).toStringAsFixed(2);
    _impuestoCtrl.text = max(0, (bruto - 916.67) * 0.15).toStringAsFixed(2);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _brutoCtrl.addListener(() { _autoCalcular(); setState(() {}); });
    for (final c in [_seguroCtrl, _pensionCtrl, _impuestoCtrl, _otrosCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in [_nombreCtrl, _brutoCtrl, _seguroCtrl, _pensionCtrl,
        _impuestoCtrl, _otrosCtrl, _netoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  // ── Submit final ─────────────────────────────────────────────────────────
  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un nombre para el presupuesto')));
      return;
    }

    // Calcular monto_total: ingreso neto si configurado, sino pide monto
    double montoTotal = 0;
    if (_tipoIngreso == 'salario' && _netoCalculado > 0) {
      montoTotal = _netoCalculado;
    } else if (_tipoIngreso != 'salario') {
      montoTotal = _parseD(_netoCtrl.text);
    }
    if (montoTotal <= 0) montoTotal = 1000; // fallback si no hay income

    setState(() => _loading = true);
    try {
      // 1. Crear presupuesto
      final res = await ApiClient.post('/presupuestos', {
        'nombre': nombre,
        'monto_total': montoTotal,
        'firebase_uid': widget.firebaseUid,
        'tipo_periodo': _tipoPeriodo,
        'dia_inicio_periodo': _diaInicio,
      });
      if (res.statusCode != 201) throw Exception(json.decode(res.body)['error'] ?? 'Error');
      final presupuestoId = json.decode(res.body)['id'] as int;

      // 2. Guardar income si fue configurado
      if (_incomeConfigurado) {
        final incBody = <String, dynamic>{
          'firebase_uid': widget.firebaseUid,
          'tipo_ingreso': _tipoIngreso,
          'calcular_automatico': _calcularAutomatico ? 1 : 0,
        };
        if (_tipoIngreso == 'salario') {
          incBody['ingreso_bruto']  = _parseD(_brutoCtrl.text);
          incBody['desc_seguro']    = _parseD(_seguroCtrl.text);
          incBody['desc_pension']   = _parseD(_pensionCtrl.text);
          incBody['desc_impuesto']  = _parseD(_impuestoCtrl.text);
          incBody['desc_otros']     = _parseD(_otrosCtrl.text);
        } else {
          incBody['ingreso_neto'] = _parseD(_netoCtrl.text);
        }
        await IncomeService.upsertIncome(presupuestoId, incBody);
      }

      // 3. Guardar gastos del paso 2
      for (final g in _gastosStep2) {
        try {
          final gBody = Map<String, dynamic>.from(g)
            ..['presupuesto_id'] = presupuestoId
            ..['firebase_uid']   = widget.firebaseUid
            ..['fecha']          = DateTime.now().toIso8601String().split('T')[0];
          final gRes = await ApiClient.post('/gastos', gBody);
          if (gRes.statusCode == 201) {
            final tipo = g['tipo'] as String? ?? '';
            if (tipo == 'fijo' || tipo == 'ahorro') {
              final gid = json.decode(gRes.body)['id'] as int?;
              if (gid != null) {
                await ApiClient.post('/presupuestos/$presupuestoId/movimientos', {
                  'firebase_uid': widget.firebaseUid,
                  'items': [{'gasto_id': gid, 'monto': g['monto']}],
                });
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Nuevo Presupuesto'),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goTo(_step - 1),
              )
            : null,
      ),
      body: Column(children: [
        // Indicador de paso
        _StepDots(current: _step),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildPaso0(),
              _buildPaso1(),
              _buildPaso2(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Paso 0 — Básicos ─────────────────────────────────────────────────────
  Widget _buildPaso0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Información básica',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Ponle nombre a tu presupuesto y define el ciclo.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 24),

        _label('Nombre del presupuesto'),
        TextField(
          controller: _nombreCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Ej: Casa, Trabajo, Personal...'),
        ),
        const SizedBox(height: 20),

        _label('Tipo de período'),
        Row(children: [
          _PeriodOption(label: 'Quincenal', sub: '14 días',
              selected: _tipoPeriodo == 'quincenal',
              onTap: () => setState(() => _tipoPeriodo = 'quincenal')),
          const SizedBox(width: 12),
          _PeriodOption(label: 'Mensual', sub: '30 días',
              selected: _tipoPeriodo == 'mensual',
              onTap: () => setState(() => _tipoPeriodo = 'mensual')),
        ]),
        const SizedBox(height: 20),

        _label('Día de inicio del período'),
        DropdownButtonFormField<int>(
          value: _diaInicio,
          dropdownColor: AppTheme.surfaceAlt,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(),
          items: List.generate(31, (i) => DropdownMenuItem(
            value: i + 1,
            child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
          )),
          onChanged: (v) => setState(() => _diaInicio = v!),
        ),
        const SizedBox(height: 36),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (_nombreCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresa un nombre')));
                return;
              }
              _goTo(1);
            },
            child: const Text('Siguiente →'),
          ),
        ),
      ]),
    );
  }

  // ── Paso 1 — Ingreso ─────────────────────────────────────────────────────
  Widget _buildPaso1() {
    final tiposIngreso = ['salario', 'informal', 'ocasional', 'otro'];
    final labelTipo = {'salario': 'Salario', 'informal': 'Informal',
        'ocasional': 'Ocasional', 'otro': 'Otro'};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿Cuánto ganas?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Define tu ingreso para calcular tu capacidad real de pago.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 24),

        // Tipo de ingreso
        _label('Tipo de ingreso'),
        Wrap(
          spacing: 8,
          children: tiposIngreso.map((t) {
            final sel = t == _tipoIngreso;
            return GestureDetector(
              onTap: () => setState(() { _tipoIngreso = t; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? AppTheme.primary : AppTheme.border),
                ),
                child: Text(labelTipo[t]!, style: TextStyle(
                  color: sel ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13,
                )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        if (_tipoIngreso == 'salario') ...[
          _buildMontoField('Ingreso bruto', _brutoCtrl),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 8),

          // Toggle auto-cálculo Panamá
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Calcular deducciones (Panamá)',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
              Text('CSS 9.75% · Educativo 1.25% · ISR automático',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ])),
            Switch(
              value: _calcularAutomatico,
              activeColor: AppTheme.primary,
              onChanged: (v) { setState(() => _calcularAutomatico = v); if (v) _autoCalcular(); },
            ),
          ]),
          const SizedBox(height: 12),
          _buildMontoField('Seguro Social (CSS)', _seguroCtrl, readOnly: _calcularAutomatico),
          const SizedBox(height: 8),
          _buildMontoField('Educativo (IFARHU)', _pensionCtrl, readOnly: _calcularAutomatico),
          const SizedBox(height: 8),
          _buildMontoField('Impuesto sobre renta', _impuestoCtrl, readOnly: _calcularAutomatico),
          const SizedBox(height: 8),
          _buildMontoField('Otros descuentos', _otrosCtrl),
          const SizedBox(height: 16),

          // Preview neto
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Ingreso neto disponible',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
              Text('\$${_netoCalculado.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: _netoCalculado >= 0 ? AppTheme.success : AppTheme.danger)),
            ]),
          ),
        ] else ...[
          _buildMontoField('Monto que recibes', _netoCtrl),
        ],

        const SizedBox(height: 32),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () { setState(() => _incomeConfigurado = false); _goTo(2); },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
            ),
            child: const Text('Omitir'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () {
              final tieneValor = _tipoIngreso == 'salario'
                  ? _parseD(_brutoCtrl.text) > 0
                  : _parseD(_netoCtrl.text) > 0;
              setState(() => _incomeConfigurado = tieneValor);
              _goTo(2);
            },
            child: const Text('Siguiente →'),
          )),
        ]),
      ]),
    );
  }

  // ── Paso 2 — Gastos ───────────────────────────────────────────────────────
  Widget _buildPaso2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tus gastos recurrentes',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Agrega tus gastos fijos y deudas. Puedes saltarte este paso.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 24),

        // Lista de gastos agregados
        if (_gastosStep2.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Column(children: [
              Icon(Icons.receipt_long_outlined, color: AppTheme.textMuted, size: 32),
              SizedBox(height: 8),
              Text('Sin gastos agregados', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ]),
          )
        else
          ..._gastosStep2.asMap().entries.map((e) {
            final i = e.key;
            final g = e.value;
            final tipo = g['tipo'] as String? ?? 'fijo';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.gastoColor(tipo),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(g['descripcion'] as String? ?? '',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
                Text('\$${(g['monto'] as double).toStringAsFixed(2)}',
                    style: TextStyle(color: AppTheme.gastoColor(tipo),
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _gastosStep2.removeAt(i)),
                  child: const Icon(Icons.close, color: AppTheme.textMuted, size: 16),
                ),
              ]),
            );
          }),

        const SizedBox(height: 16),

        // Botón agregar gasto
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => GastoFormSheet.show(
              context,
              onGuardado: (desc, monto, tipo, {
                tipoFecha = 'flexible', diaPago, frecuenciaPago, fechaPagoExacta,
                generaNotificacion = false, diasAnticipacion = 3,
                subcategoria, clasificacion,
                tipoDeuda = false, descuentoDirecto = false, fechaFin, numCuotas,
              }) async {
                final tipoReal = tipoDeuda ? 'fijo' : tipo;
                final entry = <String, dynamic>{
                  'descripcion': desc,
                  'monto': monto,
                  'tipo': tipoReal,
                  'tipo_fecha': tipoFecha,
                  'genera_notificacion': generaNotificacion,
                  'dias_anticipacion': diasAnticipacion,
                };
                if (clasificacion != null) entry['clasificacion'] = clasificacion;
                if (subcategoria != null) entry['subcategoria'] = subcategoria;
                if (tipoDeuda) {
                  entry['tipo_deuda'] = 1;
                  entry['descuento_directo'] = descuentoDirecto ? 1 : 0;
                }
                if (fechaFin != null) {
                  entry['fecha_fin'] =
                      '${fechaFin.year}-${fechaFin.month.toString().padLeft(2,"0")}-${fechaFin.day.toString().padLeft(2,"0")}';
                }
                if (numCuotas != null) entry['num_cuotas'] = numCuotas;
                if (diaPago != null) entry['dia_pago'] = diaPago;
                if (frecuenciaPago != null) entry['frecuencia_pago'] = frecuenciaPago;
                setState(() => _gastosStep2.add(entry));
              },
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Agregar gasto'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),

        const SizedBox(height: 32),

        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _loading ? null : _crear,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
            ),
            child: const Text('Omitir gastos'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: _loading ? null : _crear,
            child: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Crear presupuesto'),
          )),
        ]),
      ]),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
  );

  Widget _buildMontoField(String label, TextEditingController ctrl,
      {bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      style: TextStyle(color: readOnly ? AppTheme.textMuted : AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixText: '\$ ',
        prefixStyle: const TextStyle(color: AppTheme.textSecondary),
        filled: true,
        fillColor: readOnly ? AppTheme.surfaceAlt.withValues(alpha: 0.6) : AppTheme.surfaceAlt,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        suffixIcon: readOnly
            ? const Icon(Icons.calculate_outlined, color: AppTheme.textMuted, size: 16)
            : null,
      ),
    );
  }
}

// ── Indicador de progreso de 3 pasos ─────────────────────────────────────────
class _StepDots extends StatelessWidget {
  final int current;
  const _StepDots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == current ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == current ? AppTheme.primary : AppTheme.border,
            borderRadius: BorderRadius.circular(4),
          ),
        )),
      ),
    );
  }
}

// ── Botón de toggle para tipo de período ──────────────────────────────────────
class _PeriodOption extends StatelessWidget {
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodOption({required this.label, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 14,
            )),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(
              color: selected ? AppTheme.primary.withValues(alpha: 0.7) : AppTheme.textMuted,
              fontSize: 11,
            )),
          ]),
        ),
      ),
    );
  }
}
