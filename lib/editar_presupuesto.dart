import 'package:flutter/material.dart';
import 'dart:convert';
import 'services/api_client.dart';

class EditarPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;

  const EditarPresupuesto({
    Key? key,
    required this.presupuesto,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _EditarPresupuestoState createState() => _EditarPresupuestoState();
}

class _EditarPresupuestoState extends State<EditarPresupuesto> {
  late TextEditingController _nombreController;
  late TextEditingController _montoController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.presupuesto['nombre']);
    _montoController = TextEditingController(text: widget.presupuesto['monto_total'].toString());
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _actualizarPresupuesto() async {
    final nombre = _nombreController.text.trim();
    final monto = double.tryParse(_montoController.text);

    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre y monto válidos son obligatorios')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await ApiClient.put(
        '/presupuestos/${widget.presupuesto['id']}',
        {'nombre': nombre, 'monto_total': monto, 'firebase_uid': widget.firebaseUid},
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Presupuesto actualizado')),
        );
        Navigator.pop(context, true);
      } else {
        final err = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['error'] ?? 'Error al actualizar')),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Presupuesto'),
        backgroundColor: const Color(0xFF6ABF69),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre del Presupuesto'),
            ),
            TextField(
              controller: _montoController,
              decoration: const InputDecoration(labelText: 'Monto Total'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _actualizarPresupuesto,
                    child: const Text('Guardar Cambios'),
                  ),
          ],
        ),
      ),
    );
  }
}
