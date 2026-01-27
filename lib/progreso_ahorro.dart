import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProgresoAhorroScreen extends StatefulWidget {
  @override
  _ProgresoAhorroScreenState createState() => _ProgresoAhorroScreenState();
}

class _ProgresoAhorroScreenState extends State<ProgresoAhorroScreen> {
  List<dynamic> ahorros = [];

  @override
  void initState() {
    super.initState();
    _cargarAhorros();
  }

  Future<void> _cargarAhorros() async {
    final url = Uri.parse('http://localhost:3002/ahorros'); // Cambia 192.168.X.X por tu IP local
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        ahorros = data;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al cargar los ahorros'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Progreso de Ahorros'),
        backgroundColor: Color(0xFF6ABF69), // Verde pastel, reflejando el dinero
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ahorros.isEmpty
            ? Text('No hay ahorros registrados.')
            : ListView.builder(
          itemCount: ahorros.length,
          itemBuilder: (context, index) {
            final ahorro = ahorros[index];
            final montoTotal = double.tryParse(ahorro['monto_meta'].toString()) ?? 0.0;
            final montoAhorrado = double.tryParse(ahorro['monto_ahorrado'].toString()) ?? 0.0;

            double porcentajeCompletado = 0.0;

            // Evitar división por cero
            if (montoTotal > 0) {
              porcentajeCompletado = montoAhorrado / montoTotal;
            }

            return Card(
              elevation: 3,
              margin: EdgeInsets.symmetric(vertical: 10),
              child: ListTile(
                title: Text(ahorro['nombre']),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monto total: \$${montoTotal.toStringAsFixed(2)}'),
                    Text('Ahorrado: \$${montoAhorrado.toStringAsFixed(2)}'),

                    SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: porcentajeCompletado,
                      backgroundColor: Colors.grey[300],
                      color: Colors.green,
                      minHeight: 20,
                    ),
                    Text('${(porcentajeCompletado * 100).toStringAsFixed(2)}% completado'),
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _eliminarAhorro(ahorro['id']);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _eliminarAhorro(int id) async {
    final url = Uri.parse('http://localhost:3002/ahorros/$id');
    final response = await http.delete(url);

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ahorro eliminado con éxito'),
      ));
      _cargarAhorros(); // Recargar la lista
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al eliminar el ahorro'),
      ));
    }
  }
}
