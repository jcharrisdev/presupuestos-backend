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
          'Vista completa del trabajo y su salud financiera:\n\n'
          '• Pagos del cliente — registra anticipos, pagos parciales y pago final.\n'
          '• Colaboradores — asigna personas con su compensación. Toca el ícono + para registrar un pago. El badge muestra Pendiente / Parcial / Pagado.\n'
          '• Gastos operativos — materiales, transporte y otros costos.\n'
          '• Resumen real — utilidad calculada con lo efectivamente cobrado y pagado.\n'
          '• Proyección — estimación de ganancia si cobras el 100% del contrato, descontando costos acordados con colaboradores y gastos actuales.\n\n'
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

  Future<void> _eliminarPagoColab(int paymentId) async {
    try {
      await ServiciosService.deleteTeamMemberPayment(widget.jobId, paymentId, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── Calcular compensación esperada del colaborador según tipo ───
  double _calcMontoColaborador(Map<String, dynamic> m, double montoTotal) {
    final tipo = m['tipo_compensacion'] as String? ?? 'fijo';
    final calculado = double.tryParse(m['monto_calculado']?.toString() ?? '0') ?? 0;
    final porcentaje = double.tryParse(m['porcentaje']?.toString() ?? '0') ?? 0;
    if (tipo == 'fijo' || tipo == 'por_horas' || tipo == 'por_tarea') {
      return calculado > 0 ? calculado : (double.tryParse(m['monto_acordado']?.toString() ?? '0') ?? 0);
    } else if (tipo == 'porcentual') {
      return montoTotal * porcentaje / 100;
    }
    return 0; // 'ganancias' — circular, excluido de proyección
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
        padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
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
              _miniField(montoCtrl, _hintComp(tipoComp),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    if (nombreCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    try {
                      final monto = double.tryParse(montoCtrl.text.trim()) ?? 0;
                      await ServiciosService.addTeamMember(widget.jobId, {
                        'firebase_uid': widget.firebaseUid,
                        'nombre': nombreCtrl.text.trim(),
                        'tipo_compensacion': tipoComp,
                        'monto_acordado': tipoComp == 'fijo' || tipoComp == 'por_tarea' ? monto : 0,
                        'porcentaje': tipoComp == 'porcentual' || tipoComp == 'ganancias' ? monto : 0,
                        'tarifa_hora': tipoComp == 'por_horas' ? monto : 0,
                      });
                      _cargar();
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Agregar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pagarColaborador(Map<String, dynamic> member, double totalPagado, double montoAcordado, double pendiente) {
    final montoCtrl = TextEditingController(text: pendiente > 0 ? pendiente.toStringAsFixed(2) : '');
    final notaCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Pago a ${member['nombre']}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (montoAcordado > 0)
              Text(
                'Acordado: \$${montoAcordado.toStringAsFixed(2)}  ·  Ya pagado: \$${totalPagado.toStringAsFixed(2)}  ·  Pendiente: \$${pendiente.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            const SizedBox(height: 16),
            _miniField(montoCtrl, 'Monto a pagar',
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            _miniField(notaCtrl, 'Nota (opcional)'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  final monto = double.tryParse(montoCtrl.text.trim()) ?? 0;
                  if (monto <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    await ServiciosService.addTeamMemberPayment(widget.jobId, {
                      'firebase_uid': widget.firebaseUid,
                      'team_member_id': member['id'],
                      'monto': monto,
                      'nota': notaCtrl.text.trim().isEmpty ? null : notaCtrl.text.trim(),
                    });
                    _cargar();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const Text('Registrar pago', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Trabajo')), body: const Center(child: CircularProgressIndicator()));
    }

    final job = _data!['job'] as Map<String, dynamic>;
    final resumen = _data!['resumen'] as Map<String, dynamic>;
    final customerPayments = _data!['customerPayments'] as List<dynamic>;
    final teamMembers = _data!['teamMembers'] as List<dynamic>;
    final expenses = _data!['expenses'] as List<dynamic>;
    final teamPayments = _data!['teamPayments'] as List<dynamic>;
    final montoTotal = double.tryParse(resumen['monto_total']?.toString() ?? '0') ?? 0;

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
            _headerCard(job),
            const SizedBox(height: 12),
            _resumenCard(resumen, teamMembers),
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
                      child: _colaboradorTile(m, teamPayments, montoTotal),
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
              Expanded(child: Text(job['nombre_cliente'] as String,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
              if (job['telefono_cliente'] != null) ...[
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
          Row(children: [
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
          ]),
        ],
      ),
    );
  }

  Widget _resumenCard(Map<String, dynamic> r, List<dynamic> teamMembers) {
    final montoTotal = double.tryParse(r['monto_total']?.toString() ?? '0') ?? 0;
    final recibido = double.tryParse(r['total_recibido']?.toString() ?? '0') ?? 0;
    final pendiente = double.tryParse(r['saldo_pendiente']?.toString() ?? '0') ?? 0;
    final gastos = double.tryParse(r['total_gastos']?.toString() ?? '0') ?? 0;
    final pagosColab = double.tryParse(r['total_pagos_colaboradores']?.toString() ?? '0') ?? 0;
    final utilidad = double.tryParse(r['utilidad_neta']?.toString() ?? '0') ?? 0;
    final margen = double.tryParse(r['margen']?.toString() ?? '0') ?? 0;

    // ─── Proyección ───
    final totalColabAcordado = teamMembers.fold<double>(
        0, (sum, m) => sum + _calcMontoColaborador(m as Map<String, dynamic>, montoTotal));
    final gananciaProyectada = montoTotal - totalColabAcordado - gastos;
    final margenProyectado = montoTotal > 0 ? (gananciaProyectada / montoTotal) * 100 : 0.0;
    final tieneGanancias = teamMembers.any((m) => (m as Map)['tipo_compensacion'] == 'ganancias');

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
          // ── Resumen real ──
          const Text('Resumen real',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _filaResumen('Total contratado', montoTotal, AppTheme.textPrimary),
          _filaResumen('Total recibido', recibido, AppTheme.success),
          _filaResumen('Saldo pendiente cliente', pendiente, AppTheme.primary),
          const Divider(color: AppTheme.background, height: 16),
          _filaResumen('Gastos operativos', gastos, AppTheme.danger),
          _filaResumen('Pagos a colaboradores', pagosColab, AppTheme.danger),
          const Divider(color: AppTheme.background, height: 16),
          _filaResumen('Utilidad neta', utilidad,
              utilidad >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Margen real', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            Text('${margen.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: margen >= 0 ? AppTheme.success : AppTheme.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
          ]),

          // ── Proyección ──
          const SizedBox(height: 16),
          const Divider(color: AppTheme.background, height: 1),
          const SizedBox(height: 12),
          Row(children: const [
            Icon(Icons.trending_up, color: AppTheme.info, size: 14),
            SizedBox(width: 6),
            Text('Proyección (si cobras todo el contrato)',
                style: TextStyle(color: AppTheme.info, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          _filaResumen('Ingresos esperados', montoTotal, AppTheme.textPrimary),
          _filaResumen('Costos laborales acordados', totalColabAcordado, AppTheme.danger),
          _filaResumen('Gastos operativos actuales', gastos, AppTheme.danger),
          const Divider(color: AppTheme.background, height: 12),
          _filaResumen('Ganancia proyectada', gananciaProyectada,
              gananciaProyectada >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (margenProyectado / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppTheme.background,
                  color: margenProyectado >= 30
                      ? AppTheme.success
                      : margenProyectado >= 15
                          ? AppTheme.primary
                          : AppTheme.danger,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${margenProyectado.toStringAsFixed(1)}%',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          if (tieneGanancias) ...[
            const SizedBox(height: 6),
            const Text('* Excluye colaboradores a % de ganancias',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _filaResumen(String label, double valor, Color color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text('\$${valor.toStringAsFixed(2)}', style: TextStyle(
              color: color, fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
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
          title: Row(children: [
            Text(titulo, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text('$badge', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ]),
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
          ? Text(p['nota'] as String,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis)
          : null,
    );
  }

  Widget _colaboradorTile(Map<String, dynamic> m, List<dynamic> teamPayments, double montoTotal) {
    final montoAcordado = _calcMontoColaborador(m, montoTotal);
    final pagosDelMiembro = teamPayments.where((p) => p['team_member_id'] == m['id']).toList();
    final totalPagado = pagosDelMiembro.fold<double>(
        0, (s, p) => s + (double.tryParse(p['monto']?.toString() ?? '0') ?? 0));
    final pendiente = (montoAcordado - totalPagado).clamp(0.0, double.infinity);

    // Badge de estado
    Color badgeColor = AppTheme.danger;
    String badgeLabel = 'Pendiente';
    if (montoAcordado > 0 && totalPagado >= montoAcordado) {
      badgeColor = AppTheme.success;
      badgeLabel = 'Pagado';
    } else if (totalPagado > 0) {
      badgeColor = AppTheme.primary;
      badgeLabel = 'Parcial';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline, color: Color(0xFF0EA5E9), size: 18),
          title: Text(m['nombre'] as String? ?? '',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Text(_labelComp(m, montoTotal),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // Badge de estado de pago
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(badgeLabel,
                  style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            // Botón de pago (solo si hay saldo pendiente)
            if (pendiente > 0 || montoAcordado == 0)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 20),
                tooltip: 'Registrar pago',
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(),
                onPressed: () => _pagarColaborador(m, totalPagado, montoAcordado, pendiente),
              ),
          ]),
        ),
        // Sub-lista de pagos realizados
        for (final p in pagosDelMiembro) _pagoColabSubTile(p),
      ],
    );
  }

  Widget _pagoColabSubTile(Map<String, dynamic> p) {
    final monto = double.tryParse(p['monto']?.toString() ?? '0') ?? 0;
    final nota = p['nota'] as String?;
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 4, bottom: 4),
      child: Row(children: [
        const Icon(Icons.subdirectory_arrow_right, color: AppTheme.textMuted, size: 14),
        const SizedBox(width: 4),
        Expanded(
          child: Text(nota ?? 'Pago registrado',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        Text('\$${monto.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _eliminarPagoColab(p['id'] as int),
          child: const Icon(Icons.close, size: 14, color: AppTheme.danger),
        ),
        const SizedBox(width: 8),
      ]),
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

  String _labelComp(Map<String, dynamic> m, double montoTotal) {
    final tipo = m['tipo_compensacion'] as String? ?? 'fijo';
    final porcentaje = double.tryParse(m['porcentaje']?.toString() ?? '0') ?? 0;
    final horas = double.tryParse(m['horas_trabajadas']?.toString() ?? '0') ?? 0;
    final tarifa = double.tryParse(m['tarifa_hora']?.toString() ?? '0') ?? 0;
    switch (tipo) {
      case 'fijo':
        final v = _calcMontoColaborador(m, montoTotal);
        return 'Pago fijo: \$${v.toStringAsFixed(2)}';
      case 'porcentual':
        final v = montoTotal * porcentaje / 100;
        return 'Porcentual: ${porcentaje.toStringAsFixed(1)}% (\$${v.toStringAsFixed(2)})';
      case 'por_horas':
        return horas > 0
            ? 'Por horas: ${horas.toStringAsFixed(0)}h × \$${tarifa.toStringAsFixed(2)}'
            : 'Por horas: \$${tarifa.toStringAsFixed(2)}/h';
      case 'por_tarea':
        final v = _calcMontoColaborador(m, montoTotal);
        return 'Por tarea: \$${v.toStringAsFixed(2)}';
      case 'ganancias':
        return '${porcentaje.toStringAsFixed(1)}% de ganancias';
      default:
        return tipo;
    }
  }

  String _hintComp(String tipo) {
    switch (tipo) {
      case 'fijo': return 'Monto fijo acordado (ej. 500)';
      case 'porcentual': return 'Porcentaje del contrato (ej. 10)';
      case 'por_horas': return 'Tarifa por hora (ej. 15)';
      case 'por_tarea': return 'Monto por tarea completada';
      case 'ganancias': return 'Porcentaje de ganancias (ej. 20)';
      default: return 'Monto';
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
