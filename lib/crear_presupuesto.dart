import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;

  const CrearPresupuesto({
    Key? key,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _CrearPresupuestoState createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();

  // NUEVO
  String _tipoPeriodo = 'quincenal'; // quincenal | mensual
  int _diaInicio = 1; // 1 a 31

  // ===============================
  // CREAR PRESUPUESTO
  // ===============================
  Future<void> _crearPresupuesto() async {
    final String nombre = _nombreController.text.trim();
    final String montoTexto = _montoController.text.trim();

    if (nombre.isEmpty || montoTexto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Por favor, completa todos los campos')),
      );
      return;
    }

    final double? monto = double.tryParse(montoTexto);
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Monto inválido')),
      );
      return;
    }

    final url = Uri.parse(
      'https://presupuestos-backend-h3l6.onrender.com/presupuestos',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre': nombre,
          'monto_total': monto,
          'firebase_uid': widget.firebaseUid,

          // NUEVO
          'tipo_periodo': _tipoPeriodo,
          'dia_inicio_periodo': _diaInicio,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Presupuesto creado con éxito')),
        );

        Navigator.pop(context);
      } else {
        throw Exception('Error al crear el presupuesto');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear el presupuesto')),
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
      appBar: AppBar(title: Text('Crear Presupuesto')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: InputDecoration(
                labelText: 'Nombre del Presupuesto',
              ),
            ),

            TextField(
              controller: _montoController,
              decoration: InputDecoration(labelText: 'Monto Total'),
              keyboardType:
              TextInputType.numberWithOptions(decimal: true),
            ),

            const SizedBox(height: 20),

            // ===============================
            // TIPO DE PERÍODO
            // ===============================
            DropdownButtonFormField<String>(
              value: _tipoPeriodo,
              decoration: InputDecoration(
                labelText: 'Tipo de período',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'quincenal',
                  child: Text('Quincenal (14 días)'),
                ),
                DropdownMenuItem(
                  value: 'mensual',
                  child: Text('Mensual (30 días)'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _tipoPeriodo = value!;
                });
              },
            ),

            const SizedBox(height: 20),

            // ===============================
            // DÍA DE INICIO
            // ===============================
            DropdownButtonFormField<int>(
              value: _diaInicio,
              decoration: InputDecoration(
                labelText: 'Día de inicio del período',
              ),
              items: List.generate(31, (index) {
                final day = index + 1;
                return DropdownMenuItem(
                  value: day,
                  child: Text(day.toString()),
                );
              }),
              onChanged: (value) {
                setState(() {
                  _diaInicio = value!;
                });
              },
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _crearPresupuesto,
              child: Text('Crear Presupuesto'),
            ),
          ],
        ),
      ),
    );
  }
}
