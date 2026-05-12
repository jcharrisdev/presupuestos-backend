import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/servicios_service.dart';
import 'registro_pago_cliente_screen.dart';
import 'registro_gastos_screen.dart';

class TrabajoDetalleScreen extends StatefulWidget {
  final String firebaseUid;
  final int jobId;
  const TrabajoDetalleScreen({Key? key, required this.firebaseUid, required this.jobId}) : super(key: key);

  @override
  _TrabajoDetalleScreenState createState() => _TrabajoDetalleScreenState();
}

class _TrabajoDetalleScreenState extends State<TrabajoDetalleScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await ServiciosService.getJob(widget.jobId, widget.firebaseUid);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Detalle del trabajo',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Esta pantalla muestra el detalle completo del trabajo:\n\n'
          '• Pagos del cliente — registra anticipos, pagos parciales y el pago final.\n'
          '• Colaboradores — asigna personas al trabajo con su tipo de compensación.\n'
          '• Gastos operativos — materiales, transporte y otros costos del trabajo.\n'
          '• Resumen financiero — utilidad neta calculada automáticamente.\n\n'
          'Puedes cambiar el estado del trabajo desde el selector en la parte superior.\n'
          'Desliza un ítem a la izquierda para eliminarlo.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _cambiarEstado(String nuevoEstado) async {
    try {
      await ServiciosService.updateJob(widget.jobId, {
        'firebase_uid': widget.firebaseUid,
        'estado': nuevoEstado,
      });
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarPagoCliente(int id) async {
    try {
      await ServiciosService.deleteCustomerPayment(widget.jobId, id, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarGasto(int id) async {
    try {
      await ServiciosService.deleteExpense(widget.jobId, id, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarColaborador(int id) async {
    try {
      await ServiciosService.deleteTeamMember(widget.jobId, id, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _agregarColaborador() {
    final nombreCtrl = TextEditingController();
    String tipoComp = 'fijo';
    final montoCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Agregar colaborador',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              _miniField(nombreCtrl, 'Nombre del colaborador'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tipoComp,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: _miniDeco('Tipo de compensación'),
                items: const [
                  DropdownMenuItem(value: 'fijo', child: Text('Pago fijo')),
                  DropdownMenuItem(value: 'porcentual', child: Text('Porcentual')),
                  DropdownMenuItem(value: 'por_horas', child: Text('Por horas')),
                  DropdownMenuItem(value: 'por_tarea', child: Text('Por tarea')),
                  DropdownMenuItem(value: 'ganancias', child: Text('Participación en ganancias')),
                ],
                onChanged: (v) => setS(() => tipoComp = v ?? 'fijo'),
              ),
              const SizedBox(height: 12),
              _miniField(montoCtrl, 'Monto acordado / porcentaje',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nombreCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    try {
                      final monto = double.tryParse(montoCtrl.text.trim()) ?? 0;
                      await ServiciosService.addTeamMember(widget.jobId, {
                        'firebase_uid': widget.firebaseUid,
                        'nombre': nombreCtrl.text.trim(),
                        'tipo_compensacion': tipoComp,
                        'monto_acordado': tipoComp == 'fijo' ? monto : 0,
                        'porcentaje': tipoComp == 'porcentual' || tipoComp == 'ganancias' ? monto : 0,
                        'tarifa_hora': tipoComp == 'por_horas' ? monto : 0,
                      });
                      _cargar();
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Trabajo')), body: const Center(child: CircularProgressIndicator()));

    final job = _data!['job'] as Map<String, dynamic>;
    final resumen = _data!['resumen'] as Map<String, dynamic>;
    final customerPayments = _data!['customerPayments'] as List<dynamic>;
    final teamMembers = _data!['teamMembers'] as List<dynamic>;
    final expenses = _data!['expenses'] as List<dynamic>;
    final teamPayments = _data!['teamPayments'] as List<dynamic>;

    return Scaffold(
      appBar: AppBar(
        title: Text(job['nombre'] as String? ?? 'Trabajo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Estado y cliente
            _headerCard(job),
            const SizedBox(height: 12),
            // Resumen financiero (siempre visible)
            _resumenCard(resumen),
            const SizedBox(height: 12),
            // Pagos del cliente
            _expandibleSection(
              titulo: 'Pagos del cliente',
              icono: Icons.payments_outlined,
              color: AppTheme.success,
              badge: customerPayments.length,
              trailing: IconButton(
                icon: const Icon(Icons.add, color: AppTheme.success, size: 20),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                      RegistroPagoClienteScreen(firebaseUid: widget.firebaseUid, jobId: widget.jobId)));
                  _cargar();
                },
              ),
              children: customerPayments.isEmpty
                  ? [_emptyItem('Sin pagos registrados')]
                  : customerPayments.map((p) => _dismissible(
                      key: 'cp-${p['id']}',
                      onDismiss: () => _eliminarPagoCliente(p['id'] as int),
                      child: _pagoClienteTile(p),
                    )).toList(),
            ),
            const SizedBox(height: 12),
            // Colaboradores
            _expandibleSection(
              titulo: 'Colaboradores',
              icono: Icons.group_outlined,
              color: const Color(0xFF0EA5E9),
              badge: teamMembers.length,
              trailing: IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF0EA5E9), size: 20),
                onPressed: _agregarColaborador,
              ),
              children: teamMembers.isEmpty
                  ? [_emptyItem('Sin colaboradores asignados')]
                  : teamMembers.map((m) => _dismissible(
                      key: 'tm-${m['id']}',
                      onDismiss: () => _eliminarColaborador(m['id'] as int),
                      child: _colaboradorTile(m, teamPayments),
                    )).toList(),
            ),
            const SizedBox(height: 12),
            // Gastos operativos
            _expandibleSection(
              titulo: 'Gastos operativos',
              icono: Icons.receipt_outlined,
              color: AppTheme.danger,
              badge: expenses.length,
              trailing: IconButton(
                icon: const Icon(Icons.add, color: AppTheme.danger, size: 20),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                      RegistroGastosScreen(firebaseUid: widget.firebaseUid, jobId: widget.jobId)));
                  _cargar();
                },
              ),
              children: expenses.isEmpty
                  ? [_emptyItem('Sin gastos registrados')]
                  : expenses.map((e) => _dismissible(
                      key: 'exp-${e['id']}',
                      onDismiss: () => _eliminarGasto(e['id'] as int),
                      child: _gastoTile(e),
                    )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> job) {
    final estado = job['estado'] as String? ?? 'draft';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job['nombre_cliente'] != null)
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(job['nombre_cliente'] as String,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              if (job['telefono_cliente'] != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(job['telefono_cliente'] as String,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ]),
          if (job['descripcion'] != null) ...[
            const SizedBox(height: 6),
            Text(job['descripcion'] as String,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Estado:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: estado,
                  dropdownColor: AppTheme.surface,
                  isDense: true,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                    DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                    DropdownMenuItem(value: 'in_progress', child: Text('En progreso')),
                    DropdownMenuItem(value: 'completed', child: Text('Completado')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelado')),
                  ],
                  onChanged: (v) { if (v != null && v != estado) _cambiarEstado(v); },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumenCard(Map<String, dynamic> r) {
    final montoTotal = double.tryParse(r['monto_total']?.toString() ?? '0') ?? 0;
    final recibido = double.tryParse(r['total_recibido']?.toString() ?? '0') ?? 0;
    final pendiente = double.tryParse(r['saldo_pendiente']?.toString() ?? '0') ?? 0;
    final gastos = double.tryParse(r['total_gastos']?.toString() ?? '0') ?? 0;
    final pagosColab = double.tryParse(r['total_pagos_colaboradores']?.toString() ?? '0') ?? 0;
    final utilidad = double.tryParse(r['utilidad_neta']?.toString() ?? '0') ?? 0;
    final margen = double.tryParse(r['margen']?.toString() ?? '0') ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen financiero',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _filaResumen('Total contratado', montoTotal, AppTheme.textPrimary),
          _filaResumen('Total recibido', recibido, AppTheme.success),
          _filaResumen('Saldo pendiente', pendiente, AppTheme.primary),
          const Divider(color: AppTheme.background, height: 16),
          _filaResumen('Gastos operativos', gastos, AppTheme.danger),
          _filaResumen('Pagos a colaboradores', pagosColab, AppTheme.danger),
          const Divider(color: AppTheme.background, height: 16),
          _filaResumen('Utilidad neta', utilidad, utilidad >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Margen de rentabilidad', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('${margen.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: margen >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaResumen(String label, double valor, Color color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
            Text('\$${valor.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );

  Widget _expandibleSection({
    required String titulo,
    required IconData icono,
    required Color color,
    required int badge,
    required Widget trailing,
    required List<Widget> children,
  }) =>
      Container(
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          leading: Icon(icono, color: color, size: 20),
          title: Row(
            children: [
              Text(titulo, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('$badge', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          trailing: trailing,
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: children,
        ),
      );

  Widget _dismissible({required String key, required VoidCallback onDismiss, required Widget child}) =>
      Dismissible(
        key: Key(key),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: AppTheme.danger.withOpacity(0.15),
          child: const Icon(Icons.delete_outline, color: AppTheme.danger),
        ),
        onDismissed: (_) => onDismiss(),
        child: child,
      );

  Widget _pagoClienteTile(Map<String, dynamic> p) {
    final monto = double.tryParse(p['monto']?.toString() ?? '0') ?? 0;
    final tipo = p['tipo'] as String? ?? 'pago_parcial';
    final tipoLabel = tipo == 'anticipo' ? 'Anticipo' : tipo == 'pago_final' ? 'Pago final' : 'Pago parcial';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.attach_money, color: AppTheme.success, size: 18),
      title: Text('\$${monto.toStringAsFixed(2)}',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(tipoLabel, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      trailing: p['nota'] != null
          ? Text(p['nota'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11))
          : null,
    );
  }

  Widget _colaboradorTile(Map<String, dynamic> m, List<dynamic> teamPayments) {
    final tipoComp = m['tipo_compensacion'] as String? ?? 'fijo';
    final monto = double.tryParse(m['monto_acordado']?.toString() ?? '0') ?? 0;
    final pagado = teamPayments
        .where((p) => p['team_member_id'] == m['id'])
        .fold<double>(0, (s, p) => s + (double.tryParse(p['monto']?.toString() ?? '0') ?? 0));
    return ListTile(
      dense: true,
      leading: const Icon(Icons.person_outline, color: Color(0xFF0EA5E9), size: 18),
      title: Text(m['nombre'] as String? ?? '',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(_labelComp(tipoComp, monto),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      trailing: pagado > 0
          ? Text('Pagado: \$${pagado.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.success, fontSize: 11))
          : null,
    );
  }

  Widget _gastoTile(Map<String, dynamic> e) {
    final monto = double.tryParse(e['monto']?.toString() ?? '0') ?? 0;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.receipt_outlined, color: AppTheme.danger, size: 18),
      title: Text(e['descripcion'] as String? ?? '',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      subtitle: e['categoria'] != null
          ? Text(e['categoria'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11))
          : null,
      trailing: Text('\$${monto.toStringAsFixed(2)}',
          style: const TextStyle(color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _emptyItem(String msg) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(msg, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );

  String _labelComp(String tipo, double monto) {
    switch (tipo) {
      case 'fijo': return 'Pago fijo: \$${monto.toStringAsFixed(2)}';
      case 'porcentual': return 'Porcentual';
      case 'por_horas': return 'Por horas';
      case 'por_tarea': return 'Por tarea';
      case 'ganancias': return 'Participación en ganancias';
      default: return tipo;
    }
  }

  InputDecoration _miniDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );

  Widget _miniField(TextEditingController ctrl, String hint, {TextInputType? keyboardType}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: _miniDeco(hint),
      );
}
