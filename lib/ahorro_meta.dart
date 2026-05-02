/// Pantalla para crear metas de ahorro.
///
/// El usuario define:
///   - Nombre de la meta (ej: "Vacaciones", "Auto nuevo")
///   - Monto total a ahorrar
///   - Presupuesto al que se asocia (determina el tipo de período)
///   - Plazo en meses (1–60, slider)
///
/// El sistema calcula automáticamente la CUOTA POR PERÍODO:
///   - Si el presupuesto es QUINCENAL: cuota = monto / (meses × 2)
///   - Si el presupuesto es MENSUAL:   cuota = monto / meses
///
/// Al crear, llama a POST /gastos/ahorroMeta y el backend registra el
/// gasto de tipo 'ahorro' con el campo `numero_quincena` como contador
/// descendente de períodos (cada vez que se paga, el contador baja 1).
///
/// Para ver el progreso de las metas creadas: botón "Ver progreso" → [ProgresoAhorroScreen].
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'progreso_ahorro.dart';

/// Pantalla de creación de metas de ahorro con cálculo de cuota en tiempo real.
class AhorroMetaScreen extends StatefulWidget {
  final String firebaseUid;
  const AhorroMetaScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _AhorroMetaScreenState createState() => _AhorroMetaScreenState();
}

class _AhorroMetaScreenState extends State<AhorroMetaScreen> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl  = TextEditingController();

  /// Plazo en meses seleccionado con el slider (1–60).
  int _meses = 12;

  /// Lista de presupuestos del usuario para el dropdown.
  List<Map<String, dynamic>> _presupuestos = [];

  /// ID del presupuesto seleccionado (null si aún no eligió).
  int? _presupuestoId;

  bool _cargando = true, _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarPresupuestos();
    // Recalcular cuota cada vez que cambia el monto
    _montoCtrl.addListener(() => setState(() {}));
  }

  /// Presupuesto actualmente seleccionado en el dropdown, o null si no hay selección.
  Map<String, dynamic>? get _presupuestoSeleccionado =>
      _presupuestos.where((p) => p['id'] == _presupuestoId).isNotEmpty
          ? _presupuestos.firstWhere((p) => p['id'] == _presupuestoId)
          : null;

  /// Cantidad total de períodos del plazo.
  ///
  /// Quincenal: meses × 2 (hay 2 quincenas por mes).
  /// Mensual: igual a los meses.
  int get _periodosTotales {
    final tipo = _presupuestoSeleccionado?['tipo_periodo'] ?? 'mensual';
    return tipo == 'quincenal' ? _meses * 2 : _meses;
  }

  /// Cuota a apartar por período para cumplir la meta.
  ///
  /// Se calcula en tiempo real mientras el usuario escribe el monto.
  /// Se redondea hacia arriba al centavo más próximo para no quedar corto.
  double get _cuotaPorPeriodo {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0 || _periodosTotales <= 0) return 0;
    return (monto / _periodosTotales * 100).ceil() / 100;
  }

  /// Etiqueta del período según el tipo del presupuesto seleccionado.
  /// "quincena" o "mes".
  String get _tipoPeriodoLabel {
    final tipo = _presupuestoSeleccionado?['tipo_periodo'] ?? 'mensual';
    return tipo == 'quincenal' ? 'quincena' : 'mes';
  }

  /// Carga los presupuestos del usuario para el selector de presupuesto asociado.
  Future<void> _cargarPresupuestos() async {
    try {
      final res = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        setState(() {
          _presupuestos = List<Map<String, dynamic>>.from(json.decode(res.body));
          _cargando = false;
        });
      } else throw Exception();
    } catch (e) {
      // FIX: catch silencioso dejaba el dropdown vacío sin feedback al usuario.
      setState(() => _cargando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar presupuestos: $e')),
      );
    }
  }

  /// Envía la meta de ahorro al backend.
  ///
  /// El backend recibe `tiempo_meses` y calcula internamente:
  ///   - `numero_quincena` = periodos_total (contador descendente de períodos)
  ///   - `monto` = cuota por período
  ///
  /// Al completarse muestra un SnackBar con la cuota calculada por el servidor.
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
        // El servidor retorna la cuota y los períodos totales confirmados
        final cuota   = data['monto_periodo'] ?? _cuotaPorPeriodo;
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
    // Solo mostrar el cuadro de resumen cuando hay monto y presupuesto elegido
    final mostrarCalculo = monto > 0 && _presupuestoId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ahorro y Metas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Ahorro y Metas',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Crea metas de ahorro y el sistema calcula cuánto debes apartar en cada período.\n\n'
                  '1. Escribe el nombre de tu meta (ej: "Vacaciones").\n'
                  '2. Ingresa el monto total que quieres ahorrar.\n'
                  '3. Elige el presupuesto donde se descontará la cuota.\n'
                  '4. Ajusta el plazo con el slider (en meses).\n\n'
                  'La cuota por período se calcula automáticamente:\n'
                  '  Quincenal → monto ÷ (meses × 2)\n'
                  '  Mensual → monto ÷ meses\n\n'
                  'Toca "Ver progreso" para ver el avance de tus metas.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          // Navega al historial de metas creadas
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

                // ── INFO CARD ────────────────────────────────────────────
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
                      Text('El sistema calcula la cuota automáticamente según el tipo de período',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ])),
                  ]),
                ),

                const SizedBox(height: 24),

                // ── NOMBRE DE LA META ─────────────────────────────────────
                _label('Nombre de la meta'),
                TextField(
                  controller: _nombreCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: 'Ej: Vacaciones, Auto nuevo...'),
                ),
                const SizedBox(height: 16),

                // ── MONTO TOTAL ───────────────────────────────────────────
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

                // ── PRESUPUESTO ASOCIADO ──────────────────────────────────
                // El tipo de período del presupuesto elegido determina si la
                // cuota es por mes o por quincena.
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

                // ── PLAZO (SLIDER) ────────────────────────────────────────
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

                // ── RESUMEN DE CUOTA (visible cuando hay datos) ───────────
                // Se actualiza en tiempo real al cambiar monto, presupuesto o plazo.
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
                      // Cuota por período — dato principal
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
                        Text('$_periodosTotales períodos',
                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Tipo de período', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text(
                          _presupuestoSeleccionado?['tipo_periodo'] == 'quincenal'
                              ? 'Quincenal (14 días)' : 'Mensual (30 días)',
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Total a ahorrar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text('\$${monto.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
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

  /// Etiqueta de campo de formulario con estilo consistente.
  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
  );
}
