import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EditarPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;

  EditarPresupuesto({required this.presupuesto});

  @override
  _EditarPresupuestoState createState() => _EditarPresupuestoState();
}

class _EditarPresupuestoState extends State<EditarPresupuesto> {
  late TextEditingController _nombreController;
  late TextEditingController _montoController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.presupuesto['nombre']);
    _montoController = TextEditingController(text: widget.presupuesto['monto_total'].toString());
  }

  Future<void> _actualizarPresupuesto() async {
    final String nombre = _nombreController.text;
    final String monto = _montoController.text;

    final url = Uri.parse('https://presupuestos-backend-h3l6.onrender.com/presupuestos/${widget.presupuesto['id']}');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nombre': nombre,
        'monto_total': double.parse(monto),
      }),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Presupuesto actualizado con éxito'),
      ));
      Navigator.pop(context); // Volver a la pantalla anterior
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al actualizar el presupuesto'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar Presupuesto')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: InputDecoration(labelText: 'Nombre del Presupuesto'),
            ),
            TextField(
              controller: _montoController,
              decoration: InputDecoration(labelText: 'Monto Total'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _actualizarPresupuesto,
              child: Text('Guardar Cambios'),
            ),
          ],
        ),
      ),
    );
  }
}
