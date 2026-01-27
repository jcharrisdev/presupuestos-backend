import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  List<dynamic> gastos = [];

  double totalFijo = 0.0;
  double totalNoFijo = 0.0;
  double totalAhorro = 0.0;
  double montoTotalPresupuesto = 0.0;
  double porcentajePagados = 0.0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    montoTotalPresupuesto = _toDouble(widget.presupuesto['monto_total']);
    _cargarGastos();
  }

  // ===============================
  // CARGAR GASTOS (CON UID)
  // ===============================
  Future<void> _cargarGastos() async {
    try {
      final url = Uri.parse(
        'https://presupuestos-backend-h3l6.onrender.com/presupuestos/${widget.presupuesto['id']}/gastos'
            '?firebase_uid=${widget.firebaseUid}',
      );


      final response = await http.get(url);

      if (response.statusCode == 200) {
        final datos = json.decode(response.body);

        setState(() {
          gastos = datos;

          totalFijo = gastos
              .where((g) => g['tipo'] == 'fijo')
              .fold(0.0, (s, g) => s + _toDouble(g['monto']));

          totalNoFijo = gastos
              .where((g) => g['tipo'] == 'no fijo')
              .fold(0.0, (s, g) => s + _toDouble(g['monto']));

          totalAhorro = gastos
              .where((g) => g['tipo'] == 'ahorro')
              .fold(0.0, (s, g) => s + _toDouble(g['monto']));

          final total = gastos.length;
          final pagados = gastos.where((g) => g['pagado'] == 1).length;

          porcentajePagados = total > 0 ? pagados / total : 0.0;

          isLoading = false;
        });
      } else {
        throw Exception();
      }
    } catch (_) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar gastos')),
      );
    }
  }
  void _mostrarModalCrearGasto() {
    final descripcionCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo = 'fijo';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Agregar Gasto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descripcionCtrl,
              decoration: InputDecoration(labelText: 'Descripción'),
            ),
            TextField(
              controller: montoCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Monto'),
            ),
            DropdownButton<String>(
              value: tipo,
              items: ['fijo', 'no fijo', 'ahorro']
                  .map(
                    (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t),
                ),
              )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  tipo = v!;
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              _agregarGasto(
                descripcionCtrl.text,
                double.tryParse(montoCtrl.text) ?? 0,
                tipo,
              );
              Navigator.pop(context);
            },
            child: Text('Agregar'),
          ),
        ],
      ),
    );
  }


  // ===============================
  // ACTUALIZAR ESTADO GASTO
  // ===============================
  Future<void> _actualizarEstadoGasto(int id, bool pagado) async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/gastos/$id',
    );

    await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pagado': pagado ? 1 : 0}),
    );

    _cargarGastos();
  }

  // ===============================
  // REANUDAR GASTOS FIJOS
  // ===============================
  Future<void> _reanudarGastosFijos() async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/'
          'presupuestos/${widget.presupuesto['id']}/gastos/reanudar-fijos',
    );

    await http.put(url);
    _cargarGastos();
  }

  Future<List<dynamic>> _cargarGastosSeleccionables() async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com'
          '/presupuestos/${widget.presupuesto['id']}/gastos-seleccionables'
          '?firebase_uid=${widget.firebaseUid}',
    );

    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('Error cargando gastos seleccionables');
    }

    final data = json.decode(res.body);
    return data['gastos'];
  }


  // ===============================
  // AGREGAR GASTO
  // ===============================
  Future<void> _agregarGasto(
      String descripcion,
      double monto,
      String tipo,
      ) async {
    if (descripcion.trim().isEmpty || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Descripción y monto válidos son obligatorios')),
      );
      return;
    }

    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/gastos',
    );

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'presupuesto_id': widget.presupuesto['id'],
        'descripcion': descripcion.trim(),
        'monto': monto,
        'tipo': tipo,
        'fecha': DateTime.now().toIso8601String(),
        'firebase_uid': widget.firebaseUid,
      }),
    );

    if (response.statusCode == 201) {
      _cargarGastos();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al crear gasto (${response.statusCode})',
          ),
        ),
      );
    }
  }


  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final totalGastado = totalFijo + totalNoFijo + totalAhorro;
    final porcentajeGastado =
    montoTotalPresupuesto > 0 ? totalGastado / montoTotalPresupuesto : 0.0;

    Color colorBarra;
    if (totalGastado > montoTotalPresupuesto) {
      colorBarra = Colors.red;
    } else if (porcentajeGastado >= 0.75) {
      colorBarra = Colors.orange;
    } else {
      colorBarra = Colors.green;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalles del Presupuesto'),
        backgroundColor: Color(0xFF6ABF69),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.presupuesto['nombre'],
              style:
              TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'Monto Total: \$${montoTotalPresupuesto.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18),
            ),

            SizedBox(height: 20),
            Text('Total Gastos Fijos: \$${totalFijo.toStringAsFixed(2)}'),
            Text(
                'Total Gastos No Fijos: \$${totalNoFijo.toStringAsFixed(2)}'),
            Text(
                'Total Gastos de Ahorro: \$${totalAhorro.toStringAsFixed(2)}'),

            SizedBox(height: 20),
            Text('Progreso del Presupuesto'),
            SizedBox(height: 8),
            LinearProgressIndicator(
              value: porcentajeGastado > 1 ? 1 : porcentajeGastado,
              minHeight: 20,
              backgroundColor: Colors.grey[300],
              color: colorBarra,
            ),
            SizedBox(height: 8),
            Text(
              'Gastado: \$${totalGastado.toStringAsFixed(2)} '
                  '(${(porcentajeGastado * 100).toStringAsFixed(2)}%)',
            ),

            SizedBox(height: 30),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: porcentajePagados,
                      strokeWidth: 10,
                      backgroundColor: Colors.grey[300],
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    '${(porcentajePagados * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _mostrarModalAgregarGasto,
                  child: Text('Agregar Gasto'),
                ),
                ElevatedButton(
                  onPressed: _reanudarGastosFijos,
                  child: Text('Reanudar Fijos'),
                ),
              ],
            ),

            SizedBox(height: 20),
            if (gastos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Aún no se han creado gastos para este presupuesto.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Usa el botón "Agregar Gasto" para comenzar.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...gastos.map((g) {
                return ListTile(
                  title: Text(g['descripcion']),
                  subtitle: Text(
                    '\$${_toDouble(g['monto']).toStringAsFixed(2)} - ${g['tipo']}',
                  ),
                  trailing: Checkbox(
                    value: g['pagado'] == 1,
                    onChanged: g['pagado'] == 1
                        ? null
                        : (_) {
                      _mostrarModalPagoMovimiento(
                        movimientoId: g['id'],
                        montoSugerido: _toDouble(g['monto']),
                      );
                    },
                  ),

                );
              }).toList(),

          ],
        ),
      ),
    );
  }
  Future<void> _crearMovimientos(List items) async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com'
          '/presupuestos/${widget.presupuesto['id']}/movimientos',
    );

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firebase_uid': widget.firebaseUid,
        'items': items,
      }),
    );

    if (res.statusCode != 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creando movimientos')),
      );
    }
  }

  Future<void> _pagarMovimiento({
    required int movimientoId,
    required double montoPagado,
  }) async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/movimientos/$movimientoId/pagar',
    );

    final res = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pagado': 1,
        'monto_pagado_real': montoPagado,
        'firebase_uid': widget.firebaseUid,
      }),
    );

    if (res.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al marcar como pagado')),
      );
      return;
    }

    _cargarGastos(); // refresca la vista
  }

  void _mostrarModalPagoMovimiento({
    required int movimientoId,
    required double montoSugerido,
  }) {
    final montoCtrl = TextEditingController(
      text: montoSugerido.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Registrar pago'),
        content: TextField(
          controller: montoCtrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Monto pagado real',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final monto = double.tryParse(montoCtrl.text) ?? 0;

              if (monto <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Monto inválido')),
                );
                return;
              }

              await _pagarMovimiento(
                movimientoId: movimientoId,
                montoPagado: monto,
              );

              Navigator.pop(context);
            },
            child: Text('Confirmar pago'),
          ),
        ],
      ),
    );
  }


  // ===============================
  // MODAL AGREGAR GASTO
  // ===============================
  void _mostrarModalAgregarGasto() async {
    List<dynamic> gastosDisponibles = [];
    Map<int, bool> seleccionados = {};
    Map<int, TextEditingController> montosCtrl = {};

    try {
      gastosDisponibles = await _cargarGastosSeleccionables();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando gastos')),
      );
      return;
    }

    if (gastosDisponibles.isEmpty) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Sin gastos'),
          content: Text(
            'No hay ningún gasto asignado para este presupuesto.\n'
                'Debes crear al menos un gasto antes de continuar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _mostrarModalCrearGasto();
              },
              child: Text('Crear gasto'),
            ),
          ],
        ),
      );

      return;
    }


    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Seleccionar gastos'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: gastosDisponibles.map((g) {
                final id = g['id'];

                seleccionados[id] ??= false;
                montosCtrl[id] ??=
                    TextEditingController(text: g['monto'].toString());

                return Row(
                  children: [
                    Checkbox(
                      value: seleccionados[id],
                      onChanged: (v) {
                        setModalState(() {
                          seleccionados[id] = v ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: Text(g['descripcion']),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: montosCtrl[id],
                        keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          prefixText: '\$',
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _mostrarModalCrearGasto(); // modal viejo intacto
              },
              child: Text('Crear gasto nuevo'),
            ),
            ElevatedButton(
              onPressed: () async {
                final items = gastosDisponibles
                    .where((g) => seleccionados[g['id']] == true)
                    .map((g) {
                  final monto =
                      double.tryParse(montosCtrl[g['id']]!.text) ?? 0;
                  if (monto <= 0) return null;

                  return {
                    'gasto_id': g['id'],
                    'monto': monto,
                  };
                })
                    .where((e) => e != null)
                    .toList();

                if (items.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selecciona gastos válidos')),
                  );
                  return;
                }

                await _crearMovimientos(items);
                Navigator.pop(context);
                _cargarGastos(); // refresca vista
              },
              child: Text('Agregar seleccionados'),
            ),
          ],
        ),
      ),
    );
  }

}
