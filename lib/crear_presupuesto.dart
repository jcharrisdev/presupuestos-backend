import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/user_profile_service.dart';
import 'perfil_financiero_screen.dart';

/// Pantalla para crear un nuevo presupuesto.
/// Con el nuevo modelo, el presupuesto se CALCULA automáticamente desde
/// el ingreso global del usuario — no se inventa un monto.
///
/// Flujo:
///   1. Verificar que existe user_income (si no, redirige a PerfilFinanciero)
///   2. Solo pedir nombre + tipo de período
///   3. Backend calcula monto_total = ingreso_neto_mensual / divisor
///   4. Backend copia user_gastos_fijos como movimientos del primer período
class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;
  const CrearPresupuesto({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<CrearPresupuesto> createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final _nombreCtrl = TextEditingController();
  String _tipoPeriodo = 'quincenal';
  int _diaInicio = 1;
  bool _loading = false;
  bool _checkingIncome = true;
  Map<String, dynamic>? _income;
  Map<String, dynamic>? _perfil;

  @override
  void initState() {
    super.initState();
    _verificarIncome();
  }

  @override
  void dispose() { _nombreCtrl.dispose(); super.dispose(); }

  Future<void> _verificarIncome() async {
    setState(() => _checkingIncome = true);
    final income = await UserProfileService.getIncome(widget.firebaseUid);
    final perfil = income != null
        ? await UserProfileService.getPerfilCompleto(widget.firebaseUid)
        : null;
    if (!mounted) return;
    setState(() { _income = income; _perfil = perfil; _checkingIncome = false; });
  }

  double get _ingresoNeto => double.tryParse(
      _income?['ingreso_neto_mensual']?.toString() ?? '0') ?? 0;

  double get _ingresoNominal {
    return _tipoPeriodo == 'quincenal' ? _ingresoNeto / 2 : _ingresoNeto;
  }

  double get _compromisosPeriodo {
    final totalMensual = double.tryParse(
        _perfil?['resumen']?['total_compromisos_mensual']?.toString() ?? '0') ?? 0;
    return _tipoPeriodo == 'quincenal' ? totalMensual / 2 : totalMensual;
  }

  double get _disponiblePeriodo => _ingresoNominal - _compromisosPeriodo;

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un nombre para el presupuesto')));
      return;
    }
    if (_income == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero configura tu ingreso en el Perfil Financiero')));
      return;
    }
    setState(() => _loading = true);
    try {
      // El backend calcula monto_total desde user_income automáticamente
      final res = await ApiClient.post('/presupuestos', {
        'nombre': nombre,
        'firebase_uid': widget.firebaseUid,
        'tipo_periodo': _tipoPeriodo,
        'dia_inicio_periodo': _diaInicio,
      });
      if (res.statusCode == 201) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final err = json.decode(res.body)['error'] ?? 'Error al crear';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Nuevo presupuesto'),
      ),
      body: _checkingIncome
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _income == null
              ? _buildSinIncome()
              : _buildFormulario(),
    );
  }

  // ── Sin income configurado ───────────────────────────────────────────────
  Widget _buildSinIncome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.textMuted, size: 56),
          const SizedBox(height: 16),
          const Text('Primero configura tu ingreso',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Para crear un presupuesto real necesitas registrar cuánto ganas. '
            'El presupuesto se calcula automáticamente a partir de tu ingreso.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PerfilFinancieroScreen(firebaseUid: widget.firebaseUid),
              ));
              _verificarIncome();
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Configurar perfil financiero'),
          ),
        ]),
      ),
    );
  }

  // ── Formulario principal ─────────────────────────────────────────────────
  Widget _buildFormulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Preview de lo que se calculará
        _buildPreviewCard(),
        const SizedBox(height: 24),

        _label('Nombre del presupuesto'),
        TextField(
          controller: _nombreCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Ej: Casa, Trabajo, Personal...'),
        ),
        const SizedBox(height: 20),

        _label('Tipo de período'),
        Row(children: [
          _PeriodOption(label: 'Quincenal', sub: '14 días',
              selected: _tipoPeriodo == 'quincenal',
              onTap: () => setState(() => _tipoPeriodo = 'quincenal')),
          const SizedBox(width: 12),
          _PeriodOption(label: 'Mensual', sub: '30 días',
              selected: _tipoPeriodo == 'mensual',
              onTap: () => setState(() => _tipoPeriodo = 'mensual')),
        ]),
        const SizedBox(height: 20),

        _label('Día de inicio del período'),
        DropdownButtonFormField<int>(
          value: _diaInicio,
          dropdownColor: AppTheme.surfaceAlt,
          style: const TextStyle(color: AppTheme.textPrimary),
          items: List.generate(28, (i) => DropdownMenuItem(
            value: i + 1,
            child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
          )),
          onChanged: (v) => setState(() => _diaInicio = v!),
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _crear,
            child: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Crear presupuesto'),
          ),
        ),
      ]),
    );
  }

  Widget _buildPreviewCard() {
    final sostenible = _disponiblePeriodo >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: sostenible ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calculate_outlined,
              color: sostenible ? AppTheme.success : AppTheme.danger, size: 16),
          const SizedBox(width: 6),
          Text('Tu presupuesto ${_tipoPeriodo == "quincenal" ? "quincenal" : "mensual"}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        _PreviewRow('Ingreso neto',
            '\$${_ingresoNominal.toStringAsFixed(2)}', AppTheme.success),
        _PreviewRow('Compromisos fijos',
            '-\$${_compromisosPeriodo.toStringAsFixed(2)}', AppTheme.danger),
        const Divider(color: AppTheme.border, height: 16),
        _PreviewRow(
          'Disponible para gastos variables',
          '\$${_disponiblePeriodo.abs().toStringAsFixed(2)}',
          sostenible ? AppTheme.primary : AppTheme.danger,
          bold: true,
          prefix: sostenible ? '' : '-',
        ),
        if (!sostenible) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Tus compromisos superan tu ingreso. Revisa tus gastos fijos en el Perfil Financiero.',
              style: TextStyle(color: AppTheme.danger, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  final String prefix;
  const _PreviewRow(this.label, this.value, this.color, {this.bold = false, this.prefix = ''});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      Text('$prefix$value', style: TextStyle(
          color: color, fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
    ]),
  );
}

class _PeriodOption extends StatelessWidget {
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodOption({required this.label, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: selected ? 2 : 1),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ]),
    ),
  ));
}
