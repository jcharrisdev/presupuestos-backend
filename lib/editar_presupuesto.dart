import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class EditarPresupuesto extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final String firebaseUid;
  const EditarPresupuesto({Key? key, required this.presupuesto, required this.firebaseUid}) : super(key: key);

  @override
  _EditarPresupuestoState createState() => _EditarPresupuestoState();
}

class _EditarPresupuestoState extends State<EditarPresupuesto> {
  late TextEditingController _nombreCtrl;
  late TextEditingController _montoCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.presupuesto['nombre']);
    _montoCtrl  = TextEditingController(text: widget.presupuesto['monto_total'].toString());
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final monto  = double.tryParse(_montoCtrl.text);
    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa todos los campos')));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiClient.put('/presupuestos/${widget.presupuesto['id']}',
          {'nombre': nombre, 'monto_total': monto, 'firebase_uid': widget.firebaseUid});
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final err = json.decode(res.body);
        throw Exception(err['error'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Presupuesto')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nombre', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          TextField(
            controller: _nombreCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Nombre del presupuesto'),
          ),
          const SizedBox(height: 20),
          const Text('Monto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : ElevatedButton(onPressed: _guardar, child: const Text('Guardar cambios')),
          ),
        ]),
      ),
    );
  }
}
