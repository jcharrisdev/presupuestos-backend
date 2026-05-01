import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'progreso_ahorro.dart';

class AhorroMetaScreen extends StatefulWidget {
  final String firebaseUid;

  const AhorroMetaScreen({
    Key? key,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _AhorroMetaScreenState createState() => _AhorroMetaScreenState();
}

class _AhorroMetaScreenState extends State<AhorroMetaScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();

  int _tiempoMeses = 12;

  List<Map<String, dynamic>> _presupuestos = [];
  int? _presupuestoSeleccionadoId;

  bool _cargandoPresupuestos = true;

  @override
  void initState() {
    super.initState();
    _obtenerPresupuestos();
  }

  // ===============================
  // OBTENER PRESUPUESTOS DEL USUARIO
  // ===============================
  Future<void> _obtenerPresupuestos() async {
    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/presupuestos'
          '?firebase_uid=${widget.firebaseUid}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _presupuestos = List<Map<String, dynamic>>.from(data);
          _cargandoPresupuestos = false;
        });
      } else {
        throw Exception('Error al obtener presupuestos');
      }
    } catch (e) {
      setState(() {
        _cargandoPresupuestos = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar presupuestos')),
      );
    }
  }

  // ===============================
  // CREAR META DE AHORRO
  // ===============================
  Future<void> _crearMetaAhorro() async {
    if (_nombreController.text.isEmpty ||
        _montoController.text.isEmpty ||
        _presupuestoSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completa todos los campos')),
      );
      return;
    }

    final monto = double.tryParse(_montoController.text);
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Monto inválido')),
      );
      return;
    }

    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/gastos/ahorroMeta',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'presupuesto_id': _presupuestoSeleccionadoId,
          'descripcion': _nombreController.text,
          'monto': monto,
          'tipo': 'ahorro',
          'fecha': DateTime.now().toIso8601String(),
          'tiempo_meses': _tiempoMeses,
          'firebase_uid': widget.firebaseUid,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ahorro / Meta creado correctamente')),
        );
      } else {
        throw Exception();
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear ahorro/meta')),
      );
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ahorro Personal / Meta'),
        backgroundColor: Color(0xFF6ABF69),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _cargandoPresupuestos
            ? Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombreController,
              decoration:
              InputDecoration(labelText: 'Nombre de la Meta'),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _montoController,
              decoration:
              InputDecoration(labelText: 'Monto a Ahorrar'),
              keyboardType:
              TextInputType.numberWithOptions(decimal: true),
            ),
            SizedBox(height: 10),

            // ===============================
            // DROPDOWN DE PRESUPUESTOS
            // ===============================
            DropdownButtonFormField<int>(
              decoration:
              InputDecoration(labelText: 'Presupuesto'),
              value: _presupuestoSeleccionadoId,
              items: _presupuestos.map((p) {
                return DropdownMenuItem<int>(
                  value: p['id'],
                  child: Text(p['nombre']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _presupuestoSeleccionadoId = value;
                });
              },
            ),

            SizedBox(height: 20),
            Text(
              'Tiempo para alcanzar la meta: $_tiempoMeses meses',
            ),
            Slider(
              value: _tiempoMeses.toDouble(),
              min: 1,
              max: 60,
              divisions: 59,
              label: '$_tiempoMeses',
              onChanged: (value) {
                setState(() {
                  _tiempoMeses = value.toInt();
                });
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _crearMetaAhorro,
              child: Text('Crear Ahorro / Meta'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgresoAhorroScreen(firebaseUid: widget.firebaseUid),
                  ),
                );
              },
              child: Text('Ver Progreso del Ahorro'),
            ),
          ],
        ),
      ),
    );
  }
}
