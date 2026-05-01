import 'package:flutter/material.dart';
import 'dart:convert';
import 'services/api_client.dart';

class ProgresoAhorroScreen extends StatefulWidget {
  final String firebaseUid;

  const ProgresoAhorroScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _ProgresoAhorroScreenState createState() => _ProgresoAhorroScreenState();
}

class _ProgresoAhorroScreenState extends State<ProgresoAhorroScreen> {
  List<dynamic> ahorros = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarAhorros();
  }

  Future<void> _cargarAhorros() async {
    try {
      final response = await ApiClient.get('/ahorros?firebase_uid=${widget.firebaseUid}');
      if (response.statusCode == 200) {
        setState(() {
          ahorros = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        _showError('Error al cargar los ahorros');
      }
    } catch (_) {
      setState(() => isLoading = false);
      _showError('Error de conexión');
    }
  }

  Future<void> _eliminarAhorro(int id) async {
    try {
      final response = await ApiClient.delete('/ahorros/$id');
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ahorro eliminado')),
        );
        _cargarAhorros();
      } else {
        _showError('Error al eliminar el ahorro');
      }
    } catch (_) {
      _showError('Error de conexión');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progreso de Ahorros'),
        backgroundColor: const Color(0xFF6ABF69),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ahorros.isEmpty
                  ? const Center(child: Text('No hay ahorros registrados.'))
                  : ListView.builder(
                      itemCount: ahorros.length,
                      itemBuilder: (context, index) {
                        final ahorro = ahorros[index];
                        final montoTotal = double.tryParse(ahorro['monto_meta'].toString()) ?? 0.0;
                        final montoAhorrado = double.tryParse(ahorro['monto_ahorrado'].toString()) ?? 0.0;
                        final porcentaje = montoTotal > 0 ? montoAhorrado / montoTotal : 0.0;

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          child: ListTile(
                            title: Text(ahorro['nombre']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Meta: \$${montoTotal.toStringAsFixed(2)}'),
                                Text('Ahorrado: \$${montoAhorrado.toStringAsFixed(2)}'),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: porcentaje.clamp(0.0, 1.0),
                                  backgroundColor: Colors.grey[300],
                                  color: Colors.green,
                                  minHeight: 20,
                                ),
                                Text('${(porcentaje * 100).toStringAsFixed(1)}% completado'),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _eliminarAhorro(ahorro['id']),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
