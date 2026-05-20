import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';

class CrearDeudaSheet {
  static void show(
    BuildContext context, {
    required String firebaseUid,
    required VoidCallback onCreada,
    Map<String, dynamic>? deudaExistente,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _CrearDeudaForm(
        firebaseUid: firebaseUid,
        onCreada: onCreada,
        deudaExistente: deudaExistente,
      ),
    );
  }
}

class _CrearDeudaForm extends StatefulWidget {
  final String firebaseUid;
  final VoidCallback onCreada;
  final Map<String, dynamic>? deudaExistente;
  const _CrearDeudaForm({
    required this.firebaseUid,
    required this.onCreada,
    this.deudaExistente,
  });

  @override
  State<_CrearDeudaForm> createState() => _CrearDeudaFormState();
}

class _CrearDeudaFormState extends State<_CrearDeudaForm> {
  final _nombreCtrl      = TextEditingController();
  final _totalCtrl       = TextEditingController();
  final _pendienteCtrl   = TextEditingController();
  final _tasaCtrl        = TextEditingController();
  final _plazoCtrl       = TextEditingController();
  final _pagoMinCtrl     = TextEditingController();
  final _cuotaFijaCtrl   = TextEditingController();
  final _numCuotasCtrl   = TextEditingController();
  final _acreedorCtrl    = TextEditingController();
  final _notasCtrl       = TextEditingController();

  String _tipo           = 'personal';
  bool _esLetra          = false;
  int? _diaPago;
  int? _diaPago2;
  int _mesInicioPago     = DateTime.now().month;
  DateTime? _fechaProximoPago;
  bool _guardando        = false;

  bool get _modoEdicion => widget.deudaExistente != null;

  static const _tipos = [
    {'value': 'tarjeta_credito', 'label': 'Tarjeta'},
    {'value': 'prestamo',        'label': 'Préstamo'},
    {'value': 'hipoteca',        'label': 'Hipoteca'},
    {'value': 'auto',            'label': 'Auto'},
    {'value': 'personal',        'label': 'Personal'},
    {'value': 'otro',            'label': 'Otro'},
  ];

