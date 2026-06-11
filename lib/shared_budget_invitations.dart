import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/shared_budget_service.dart';
import 'theme/app_theme.dart';
import 'utils/money.dart';

class SharedBudgetInvitationsScreen extends StatefulWidget {
  final String firebaseUid;
  const SharedBudgetInvitationsScreen({super.key, required this.firebaseUid});

  @override
  State<SharedBudgetInvitationsScreen> createState() => _SharedBudgetInvitationsScreenState();
}

class _SharedBudgetInvitationsScreenState extends State<SharedBudgetInvitationsScreen> {
  List<dynamic> _invitations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final data = await SharedBudgetService.getInvitations(widget.firebaseUid);
    if (mounted) setState(() { _invitations = data; _loading = false; });
  }

  Future<void> _accept(dynamic inv) async {
    double? ingreso;
    if (inv['regla_reparto'] == 'proporcional') {
      ingreso = await _askIngreso();
      if (ingreso == null) return;
    } else if (inv['regla_reparto'] == 'pool_contribucion') {
      ingreso = await _askContribucion();
      if (ingreso == null) return;
    }
    final ok = await SharedBudgetService.acceptInvitation(inv['token'], widget.firebaseUid, ingresoDeclarado: ingreso);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitación aceptada'), backgroundColor: AppTheme.success));
      _cargar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al aceptar'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _reject(dynamic inv) async {
    final ok = await SharedBudgetService.rejectInvitation(inv['token'], widget.firebaseUid);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitación rechazada')));
      _cargar();
    }
  }

  Future<double?> _askIngreso() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Ingreso mensual', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Este presupuesto usa reparto proporcional. Ingresa tu ingreso mensual para calcular tu responsabilidad.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Ingreso mensual', prefixText: 'B/. '),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)),
            child: const Text('Confirmar', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<double?> _askContribucion() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Tu contribución mensual', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Este presupuesto usa fondo común. Ingresa cuánto aportarás mensualmente al fondo compartido.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Contribución mensual', prefixText: 'B/. '),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)),
            child: const Text('Confirmar', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Invitaciones', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _invitations.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _invitations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(_invitations[i]),
                  ),
                ),
    );
  }

  Widget _card(dynamic inv) {
    final expires = DateTime.tryParse(inv['expires_at'] ?? '');
    final expiresStr = expires != null ? DateFormat('dd/MM/yyyy').format(expires) : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(inv['presupuesto_nombre'] ?? '', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('De: ${inv['owner_uid']}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text('Expira: $expiresStr', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _reject(inv),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.danger), foregroundColor: AppTheme.danger),
              child: const Text('Rechazar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _accept(inv),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
              child: const Text('Aceptar'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _empty() => Container(
    color: AppTheme.background,
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.mail_outline, color: AppTheme.textSecondary, size: 56),
        SizedBox(height: 12),
        Text('Sin invitaciones pendientes', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text('Cuando alguien te invite aparecerá aquí', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ]),
    ),
  );
}
