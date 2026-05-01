import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'editar_presupuesto.dart';

class DetallesPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;
  const DetallesPresupuesto({Key? key, required this.presupuesto, required this.firebaseUid}) : super(key: key);

  @override
  _DetallesPresupuestoState createState() => _DetallesPresupuestoState();
}

class _DetallesPresupuestoState extends State<DetallesPresupuesto> {
  List<dynamic> movimientos = [];
  Map<String, dynamic>? periodo;
  double totalFijo = 0, totalNoFijo = 0, totalAhorro = 0;
  double montoTotal = 0, porcentajePagados = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    montoTotal = _d(widget.presupuesto['monto_total']);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiClient.get('/presupuestos/${widget.presupuesto['id']}/detalle?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          movimientos = data['movimientos'];
          periodo     = data['periodo'];
          totalFijo   = _d(data['resumen']['totalFijo']);
          totalNoFijo = _d(data['resumen']['totalNoFijo']);
          totalAhorro = _d(data['resumen']['totalAhorro']);
          porcentajePagados = _d(data['resumen']['porcentajePagados']);
          isLoading   = false;
        });
      } else { throw Exception(); }
    } catch (_) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al cargar detalle')));
    }
  }

  Future<void> _reanudar() async {
    await ApiClient.put('/presupuestos/${widget.presupuesto['id']}/gastos/reanudar-fijos', {});
    _cargar();
  }

  Future<List<dynamic>> _seleccionables() async {
    final res = await ApiClient.get('/presupuestos/${widget.presupuesto['id']}/gastos-seleccionables?firebase_uid=${widget.firebaseUid}');
    if (res.statusCode != 200) throw Exception();
    return json.decode(res.body)['gastos'];
  }

  Future<void> _agregarGasto(String desc, double monto, String tipo) async {
    if (desc.trim().isEmpty || monto <= 0) return;
    final res = await ApiClient.post('/gastos', {
      'presupuesto_id': widget.presupuesto['id'],
      'descripcion': desc.trim(), 'monto': monto, 'tipo': tipo,
      'fecha': DateTime.now().toIso8601String().split('T')[0],
      'firebase_uid': widget.firebaseUid,
    });
    if (res.statusCode != 201) return;
    if (tipo == 'fijo' || tipo == 'fijo_x_periodo' || tipo == 'ahorro') {
      final id = json.decode(res.body)['id'];
      await ApiClient.post('/presupuestos/${widget.presupuesto['id']}/movimientos', {
        'firebase_uid': widget.firebaseUid,
        'items': [{'gasto_id': id, 'monto': monto}],
      });
    }
    _cargar();
  }

  Future<void> _crearMovimientos(List items) async {
    await ApiClient.post('/presupuestos/${widget.presupuesto['id']}/movimientos',
        {'firebase_uid': widget.firebaseUid, 'items': items});
    _cargar();
  }

  Future<void> _pagar(int mid, double monto) async {
    final res = await ApiClient.put('/movimientos/$mid/pagar', {
      'pagado': 1, 'monto_pagado_real': monto, 'firebase_uid': widget.firebaseUid,
    });
    if (res.statusCode == 200) _cargar();
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al registrar pago')));
  }

  void _modalPago(int mid, double sugerido) {
    final ctrl = TextEditingController(text: sugerido.toStringAsFixed(2));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Registrar pago', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          const Text('Ingresa el monto real pagado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '\$ ', prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final m = double.tryParse(ctrl.text) ?? 0;
                if (m <= 0) return;
                Navigator.pop(context);
                _pagar(mid, m);
              },
              child: const Text('Confirmar pago'),
            ),
          ),
        ]),
      ),
    );
  }

  void _modalNuevoGasto() {
    final descCtrl  = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo = 'fijo';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nuevo gasto', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(controller: descCtrl, style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Descripción')),
          const SizedBox(height: 12),
          TextField(controller: montoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00')),
          const SizedBox(height: 16),
          const Text('Tipo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: ['fijo', 'no fijo', 'ahorro'].map((t) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
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
            ),
          )).toList()),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _agregarGasto(descCtrl.text, double.tryParse(montoCtrl.text) ?? 0, tipo);
            },
            child: const Text('Agregar gasto'),
          )),
        ]),
      )),
    );
  }

  void _modalSeleccionar() async {
    List<dynamic> gastos = [];
    try { gastos = await _seleccionables(); } catch (_) { return; }

    if (!mounted) return;
    if (gastos.isEmpty) { _modalNuevoGasto(); return; }

    final sel   = <int, bool>{};
    final montos = <int, TextEditingController>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              const Text('Agregar al período', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _modalNuevoGasto(); },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Crear nuevo'),
              ),
            ]),
          ),
          const Divider(color: AppTheme.border),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            ...gastos.map((g) {
              final id = g['id'] as int;
              sel[id]   ??= false;
              montos[id] ??= TextEditingController(text: g['monto'].toString());
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel[id]! ? AppTheme.primary.withOpacity(0.06) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel[id]! ? AppTheme.primary.withOpacity(0.3) : AppTheme.border),
                ),
                child: Row(children: [
                  Checkbox(value: sel[id], onChanged: (v) => setS(() => sel[id] = v ?? false)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g['descripcion'], style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    TipoChip(g['tipo']),
                  ])),
                  SizedBox(width: 90, child: TextField(
                    controller: montos[id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(prefixText: '\$', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                  )),
                ]),
              );
            }),
          ])),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                final items = gastos
                    .where((g) => sel[g['id']] == true)
                    .map((g) {
                      final m = double.tryParse(montos[g['id']]!.text) ?? 0;
                      return m > 0 ? {'gasto_id': g['id'], 'monto': m} : null;
                    }).where((e) => e != null).toList();
                if (items.isEmpty) return;
                Navigator.pop(ctx);
                await _crearMovimientos(items);
              },
              child: const Text('Agregar seleccionados'),
            )),
          ),
        ]),
      )),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalGastado = totalFijo + totalNoFijo + totalAhorro;
    final pctGasto = montoTotal > 0 ? (totalGastado / montoTotal).clamp(0.0, 1.0) : 0.0;
    final disponible = montoTotal - totalGastado;

    Color barColor;
    if (totalGastado > montoTotal) barColor = AppTheme.danger;
    else if (pctGasto >= 0.85) barColor = AppTheme.warning;
    else barColor = AppTheme.success;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.presupuesto['nombre'], overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditarPresupuesto(presupuesto: widget.presupuesto, firebaseUid: widget.firebaseUid),
              ));
              _cargar();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: _cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Período info
                  if (periodo != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          'Período ${periodo!['numero_periodo']}  ·  ${_fmtDate(periodo!['fecha_inicio'])}  →  ${_fmtDate(periodo!['fecha_fin'])}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    ),

                  const SizedBox(height: 20),

                  // Balance principal
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Presupuesto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('\$${montoTotal.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      const SizedBox(height: 20),

                      // Barra progreso
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pctGasto,
                          minHeight: 8,
                          backgroundColor: AppTheme.surfaceAlt,
                          color: barColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Text('Gastado \$${totalGastado.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        const Spacer(),
                        Text(
                          disponible >= 0 ? 'Disponible \$${disponible.toStringAsFixed(2)}' : 'Excedido \$${(-disponible).toStringAsFixed(2)}',
                          style: TextStyle(color: disponible >= 0 ? AppTheme.success : AppTheme.danger, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // Stats por tipo
                  Row(children: [
                    _StatCard('Fijos', totalFijo, AppTheme.colorFijo),
                    const SizedBox(width: 8),
                    _StatCard('Variables', totalNoFijo, AppTheme.colorNoFijo),
                    const SizedBox(width: 8),
                    _StatCard('Ahorro', totalAhorro, AppTheme.colorAhorro),
                  ]),

                  const SizedBox(height: 14),

                  // Indicador de pagos
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
                    child: Row(children: [
                      SizedBox(
                        width: 56, height: 56,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(
                            value: porcentajePagados, strokeWidth: 5,
                            backgroundColor: AppTheme.surfaceAlt, color: AppTheme.success,
                          ),
                          Text('${(porcentajePagados * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Progreso de pagos', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(
                          '${movimientos.where((m) => m['pagado'] == 1).length} de ${movimientos.length} movimientos pagados',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 20),

                  // Acciones
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _modalSeleccionar,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Agregar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _reanudar,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reanudar fijos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                  ]),

                  const SizedBox(height: 20),
                  const LabelDivider('MOVIMIENTOS'),

                  // Lista de movimientos
                  if (movimientos.isEmpty)
                    _emptyMovimientos()
                  else
                    ...movimientos.map((m) => _MovimientoTile(
                      m: m, onPagar: () => _modalPago(m['id'], _d(m['monto'])),
                    )),

                  const SizedBox(height: 30),
                ]),
              ),
            ),
    );
  }

  String _fmtDate(dynamic d) {
    final s = d?.toString() ?? '';
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  Widget _emptyMovimientos() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(child: Column(children: [
      Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
      const SizedBox(height: 12),
      const Text('Sin movimientos en este período', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      const SizedBox(height: 6),
      const Text('Toca "Agregar" para registrar gastos', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    ])),
  );
}

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ]),
        const SizedBox(height: 6),
        Text('\$${value.toStringAsFixed(0)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _MovimientoTile extends StatelessWidget {
  final Map<String, dynamic> m;
  final VoidCallback onPagar;
  const _MovimientoTile({required this.m, required this.onPagar});

  @override
  Widget build(BuildContext context) {
    final pagado = m['pagado'] == 1;
    final monto  = double.tryParse(m['monto'].toString()) ?? 0;
    final real   = m['monto_pagado_real'] != null ? double.tryParse(m['monto_pagado_real'].toString()) : null;
    final dif    = real != null ? real - monto : null;
    final tipo   = m['tipo'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: pagado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pagado ? AppTheme.success.withOpacity(0.2) : AppTheme.border),
      ),
      child: Row(children: [
        // Icono tipo
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.gastoColor(tipo).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_tipoIcon(tipo), color: AppTheme.gastoColor(tipo), size: 18),
        ),
        const SizedBox(width: 14),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m['descripcion'], style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
            decoration: pagado ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 3),
          Row(children: [
            TipoChip(tipo),
            if (pagado && real != null) ...[
              const SizedBox(width: 6),
              Text(
                '${dif! >= 0 ? '+' : ''}\$${dif.toStringAsFixed(2)}',
                style: TextStyle(color: dif > 0 ? AppTheme.danger : AppTheme.success, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ]),
        ])),

        // Monto y acción
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '\$${monto.toStringAsFixed(2)}',
            style: TextStyle(
              color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 15,
              decoration: pagado ? TextDecoration.lineThrough : null,
            ),
          ),
          if (pagado && real != null)
            Text('\$${real.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (!pagado)
            GestureDetector(
              onTap: onPagar,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: const Text('Pagar', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            )
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),
    );
  }

  IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'fijo':            return Icons.repeat;
      case 'fijo_x_periodo':  return Icons.event_repeat;
      case 'no fijo':         return Icons.shopping_cart_outlined;
      case 'ahorro':          return Icons.savings_outlined;
      default:                return Icons.attach_money;
    }
  }
}
