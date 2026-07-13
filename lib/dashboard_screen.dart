import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'utils/money.dart';
import 'services/estado_anual_service.dart';
import 'services/calendar_service.dart';
import 'services/savings_service.dart';
import 'mes_detalle_screen.dart';
import 'widgets/financiero/agregar_gasto_sheet.dart';

class DashboardScreen extends StatefulWidget {
  final String firebaseUid;
  const DashboardScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _now = DateTime.now();

  Map<String, dynamic>? _mes;
  List<dynamic> _proximosPagos = [];
  List<Map<String, dynamic>> _alertas = [];
  List<dynamic> _metas = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Mes actual
      final mes = await EstadoAnualService.getMes(
          widget.firebaseUid, _now.year, _now.month);

      // Proximos pagos del calendario
      List<dynamic> pagos = [];
      try {
        final res = await CalendarService.getEventos(
            widget.firebaseUid, _now.month, _now.year);
        pagos = (res as List?)
            ?.where((e) => e['estado'] == 'pendiente')
            .toList() ?? [];
        pagos.sort((a, b) {
          final da = a['fecha_evento']?.toString() ?? '';
          final db = b['fecha_evento']?.toString() ?? '';
          return da.compareTo(db);
        });
        if (pagos.length > 5) pagos = pagos.sublist(0, 5);
      } catch (_) {}

      // Alertas no leídas
      List<Map<String, dynamic>> alertas = [];
      try {
        final al = await EstadoAnualService.getAlertas(
            widget.firebaseUid, anio: _now.year, mes: _now.month);
        alertas = (al['alertas'] as List? ?? []).cast<Map<String, dynamic>>();
      } catch (_) {}

