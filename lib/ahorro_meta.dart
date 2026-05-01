import 'package:flutter/material.dart';
import 'dart:convert';
import 'services/api_client.dart';
import 'progreso_ahorro.dart';

class AhorroMetaScreen extends StatefulWidget {
  final String firebaseUid;

  const AhorroMetaScreen({Key? key, required this.firebaseUid}) : super(key: key);

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
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _obtenerPresupuestos();
  }

  Future<void> _obtenerPresupuestos() async {
    try {
      final response = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _presupuestos = List<Map<String, dynamic>>.from(data);
          _cargandoPresupuestos = false;
        });
      } else {
        throw Exception();
      }
    } catch (_) {
      setState(() => _cargandoPresupuestos = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al cargar presupuestos')),
      );
    }
  }

  Future<void> _crearMetaAhorro() async {
    if (_nombreController.text.isEmpty ||
        _montoController.text.isEmpty ||
        _presupuestoSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos')),
      );
      return;
    }

    final monto = double.tryParse(_montoController.text);
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto inválido')),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final response = await ApiClient.post('/gastos/ahorroMeta', {
        'presupuesto_id': _presupuestoSeleccionadoId,
        'descripcion': _nombreController.text.trim(),
        'monto': monto,
        'tipo': 'ahorro',
        'fecha': DateTime.now().toIso8601String().split('T')[0],
        'tiempo_meses': _tiempoMeses,
        'firebase_uid': widget.firebaseUid,
      });

      if (!mounted) return;

      if (response.statusCode == 201) {
        _nombreController.clear();
        _montoController.clear();
        setState(() => _presupuestoSeleccionadoId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ahorro / Meta creado correctamente')),
        );
      } else {
        throw Exception();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al crear ahorro/meta')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
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
        title: const Text('Ahorro Personal / Meta'),
        backgroundColor: const Color(0xFF6ABF69),
      ),
      body: _cargandoPresupuestos
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nombreController,
                    decoration: const InputDecoration(labelText: 'Nombre de la Meta'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _montoController,
                    decoration: const InputDecoration(labelText: 'Monto a Ahorrar'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Presupuesto'),
                    value: _presupuestoSeleccionadoId,
                    items: _presupuestos.map((p) => DropdownMenuItem<int>(
                      value: p['id'],
                      child: Text(p['nombre']),
                    )).toList(),
                    onChanged: (v) => setState(() => _presupuestoSeleccionadoId = v),
                  ),
                  const SizedBox(height: 20),
                  Text('Tiempo para alcanzar la meta: $_tiempoMeses meses'),
                  Slider(
                    value: _tiempoMeses.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    label: '$_tiempoMeses',
                    onChanged: (v) => setState(() => _tiempoMeses = v.toInt()),
                  ),
                  const SizedBox(height: 20),
                  _guardando
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _crearMetaAhorro,
                          child: const Text('Crear Ahorro / Meta'),
                        ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProgresoAhorroScreen(firebaseUid: widget.firebaseUid),
                      ),
                    ),
                    child: const Text('Ver Progreso del Ahorro'),
                  ),
                ],
              ),
            ),
    );
  }
}
