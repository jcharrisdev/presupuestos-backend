import 'package:flutter/material.dart';
import 'dart:convert';
import 'services/api_client.dart';

class DetallesPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;

  const DetallesPresupuesto({
    Key? key,
    required this.presupuesto,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _DetallesPresupuestoState createState() => _DetallesPresupuestoState();
}

class _DetallesPresupuestoState extends State<DetallesPresupuesto> {
  List<dynamic> movimientos = [];
  Map<String, dynamic>? periodo;

  double totalFijo = 0;
  double totalNoFijo = 0;
  double totalAhorro = 0;
  double montoTotalPresupuesto = 0;
  double porcentajePagados = 0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    montoTotalPresupuesto = _toDouble(widget.presupuesto['monto_total']);
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    setState(() => isLoading = true);
    try {
      final response = await ApiClient.get(
        '/presupuestos/${widget.presupuesto['id']}/detalle?firebase_uid=${widget.firebaseUid}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          movimientos = data['movimientos'];
          periodo = data['periodo'];
          totalFijo = _toDouble(data['resumen']['totalFijo']);
          totalNoFijo = _toDouble(data['resumen']['totalNoFijo']);
          totalAhorro = _toDouble(data['resumen']['totalAhorro']);
          porcentajePagados = _toDouble(data['resumen']['porcentajePagados']);
          isLoading = false;
        });
      } else {
        throw Exception();
      }
    } catch (_) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al cargar el detalle')),
      );
    }
  }

  Future<void> _reanudarGastosFijos() async {
    await ApiClient.put(
      '/presupuestos/${widget.presupuesto['id']}/gastos/reanudar-fijos',
      {},
    );
    _cargarDetalle();
  }

  Future<List<dynamic>> _cargarGastosSeleccionables() async {
    final res = await ApiClient.get(
      '/presupuestos/${widget.presupuesto['id']}/gastos-seleccionables?firebase_uid=${widget.firebaseUid}',
    );
    if (res.statusCode != 200) throw Exception('Error cargando gastos seleccionables');
    return json.decode(res.body)['gastos'];
  }

  Future<void> _agregarGasto(String descripcion, double monto, String tipo) async {
    if (descripcion.trim().isEmpty || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descripción y monto válidos son obligatorios')),
      );
      return;
    }

    final response = await ApiClient.post('/gastos', {
      'presupuesto_id': widget.presupuesto['id'],
      'descripcion': descripcion.trim(),
      'monto': monto,
      'tipo': tipo,
      'fecha': DateTime.now().toIso8601String().split('T')[0],
      'firebase_uid': widget.firebaseUid,
    });

    if (response.statusCode != 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear gasto (${response.statusCode})')),
      );
      return;
    }

    // Para gastos fijos y ahorros, crear movimiento en el período activo explícitamente
    if (tipo == 'fijo' || tipo == 'fijo_x_periodo' || tipo == 'ahorro') {
      final data = json.decode(response.body);
      final gastoId = data['id'];
      await ApiClient.post(
        '/presupuestos/${widget.presupuesto['id']}/movimientos',
        {
          'firebase_uid': widget.firebaseUid,
          'items': [{'gasto_id': gastoId, 'monto': monto}],
        },
      );
    }

    _cargarDetalle();
  }

  Future<void> _crearMovimientos(List items) async {
    final res = await ApiClient.post(
      '/presupuestos/${widget.presupuesto['id']}/movimientos',
      {'firebase_uid': widget.firebaseUid, 'items': items},
    );

    if (res.statusCode != 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creando movimientos')),
      );
    }
  }

  Future<void> _pagarMovimiento({required int movimientoId, required double montoPagado}) async {
    final res = await ApiClient.put('/movimientos/$movimientoId/pagar', {
      'pagado': 1,
      'monto_pagado_real': montoPagado,
      'firebase_uid': widget.firebaseUid,
    });

    if (!mounted) return;

    if (res.statusCode == 200) {
      _cargarDetalle();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al registrar el pago')),
      );
    }
  }

  void _mostrarModalPago({required int movimientoId, required double montoSugerido}) {
    final montoCtrl = TextEditingController(text: montoSugerido.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Registrar pago'),
        content: TextField(
          controller: montoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Monto pagado real', prefixText: '\$ '),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final monto = double.tryParse(montoCtrl.text) ?? 0;
              if (monto <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Monto inválido')),
                );
                return;
              }
              Navigator.pop(context);
              await _pagarMovimiento(movimientoId: movimientoId, montoPagado: monto);
            },
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
  }

  void _mostrarModalCrearGasto() {
    final descripcionCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo = 'fijo';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nuevo gasto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descripcionCtrl, decoration: const InputDecoration(labelText: 'Descripción')),
              TextField(
                controller: montoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              DropdownButton<String>(
                value: tipo,
                items: ['fijo', 'no fijo', 'ahorro']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setS(() => tipo = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _agregarGasto(
                  descripcionCtrl.text,
                  double.tryParse(montoCtrl.text) ?? 0,
                  tipo,
                );
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarModalAgregarGasto() async {
    List<dynamic> gastosDisponibles = [];
    try {
      gastosDisponibles = await _cargarGastosSeleccionables();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error cargando gastos')),
      );
      return;
    }

    if (!mounted) return;

    if (gastosDisponibles.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sin gastos'),
          content: const Text(
            'No hay gastos asignados para este presupuesto.\nCrea al menos uno para continuar.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _mostrarModalCrearGasto(); },
              child: const Text('Crear gasto'),
            ),
          ],
        ),
      );
      return;
    }

    final Map<int, bool> seleccionados = {};
    final Map<int, TextEditingController> montosCtrl = {};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Seleccionar gastos'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: gastosDisponibles.map((g) {
                final id = g['id'] as int;
                seleccionados[id] ??= false;
                montosCtrl[id] ??= TextEditingController(text: g['monto'].toString());

                return Row(
                  children: [
                    Checkbox(
                      value: seleccionados[id],
                      onChanged: (v) => setS(() => seleccionados[id] = v ?? false),
                    ),
                    Expanded(child: Text(g['descripcion'])),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: montosCtrl[id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(prefixText: '\$'),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(ctx); _mostrarModalCrearGasto(); },
              child: const Text('Crear gasto nuevo'),
            ),
            ElevatedButton(
              onPressed: () async {
                final items = gastosDisponibles
                    .where((g) => seleccionados[g['id']] == true)
                    .map((g) {
                      final monto = double.tryParse(montosCtrl[g['id']]!.text) ?? 0;
                      return monto > 0 ? {'gasto_id': g['id'], 'monto': monto} : null;
                    })
                    .where((e) => e != null)
                    .toList();

                if (items.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Selecciona gastos válidos')),
                  );
                  return;
                }

                await _crearMovimientos(items);
                if (!mounted) return;
                Navigator.pop(ctx);
                _cargarDetalle();
              },
              child: const Text('Agregar seleccionados'),
            ),
          ],
        ),
      ),
    );
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final totalGastado = totalFijo + totalNoFijo + totalAhorro;
    final porcentajeGastado = montoTotalPresupuesto > 0 ? totalGastado / montoTotalPresupuesto : 0.0;

    Color colorBarra;
    if (totalGastado > montoTotalPresupuesto) colorBarra = Colors.red;
    else if (porcentajeGastado >= 0.75) colorBarra = Colors.orange;
    else colorBarra = Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Presupuesto'),
        backgroundColor: const Color(0xFF6ABF69),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.presupuesto['nombre'],
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (periodo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        'Período ${periodo!['numero_periodo']} · ${periodo!['fecha_inicio']} → ${periodo!['fecha_fin']}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ),
                  Text('Monto Total: \$${montoTotalPresupuesto.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 18)),

                  const SizedBox(height: 16),
                  Text('Fijos: \$${totalFijo.toStringAsFixed(2)}'),
                  Text('No fijos: \$${totalNoFijo.toStringAsFixed(2)}'),
                  Text('Ahorro: \$${totalAhorro.toStringAsFixed(2)}'),

                  const SizedBox(height: 16),
                  const Text('Progreso del presupuesto'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: porcentajeGastado.clamp(0.0, 1.0),
                    minHeight: 20,
                    backgroundColor: Colors.grey[300],
                    color: colorBarra,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gastado: \$${totalGastado.toStringAsFixed(2)} (${(porcentajeGastado * 100).toStringAsFixed(1)}%)',
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: CircularProgressIndicator(
                            value: porcentajePagados,
                            strokeWidth: 10,
                            backgroundColor: Colors.grey[300],
                            color: Colors.green,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(porcentajePagados * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text('pagado', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _mostrarModalAgregarGasto,
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _reanudarGastosFijos,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reanudar fijos'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  if (movimientos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No hay movimientos en este período.',
                              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Usa "Agregar" para registrar gastos.',
                              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...movimientos.map((m) {
                      final monto = _toDouble(m['monto']);
                      final montoPagado = m['monto_pagado_real'] != null
                          ? _toDouble(m['monto_pagado_real'])
                          : null;
                      final pagado = m['pagado'] == 1;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(m['descripcion']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Presupuestado: \$${monto.toStringAsFixed(2)} · ${m['tipo']}'),
                              if (pagado && montoPagado != null)
                                Text(
                                  'Pagado: \$${montoPagado.toStringAsFixed(2)}  '
                                  '(${montoPagado > monto ? '+' : ''}\$${(montoPagado - monto).toStringAsFixed(2)})',
                                  style: TextStyle(
                                    color: montoPagado > monto ? Colors.red : Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: pagado
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                                  onPressed: () => _mostrarModalPago(
                                    movimientoId: m['id'],
                                    montoSugerido: monto,
                                  ),
                                ),
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
    );
  }
}