      // Metas de ahorro activas
      List<dynamic> metas = [];
      try {
        final m = await SavingsService.getAhorros(widget.firebaseUid);
        metas = m.where((x) =>
            (x['activa'] as int? ?? 1) == 1).take(3).toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _mes = mes;
        _proximosPagos = pagos;
        _alertas = alertas;
        _metas = metas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        // U4 — rol del Dashboard: el AHORA (hoy, esta quincena, alertas)
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hoy'),
            Text('Simple: qué pagar, cuánto puedes usar y qué recortar',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirAgregarGasto,
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.background,
        icon: const Icon(Icons.add),
        label: const Text('Agregar gasto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(onRefresh: _cargar, child: _buildBody()),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off, color: AppTheme.textMuted, size: 48),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
      ]),
    ),
  );

  Widget _buildBody() {
    final r = (_mes?['resumen'] as Map<String, dynamic>?) ?? {};
    final ingEst   = _d(r['ingreso_estimado']);
    final ingReal  = _d(r['ingreso_real']);
    final ingreso  = ingReal > 0 ? ingReal : ingEst;
    final fijos    = _d(r['fijos_reales']);
    final vars     = _d(r['variables_reales']);
    final noPres   = _d(r['no_presupuestados']);
    final gastos   = fijos + vars + noPres;
    final remReal  = _d(r['remanente_real']);
    final pct      = ingreso > 0 ? (gastos / ingreso).clamp(0.0, 1.0) : 0.0;
    final mesNombre = _mesLabel(_now.month);

    // Compromisos pendientes
    final gastosFijos = ((_mes?['compromisos_fijos']?['gastos_fijos']) as List? ?? [])
        .cast<Map<String, dynamic>>();
    final registros = (_mes?['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    final pagadosIds = registros
        .where((r) => r['origen_fijo_id'] != null)
        .map((r) => (r['origen_fijo_id'] as num).toInt())
        .toSet();
    final pendientes = gastosFijos.where((g) {
      final id = (g['id'] as num?)?.toInt() ?? -1;
      return !pagadosIds.contains(id);
    }).toList();
    final totalPendiente = pendientes.fold(0.0, (s, g) => s + _d(g['monto']));

    final deudas = ((_mes?['compromisos_fijos']?['deudas']) as List? ?? [])
        .cast<Map<String, dynamic>>();
    final quincena = _now.day <= 15 ? 1 : 2;
    final ingresoQuincena = ingreso / 2;
    final compromisosQuincena = _compromisosQuincena(
      quincena: quincena,
      gastosFijos: gastosFijos,
      deudas: deudas,
    );
    final disponibleQuincena = ingresoQuincena - compromisosQuincena;

    // Sobres por categoría
    final sobres = (_mes?['analisis_categorias'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((c) => _d(c['presupuestado']) > 0 || _d(c['total_gastado']) > 0)
        .toList();

    // E3 — alerta más urgente (nivel danger) para mostrarla arriba de todo
    Map<String, dynamic>? alertaUrgente;
    for (final a in _alertas) {
      if ((a['nivel'] as String? ?? '') == 'danger') { alertaUrgente = a; break; }
    }

    // C1 — pagos de esta semana (próximos 7 días)
    final hoyD = DateTime(_now.year, _now.month, _now.day);
    final finSemana = hoyD.add(const Duration(days: 7));
    double totalSemana = 0;
    int countSemana = 0;
    for (final p in _proximosPagos) {
      final f = DateTime.tryParse((p as Map)['fecha_evento']?.toString() ?? '');
      if (f != null && !f.isAfter(finSemana)) {
        totalSemana += _d(p['monto_esperado']);
        countSemana++;
      }
    }
    final diasRestantesMes = DateTime(_now.year, _now.month + 1, 0).day - _now.day + 1;
    final gastoDiarioSeguro = diasRestantesMes > 0 && remReal > 0
        ? remReal / diasRestantesMes
        : 0.0;
    final ultimoDiaMes = DateTime(_now.year, _now.month + 1, 0).day;
    final finQuincena = quincena == 1 ? 15 : ultimoDiaMes;
    final diasRestantesQuincena = (finQuincena - _now.day + 1).clamp(1, 31).toInt();
    final gastoDiarioQuincena = disponibleQuincena > 0
        ? disponibleQuincena / diasRestantesQuincena
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── E3 · ALERTA MÁS URGENTE (arriba de todo) ──────────────────────
        if (alertaUrgente != null) ...[
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => MesDetalleScreen(
                firebaseUid: widget.firebaseUid,
                anio: _now.year, mes: _now.month, label: mesNombre,
              ),
            )).then((_) => _cargar()),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(alertaUrgente['titulo'] as String? ?? 'Atención',
                      style: const TextStyle(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.w800)),
                  if ((alertaUrgente['accion_sugerida'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(alertaUrgente['accion_sugerida'] as String,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
                  ],
                ])),
                const Icon(Icons.chevron_right, color: AppTheme.danger, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── MODO QUINCENA: decisión principal del día ───────────────────
        _QuincenaDecisionCard(
          quincena: quincena,
          ingresoQuincena: ingresoQuincena,
          compromisosQuincena: compromisosQuincena,
          disponibleQuincena: disponibleQuincena,
          diasRestantes: diasRestantesQuincena,
          gastoDiarioSeguro: gastoDiarioQuincena,
          onRegistrarGasto: _abrirAgregarGasto,
          onEscanearFactura: _abrirScanner,
          onVerPagos: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MesDetalleScreen(
              firebaseUid: widget.firebaseUid,
              anio: _now.year,
              mes: _now.month,
              label: mesNombre,
              initialTabIndex: 2,
            ),
          )).then((_) => _cargar()),
        ),
        const SizedBox(height: 12),

        // ── GUÍA SIMPLE "FOR DUMMIES" ───────────────────────────────────
        _DummiesGuideCard(
          remanente: remReal,
          gastoDiarioSeguro: gastoDiarioSeguro,
          pendientesCount: pendientes.length,
          pendientesTotal: totalPendiente,
          hormigaCount: _d(r['hormiga_count']).toInt(),
          hormigaTotal: _d(r['hormiga_total']),
          onRegistrarGasto: _abrirAgregarGasto,
          onVerMes: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MesDetalleScreen(
              firebaseUid: widget.firebaseUid,
              anio: _now.year,
              mes: _now.month,
              label: mesNombre,
              initialTabIndex: 1,
            ),
          )).then((_) => _cargar()),
        ),
        const SizedBox(height: 12),

        // ── CARD PRINCIPAL DEL MES ────────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MesDetalleScreen(
              firebaseUid: widget.firebaseUid,
              anio: _now.year, mes: _now.month, label: mesNombre,
            ),
          )).then((_) => _cargar()),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('HOY · $mesNombre ${_now.year}',
                      style: const TextStyle(color: AppTheme.primary,
                          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _MiniStat('Ingreso', Money.fmt(ingreso), AppTheme.success)),
                Expanded(child: _MiniStat('Gastado', Money.fmt(gastos),
                    pct > 0.9 ? AppTheme.danger : pct > 0.7 ? AppTheme.warning : AppTheme.textPrimary)),
                Expanded(child: _MiniStat('Remanente', Money.fmt(remReal),
                    remReal >= 0 ? AppTheme.success : AppTheme.danger)),
              ]),
              const SizedBox(height: 14),
              // Barra de uso
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  color: pct > 0.9 ? AppTheme.danger
                      : pct > 0.7 ? AppTheme.warning
                      : AppTheme.success,
                  backgroundColor: AppTheme.surfaceAlt,
                ),
              ),
              const SizedBox(height: 6),
              Text('${(pct * 100).toStringAsFixed(1)}% del ingreso usado',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              if (ingReal == 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: AppTheme.warning, size: 13),
                    SizedBox(width: 6),
                    Text('Ingreso real no registrado — usando estimado',
                        style: TextStyle(color: AppTheme.warning, fontSize: 11)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

        // ── DISPONIBLE QUINCENAL ─────────────────────────────────────────
        if (ingreso > 0) ...[
          const SizedBox(height: 12),
          _QuincenalCard(
            quincena: quincena,
            mesNombre: mesNombre,
            ingreso: ingreso,
            gastosFijos: gastosFijos,
            deudas: deudas,
          ),
        ],

        // ── COMPROMISOS PENDIENTES ────────────────────────────────────────
        if (pendientes.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => MesDetalleScreen(
                firebaseUid: widget.firebaseUid,
                anio: _now.year, mes: _now.month, label: mesNombre,
              ),
            )).then((_) => _cargar()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.pending_actions, color: AppTheme.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '${pendientes.length} ${pendientes.length == 1 ? 'compromiso' : 'compromisos'} por pagar · ${Money.fmt(totalPendiente)}',
                  style: const TextStyle(color: AppTheme.warning,
                      fontSize: 13, fontWeight: FontWeight.w600),
                )),
                const Icon(Icons.chevron_right, color: AppTheme.warning, size: 16),
              ]),
            ),
          ),
        ],

        // ── SOBRES DEL MES ────────────────────────────────────────────────
        if (sobres.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('SOBRES DEL MES', Icons.account_balance_wallet_outlined, AppTheme.primary),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sobres.map((c) {
                final rawCat = c['categoria'] as String? ?? '';
                final nombre = rawCat.isNotEmpty
                    ? '${rawCat[0].toUpperCase()}${rawCat.substring(1)}'
                    : rawCat;
                final presup = _d(c['presupuestado']);
                final total  = _d(c['total_gastado']);
                final bar    = presup > 0 ? (total / presup).clamp(0.0, 1.0) : 0.0;
                final excede = presup > 0 && total > presup;
                final color  = excede ? AppTheme.danger
                    : bar > 0.8 ? AppTheme.warning
                    : AppTheme.success;
                return Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: excede
                        ? AppTheme.danger.withValues(alpha: 0.5)
                        : AppTheme.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textPrimary,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: bar,
                        minHeight: 4,
                        color: color,
                        backgroundColor: AppTheme.surfaceAlt,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      excede
                          ? '+${Money.fmt((total - presup))} excedido'
                          : presup > 0
                              ? '${Money.fmt((presup - total))} restante'
                              : '${Money.fmt(total)}',
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],

        // ── GASTOS HORMIGA ────────────────────────────────────────────────
        if (_d(r['hormiga_count']) > 0) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => MesDetalleScreen(
                firebaseUid: widget.firebaseUid,
                anio: _now.year, mes: _now.month, label: mesNombre,
              ),
            )).then((_) => _cargar()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                const Text('🐜', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '${_d(r['hormiga_count']).toInt()} gastos hormiga · ${Money.fmt(_d(r['hormiga_total']))} acumulado',
                  style: TextStyle(color: AppTheme.textSecondary,
                      fontSize: 13, fontWeight: FontWeight.w500),
                )),
                Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 16),
              ]),
            ),
          ),
        ],

        // ── ALERTAS (resto, sin repetir la urgente del tope) ──────────────
        if (_alertas.where((a) => !identical(a, alertaUrgente)).isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('ALERTAS', Icons.notifications_active, AppTheme.warning),
          const SizedBox(height: 8),
          ..._alertas.where((a) => !identical(a, alertaUrgente)).take(3).map((a) {
            final nivel = a['nivel'] as String? ?? 'info';
            final color = nivel == 'danger' ? AppTheme.danger
                : nivel == 'warning' ? AppTheme.warning : AppTheme.info;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(a['titulo'] as String? ?? '',
                  style: TextStyle(color: color, fontSize: 12,
                      fontWeight: FontWeight.w600)),
            );
          }),
        ],

        // ── PRÓXIMOS PAGOS ────────────────────────────────────────────────
        if (_proximosPagos.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(children: [
            const _SectionLabel('PRÓXIMOS PAGOS', Icons.calendar_today, AppTheme.info),
            const Spacer(),
            // C1 — resumen de lo que cae en los próximos 7 días
            if (countSemana > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Esta semana · ${Money.fmt(totalSemana)}',
                    style: const TextStyle(color: AppTheme.warning,
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: _proximosPagos.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value as Map<String, dynamic>;
                final fecha = (p['fecha_evento']?.toString() ?? '').substring(0, 10);
                final monto = _d(p['monto_esperado']);
                final f = DateTime.tryParse(p['fecha_evento']?.toString() ?? '');
                final esSemana = f != null && !f.isAfter(finSemana);
                return Column(children: [
                  if (i > 0) Divider(color: AppTheme.border, height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    leading: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: (esSemana ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(Icons.payment,
                          color: esSemana ? AppTheme.warning : AppTheme.info, size: 16),
                    ),
                    title: Row(children: [
                      Flexible(child: Text(p['titulo'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.textPrimary,
                              fontSize: 13, fontWeight: FontWeight.w600))),
                      if (esSemana) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Esta semana',
                              style: TextStyle(color: AppTheme.warning,
                                  fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    subtitle: Text(fecha,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    trailing: Text('${Money.fmt(monto)}',
                        style: TextStyle(color: esSemana ? AppTheme.warning : AppTheme.info,
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ] else ...[
          const SizedBox(height: 20),
          _SectionLabel('PRÓXIMOS PAGOS', Icons.calendar_today, AppTheme.info),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text('Sin pagos pendientes este mes.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
        ],

        // ── METAS DE AHORRO ───────────────────────────────────────────────
        if (_metas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('METAS DE AHORRO', Icons.savings_outlined, AppTheme.colorAhorro),
          const SizedBox(height: 8),
          ..._metas.map((m) {
            final nombre = m['nombre'] as String? ?? '';
            final meta   = _d(m['monto_objetivo'] ?? m['monto_total']);
            final actual = _d(m['monto_actual'] ?? m['total_aportado']);
            final pctM   = meta > 0 ? (actual / meta).clamp(0.0, 1.0) : 0.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nombre,
                      style: TextStyle(color: AppTheme.textPrimary,
                          fontSize: 13, fontWeight: FontWeight.w600))),
                  Text('${Money.fmt0(actual)} / ${Money.fmt0(meta)}',
                      style: const TextStyle(color: AppTheme.colorAhorro,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pctM,
                    minHeight: 6,
                    color: AppTheme.colorAhorro,
                    backgroundColor: AppTheme.surfaceAlt,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(pctM * 100).toStringAsFixed(0)}% completado',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            );
          }),
        ],

        const SizedBox(height: 80), // espacio para el FAB
      ],
    );
  }

  void _abrirAgregarGasto() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgregarGastoSheet(
        firebaseUid: widget.firebaseUid,
        anio: _now.year,
        mes: _now.month,
        analisisCategorias: (_mes?['analisis_categorias'] as List?)
            ?.cast<Map<String, dynamic>>(),
      ),
    );
    if (res == true) _cargar();
  }

  void _abrirScanner() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
    )).then((_) => _cargar());
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  double _compromisosQuincena({
    required int quincena,
    required List<Map<String, dynamic>> gastosFijos,
    required List<Map<String, dynamic>> deudas,
  }) {
    double total = 0;
    for (final g in gastosFijos) {
      final diaPago  = g['dia_pago'] as int?;
      final diaPago2 = g['dia_pago_2'] as int?;
      final monto = _d(g['monto']);
      final tieneDos = diaPago != null && diaPago2 != null;
      final montoQ = tieneDos ? monto / 2 : monto;

      if (diaPago == null || diaPago == 15) {
        total += monto / 2;
      } else {
        if (quincena == 1 && diaPago >= 1 && diaPago <= 14) total += montoQ;
        if (quincena == 2 && diaPago >= 16) total += montoQ;
        if (diaPago2 != null) {
          if (quincena == 1 && diaPago2 >= 1 && diaPago2 <= 14) total += montoQ;
          if (quincena == 2 && diaPago2 >= 16) total += montoQ;
        }
      }
    }
    for (final d in deudas) {
      total += _d(d['cuota']) / 2;
    }
    return total;
  }

  static String _mesLabel(int m) => const [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ][m];
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: TextStyle(color: AppTheme.textMuted,
        fontSize: 10, letterSpacing: 0.4)),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(color: color,
        fontSize: 14, fontWeight: FontWeight.w700)),
  ]);
}

class _QuincenaDecisionCard extends StatelessWidget {
  final int quincena;
  final double ingresoQuincena;
  final double compromisosQuincena;
  final double disponibleQuincena;
  final int diasRestantes;
  final double gastoDiarioSeguro;
  final VoidCallback onRegistrarGasto;
  final VoidCallback onEscanearFactura;
  final VoidCallback onVerPagos;

  const _QuincenaDecisionCard({
    required this.quincena,
    required this.ingresoQuincena,
    required this.compromisosQuincena,
    required this.disponibleQuincena,
    required this.diasRestantes,
    required this.gastoDiarioSeguro,
    required this.onRegistrarGasto,
    required this.onEscanearFactura,
    required this.onVerPagos,
  });

  @override
  Widget build(BuildContext context) {
    final color = disponibleQuincena <= 0
        ? AppTheme.danger
        : disponibleQuincena < ingresoQuincena * 0.20
            ? AppTheme.warning
            : AppTheme.success;
    final estado = disponibleQuincena <= 0
        ? 'No gastes libremente'
        : disponibleQuincena < ingresoQuincena * 0.20
            ? 'Modo cuidado'
            : 'Puedes respirar';
    final consejo = disponibleQuincena <= 0
        ? 'Tus compromisos cubren o superan esta quincena. Solo registra pagos necesarios.'
        : 'Si te limitas a ${Money.fmt(gastoDiarioSeguro)} por día, llegas mejor al próximo cobro.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.18),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('MODO QUINCENA · Q$quincena',
                style: TextStyle(color: color, fontSize: 11,
                    fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          ),
          const Spacer(),
          Icon(Icons.payments_outlined, color: color, size: 20),
        ]),
        const SizedBox(height: 14),
        Text(estado,
            style: TextStyle(color: AppTheme.textPrimary,
                fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(consejo,
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 13, height: 1.35)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _DecisionMetric(
            label: 'Cobro Q$quincena',
            value: Money.fmt(ingresoQuincena),
            color: AppTheme.success,
          )),
          Expanded(child: _DecisionMetric(
            label: 'Separar',
            value: Money.fmt(compromisosQuincena),
            color: AppTheme.warning,
          )),
          Expanded(child: _DecisionMetric(
            label: 'Libre',
            value: Money.fmt(disponibleQuincena),
            color: color,
          )),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(children: [
            Icon(Icons.today_outlined, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Te quedan $diasRestantes ${diasRestantes == 1 ? 'día' : 'días'} en esta quincena.',
              style: TextStyle(color: AppTheme.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w600),
            )),
            Text(Money.fmt(gastoDiarioSeguro),
                style: TextStyle(color: color,
                    fontSize: 15, fontWeight: FontWeight.w900)),
            Text(' /día',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onRegistrarGasto,
              icon: const Icon(Icons.add_card, size: 17),
              label: const Text('Gasté algo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.background,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEscanearFactura,
              icon: const Icon(Icons.qr_code_scanner, size: 17),
              label: const Text('Factura'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ),
          IconButton(
            onPressed: onVerPagos,
            tooltip: 'Ver pagos de la quincena',
            color: color,
            icon: const Icon(Icons.checklist_rtl),
          ),
        ]),
      ]),
    );
  }
}

