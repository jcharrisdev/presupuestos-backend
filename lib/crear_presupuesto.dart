import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;
  const CrearPresupuesto({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CrearPresupuestoState createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl  = TextEditingController();
  String _tipoPeriodo = 'mensual';
  int _diaInicio = 1;
  bool _loading = false;

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    final monto  = double.tryParse(_montoCtrl.text.trim());

    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos correctamente')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await ApiClient.post('/presupuestos', {
        'nombre': nombre, 'monto_total': monto,
        'firebase_uid': widget.firebaseUid,
        'tipo_periodo': _tipoPeriodo, 'dia_inicio_periodo': _diaInicio,
      });

      if (res.statusCode == 201) {
        if (!mounted) return;
        Navigator.pop(context);
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
  void dispose() { _nombreCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo Presupuesto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Nombre del presupuesto'),
            TextField(
              controller: _nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Ej: Casa, Trabajo, Personal...'),
            ),
            const SizedBox(height: 20),

            _label('Monto total del período'),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(prefixText: '\$ ', prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 20),

            _label('Tipo de período'),
            Row(children: [
              _PeriodOption(
                label: 'Quincenal', sub: '14 días',
                selected: _tipoPeriodo == 'quincenal',
                onTap: () => setState(() => _tipoPeriodo = 'quincenal'),
              ),
              const SizedBox(width: 12),
              _PeriodOption(
                label: 'Mensual', sub: '30 días',
                selected: _tipoPeriodo == 'mensual',
                onTap: () => setState(() => _tipoPeriodo = 'mensual'),
              ),
            ]),
            const SizedBox(height: 20),

            _label('Día de inicio del período'),
            DropdownButtonFormField<int>(
              value: _diaInicio,
              dropdownColor: AppTheme.surfaceAlt,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(),
              items: List.generate(31, (i) => DropdownMenuItem(
                value: i + 1,
                child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
              )),
              onChanged: (v) => setState(() => _diaInicio = v!),
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : ElevatedButton(onPressed: _crear, child: const Text('Crear Presupuesto')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
  );
}

class _PeriodOption extends StatelessWidget {
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodOption({required this.label, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withOpacity(0.1) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: selected ? 1.5 : 1),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(color: selected ? AppTheme.primary : AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(color: selected ? AppTheme.primary.withOpacity(0.7) : AppTheme.textMuted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}
