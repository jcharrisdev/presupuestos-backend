import 'package:flutter/material.dart';
import 'services/shared_budget_service.dart';
import 'theme/app_theme.dart';

class SharedBudgetCreateScreen extends StatefulWidget {
  final String firebaseUid;
  const SharedBudgetCreateScreen({super.key, required this.firebaseUid});

  @override
  State<SharedBudgetCreateScreen> createState() => _SharedBudgetCreateScreenState();
}

class _SharedBudgetCreateScreenState extends State<SharedBudgetCreateScreen> {
  final _nombreCtrl        = TextEditingController();
  final _emailCtrl         = TextEditingController();
  final _ingresoCtrl       = TextEditingController();
  final _contribucionCtrl  = TextEditingController();

  String _tipoPeriodo = 'mensual';
  String _regla = 'equitativo';
  double _pctOwner = 50;
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _ingresoCtrl.dispose();
    _contribucionCtrl.dispose();
    super.dispose();
  }

  bool _emailValido(String email) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (nombre.isEmpty) { _snack('Ingresa un nombre'); return; }
    if (email.isEmpty || !_emailValido(email)) { _snack('Ingresa un email válido'); return; }
    if (_regla == 'proporcional' && (double.tryParse(_ingresoCtrl.text) ?? 0) <= 0) {
      _snack('Ingresa tu ingreso mensual'); return;
    }
    if (_regla == 'pool_contribucion' && (double.tryParse(_contribucionCtrl.text) ?? 0) <= 0) {
      _snack('Ingresa tu contribución mensual al fondo'); return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'nombre': nombre,
      'tipo_periodo': _tipoPeriodo,
      'dia_inicio_periodo': 1,
      'regla_reparto': _regla,
      'firebase_uid': widget.firebaseUid,
      if (_regla == 'porcentual') 'porcentaje_owner': _pctOwner,
      if (_regla == 'proporcional') 'ingreso_owner': double.tryParse(_ingresoCtrl.text) ?? 0,
      if (_regla == 'pool_contribucion') 'contribucion_owner': double.tryParse(_contribucionCtrl.text) ?? 0,
    };
    final result = await SharedBudgetService.create(body);
    if (!mounted) return;
    if (result != null) {
      final ok = await SharedBudgetService.invite(result['id'], email, widget.firebaseUid);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Presupuesto creado e invitación enviada'), backgroundColor: AppTheme.success,
        ));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Presupuesto creado, pero hubo un error al invitar'), backgroundColor: AppTheme.warning,
        ));
        Navigator.pop(context);
      }
    } else {
      _snack('Error al crear el presupuesto');
    }
    setState(() => _saving = false);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Nuevo compartido', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Nombre del presupuesto'),
          const SizedBox(height: 6),
          _input(_nombreCtrl, 'Ej: Gastos del hogar'),
          const SizedBox(height: 20),
          _label('Período'),
          const SizedBox(height: 6),
          _periodoToggle(),
          const SizedBox(height: 20),
          _label('Regla de reparto'),
          const SizedBox(height: 6),
          _reglaDropdown(),
          if (_regla == 'porcentual') ...[
            const SizedBox(height: 16),
            _label('Tu porcentaje: ${_pctOwner.toStringAsFixed(0)}%  ·  Otro: ${(100 - _pctOwner).toStringAsFixed(0)}%'),
            Slider(
              value: _pctOwner, min: 10, max: 90, divisions: 16,
              activeColor: AppTheme.primary,
              onChanged: (v) => setState(() => _pctOwner = v),
            ),
          ],
          if (_regla == 'proporcional') ...[
            const SizedBox(height: 16),
            _label('Tu ingreso mensual'),
            const SizedBox(height: 6),
            _input(_ingresoCtrl, '0.00', numeric: true),
          ],
          if (_regla == 'pool_contribucion') ...[
            const SizedBox(height: 16),
            _label('Tu contribución mensual al fondo (\$)'),
            const SizedBox(height: 6),
            _input(_contribucionCtrl, '0.00', numeric: true),
            const SizedBox(height: 6),
            const Text(
              'El invitado declarará su contribución al aceptar la invitación. '
              'El fondo total = tu aporte + el de tu compañero.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          _label('Email del co-dueño'),
          const SizedBox(height: 6),
          _input(_emailCtrl, 'correo@ejemplo.com', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 8),
          const Text('El invitado verá la invitación cuando abra la sección "Compartido".',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Crear y enviar invitación', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600));

  Widget _input(TextEditingController ctrl, String hint, {TextInputType? keyboard, bool numeric = false}) => TextField(
    controller: ctrl,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : keyboard,
    style: const TextStyle(color: AppTheme.textPrimary),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textMuted),
      filled: true,
      fillColor: AppTheme.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );

  Widget _periodoToggle() => Container(
    decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
    child: Row(children: ['mensual', 'quincenal'].map((p) {
      final selected = _tipoPeriodo == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tipoPeriodo = p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              p == 'mensual' ? 'Mensual' : 'Quincenal',
              style: TextStyle(color: selected ? Colors.black : AppTheme.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }).toList()),
  );

  Widget _reglaDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _regla,
        isExpanded: true,
        dropdownColor: AppTheme.surface,
        style: const TextStyle(color: AppTheme.textPrimary),
        items: const [
          DropdownMenuItem(value: 'equitativo', child: Text('50/50 equitativo')),
          DropdownMenuItem(value: 'porcentual', child: Text('Porcentual manual')),
          DropdownMenuItem(value: 'proporcional', child: Text('Proporcional a ingresos')),
          DropdownMenuItem(value: 'pool_contribucion', child: Text('Fondo común (cada uno aporta su monto)')),
        ],
        onChanged: (v) => setState(() => _regla = v!),
      ),
    ),
  );
}
