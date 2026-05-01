import 'package:flutter/material.dart';
import 'dart:convert';
import 'services/api_client.dart';

class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;

  const CrearPresupuesto({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CrearPresupuestoState createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();
  String _tipoPeriodo = 'quincenal';
  int _diaInicio = 1;
  bool _loading = false;

  Future<void> _crearPresupuesto() async {
    final nombre = _nombreController.text.trim();
    final monto = double.tryParse(_montoController.text.trim());

    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos correctamente')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await ApiClient.post('/presupuestos', {
        'nombre': nombre,
        'monto_total': monto,
        'firebase_uid': widget.firebaseUid,
        'tipo_periodo': _tipoPeriodo,
        'dia_inicio_periodo': _diaInicio,
      });

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Presupuesto creado con éxito')),
        );
        Navigator.pop(context);
      } else {
        final err = json.decode(response.body);
        throw Exception(err['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Presupuesto'),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _tipoPeriodo,
              decoration: const InputDecoration(labelText: 'Tipo de período'),
              items: const [
                DropdownMenuItem(value: 'quincenal', child: Text('Quincenal (14 días)')),
                DropdownMenuItem(value: 'mensual', child: Text('Mensual (30 días)')),
              ],
              onChanged: (v) => setState(() => _tipoPeriodo = v!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              value: _diaInicio,
              decoration: const InputDecoration(labelText: 'Día de inicio del período'),
              items: List.generate(31, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
              onChanged: (v) => setState(() => _diaInicio = v!),
            ),
            const SizedBox(height: 30),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _crearPresupuesto,
                    child: const Text('Crear Presupuesto'),
                  ),
          ],
        ),
      ),
    );
  }
}
