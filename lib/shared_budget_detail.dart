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

class _SharedBudgetDetailScreenState extends State<SharedBudgetDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map<String, dynamic>? _budget;
  List<dynamic> _expenses = [];
  List<dynamic> _settlements = [];
  bool _loadingBudget = true;
  bool _loadingExpenses = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargarBudget();
    _cargarExpenses();
    _cargarSettlements();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _cargarBudget() async {
    final data = await SharedBudgetService.getDetail(widget.budgetId, widget.firebaseUid);
    if (mounted) setState(() { _budget = data; _loadingBudget = false; });
  }

  Future<void> _cargarExpenses() async {
    final data = await SharedBudgetService.getExpenses(widget.budgetId, widget.firebaseUid);
    if (mounted) setState(() { _expenses = data; _loadingExpenses = false; });
  }

  Future<void> _cargarSettlements() async {
    final data = await SharedBudgetService.getSettlements(widget.budgetId, widget.firebaseUid);
    if (mounted) setState(() => _settlements = data);
  }

  Future<void> _recargar() async {
    setState(() { _loadingBudget = true; _loadingExpenses = true; });
    await Future.wait([_cargarBudget(), _cargarExpenses(), _cargarSettlements()]);
  }

  String _otroUid() {
    if (_budget == null) return '';
    final members = _budget!['members'] as List? ?? [];
    final otro = members.firstWhere((m) => m['firebase_uid'] != widget.firebaseUid, orElse: () => null);
    return otro != null ? otro['firebase_uid'] as String : '';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _budget?['nombre'] ?? 'Presupuesto compartido';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(nombre, style: const TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [Tab(text: 'Gastos'), Tab(text: 'Balance')],
        ),
      ),
      body: _loadingBudget
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tab,
              children: [_tabGastos(), _tabBalance()],
            ),
      floatingActionButton: _budget?['estado'] == 'active'
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              onPressed: _showAgregarGasto,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Agregar gasto', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  // ── TAB GASTOS ─────────────────────────────────────────────────────────────

  Widget _tabGastos() {
    if (_loadingExpenses) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    if (_expenses.isEmpty) return Container(
      color: AppTheme.background,
      child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, color: AppTheme.textSecondary, size: 48),
        SizedBox(height: 10),
        Text('Sin gastos aún', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        Text('Agrega el primer gasto compartido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ])),
    );
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _recargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _expenses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _expenseCard(_expenses[i]),
      ),
    );
  }

  Widget _expenseCard(dynamic e) {
    final monto = double.tryParse(e['monto']?.toString() ?? '0') ?? 0.0;
    final miResp = double.tryParse(e['mi_responsabilidad']?.toString() ?? '0') ?? 0.0;
    final pagadoPor = e['pagado_por'] as String? ?? '';
    final yoPague = pagadoPor == widget.firebaseUid;
    final esPersonal = (e['es_personal'] as int? ?? 0) == 1;
    final fecha = e['fecha'] != null ? (e['fecha'] as String).substring(0, 10) : '';

    return Dismissible(
      key: Key('expense_${e['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Eliminar gasto', style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text('¿Estás seguro?', style: TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) async {
        await SharedBudgetService.deleteExpense(e['id'], widget.firebaseUid);
        _recargar();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: esPersonal ? AppTheme.textMuted.withOpacity(0.15) : (yoPague ? AppTheme.success.withOpacity(0.15) : AppTheme.info.withOpacity(0.15)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              esPersonal ? Icons.person_outline : Icons.receipt_outlined,
              color: esPersonal ? AppTheme.textMuted : (yoPague ? AppTheme.success : AppTheme.info),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['descripcion'] ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              esPersonal ? 'Gasto personal · $fecha' : '${yoPague ? 'Tú pagaste' : 'Otro pagó'} · $fecha',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${monto.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            if (!esPersonal)
              Text('Tu parte: \$${miResp.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }

  // ── TAB BALANCE ────────────────────────────────────────────────────────────

  Widget _tabBalance() {
    final balance = double.tryParse(_budget?['balance_neto']?.toString() ?? '0') ?? 0.0;
    final otroUid = _otroUid();

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _recargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _balanceCard(balance, otroUid),
          const SizedBox(height: 16),
          if (balance.abs() > 0.01 && _budget?['estado'] == 'active') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showRegistrarPago(otroUid, balance),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.payments_outlined, color: Colors.black),
                label: const Text('Registrar pago', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_settlements.isNotEmpty) ...[
            const Text('Historial de pagos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._settlements.map((s) => _settlementTile(s)),
          ],
        ],
      ),
    );
  }

  Widget _balanceCard(double balance, String otroUid) {
    final yoDebes = balance > 0.01;
    final meDeben = balance < -0.01;
    final color = yoDebes ? AppTheme.danger : (meDeben ? AppTheme.success : AppTheme.textSecondary);
    final icon = yoDebes ? Icons.arrow_upward : (meDeben ? Icons.arrow_downward : Icons.check_circle_outline);
    final titulo = yoDebes ? 'Debes' : (meDeben ? 'Te deben' : 'Sin deudas pendientes');
    final label = yoDebes ? 'a ${_shortUid(otroUid)}' : (meDeben ? '${_shortUid(otroUid)}' : '');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 40),
        const SizedBox(height: 8),
        Text(titulo, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
        if (balance.abs() > 0.01) ...[
          Text('\$${balance.abs().toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _settlementTile(dynamic s) {
    final yoPague = s['pagador_uid'] == widget.firebaseUid;
    final monto = double.tryParse(s['monto']?.toString() ?? '0') ?? 0.0;
    final fecha = (s['fecha'] as String? ?? '').substring(0, 10);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Icon(yoPague ? Icons.arrow_upward : Icons.arrow_downward, color: yoPague ? AppTheme.danger : AppTheme.success, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(yoPague ? 'Pagaste a ${_shortUid(s['receptor_uid'])}' : 'Recibiste de ${_shortUid(s['pagador_uid'])}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          if ((s['nota'] as String? ?? '').isNotEmpty)
            Text(s['nota'], style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(color: yoPague ? AppTheme.danger : AppTheme.success, fontWeight: FontWeight.bold)),
          Text(fecha, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
      ]),
    );
  }

  String _shortUid(String uid) {
    final parts = uid.split('@');
    return parts.isNotEmpty ? parts[0] : uid;
  }

  // ── MODALES ────────────────────────────────────────────────────────────────

  void _showAgregarGasto() {
    final descCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    String pagadoPor = widget.firebaseUid;
    bool esPersonal = false;
    String? reglaOverride;
    DateTime fecha = DateTime.now();
    final otroUid = _otroUid();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Agregar gasto', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _modalInput(descCtrl, 'Descripción'),
            const SizedBox(height: 10),
            _modalInput(montoCtrl, 'Monto', numeric: true),
            const SizedBox(height: 10),
            // Quién pagó
            if (!esPersonal) ...[
              const Text('¿Quién pagó?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
                      if (otroUid.isNotEmpty) DropdownMenuItem(value: otroUid, child: Text(_shortUid(otroUid))),
                    ],
                    onChanged: (v) => setModalState(() => pagadoPor = v!),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Gasto personal toggle
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Gasto personal (no se divide)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Switch(value: esPersonal, activeColor: AppTheme.primary, onChanged: (v) => setModalState(() => esPersonal = v)),
            ]),
            const SizedBox(height: 6),
            // Fecha
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) setModalState(() => fecha = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd/MM/yyyy').format(fecha), style: const TextStyle(color: AppTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final desc = descCtrl.text.trim();
                  final monto = double.tryParse(montoCtrl.text);
                  if (desc.isEmpty || monto == null || monto <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa todos los campos')));
                    return;
                  }
                  final body = <String, dynamic>{
                    'descripcion': desc,
                    'monto': monto,
                    'pagado_por': esPersonal ? widget.firebaseUid : pagadoPor,
                    'es_personal': esPersonal,
                    if (esPersonal) 'firebase_uid_personal': widget.firebaseUid,
                    if (reglaOverride != null) 'regla_override': reglaOverride,
                    'fecha': DateFormat('yyyy-MM-dd').format(fecha),
                    'firebase_uid': widget.firebaseUid,
                  };
                  Navigator.pop(ctx);
                  final ok = await SharedBudgetService.createExpense(widget.budgetId, body);
                  if (ok) _recargar();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Guardar gasto', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
      }),
    );
  }

  void _showRegistrarPago(String otroUid, double balanceNeto) {
    final montoCtrl = TextEditingController(text: balanceNeto.abs().toStringAsFixed(2));
    final notaCtrl = TextEditingController();
    DateTime fecha = DateTime.now();
    final yoDebes = balanceNeto > 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              yoDebes ? 'Registrar pago a ${_shortUid(otroUid)}' : 'Registrar cobro de ${_shortUid(otroUid)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _modalInput(montoCtrl, 'Monto', numeric: true),
            const SizedBox(height: 10),
            _modalInput(notaCtrl, 'Nota (opcional)'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) setModalState(() => fecha = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd/MM/yyyy').format(fecha), style: const TextStyle(color: AppTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final monto = double.tryParse(montoCtrl.text);
                  if (monto == null || monto <= 0) return;
                  final body = {
                    'receptor_uid': yoDebes ? otroUid : widget.firebaseUid,
                    'monto': monto,
                    'nota': notaCtrl.text.trim(),
                    'fecha': DateFormat('yyyy-MM-dd').format(fecha),
                    'firebase_uid': widget.firebaseUid,
                  };
                  Navigator.pop(ctx);
                  final ok = await SharedBudgetService.createSettlement(widget.budgetId, body);
                  if (ok) _recargar();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Confirmar pago', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