class _DecisionMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DecisionMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: TextStyle(color: AppTheme.textMuted,
              fontSize: 10, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color,
              fontSize: 14, fontWeight: FontWeight.w900)),
    ],
  );
}

class _DummiesGuideCard extends StatelessWidget {
  final double remanente;
  final double gastoDiarioSeguro;
  final int pendientesCount;
  final double pendientesTotal;
  final int hormigaCount;
  final double hormigaTotal;
  final VoidCallback onRegistrarGasto;
  final VoidCallback onVerMes;

  const _DummiesGuideCard({
    required this.remanente,
    required this.gastoDiarioSeguro,
    required this.pendientesCount,
    required this.pendientesTotal,
    required this.hormigaCount,
    required this.hormigaTotal,
    required this.onRegistrarGasto,
    required this.onVerMes,
  });

  @override
  Widget build(BuildContext context) {
    final color = remanente < 0
        ? AppTheme.danger
        : pendientesCount > 0
            ? AppTheme.warning
            : AppTheme.success;
    final titulo = remanente < 0
        ? 'Alto: estás en negativo'
        : pendientesCount > 0
            ? 'Primero paga lo pendiente'
            : 'Vas bien por ahora';
    final accion = remanente < 0
        ? 'No hagas gastos nuevos. Revisa qué puedes mover o cancelar.'
        : pendientesCount > 0
            ? 'Separa ${Money.fmt(pendientesTotal)} antes de gastar en otra cosa.'
            : 'Puedes gastar aprox. ${Money.fmt(gastoDiarioSeguro)} por día sin pasarte.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_objects_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GUÍA SIMPLE',
                style: TextStyle(color: color, fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 0.7)),
            const SizedBox(height: 4),
            Text(titulo,
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(accion,
                style: TextStyle(color: AppTheme.textSecondary,
                    fontSize: 13, height: 1.35)),
          ])),
        ]),
        const SizedBox(height: 14),
        _SimpleStep(
          number: '1',
          text: pendientesCount > 0
              ? 'Paga o separa tus compromisos pendientes.'
              : 'No tienes compromisos urgentes pendientes.',
          color: pendientesCount > 0 ? AppTheme.warning : AppTheme.success,
        ),
        _SimpleStep(
          number: '2',
          text: 'Registra cada compra al momento para saber cuánto queda.',
          color: AppTheme.primary,
        ),
        _SimpleStep(
          number: '3',
          text: hormigaCount > 0
              ? 'Cuida los gastos hormiga: ya van $hormigaCount por ${Money.fmt(hormigaTotal)}.'
              : 'Mantén los gastos hormiga en cero o muy bajitos.',
          color: hormigaCount > 0 ? AppTheme.warning : AppTheme.success,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onRegistrarGasto,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar gasto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.background,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onVerMes,
            style: OutlinedButton.styleFrom(foregroundColor: color),
            child: const Text('Ver mes'),
          ),
        ]),
      ]),
    );
  }
}