  static const _meses = [
    'Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.deudaExistente;
    if (d != null) {
      _nombreCtrl.text    = d['nombre'] as String? ?? '';
      _tipo               = d['tipo'] as String? ?? 'personal';
      _esLetra            = (d['es_letra'] as int? ?? 0) == 1;
      _totalCtrl.text     = _fmt(d['monto_total']);
      _pendienteCtrl.text = _fmt(d['monto_pendiente']);
      _tasaCtrl.text      = _fmt(d['tasa_interes']);
      _pagoMinCtrl.text   = _fmt(d['pago_minimo']);
      _cuotaFijaCtrl.text = _fmt(d['cuota_fija']);
      _notasCtrl.text     = d['notas'] as String? ?? '';
      _acreedorCtrl.text  = d['nombre_acreedor'] as String? ?? '';
      final numCuotas = d['num_cuotas_total'];
      if (numCuotas != null) _numCuotasCtrl.text = numCuotas.toString();
      _mesInicioPago = (d['mes_inicio_pago'] as int?) ?? DateTime.now().month;
      final fechaStr = d['fecha_proximo_pago'] as String?;
      if (fechaStr != null && fechaStr.isNotEmpty) {
        _fechaProximoPago = DateTime.tryParse(fechaStr.substring(0, 10));
      }
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final d = v.toDouble();
      if (d == 0) return '';
      return d % 1 == 0 ? d.toInt().toString() : d.toString();
    }
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed == null || parsed == 0) return '';
      return parsed % 1 == 0 ? parsed.toInt().toString() : v;
    }
    return '';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _totalCtrl.dispose();
    _pendienteCtrl.dispose();
    _tasaCtrl.dispose();
    _plazoCtrl.dispose();
    _pagoMinCtrl.dispose();
    _cuotaFijaCtrl.dispose();
    _numCuotasCtrl.dispose();
    _acreedorCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  static double _pmt(double saldo, double tasaAnual, int plazo) {
    if (saldo <= 0 || plazo <= 0) return 0;
    if (tasaAnual <= 0) return saldo / plazo;
    final r = tasaAnual / 100 / 12;
    final factor = math.pow(1 + r, plazo);
    return saldo * r * factor / (factor - 1);
  }

  double get _cuotaCalculada {
    final saldo = double.tryParse(_pendienteCtrl.text.replaceAll(',', '')) ?? 0;
    final tasa  = double.tryParse(_tasaCtrl.text.replaceAll(',', '')) ?? 0;
    final plazo = int.tryParse(_plazoCtrl.text) ?? 0;
    return _pmt(saldo, tasa, plazo);
  }

  String _tasaHint(String tipo) {
    switch (tipo) {
      case 'tarjeta_credito': return 'Tarjetas en Panamá: 18–36%. Revisa tu estado de cuenta.';
      case 'prestamo':        return 'Préstamos personales: 6–18%. Busca la TEA en tu contrato.';
      case 'hipoteca':        return 'Hipotecas: 4–8% anual. Está en tu escritura o contrato.';
      case 'auto':            return 'Préstamos de auto: 4–10%. En el contrato de financiamiento.';
      default:                return 'Busca la Tasa Efectiva Anual (TEA) en tu contrato o estado.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(
              _modoEdicion ? 'Editar deuda' : 'Nueva deuda',
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),

            // ── Nombre ──────────────────────────────────────────────────────
            TextField(
              controller: _nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                  labelText: 'Nombre (ej: Tarjeta Visa, Préstamo banco)'),
            ),
            const SizedBox(height: 16),

            // ── Tipo ────────────────────────────────────────────────────────
            const Text('TIPO DE DEUDA',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tipos.map((t) {
                final sel = _tipo == t['value'];
                return GestureDetector(
                  onTap: () => setState(() => _tipo = t['value']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.danger.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: sel ? AppTheme.danger : AppTheme.border),
                    ),
                    child: Text(t['label']!, style: TextStyle(
                      color: sel ? AppTheme.danger : AppTheme.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w600,
                    )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── ¿Es compra a letra / plazo fijo? ────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Switch(
                    value: _esLetra,
                    onChanged: (v) => setState(() => _esLetra = v),
                    activeColor: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Compra a plazo / cuotas fijas',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text('Préstamos con cuota mensual fija (carro, electrodoméstico, etc.)',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    ]),
                  ),
                ]),
                if (_esLetra) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _cuotaFijaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                            labelText: 'Cuota mensual fija (\$)', prefixText: '\$ '),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _numCuotasCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                            labelText: 'Número de cuotas'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _acreedorCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                        labelText: 'Nombre del acreedor (opcional)',
                        hintText: 'Banco, tienda, persona…'),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // ── Montos ──────────────────────────────────────────────────────
            TextField(
              controller: _totalCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                  prefixText: '\$ ', labelText: 'Monto total original'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pendienteCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                  prefixText: '\$ ', labelText: 'Saldo pendiente actual'),
            ),
            const SizedBox(height: 12),

            // ── Tasa de interés — siempre visible ───────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TASA DE INTERÉS',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
                const SizedBox(height: 10),
                TextField(
                  controller: _tasaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    suffixText: '% anual',
                    labelText: 'Tasa de interés (TEA)',
                    hintText: 'Ej: 24',
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.lightbulb_outline, color: AppTheme.textMuted, size: 13),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_tasaHint(_tipo),
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            if (!_esLetra) ...[
              // ── Plazo + pago mínimo (solo para deudas no letra) ─────────
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _plazoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: AppTheme.textPrimary),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      suffixText: 'meses',
                      labelText: 'Plazo restante',
                      hintText: 'Ej: 36',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pagoMinCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      labelText: 'Pago mínimo',
                      hintText: _cuotaCalculada > 0
                          ? _cuotaCalculada.toStringAsFixed(2)
                          : 'Ej: 250',
                    ),
                  ),
                ),
              ]),
              if (_cuotaCalculada > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calculate_outlined, color: AppTheme.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Cuota calculada (PMT)',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      Text('\$ ${_cuotaCalculada.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.primary,
                              fontSize: 17, fontWeight: FontWeight.w700)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Total: \$ ${(_cuotaCalculada * (int.tryParse(_plazoCtrl.text) ?? 0)).toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      Text('Intereses: \$ ${(_cuotaCalculada * (int.tryParse(_plazoCtrl.text) ?? 0) - (double.tryParse(_pendienteCtrl.text.replaceAll(',', '')) ?? 0)).toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.warning, fontSize: 10)),
                    ]),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // ── Días de pago (quincena) ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DÍAS DE PAGO',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                const Text('Si pagas por quincena, ingresa ambos días.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _DiaPagoSelector(
                    label: 'Día (1–15)',
                    value: _diaPago,
                    minDay: 1,
                    maxDay: 15,
                    onChanged: (v) => setState(() => _diaPago = v),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _DiaPagoSelector(
                    label: 'Día (16–31)',
                    value: _diaPago2,
                    minDay: 16,
                    maxDay: 31,
                    onChanged: (v) => setState(() => _diaPago2 = v),
                  )),
                ]),
                const SizedBox(height: 6),
                if (_diaPago != null && _diaPago2 != null)
                  Text('Pago quincenal: día $_diaPago y día $_diaPago2 de cada mes',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 11,
                          fontWeight: FontWeight.w600))
                else if (_diaPago != null)
                  Text('Pago mensual: día $_diaPago de cada mes',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 11,
                          fontWeight: FontWeight.w600))
                else
                  const Text('Sin día de pago configurado',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Mes de inicio de pago ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DESDE CUÁNDO AFECTA TU PRESUPUESTO',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _mesInicioPago,
                  decoration: const InputDecoration(labelText: 'Mes de inicio'),
                  dropdownColor: AppTheme.surfaceAlt,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  items: List.generate(12, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(_meses[i]),
                  )),
                  onChanged: (v) => setState(() => _mesInicioPago = v ?? _mesInicioPago),
                ),
                const SizedBox(height: 4),
                Text(
                  'Esta deuda aparecerá en tu estado financiero desde ${_meses[_mesInicioPago - 1]}.',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Notas ───────────────────────────────────────────────────────
            TextField(
              controller: _notasCtrl,
              maxLines: 2,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  hintText: 'Ej: tasa especial hasta dic 2025, negociar refinanciamiento…'),
            ),
            const SizedBox(height: 16),

            // ── Fecha próximo pago ──────────────────────────────────────────
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
                  const Icon(Icons.calendar_today_outlined,
                      color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    _fechaProximoPago != null
                        ? 'Próximo pago: ${_fechaProximoPago!.toIso8601String().substring(0, 10)}'
                        : 'Fecha del próximo pago (opcional)',
                    style: TextStyle(
                      color: _fechaProximoPago != null
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: AppTheme.background))
                    : Text(_modoEdicion ? 'Guardar cambios' : 'Guardar deuda'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaProximoPago ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
                primary: AppTheme.primary, surface: AppTheme.surfaceAlt)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _fechaProximoPago = picked);
  }

  Future<void> _guardar() async {
    final nombre    = _nombreCtrl.text.trim();
    final total     = double.tryParse(_totalCtrl.text) ?? 0;
    final pendiente = double.tryParse(_pendienteCtrl.text) ?? 0;

    if (nombre.isEmpty || total <= 0 || pendiente <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa nombre, monto total y saldo pendiente')));
      return;
    }

    if (_esLetra) {
      final cuota = double.tryParse(_cuotaFijaCtrl.text) ?? 0;
      if (cuota <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingresa la cuota mensual fija')));
        return;
      }
    }

    setState(() => _guardando = true);
    try {
      final body = <String, dynamic>{
        'firebase_uid': widget.firebaseUid,
        'nombre': nombre,
        'tipo': _tipo,
        'monto_total': total,
        'monto_pendiente': pendiente,
        'es_letra': _esLetra ? 1 : 0,
        'mes_inicio_pago': _mesInicioPago,
      };

      final notas = _notasCtrl.text.trim();
      if (notas.isNotEmpty) body['notas'] = notas;

      if (_esLetra) {
        final cuota = double.tryParse(_cuotaFijaCtrl.text);
        if (cuota != null && cuota > 0) body['cuota_fija'] = cuota;
        final numCuotas = int.tryParse(_numCuotasCtrl.text);
        if (numCuotas != null && numCuotas > 0) body['num_cuotas_total'] = numCuotas;
        final acreedor = _acreedorCtrl.text.trim();
        if (acreedor.isNotEmpty) body['nombre_acreedor'] = acreedor;
      } else {
        final tasa  = double.tryParse(_tasaCtrl.text);
        final plazo = int.tryParse(_plazoCtrl.text) ?? 0;
        if (tasa != null && tasa > 0) body['tasa_interes'] = tasa;
        final pagoMinManual = double.tryParse(_pagoMinCtrl.text);
        final cuotaPmt = (tasa != null && tasa > 0 && plazo > 0)
            ? _pmt(pendiente, tasa, plazo)
            : 0.0;
        final pagoFinal = pagoMinManual != null && pagoMinManual > 0
            ? pagoMinManual
            : (cuotaPmt > 0 ? cuotaPmt : null);
        if (pagoFinal != null) body['pago_minimo'] = double.parse(pagoFinal.toStringAsFixed(2));
        if (plazo > 0) body['num_cuotas_total'] = plazo;
      }

      if (_diaPago != null) body['dia_pago'] = _diaPago;
      if (_diaPago2 != null) body['dia_pago_2'] = _diaPago2;
      if (_fechaProximoPago != null) {
        body['fecha_proximo_pago'] =
            _fechaProximoPago!.toIso8601String().substring(0, 10);
      }

      if (_modoEdicion) {
        await DeudasService.editar(widget.deudaExistente!['id'] as int, body);
      } else {
        await DeudasService.crear(body);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onCreada();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ── Selector de día con botones (no TextField) ────────────────────────────────
class _DiaPagoSelector extends StatelessWidget {
  final String label;
  final int? value;
  final int minDay;
  final int maxDay;
  final void Function(int?) onChanged;

  const _DiaPagoSelector({
    required this.label,
    required this.value,
    required this.minDay,
    required this.maxDay,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: AppTheme.surfaceAlt,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      hint: const Text('—', style: TextStyle(color: AppTheme.textMuted)),
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('—',
            style: TextStyle(color: AppTheme.textMuted))),
        ...List.generate(
          maxDay - minDay + 1,
          (i) => DropdownMenuItem(value: minDay + i, child: Text('Día ${minDay + i}')),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
