import 'package:flutter/material.dart';
import 'services/shared_budget_service.dart';
import 'services/cache_service.dart';
import 'theme/app_theme.dart';
import 'shared_budget_create.dart';
import 'shared_budget_detail.dart';
import 'shared_budget_invitations.dart';

class SharedBudgetsListScreen extends StatefulWidget {
  final String firebaseUid;
  const SharedBudgetsListScreen({super.key, required this.firebaseUid});

  @override
  State<SharedBudgetsListScreen> createState() => _SharedBudgetsListScreenState();
}

class _SharedBudgetsListScreenState extends State<SharedBudgetsListScreen> {
  List<dynamic> _budgets = [];
  bool _loading = true;
  bool _refreshing = false;
  int _pendingInvitations = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
    _checkInvitations();
  }

  Future<void> _checkInvitations() async {
    final invs = await SharedBudgetService.getInvitations(widget.firebaseUid);
    if (mounted) setState(() => _pendingInvitations = invs.length);
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final cacheKey = '${widget.firebaseUid}_shared_budgets';
    final cached = CacheService.get(cacheKey);
    if (cached != null && !silencioso) {
      setState(() { _budgets = List<dynamic>.from(cached); _loading = false; _refreshing = true; });
    } else if (!silencioso) {
      setState(() => _loading = true);
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final data = await SharedBudgetService.getAll(widget.firebaseUid);
      await CacheService.set(cacheKey, data);
      if (mounted) setState(() { _budgets = data; _loading = false; _refreshing = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  String _balanceLabel(dynamic b) {
    final balance = double.tryParse(b['balance_neto']?.toString() ?? '0') ?? 0.0;
    if (balance > 0.01) return 'Debes \$${balance.toStringAsFixed(2)}';
    if (balance < -0.01) return 'Te deben \$${(-balance).toStringAsFixed(2)}';
    return 'Sin deudas';
  }

  Color _balanceColor(dynamic b) {
    final balance = double.tryParse(b['balance_neto']?.toString() ?? '0') ?? 0.0;
    if (balance > 0.01) return AppTheme.danger;
    if (balance < -0.01) return AppTheme.success;
    return AppTheme.textSecondary;
  }

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'active': return AppTheme.success;
      case 'waiting_for_members': return AppTheme.warning;
      case 'paused': return AppTheme.textSecondary;
      case 'closed': return AppTheme.danger;
      default: return AppTheme.textSecondary;
    }
  }

  String _estadoLabel(String estado) {
    switch (estado) {
      case 'active': return 'Activo';
      case 'waiting_for_members': return 'Esperando miembro';
      case 'paused': return 'Pausado';
      case 'closed': return 'Cerrado';
      case 'draft': return 'Borrador';
      default: return estado;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Compartido', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline, color: AppTheme.textPrimary),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SharedBudgetInvitationsScreen(firebaseUid: widget.firebaseUid),
                  ));
                  _cargar(silencioso: true);
                  _checkInvitations();
                },
              ),
              if (_pendingInvitations > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                    child: Text('$_pendingInvitations', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(children: [
              if (_refreshing) const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
              Expanded(
                child: _budgets.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: AppTheme.primary,
                        onRefresh: () => _cargar(silencioso: true),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _budgets.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _card(_budgets[i]),
                        ),
                      ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => SharedBudgetCreateScreen(firebaseUid: widget.firebaseUid),
          ));
          _cargar(silencioso: true);
        },
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Nuevo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(rol, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _card(dynamic b) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SharedBudgetDetailScreen(budgetId: b['id'], firebaseUid: widget.firebaseUid),
        ));
        _cargar(silencioso: true);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(b['nombre'] ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Row(children: [
              if ((b['rol'] as String?) != null) ...[
                _rolChip(b['rol'] as String),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _estadoColor(b['estado'] ?? '').withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_estadoLabel(b['estado'] ?? ''), style: TextStyle(color: _estadoColor(b['estado'] ?? ''), fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.sync_alt, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(b['tipo_periodo'] == 'quincenal' ? 'Quincenal' : 'Mensual', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(width: 12),
            Icon(Icons.balance, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(_reglaNombre(b['regla_reparto'] ?? ''), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ]),
          if (b['estado'] == 'active') ...[
            const SizedBox(height: 8),
            Text(_balanceLabel(b), style: TextStyle(color: _balanceColor(b), fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  String _reglaNombre(String regla) {
    switch (regla) {
      case 'equitativo': return '50/50';
      case 'porcentual': return 'Porcentual';
      case 'proporcional': return 'Por ingresos';
      default: return regla;
    }
  }

  Widget _empty() => Container(
    color: AppTheme.background,
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.group_outlined, color: AppTheme.textSecondary, size: 56),
        const SizedBox(height: 12),
        const Text('Sin presupuestos compartidos', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Crea uno y compártelo con otra persona', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ]),
    ),
  );
}
