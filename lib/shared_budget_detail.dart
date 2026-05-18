import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/shared_budget_service.dart';
import 'theme/app_theme.dart';

class SharedBudgetDetailScreen extends StatefulWidget {
  final int budgetId;
  final String firebaseUid;
  const SharedBudgetDetailScreen({super.key, required this.budgetId, required this.firebaseUid});

  @override
  State<SharedBudgetDetailScreen> createState() => _SharedBudgetDetailScreenState();
}

class _SharedBudgetDetailScreenState extends State<SharedBudgetDetailScreen> {
  Map<String, dynamic>? _budget;
  List<dynamic> _expenses = [];
  bool _loadingBudget = true;
  bool _loadingExpenses = true;

  final _fmt = NumberFormat('#,##0.00', 'es');

  String get _miRol {
    if (_budget == null) return '';
    final members = _budget!['members'] as List? ?? [];
    final me = members.firstWhere(
      (m) => m['firebase_uid'] == widget.firebaseUid,
      orElse: () => null,
    );
    return (me?['rol'] as String?) ?? '';
  }

  bool get _puedeAgregarGasto => SharedBudgetService.canAddExpense(_miRol);
  bool get _puedeEditar => SharedBudgetService.canEdit(_miRol);
  bool get _esCreador => SharedBudgetService.isCreador(_miRol);

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    setState(() { _loadingBudget = true; _loadingExpenses = true; });
    await Future.wait([_cargarBudget(), _cargarExpenses()]);
  }

  Future<void> _cargarBudget() async {
    final data = await SharedBudgetService.getDetail(widget.budgetId, widget.firebaseUid);
    if (mounted) setState(() { _budget = data; _loadingBudget = false; });
  }

  Future<void> _cargarExpenses() async {
    final data = await SharedBudgetService.getExpenses(widget.budgetId, widget.firebaseUid);
    if (mounted) setState(() { _expenses = data; _loadingExpenses = false; });
  }

  String _otroUid() {
    if (_budget == null) return '';
    final members = _budget!['members'] as List? ?? [];
    final otro = members.firstWhere(
      (m) => m['firebase_uid'] != widget.firebaseUid,
      orElse: () => null,
    );
    return otro != null ? otro['firebase_uid'] as String : '';
  }

  String _shortUid(String uid) {
    final parts = uid.split('@');
    return parts.isNotEmpty ? parts[0] : uid;
  }

  // ── Computed totals ────────────────────────────────────────────────────────

  List<dynamic> get _gastos => _expenses.where((e) => (e['es_personal'] as int? ?? 0) == 0).toList();

  double get _totalMiResponsabilidad =>
      _gastos.fold(0.0, (s, e) => s + (double.tryParse(e['mi_responsabilidad']?.toString() ?? '0') ?? 0));

  double get _totalPagadoPorMi =>
      _gastos.where(_miPartePagada).fold(0.0, (s, e) => s + (double.tryParse(e['mi_responsabilidad']?.toString() ?? '0') ?? 0));

  int get _movimientosPagados => _gastos.where(_miPartePagada).length;

  // Pagado = solo cuando el usuario confirmó explícitamente vía "Pagar"
  // No se asume pagado por ser el pagado_por (puede ser planificación futura)
  bool _miPartePagada(dynamic e) => (e['mi_parte_pagada'] as int? ?? 0) == 1;

  bool _suPartePagada(dynamic e) => (e['su_parte_pagada'] as int? ?? 0) == 1;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nombre = _budget?['nombre'] ?? 'Presupuesto compartido';
    final estado = _budget?['estado'] as String? ?? '';
    // Operativo = puede recibir gastos (cualquier estado salvo cerrado/pausado)
    final puedeOperar = estado != 'closed' && estado != 'paused' && estado.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Row(children: [
          Expanded(child: Text(nombre, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16))),
          if (_miRol.isNotEmpty) _rolChip(_miRol),
        ]),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _recargar),
          if (_esCreador)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
              onPressed: _showEliminarDialog,
            ),
        ],
      ),
      body: _loadingBudget
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _recargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPeriodoBanner(),
                  const SizedBox(height: 12),
                  if (_budget?['modo_pool'] == true)
                    _buildPoolCard()
                  else ...[
                    _buildResumenCard(),
                    const SizedBox(height: 12),
                    _buildProgressRow(),
                  ],
                  const SizedBox(height: 16),
                  _buildBotones(puedeOperar),
                  if (_budget?['modo_pool'] != true) ...[
                    const SizedBox(height: 12),
                    _buildBalanceCard(),
                  ],
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('MOVIMIENTOS',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                  ),
                  if (_loadingExpenses)
                    const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  else if (_expenses.isEmpty)
                    _buildEmpty()
                  else
                    ..._expenses.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _expenseCard(e),
                        )),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Header cards ───────────────────────────────────────────────────────────

  Widget _buildPeriodoBanner() {
    final inicio = _budget?['periodo_inicio'] ?? _budget?['fecha_inicio'] ?? '';
    final fin = _budget?['periodo_fin'] ?? _budget?['fecha_fin'] ?? '';
    final regla = _budget?['regla_reparto'] ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            inicio.toString().isNotEmpty ? '$inicio → $fin' : 'Período activo',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        if (regla.toString().isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.info.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(regla.toString(), style: const TextStyle(color: AppTheme.info, fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _buildResumenCard() {
    final totalMio = _totalMiResponsabilidad;
    final pagado = _totalPagadoPorMi;
    final pendiente = (totalMio - pagado).clamp(0.0, double.infinity);
    final pct = totalMio > 0 ? (pagado / totalMio).clamp(0.0, 1.0) : 0.0;
    final barColor = pct >= 0.9 ? AppTheme.danger : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Mi presupuesto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text('\$${_fmt.format(totalMio)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 8,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Pagado \$${_fmt.format(pagado)}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(
            pendiente > 0 ? 'Pendiente \$${_fmt.format(pendiente)}' : '✓ Todo pagado',
            style: TextStyle(
              color: pendiente > 0 ? AppTheme.danger : AppTheme.success,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildProgressRow() {
    final total = _gastos.length;
    final pagados = _movimientosPagados;
    final pct = total > 0 ? pagados / total : 0.0;
    final color = pct == 1.0 ? AppTheme.success : (pct >= 0.5 ? AppTheme.primary : AppTheme.textSecondary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 52, height: 52,
            child: CircularProgressIndicator(
              value: pct, strokeWidth: 5,
              backgroundColor: AppTheme.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('${(pct * 100).toInt()}%',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Progreso de pagos',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          Text('$pagados de $total movimientos confirmados',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildBalanceCard() {
    final balance = double.tryParse(_budget?['balance_neto']?.toString() ?? '0') ?? 0.0;
    final otroUid = _otroUid();
    if (balance == 0.0 && otroUid.isEmpty) return const SizedBox.shrink();

    final debes = balance > 0.01;
    final teDeben = balance < -0.01;
    final liquidado = !debes && !teDeben;

    final color = debes ? AppTheme.danger : (teDeben ? AppTheme.success : AppTheme.textSecondary);
    final label = debes
        ? 'Debes \$${balance.toStringAsFixed(2)} a ${_shortUid(otroUid)}'
        : teDeben
            ? '${_shortUid(otroUid)} te debe \$${(-balance).toStringAsFixed(2)}'
            : 'Sin deudas pendientes';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: liquidado ? AppTheme.border : color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(
          liquidado ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined,
          color: color, size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
        if (!liquidado)
          TextButton(
            onPressed: () => _showLiquidarDialog(balance, otroUid),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Liquidar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
      ]),
    );
  }

  void _showLiquidarDialog(double balance, String otroUid) {
    final montoCtrl = TextEditingController(
      text: balance.abs().toStringAsFixed(2),
    );
    final debes = balance > 0;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          debes ? 'Registrar pago que hiciste' : 'Registrar pago que recibiste',
          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            debes
                ? 'Registra cuánto le pagaste a ${_shortUid(otroUid)}.'
                : 'Registra cuánto te pagó ${_shortUid(otroUid)}.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surfaceAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () async {
              final monto = double.tryParse(montoCtrl.text);
              if (monto == null || monto <= 0) return;
              Navigator.pop(context);
              final body = <String, dynamic>{
                'firebase_uid': widget.firebaseUid,
                'receptor_uid': debes ? otroUid : widget.firebaseUid,
                'monto': monto,
                'fecha': DateTime.now().toIso8601String().substring(0, 10),
              };
              // Si recibo el pago, el pagador es el otro
              if (!debes) body['firebase_uid'] = otroUid;
              // Siempre el que llama es el que registra su propio pago
              body['firebase_uid'] = widget.firebaseUid;
              body['receptor_uid'] = debes ? otroUid : widget.firebaseUid;
              final ok = await SharedBudgetService.createSettlement(widget.budgetId, body);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Pago registrado' : 'Error al registrar el pago'),
                  backgroundColor: ok ? AppTheme.success : AppTheme.danger,
                ));
                if (ok) _recargar();
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(() => montoCtrl.dispose());
  }

  Widget _rolChip(String rol) {
    const colors = {
      'creador': AppTheme.primary,
      'owner': AppTheme.primary,
      'admin': AppTheme.info,
      'participante': AppTheme.success,
      'lectura': AppTheme.textMuted,
    };
    final color = colors[rol] ?? AppTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(rol, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildBotones(bool puedeOperar) {
    final regla = _budget?['regla_reparto'] as String? ?? '';
    final puedeEditorDivision = _puedeEditar && (regla == 'porcentual' || regla == 'pool_contribucion');
    return Column(children: [
      Row(children: [
        if (puedeOperar && _puedeAgregarGasto) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _showAgregarGasto,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (_esCreador)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _showEliminarDialog,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Eliminar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ]),
      if (puedeEditorDivision) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _editarDivision,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Editar división entre miembros'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
      if (_puedeEditar) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showGestionarMiembros,
            icon: const Icon(Icons.manage_accounts_outlined, size: 18),
            label: const Text('Gestionar miembros y roles'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _buildPoolCard() {
    final totalContrib = double.tryParse(_budget?['total_contribucion']?.toString() ?? '0') ?? 0;
    final totalGastos  = double.tryParse(_budget?['total_gastos']?.toString() ?? '0') ?? 0;
    final balance      = double.tryParse(_budget?['balance_disponible']?.toString() ?? '0') ?? 0;
    final members      = _budget?['members'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FONDO COMÚN', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total aportes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text('\$${_fmt.format(totalContrib)}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total gastado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text('\$${_fmt.format(totalGastos)}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
        ]),
        const Divider(color: AppTheme.border, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Disponible', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(
            '\$${_fmt.format(balance)}',
            style: TextStyle(
              color: balance >= 0 ? AppTheme.success : AppTheme.danger,
              fontSize: 22, fontWeight: FontWeight.w800,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('APORTES POR PERSONA', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        ...members.map((m) {
          final contrib = double.tryParse(m['contribucion_mensual']?.toString() ?? '0') ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_shortUid(m['firebase_uid'] as String),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Row(children: [
                if ((m['rol'] as String?) != null && (m['rol'] as String).isNotEmpty) ...[
                  _rolChip(m['rol'] as String),
                  const SizedBox(width: 6),
                ],
                Text('\$${_fmt.format(contrib)}',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
              ]),
            ]),
          );
        }),
      ]),
    );
  }

  Future<void> _editarDivision() async {
    final members = List<dynamic>.from(_budget?['members'] ?? []);
    final regla   = _budget?['regla_reparto'] as String? ?? '';
    final controllers = <String, TextEditingController>{};
    for (final m in members) {
      final uid   = m['firebase_uid'] as String;
      final valor = regla == 'pool_contribucion'
          ? (m['contribucion_mensual']?.toString() ?? '0')
          : (m['porcentaje']?.toString() ?? '0');
      controllers[uid] = TextEditingController(text: valor);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        double totalPct() => members.fold(0.0, (s, m) {
          final uid = m['firebase_uid'] as String;
          return s + (double.tryParse(controllers[uid]?.text ?? '0') ?? 0);
        });
        final bool isPct  = regla == 'porcentual';
        final double suma = isPct ? totalPct() : 0;
        final bool valid  = !isPct || (suma > 99.9 && suma < 100.1);

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(
              isPct ? 'Editar porcentajes' : 'Editar contribuciones mensuales',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...members.map((m) {
              final uid = m['firebase_uid'] as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(child: Text(_shortUid(uid), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: controllers[uid],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      textAlign: TextAlign.right,
                      onChanged: (_) => setM(() {}),
                      decoration: InputDecoration(
                        suffixText: isPct ? '%' : '\$',
                        suffixStyle: const TextStyle(color: AppTheme.textSecondary),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
              );
            }),
            if (isPct) ...[
              const SizedBox(height: 4),
              Text(
                'Total: ${suma.toStringAsFixed(1)}% ${valid ? "✓" : "(debe ser 100%)"}',
                style: TextStyle(color: valid ? AppTheme.success : AppTheme.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: valid ? () async {
                  Navigator.pop(ctx);
                  for (final m in members) {
                    final uid   = m['firebase_uid'] as String;
                    final valor = double.tryParse(controllers[uid]?.text ?? '0') ?? 0;
                    await SharedBudgetService.updateMember(
                      widget.budgetId, uid, widget.firebaseUid,
                      porcentaje: isPct ? valor : null,
                      contribucionMensual: !isPct ? valor : null,
                    );
                  }
                  _recargar();
                } : null,
                child: const Text('Guardar cambios'),
              ),
            ),
          ]),
        );
      }),
    );
    for (final c in controllers.values) { c.dispose(); }
  }

  Widget _buildEmpty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 40),
    alignment: Alignment.center,
    child: const Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.receipt_long_outlined, color: AppTheme.textSecondary, size: 48),
      SizedBox(height: 10),
      Text('Sin gastos aún', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      Text('Agrega el primer gasto compartido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ]),
  );

  // ── Expense card ───────────────────────────────────────────────────────────

  Widget _expenseCard(dynamic e) {
    final monto = double.tryParse(e['monto']?.toString() ?? '0') ?? 0.0;
    final miResp = double.tryParse(e['mi_responsabilidad']?.toString() ?? '0') ?? 0.0;
    final esPersonal = (e['es_personal'] as int? ?? 0) == 1;
    final fecha = e['fecha'] != null ? (e['fecha'] as String).substring(0, 10) : '';
    final miPagada = _miPartePagada(e);
    final suPagada = _suPartePagada(e);
    final todo = miPagada && suPagada;

    return Dismissible(
      key: Key('exp_${e['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Eliminar gasto', style: TextStyle(color: AppTheme.textPrimary)),
          content: const Text('¿Estás seguro?', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ).then((v) => v ?? false),
      onDismissed: (_) async {
        await SharedBudgetService.deleteExpense(e['id'], widget.firebaseUid);
        _recargar();
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: todo ? AppTheme.success.withOpacity(0.5) : AppTheme.border),
        ),
        child: Column(children: [
          // ── Top: icon + descripción + montos ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: todo
                      ? AppTheme.success.withOpacity(0.12)
                      : (esPersonal ? AppTheme.textMuted.withOpacity(0.12) : AppTheme.primary.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  esPersonal ? Icons.person_outline : Icons.receipt_outlined,
                  color: todo ? AppTheme.success : (esPersonal ? AppTheme.textMuted : AppTheme.primary),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['descripcion'] ?? '',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: esPersonal ? AppTheme.textMuted.withOpacity(0.15) : AppTheme.info.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      esPersonal ? 'Personal' : 'Compartido',
                      style: TextStyle(
                        color: esPersonal ? AppTheme.textMuted : AppTheme.info,
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(fecha, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // Mi parte — número grande
                Text('\$${miResp.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                // Total — número pequeño
                Text('Total \$${monto.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ]),
          ),

          // ── Bottom split (solo gastos compartidos) ─────────────────
          if (!esPersonal) ...[
            Divider(height: 1, color: AppTheme.border),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: IntrinsicHeight(
                child: Row(children: [
                  // Mitad ellos
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: suPagada ? AppTheme.success.withOpacity(0.13) : Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      child: Row(children: [
                        Icon(
                          suPagada ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: suPagada ? AppTheme.success : AppTheme.textMuted,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          suPagada ? 'Confirmado' : 'Pendiente',
                          style: TextStyle(
                            color: suPagada ? AppTheme.success : AppTheme.textMuted,
                            fontSize: 11, fontWeight: FontWeight.w500,
                          ),
                        )),
                      ]),
                    ),
                  ),
                  // Divisor vertical
                  Container(width: 1, color: AppTheme.border),
                  // Mitad yo
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: miPagada ? AppTheme.success.withOpacity(0.13) : Colors.transparent,
                      padding: EdgeInsets.symmetric(vertical: miPagada ? 10 : 8, horizontal: 14),
                      child: miPagada
                          ? Row(children: const [
                              Icon(Icons.check_circle, color: AppTheme.success, size: 15),
                              SizedBox(width: 6),
                              Text('Pagado',
                                  style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w500)),
                            ])
                          : Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 30,
                                child: ElevatedButton(
                                  onPressed: () => _pagarMiParte(e),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Pagar',
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _pagarMiParte(dynamic e) async {
    final miResp = double.tryParse(e['mi_responsabilidad']?.toString() ?? '0') ?? 0.0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar pago',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e['descripcion'] ?? '', style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          Text('\$${miResp.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.primary, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('¿Confirmas que realizaste este pago?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Confirmar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await SharedBudgetService.confirmarMiParte(e['id'], widget.firebaseUid);
    if (mounted) {
      if (ok) {
        _recargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al confirmar el pago')),
        );
      }
    }
  }

  void _showGestionarMiembros() {
    final members = List<dynamic>.from(_budget?['members'] ?? []);
    final emailCtrl = TextEditingController();
    String rolNuevoInvitado = 'participante';
    bool invitando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Gestionar miembros',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Cambia roles o invita a alguien nuevo.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              // ── Lista de miembros actuales ──────────────────────────
              ...members.map((m) {
                final uid = m['firebase_uid'] as String;
                final rol = (m['rol'] as String?) ?? 'participante';
                final esMismo = uid == widget.firebaseUid;
                final esCreadorMiembro = rol == 'creador' || rol == 'owner';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_shortUid(uid),
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                      if (esMismo)
                        const Text('(tú)', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    ])),
                    if (esCreadorMiembro || esMismo)
                      _rolChip(rol)
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: rol,
                            dropdownColor: AppTheme.surface,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 'admin', child: Text('admin')),
                              DropdownMenuItem(value: 'participante', child: Text('participante')),
                              DropdownMenuItem(value: 'lectura', child: Text('lectura')),
                            ],
                            onChanged: _esCreador
                                ? (nuevoRol) async {
                                    if (nuevoRol == null || nuevoRol == rol) return;
                                    final ok = await SharedBudgetService.changeRole(
                                        widget.budgetId, uid, widget.firebaseUid, nuevoRol);
                                    if (ok) {
                                      setM(() => m['rol'] = nuevoRol);
                                      _recargar();
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Error al cambiar el rol')));
                                    }
                                  }
                                : (nuevoRol) async {
                                    if (nuevoRol == null || nuevoRol == rol || nuevoRol == 'admin') return;
                                    final ok = await SharedBudgetService.changeRole(
                                        widget.budgetId, uid, widget.firebaseUid, nuevoRol);
                                    if (ok) {
                                      setM(() => m['rol'] = nuevoRol);
                                      _recargar();
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Error al cambiar el rol')));
                                    }
                                  },
                          ),
                        ),
                      ),
                  ]),
                );
              }),
              // ── Invitar nuevo participante ──────────────────────────
              const Divider(color: AppTheme.border, height: 28),
              const Text('Invitar a alguien nuevo',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'correo@gmail.com',
                  hintStyle: const TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: rolNuevoInvitado,
                    isExpanded: true,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 'admin',        child: Text('Admin — puede invitar y editar')),
                      DropdownMenuItem(value: 'participante', child: Text('Participante — puede agregar gastos')),
                      DropdownMenuItem(value: 'lectura',      child: Text('Solo lectura')),
                    ],
                    onChanged: (v) => setM(() => rolNuevoInvitado = v!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: invitando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Enviar invitación',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: invitando ? null : () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ingresa un email válido')));
                      return;
                    }
                    setM(() => invitando = true);
                    final ok = await SharedBudgetService.invite(
                        widget.budgetId, email, widget.firebaseUid,
                        rolInvitado: rolNuevoInvitado);
                    setM(() => invitando = false);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Invitación enviada a $email' : 'Error al enviar la invitación'),
                        backgroundColor: ok ? AppTheme.success : AppTheme.danger,
                      ));
                    }
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    ).whenComplete(() => emailCtrl.dispose());
  }

  void _showEliminarDialog() {
    final otroUid = _otroUid();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar presupuesto',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_outlined, color: AppTheme.danger, size: 36),
          const SizedBox(height: 12),
          const Text(
            'Se enviará una solicitud de eliminación al co-dueño. El presupuesto solo se eliminará si ambos lo aprueban.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
          if (otroUid.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Co-dueño: ${_shortUid(otroUid)}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await SharedBudgetService.requestDelete(widget.budgetId, widget.firebaseUid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Solicitud enviada al co-dueño' : 'Error al enviar la solicitud'),
                  backgroundColor: ok ? AppTheme.success : AppTheme.danger,
                ));
              }
            },
            child: const Text('Solicitar eliminación',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAgregarGasto() {
    final descCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    String pagadoPor = widget.firebaseUid;
    bool esPersonal = false;
    bool yaPagado = false;
    DateTime fecha = DateTime.now();
    final otroUid = _otroUid();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Agregar gasto',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _modalInput(descCtrl, 'Descripción'),
            const SizedBox(height: 10),
            _modalInput(montoCtrl, 'Monto', numeric: true),
            const SizedBox(height: 10),
            if (!esPersonal) ...[
              const Text('¿Quién lo pagará / ya pagó?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: pagadoPor,
                    isExpanded: true,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    items: [
                      DropdownMenuItem(value: widget.firebaseUid, child: Text('Yo (${_shortUid(widget.firebaseUid)})')),
                      if (otroUid.isNotEmpty)
                        DropdownMenuItem(value: otroUid, child: Text(_shortUid(otroUid))),
                    ],
                    onChanged: (v) => setM(() => pagadoPor = v!),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Toggle: ¿ya se pagó? — para tracking en tiempo real vs planificación
            if (!esPersonal) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: yaPagado ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: yaPagado ? AppTheme.success.withValues(alpha: 0.4) : Colors.transparent),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      yaPagado ? '¿Ya se pagó? Sí' : '¿Ya se pagó? No (planeado)',
                      style: TextStyle(
                        color: yaPagado ? AppTheme.success : AppTheme.textSecondary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      yaPagado ? 'Se confirma el pago del pagador al guardar' : 'Nadie paga aún — se confirma después',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ]),
                  Switch(
                    value: yaPagado,
                    activeColor: AppTheme.success,
                    onChanged: (v) => setM(() => yaPagado = v),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Gasto personal (no se divide)',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Switch(
                value: esPersonal,
                activeColor: AppTheme.primary,
                onChanged: (v) => setM(() { esPersonal = v; if (v) yaPagado = false; }),
              ),
            ]),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final p = await showDatePicker(
                    context: ctx, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (p != null) setM(() => fecha = p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd/MM/yyyy').format(fecha),
                      style: const TextStyle(color: AppTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final desc = descCtrl.text.trim();
                  final monto = double.tryParse(montoCtrl.text);
                  if (desc.isEmpty || monto == null || monto <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Completa todos los campos')));
                    return;
                  }
                  final body = <String, dynamic>{
                    'descripcion': desc,
                    'monto': monto,
                    'pagado_por': esPersonal ? widget.firebaseUid : pagadoPor,
                    'es_personal': esPersonal,
                    if (esPersonal) 'firebase_uid_personal': widget.firebaseUid,
                    'fecha': DateFormat('yyyy-MM-dd').format(fecha),
                    'firebase_uid': widget.firebaseUid,
                    'ya_pagado': yaPagado,
                  };
                  Navigator.pop(ctx);
                  final ok = await SharedBudgetService.createExpense(widget.budgetId, body);
                  if (ok) _recargar();
                },
                child: const Text('Guardar gasto',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Widget _modalInput(TextEditingController ctrl, String hint, {bool numeric = false}) => TextField(
    controller: ctrl,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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
}
