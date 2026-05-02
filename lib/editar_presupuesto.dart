/// Pantalla de edición de un presupuesto existente.
///
/// Solo permite cambiar el nombre y el monto total.
/// El tipo de período y el día de inicio NO son editables una vez creado
/// porque cambiarlos alteraría el historial de períodos ya generados.
///
/// Al guardar llama a PUT /presupuestos/:id y hace `Navigator.pop(true)`
/// para que la pantalla anterior sepa que debe recargar los datos.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

/// Formulario de edición de nombre y monto de un presupuesto.
class EditarPresupuesto extends StatefulWidget {
  /// Objeto completo del presupuesto a editar (incluye `id`, `nombre`, `monto_total`).
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
    // Pre-rellenar los campos con los valores actuales del presupuesto
    _nombreCtrl = TextEditingController(text: widget.presupuesto['nombre']);
    _montoCtrl  = TextEditingController(text: widget.presupuesto['monto_total'].toString());
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  /// Guarda los cambios enviando PUT /presupuestos/:id al backend.
  ///
  /// Retorna `true` al hacer pop para que el caller sepa recargar.
  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final monto  = double.tryParse(_montoCtrl.text);
    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa todos los campos')));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiClient.put(
        '/presupuestos/${widget.presupuesto['id']}',
        {'nombre': nombre, 'monto_total': monto, 'firebase_uid': widget.firebaseUid},
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true); // true = se guardaron cambios
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
      appBar: AppBar(
        title: const Text('Editar Presupuesto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Editar presupuesto',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Aquí puedes cambiar el nombre o el monto total del presupuesto.\n\n'
                  '• El nombre es solo para identificarlo en la lista.\n'
                  '• El monto total es el límite de gasto por período. '
                  'Cambiarlo afecta el período actual y todos los futuros.\n\n'
                  'El tipo de período y el día de inicio no se pueden cambiar una vez creado '
                  'el presupuesto para mantener el historial de períodos consistente.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── NOMBRE ────────────────────────────────────────────────────
          const Text('Nombre', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          TextField(
            controller: _nombreCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Nombre del presupuesto'),
          ),
          const SizedBox(height: 20),

          // ── MONTO ─────────────────────────────────────────────────────
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

          // Spacer empuja el botón al fondo de la pantalla
          const Spacer(),

          // ── BOTÓN GUARDAR ─────────────────────────────────────────────
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