class _SimpleStep extends StatelessWidget {
  final String number;
  final String text;
  final Color color;

  const _SimpleStep({
    required this.number,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Text(number,
            style: TextStyle(color: color, fontSize: 11,
                fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 9),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(text,
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 12, height: 1.3)),
      )),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SectionLabel(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 14),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: color,
        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
  ]);
}

class _QuincenalCard extends StatelessWidget {
  final int quincena;
  final String mesNombre;
  final double ingreso;
  final List<Map<String, dynamic>> gastosFijos;
  final List<Map<String, dynamic>> deudas;

  const _QuincenalCard({
    required this.quincena,
    required this.mesNombre,
    required this.ingreso,
    required this.gastosFijos,
    required this.deudas,
  });

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  double _compromisosQuincena() {
    double total = 0;
    for (final g in gastosFijos) {
      final diaPago  = g['dia_pago'] as int?;
      final diaPago2 = g['dia_pago_2'] as int?;
      final monto = _d(g['monto']);
      final tieneDos = diaPago != null && diaPago2 != null;
      final montoQ = tieneDos ? monto / 2 : monto;

      if (diaPago == null) {
        total += monto / 2;
      } else if (diaPago == 15) {
        total += monto / 2;
      } else {
        if (quincena == 1 && diaPago >= 1 && diaPago <= 14) total += montoQ;
        if (quincena == 2 && diaPago >= 16) total += montoQ;
        if (diaPago2 != null) {
          if (quincena == 1 && diaPago2 >= 1 && diaPago2 <= 14) total += montoQ;
          if (quincena == 2 && diaPago2 >= 16) total += montoQ;
        }
      }
    }
    for (final d in deudas) {
      total += _d(d['cuota']) / 2;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final ingresoQ   = ingreso / 2;
    final compQ      = _compromisosQuincena();
    final disponible = ingresoQ - compQ;
    final color = disponible > ingresoQ * 0.3 ? AppTheme.success
        : disponible > 0 ? AppTheme.warning
        : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calendar_view_week, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            'Q$quincena · $mesNombre'.toUpperCase(),
            style: TextStyle(color: color, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
        ]),
        const SizedBox(height: 12),
        _FilaQ('Cobro estimado', ingresoQ, AppTheme.success),
        _FilaQ('Compromisos Q$quincena', -compQ, AppTheme.textSecondary),
        Divider(color: AppTheme.border, height: 14),
        _FilaQ('Disponible libre', disponible, color, bold: true),
        const SizedBox(height: 4),
        Text(
          disponible > 0
              ? 'Después de compromisos fijos de esta quincena'
              : 'Compromisos superan el cobro quincenal',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
        ),
      ]),
    );
  }
}

class _FilaQ extends StatelessWidget {
  final String label;
  final double valor;
  final Color color;
  final bool bold;
  const _FilaQ(this.label, this.valor, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(label,
          style: TextStyle(
            color: AppTheme.textSecondary, fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ))),
      Text(
        valor < 0 ? '−${Money.fmt(-valor)}' : Money.fmt(valor),
        style: TextStyle(
          color: color, fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ]),
  );
}
