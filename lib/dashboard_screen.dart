import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/shared_budget_service.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'cobros_home.dart';
import 'shared_budgets_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String firebaseUid;
  const DashboardScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Data
  Map<String, dynamic>? _presupuesto;
  List<dynamic> _sharedBudgets = [];
  List<dynamic> _proximosPagos = [];
  Map<String, dynamic>? _metaAhorro;
  List<dynamic> _todasMetas = [];
  Map<String, dynamic>? _resumenVentas;

  // Loading
  bool _loadingPresupuesto = true;
  bool _loadingShared = true;
  bool _loadingPagos = true;
  bool _loadingAhorro = true;
  bool _loadingVentas = true;

  // Errors
  String? _errorPresupuesto;
  String? _errorAhorro;
  String? _errorVentas;

  final _fmt = NumberFormat('#,##0.00', 'es');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final now = DateTime.now();
    setState(() {
      _loadingPresupuesto = _loadingShared = _loadingPagos = _loadingAhorro = _loadingVentas = true;
      _errorPresupuesto = _errorAhorro = _errorVentas = null;
    });
    await Future.wait([
      _cargarPresupuesto(),
      _cargarSharedBudgets(),
      _cargarProximosPagos(now),
      _cargarAhorro(),
      _cargarVentas(),
    ]);
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _cargarPresupuesto() async {
    try {
      final res = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        final activo = list.firstWhere(
          (p) => p['estado'] == 'activo' || p['estado'] == null,
          orElse: () => list.isNotEmpty ? list.first : null,
        );
        if (mounted) setState(() { _presupuesto = activo; _loadingPresupuesto = false; });
      } else {
        if (mounted) setState(() { _errorPresupuesto = 'Error ${res.statusCode}'; _loadingPresupuesto = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorPresupuesto = e.toString(); _loadingPresupuesto = false; });
    }
  }

  Future<void> _cargarSharedBudgets() async {
    try {
      final data = await SharedBudgetService.getAll(widget.firebaseUid);
      if (mounted) setState(() { _sharedBudgets = data; _loadingShared = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingShared = false);
    }
  }

  Future<void> _cargarProximosPagos(DateTime now) async {
    try {
      final res = await ApiClient.get(
        '/calendario/eventos?firebase_uid=${widget.firebaseUid}&mes=${now.month}&anio=${now.year}',
      );
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        final en7Dias = now.add(const Duration(days: 7));
        final proximos = list.where((e) {
          if (e['estado'] != 'pendiente') return false;
          try {
            final f = DateTime.parse(e['fecha_evento'] as String);
            return !f.isBefore(DateTime(now.year, now.month, now.day)) && f.isBefore(en7Dias);
          } catch (_) { return false; }
        }).toList()
          ..sort((a, b) => (a['fecha_evento'] as String).compareTo(b['fecha_evento'] as String));
        if (mounted) setState(() { _proximosPagos = proximos; _loadingPagos = false; });
      } else {
        if (mounted) setState(() => _loadingPagos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPagos = false);
    }
  }

  Future<void> _cargarAhorro() async {
    try {
      final res = await ApiClient.get('/ahorros?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        if (mounted) {
          Map<String, dynamic>? mejor;
          double mejorPct = -1;
          for (final m in list) {
            final meta = double.tryParse(m['monto']?.toString() ?? '0') ?? 0;
            final ahorrado = double.tryParse(m['total_ahorrado']?.toString() ?? '0') ?? 0;
            final pct = meta > 0 ? ahorrado / meta : 0;
            if (pct > mejorPct) { mejorPct = pct.toDouble(); mejor = Map<String, dynamic>.from(m); }
          }
          setState(() { _metaAhorro = mejor; _todasMetas = list; _loadingAhorro = false; });
        }
      } else {
        if (mounted) setState(() { _errorAhorro = 'Error ${res.statusCode}'; _loadingAhorro = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorAhorro = e.toString(); _loadingAhorro = false; });
    }
  }

  Future<void> _cargarVentas() async {
    try {
      final res = await ApiClient.get('/ventas?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        final activas = list.where((v) => v['estado'] == 'activa').toList();
        double cobrado = 0;
        for (final v in activas) {
          cobrado += double.tryParse(v['total_cobrado']?.toString() ?? '0') ?? 0;
        }
        if (mounted) setState(() {
          _resumenVentas = {'cantidad': activas.length, 'total_cobrado': cobrado};
          _loadingVentas = false;
        });
      } else {
        if (mounted) setState(() { _errorVentas = 'Error ${res.statusCode}'; _loadingVentas = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorVentas = e.toString(); _loadingVentas = false; });
    }
  }

  // ── Financial computations ─────────────────────────────────────────────────

  double get _gastado =>
      double.tryParse(_presupuesto?['gastado']?.toString() ?? _presupuesto?['total_gastado']?.toString() ?? '0') ?? 0;

  double get _totalPresupuesto =>
      double.tryParse(_presupuesto?['monto_total']?.toString() ?? '0') ?? 0;

  double get _disponible =>
      double.tryParse(_presupuesto?['disponible']?.toString() ?? '0') ??
      (_totalPresupuesto - _gastado).clamp(0.0, double.infinity);

  double get _totalAhorro =>
      double.tryParse(_presupuesto?['total_ahorro']?.toString() ?? '0') ?? 0;

  double get _sharedBalanceNeto =>
      _sharedBudgets.fold(0.0, (s, b) => s + (double.tryParse(b['balance_neto']?.toString() ?? '0') ?? 0));

  double _getPctPeriodo() {
    try {
      final inicio = _presupuesto?['fecha_inicio'] ?? _presupuesto?['periodo_inicio'];
      final fin = _presupuesto?['fecha_fin'] ?? _presupuesto?['periodo_fin'];
      if (inicio == null || fin == null) return 0.5;
      final start = DateTime.parse(inicio.toString());
      final end = DateTime.parse(fin.toString());
      final now = DateTime.now();
      if (now.isBefore(start)) return 0;
      if (now.isAfter(end)) return 1;
      final total = end.difference(start).inDays;
      if (total == 0) return 1;
      return (now.difference(start).inDays / total).clamp(0.0, 1.0);
    } catch (_) { return 0.5; }
  }

  // Índice de Salud Financiera (0–100)
  int _calcularPuntaje() {
    if (_presupuesto == null) return 0;
    final total = _totalPresupuesto;
    if (total == 0) return 75;

    int score = 0;
    final gastadoPct = total > 0 ? _gastado / total : 0;
    final periodoPct = _getPctPeriodo();
    final diff = gastadoPct - periodoPct;

    // Control de presupuesto (40 pts)
    if (_gastado >= total) score += 0;
    else if (diff > 0.25) score += 10;
    else if (diff > 0.10) score += 25;
    else score += 40;

    // Tasa de ahorro (30 pts)
    final tasaAhorro = total > 0 ? _totalAhorro / total : 0;
    if (tasaAhorro >= 0.20) score += 30;
    else if (tasaAhorro >= 0.10) score += 20;
    else if (tasaAhorro >= 0.05) score += 10;

    // Balance compartido (20 pts)
    final balAbs = _sharedBalanceNeto.abs();
    if (balAbs < 1) score += 20;
    else if (balAbs < 50) score += 15;
    else if (balAbs < 200) score += 8;

    // Flujo de caja positivo (10 pts)
    final cobrado = (_resumenVentas?['total_cobrado'] as double?) ?? 0;
    if (cobrado > 0 && cobrado >= _gastado) score += 10;

    return score.clamp(0, 100);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Dashboard', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSaludCard(),
            const SizedBox(height: 12),
            _buildPeriodoCard(),
            const SizedBox(height: 12),
            _buildMiniRow(),
            const SizedBox(height: 12),
            _buildAhorroCard(),
            const SizedBox(height: 12),
            _buildCompartidoCard(),
            const SizedBox(height: 12),
            _buildProximosPagosCard(),
            const SizedBox(height: 12),
            _buildVentasCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Card helpers ───────────────────────────────────────────────────────────

  Widget _skeleton({double height = 100}) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border),
    ),
  );

  Widget _cardWrapper({
    required String title,
    required Color accentColor,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 3, height: 14,
              decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }

  // ── 1. Salud Financiera ────────────────────────────────────────────────────

  Widget _buildSaludCard() {
    final allLoaded = !_loadingPresupuesto && !_loadingShared && !_loadingVentas;
    if (!allLoaded) return _skeleton(height: 110);

    final score = _calcularPuntaje();
    final Color scoreColor;
    final String scoreLabel;
    if (score >= 90) { scoreColor = AppTheme.success; scoreLabel = 'EXCELENTE'; }
    else if (score >= 75) { scoreColor = AppTheme.success; scoreLabel = 'BUENA'; }
    else if (score >= 60) { scoreColor = AppTheme.primary; scoreLabel = 'REGULAR'; }
    else if (score >= 40) { scoreColor = Colors.orange; scoreLabel = 'BAJA'; }
    else { scoreColor = AppTheme.danger; scoreLabel = 'CRÍTICA'; }

    final insights = _buildInsights();

    return _cardWrapper(
      title: 'SALUD FINANCIERA',
      accentColor: scoreColor,
      child: Column(children: [
        Row(children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 68, height: 68,
              child: CircularProgressIndicator(
                value: score / 100, strokeWidth: 7,
                backgroundColor: AppTheme.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(scoreColor),
              ),
            ),
            Text('$score',
                style: TextStyle(color: scoreColor, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(scoreLabel, style: TextStyle(color: scoreColor, fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Índice de Salud Financiera',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
        ]),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          ...insights.map((i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                i.positive ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: i.positive ? AppTheme.success : AppTheme.danger,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(i.text,
                  style: TextStyle(
                    color: i.positive ? AppTheme.textSecondary : AppTheme.danger,
                    fontSize: 12,
                  ))),
            ]),
          )),
        ],
      ]),
    );
  }

  List<_Insight> _buildInsights() {
    final insights = <_Insight>[];
    if (_presupuesto == null) return insights;

    final total = _totalPresupuesto;
    if (total > 0) {
      final gastadoPct = _gastado / total;
      final periodoPct = _getPctPeriodo();
      final diff = gastadoPct - periodoPct;

      if (_gastado >= total) {
        insights.add(_Insight('Presupuesto agotado este período', positive: false));
      } else if (diff > 0.20) {
        insights.add(_Insight('Ritmo de gasto alto: ${(diff * 100).toStringAsFixed(0)}% por encima del período', positive: false));
      } else if (diff <= 0.05) {
        insights.add(_Insight('Gasto bajo control para el período actual', positive: true));
      }

      final tasaAhorro = _totalAhorro / total;
      if (tasaAhorro >= 0.20) {
        insights.add(_Insight('Tasa de ahorro excelente (${(tasaAhorro * 100).toStringAsFixed(0)}%)', positive: true));
      } else if (tasaAhorro < 0.10 && tasaAhorro >= 0) {
        insights.add(_Insight('Tasa de ahorro baja (${(tasaAhorro * 100).toStringAsFixed(0)}%) — meta recomendada: 20%', positive: false));
      }
    }

    final bal = _sharedBalanceNeto;
    if (bal > 100) {
      insights.add(_Insight('Deuda compartida pendiente: \$${_fmt.format(bal)}', positive: false));
    } else if (bal.abs() < 1 && _sharedBudgets.isNotEmpty) {
      insights.add(_Insight('Deudas compartidas al día', positive: true));
    }

    if (_proximosPagos.isNotEmpty) {
      insights.add(_Insight('${_proximosPagos.length} pago(s) urgente(s) esta semana', positive: false));
    }

    return insights.take(4).toList();
  }

  // ── 2. Período actual ──────────────────────────────────────────────────────

  Widget _buildPeriodoCard() {
    if (_loadingPresupuesto) return _skeleton(height: 180);
    if (_errorPresupuesto != null) {
      return _cardWrapper(
        title: 'PERÍODO ACTUAL',
        accentColor: AppTheme.colorFijo,
        child: Column(children: [
          Text('Error al cargar', style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          TextButton(onPressed: _cargarPresupuesto, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_presupuesto == null) {
      return _cardWrapper(
        title: 'PERÍODO ACTUAL',
        accentColor: AppTheme.colorFijo,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ListaPresupuestos(firebaseUid: widget.firebaseUid),
        )),
        child: Row(children: [
          const Text('Sin presupuesto activo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const Spacer(),
          Icon(Icons.add_circle_outline, color: AppTheme.colorFijo, size: 20),
        ]),
      );
    }

    final nombre = _presupuesto!['nombre'] ?? '';
    final total = _totalPresupuesto;
    final gastado = _gastado;
    final disponible = _disponible;
    final pctGasto = total > 0 ? (gastado / total).clamp(0.0, 1.0) : 0.0;
    final pctPeriodo = _getPctPeriodo();
    final barColor = pctGasto >= 1.0 ? AppTheme.danger : (pctGasto > 0.85 ? Colors.orange : AppTheme.primary);

    // Pace analysis
    final diff = pctGasto - pctPeriodo;
    final String paceText;
    final Color paceColor;
    final IconData paceIcon;
    if (pctGasto >= 1.0) {
      paceText = 'Presupuesto agotado';
      paceColor = AppTheme.danger; paceIcon = Icons.error_outline;
    } else if (diff > 0.20) {
      paceText = 'Ritmo alto — gastas más rápido de lo esperado';
      paceColor = AppTheme.danger; paceIcon = Icons.trending_up;
    } else if (diff > 0.08) {
      paceText = 'Ritmo ligeramente elevado';
      paceColor = Colors.orange; paceIcon = Icons.trending_up;
    } else if (diff < -0.10) {
      paceText = 'Excelente control — gasto por debajo del ritmo';
      paceColor = AppTheme.success; paceIcon = Icons.trending_down;
    } else {
      paceText = 'Ritmo ideal para el período';
      paceColor = AppTheme.success; paceIcon = Icons.trending_flat;
    }

    return _cardWrapper(
      title: 'PERÍODO ACTUAL',
      accentColor: AppTheme.colorFijo,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ListaPresupuestos(firebaseUid: widget.firebaseUid),
      )),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(nombre,
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('\$${_fmt.format(gastado)}',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 26)),
            const Text('gastado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${_fmt.format(total)}',
                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 14)),
            const Text('presupuesto', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 10),
        // Barra de gasto
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pctGasto, minHeight: 7,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(pctGasto * 100).toStringAsFixed(1)}% gastado',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          Text('Disponible \$${_fmt.format(disponible)}',
              style: TextStyle(
                color: disponible < total * 0.1 ? AppTheme.danger : AppTheme.success,
                fontSize: 10, fontWeight: FontWeight.w600,
              )),
        ]),
        const SizedBox(height: 8),
        // Barra del período
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pctPeriodo, minHeight: 4,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: const AlwaysStoppedAnimation(AppTheme.textMuted),
          ),
        ),
        const SizedBox(height: 4),
        Text('${(pctPeriodo * 100).toStringAsFixed(0)}% del período transcurrido',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        const SizedBox(height: 10),
        // Indicador de ritmo
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: paceColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(paceIcon, color: paceColor, size: 14),
            const SizedBox(width: 7),
            Expanded(child: Text(paceText,
                style: TextStyle(color: paceColor, fontSize: 11, fontWeight: FontWeight.w500))),
          ]),
        ),
      ]),
    );
  }

  // ── 3. Mini row (Flujo Neto + Tasa Ahorro) ────────────────────────────────

  Widget _buildMiniRow() {
    return Row(children: [
      Expanded(child: _buildFlujoCaja()),
      const SizedBox(width: 10),
      Expanded(child: _buildTasaAhorro()),
    ]);
  }

  Widget _buildFlujoCaja() {
    if (_loadingVentas || _loadingPresupuesto) return _skeleton(height: 90);
    final cobrado = (_resumenVentas?['total_cobrado'] as double?) ?? 0;
    final neto = cobrado - _gastado;
    final pos = neto >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 3, height: 12,
            decoration: BoxDecoration(color: AppTheme.success, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          const Text('FLUJO NETO',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Text(
          '${pos ? '+' : '-'}\$${_fmt.format(neto.abs())}',
          style: TextStyle(
              color: pos ? AppTheme.success : AppTheme.danger,
              fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 3),
        Text(pos ? 'Superávit' : 'Déficit',
            style: TextStyle(color: pos ? AppTheme.success : AppTheme.danger, fontSize: 11)),
      ]),
    );
  }

  Widget _buildTasaAhorro() {
    if (_loadingPresupuesto) return _skeleton(height: 90);
    final total = _totalPresupuesto;
    final tasa = total > 0 ? (_totalAhorro / total * 100) : 0.0;
    final good = tasa >= 20;
    final ok = tasa >= 10;
    final color = good ? AppTheme.success : (ok ? AppTheme.primary : AppTheme.danger);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 3, height: 12,
            decoration: BoxDecoration(color: AppTheme.colorAhorro, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          const Text('TASA AHORRO',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Text('${tasa.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 3),
        Text(good ? '✓ Sobre la meta' : (ok ? '≈ Cerca de la meta' : '↓ Meta: 20%'),
            style: TextStyle(color: color, fontSize: 11)),
      ]),
    );
  }

  // ── 4. Ahorro y Metas ─────────────────────────────────────────────────────

  Widget _buildAhorroCard() {
    if (_loadingAhorro) return _skeleton(height: 120);
    if (_errorAhorro != null) {
      return _cardWrapper(
        title: 'AHORRO Y METAS',
        accentColor: AppTheme.colorAhorro,
        child: Column(children: [
          Text('Error al cargar', style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          TextButton(onPressed: _cargarAhorro, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_metaAhorro == null) {
      return _cardWrapper(
        title: 'AHORRO Y METAS',
        accentColor: AppTheme.colorAhorro,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AhorroMetaScreen(firebaseUid: widget.firebaseUid),
        )),
        child: Row(children: [
          const Text('Sin metas de ahorro activas', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Icon(Icons.add_circle_outline, color: AppTheme.colorAhorro, size: 20),
        ]),
      );
    }

    final nombre = _metaAhorro!['descripcion'] ?? _metaAhorro!['nombre'] ?? '';
    final meta = double.tryParse(_metaAhorro!['monto']?.toString() ?? '0') ?? 0;
    final ahorrado = double.tryParse(_metaAhorro!['total_ahorrado']?.toString() ?? '0') ?? 0;
    final pct = meta > 0 ? (ahorrado / meta).clamp(0.0, 1.0) : 0.0;
    final restantes = _todasMetas.length - 1;

    return _cardWrapper(
      title: 'AHORRO Y METAS',
      accentColor: AppTheme.colorAhorro,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AhorroMetaScreen(firebaseUid: widget.firebaseUid),
      )),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(nombre,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: AppTheme.colorAhorro, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 8,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: const AlwaysStoppedAnimation(AppTheme.colorAhorro),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('\$${_fmt.format(ahorrado)} ahorrado',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text('Meta: \$${_fmt.format(meta)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
        if (restantes > 0) ...[
          const SizedBox(height: 8),
          Text('+ $restantes meta${restantes != 1 ? 's' : ''} más activa${restantes != 1 ? 's' : ''}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ]),
    );
  }

  // ── 5. Deudas compartidas ─────────────────────────────────────────────────

  Widget _buildCompartidoCard() {
    if (_loadingShared) return _skeleton(height: 90);
    final activos = _sharedBudgets.where((b) => b['estado'] == 'active').toList();
    if (activos.isEmpty) {
      return _cardWrapper(
        title: 'DEUDAS COMPARTIDAS',
        accentColor: AppTheme.info,
        child: const Text('Sin presupuestos compartidos activos',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      );
    }

    final balance = _sharedBalanceNeto;
    final debes = balance > 0.01;
    final teDeben = balance < -0.01;
    final color = debes ? AppTheme.danger : (teDeben ? AppTheme.success : AppTheme.textSecondary);
    final label = debes ? '↑ Debes' : (teDeben ? '↓ Te deben' : '✓ Sin deudas');

    final conBalance = activos
        .where((b) => (double.tryParse(b['balance_neto']?.toString() ?? '0') ?? 0).abs() > 0.01)
        .take(3)
        .toList();

    return _cardWrapper(
      title: 'DEUDAS COMPARTIDAS',
      accentColor: AppTheme.info,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => SharedBudgetsListScreen(firebaseUid: widget.firebaseUid),
      )),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          Text('\$${_fmt.format(balance.abs())}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
        ]),
        if (conBalance.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 10),
          ...conBalance.map((b) {
            final bal = double.tryParse(b['balance_neto']?.toString() ?? '0') ?? 0;
            final c = bal > 0 ? AppTheme.danger : AppTheme.success;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.fiber_manual_record, color: c, size: 7),
                const SizedBox(width: 8),
                Expanded(child: Text(b['nombre'] ?? '',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${bal > 0 ? 'Debes' : 'Te deben'} \$${_fmt.format(bal.abs())}',
                    style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w500)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ── 6. Próximos 7 días ────────────────────────────────────────────────────

  Widget _buildProximosPagosCard() {
    if (_loadingPagos) return _skeleton(height: 90);

    if (_proximosPagos.isEmpty) {
      return _cardWrapper(
        title: 'PRÓXIMOS 7 DÍAS',
        accentColor: AppTheme.colorNoFijo,
        child: Row(children: const [
          Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
          SizedBox(width: 8),
          Text('Sin pagos urgentes esta semana',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ]),
      );
    }

    final totalPendiente = _proximosPagos.fold<double>(
      0, (s, e) => s + (double.tryParse(e['monto_esperado']?.toString() ?? '0') ?? 0));
    final now = DateTime.now();

    return _cardWrapper(
      title: 'PRÓXIMOS 7 DÍAS',
      accentColor: AppTheme.colorNoFijo,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_proximosPagos.length} pago${_proximosPagos.length != 1 ? 's' : ''} pendiente${_proximosPagos.length != 1 ? 's' : ''}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text('\$${_fmt.format(totalPendiente)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 12),
        Divider(color: AppTheme.border, height: 1),
        const SizedBox(height: 10),
        ..._proximosPagos.take(4).map((e) {
          final titulo = e['titulo'] ?? e['descripcion'] ?? '';
          final monto = double.tryParse(e['monto_esperado']?.toString() ?? '0') ?? 0;
          DateTime? fecha;
          try { fecha = DateTime.parse(e['fecha_evento'] as String); } catch (_) {}
          final dias = fecha != null ? fecha.difference(DateTime(now.year, now.month, now.day)).inDays : null;
          final urgente = dias != null && dias <= 1;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: urgente ? AppTheme.danger : AppTheme.colorNoFijo,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(titulo,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              if (dias != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (urgente ? AppTheme.danger : AppTheme.textMuted).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dias == 0 ? 'Hoy' : (dias == 1 ? 'Mañana' : '$dias días'),
                    style: TextStyle(
                        color: urgente ? AppTheme.danger : AppTheme.textMuted,
                        fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(width: 8),
              Text('\$${_fmt.format(monto)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          );
        }),
      ]),
    );
  }

  // ── 7. Cobros activos ─────────────────────────────────────────────────────

  Widget _buildVentasCard() {
    if (_loadingVentas) return _skeleton(height: 80);
    if (_errorVentas != null) {
      return _cardWrapper(
        title: 'COBROS ACTIVOS',
        accentColor: AppTheme.primary,
        child: Column(children: [
          Text('Error al cargar', style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          TextButton(onPressed: _cargarVentas, child: const Text('Reintentar')),
        ]),
      );
    }

    final cantidad = _resumenVentas?['cantidad'] as int? ?? 0;
    final cobrado = (_resumenVentas?['total_cobrado'] as double?) ?? 0;

    if (cantidad == 0) {
      return _cardWrapper(
        title: 'COBROS ACTIVOS',
        accentColor: AppTheme.primary,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => CobrosHome(firebaseUid: widget.firebaseUid),
        )),
        child: Row(children: [
          const Icon(Icons.trending_flat, color: AppTheme.textMuted, size: 18),
          const SizedBox(width: 8),
          const Text('Sin cobros activos este mes',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
        ]),
      );
    }

    return _cardWrapper(
      title: 'COBROS ACTIVOS',
      accentColor: AppTheme.primary,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CobrosHome(firebaseUid: widget.firebaseUid),
      )),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$cantidad venta${cantidad != 1 ? 's' : ''} activa${cantidad != 1 ? 's' : ''}',
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 3),
          const Text('Total cobrado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ])),
        Text('\$${_fmt.format(cobrado)}',
            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 20)),
      ]),
    );
  }
}

// ── Insight model ──────────────────────────────────────────────────────────────

class _Insight {
  final String text;
  final bool positive;
  const _Insight(this.text, {required this.positive});
}
