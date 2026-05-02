import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'progreso_ahorro.dart';

class AhorroMetaScreen extends StatefulWidget {
  final String firebaseUid;
  const AhorroMetaScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _AhorroMetaScreenState createState() => _AhorroMetaScreenState();
}

class _AhorroMetaScreenState extends State<AhorroMetaScreen> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl  = TextEditingController();
  int _meses = 12;
  List<Map<String, dynamic>> _presupuestos = [];
  int? _presupuestoId;
  bool _cargando = true, _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarPresupuestos();
    _montoCtrl.addListener(() => setState(() {}));
  }

  Map<String, dynamic>? get _presupuestoSeleccionado =>
      _presupuestos.where((p) => p['id'] == _presupuestoId).isNotEmpty
          ? _presupuestos.firstWhere((p) => p['id'] == _presupuestoId)
          : null;

  int get _periodosTotales {
    final tipo = _presupuestoSeleccionado?['tipo_periodo'] ?? 'mensual';
    return tipo == 'quincenal' ? _meses * 2 : _meses;
  }

  double get _cuotaPorPeriodo {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0 || _periodosTotales <= 0) return 0;
    return (monto / _periodosTotales * 100).ceil() / 100;
  }

  String get _tipoPeriodoLabel {
    final tipo = _presupuestoSeleccionado?['tipo_periodo'] ?? 'mensual';
    return tipo == 'quincenal' ? 'quincena' : 'mes';
  }

  Future<void> _cargarPresupuestos() async {
    try {
      final res = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        setState(() {
          _presupuestos = List<Map<String, dynamic>>.from(json.decode(res.body));
          _cargando = false;
        });
      } else throw Exception();
    } catch (_) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    if (_nombreCtrl.text.isEmpty || _montoCtrl.text.isEmpty || _presupuestoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa todos los campos')));
      return;
    }
    final monto = double.tryParse(_montoCtrl.text);
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final res = await ApiClient.post('/gastos/ahorroMeta', {
        'presupuesto_id': _presupuestoId,
        'descripcion': _nombreCtrl.text.trim(),
        'monto': monto,
        'fecha': DateTime.now().toIso8601String().split('T')[0],
        'tiempo_meses': _meses,
        'firebase_uid': widget.firebaseUid,
      });
      if (!mounted) return;
      if (res.statusCode == 201) {
        final data = json.decode(res.body);
        final cuota = data['monto_periodo'] ?? _cuotaPorPeriodo;
        final periodos = data['periodos_total'] ?? _periodosTotales;
        _nombreCtrl.clear();
        _montoCtrl.clear();
        setState(() => _presupuestoId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Meta creada · \$${cuota.toStringAsFixed(2)} por período · $periodos períodos')),
        );
      } else throw Exception();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al crear meta')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    final mostrarCalculo = monto > 0 && _presupuestoId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ahorro y Metas'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProgresoAhorroScreen(firebaseUid: widget.firebaseUid),
            )),
            icon: const Icon(Icons.bar_chart, size: 16, color: AppTheme.primary),
            label: const Text('Ver progreso', style: TextStyle(color: AppTheme.primary, fontSize: 13)),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.colorAhorro.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.colorAhorro.withOpacity(0.2)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.savings_outlined, color: AppTheme.colorAhorro, size: 28),
                    SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Nueva meta de ahorro', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 3),
                      Text('El sistema calcula la cuota automáticamente según el tipo de período', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ])),
                  ]),
                ),

                const SizedBox(height: 24),
                _label('Nombre de la meta'),
                TextField(
                  controller: _nombreCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: 'Ej: Vacaciones, Auto nuevo...'),
                ),
                const SizedBox(height: 16),

                _label('Monto total a ahorrar'),
                TextField(
                  controller: _montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: AppTheme.colorAhorro, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Presupuesto asociado'),
                DropdownButtonFormField<int>(
                  value: _presupuestoId,
                  dropdownColor: AppTheme.surfaceAlt,
                  hint: const Text('Selecciona un presupuesto', style: TextStyle(color: AppTheme.textMuted)),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(),
                  items: _presupuestos.map((p) {
                    final tipo = p['tipo_periodo'] == 'quincenal' ? 'Quincenal' : 'Mensual';
                    return DropdownMenuItem<int>(
                      value: p['id'],
                      child: Text('${p['nombre']} · $tipo', style: const TextStyle(color: AppTheme.textPrimary)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _presupuestoId = v),
                ),

                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _label('Plazo'),
                  Text('$_meses ${_meses == 1 ? "mes" : "meses"}',
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
                Slider(
                  value: _meses.toDouble(), min: 1, max: 60, divisions: 59,
                  label: '$_meses meses',
                  onChanged: (v) => setState(() => _meses = v.toInt()),
                ),

                // Resumen de cuotas calculado
                if (mostrarCalculo) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.colorAhorro.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.colorAhorro.withOpacity(0.25)),
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Cuota por período', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text(
                          '\$${_cuotaPorPeriodo.toStringAsFixed(2)} / $_tipoPeriodoLabel',
                          style: const TextStyle(color: AppTheme.colorAhorro, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      const Divider(color: AppTheme.border, height: 1),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Total de períodos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text('$_periodosTotales períodos', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Tipo de período', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text(
                          _presupuestoSeleccionado?['tipo_periodo'] == 'quincenal' ? 'Quincenal (14 días)' : 'Mensual (30 días)',
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Total a ahorrar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text('\$${monto.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ]),
                  ),
                ],

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: _guardando
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                      : ElevatedButton(onPressed: _crear, child: const Text('Crear meta')),
                ),
              ]),
            ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
  );
}
