import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';
import '../widgets/ayuda_sheet.dart';
import '../widgets/empty_state.dart';
import 'crear_deuda_sheet.dart';
import 'abono_deuda_sheet.dart';
import 'historial_abonos_sheet.dart';
import '../utils/money.dart';

class DeudasScreen extends StatefulWidget {
  final String firebaseUid;
  const DeudasScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<DeudasScreen> createState() => _DeudasScreenState();
}

class _DeudasScreenState extends State<DeudasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<dynamic> _deudas = [];
  double _totalPendiente = 0;
  double _totalPagoMinimo = 0;
  bool _loading = true;
  bool _incluirSaldadas = false;

  Map<String, dynamic>? _proyeccion;
  bool _loadingProy = true;

  double _extraMensual = 0;
  String _estrategia = 'avalanche';
  Map<String, dynamic>? _simulador;
  bool _loadingSim = false;

  Map<String, dynamic>? _plan;
  bool _loadingPlan = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _onTabChanged(_tabs.index);
    });
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged(int i) {
    if (i == 1 && _proyeccion == null) _cargarProyeccion();
    if (i == 2 && _simulador == null) _cargarSimulador();
    if (i == 3) { _plan = null; _cargarPlan(); } // siempre recarga al abrir Mi Plan
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await DeudasService.getAll(widget.firebaseUid,
          incluirSaldadas: _incluirSaldadas);
      if (!mounted) return;
      final lista = (data['deudas'] as List? ?? []);
      lista.sort((a, b) => _d(b['tasa_interes']).compareTo(_d(a['tasa_interes'])));
      setState(() {
        _deudas = lista;
        _totalPendiente = _d(data['total_pendiente']);
        _totalPagoMinimo = _d(data['total_pago_minimo']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _cargarProyeccion() async {
    setState(() => _loadingProy = true);
    try {
      final data = await DeudasService.getProyeccion(widget.firebaseUid);
      if (!mounted) return;
      setState(() { _proyeccion = data; _loadingProy = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProy = false);
    }
  }

  Future<void> _cargarSimulador() async {
    setState(() => _loadingSim = true);
    try {
      final data = await DeudasService.getSimulador(
          widget.firebaseUid, _extraMensual, _estrategia);
      if (!mounted) return;
      setState(() { _simulador = data; _loadingSim = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSim = false);
    }
  }

  Future<void> _cargarPlan() async {
    setState(() => _loadingPlan = true);
    try {
      final data = await DeudasService.getPlan(
          widget.firebaseUid, _estrategia, _extraMensual);
      if (!mounted) return;
      setState(() { _plan = data; _loadingPlan = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  Future<void> _archivar(int id, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Archivar deuda',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('¿Marcar "$nombre" como saldada/archivada?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archivar')),
        ],
      ),
    );
    if (ok == true) {
      await DeudasService.archivar(id, widget.firebaseUid);
      _cargar();
      // Resetear caché de las otras tabs
      setState(() { _proyeccion = null; _simulador = null; _plan = null; });
    }
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Mis Deudas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => AyudaSheet.show(context,
              titulo: 'Mis Deudas',
              subtitulo: 'Controla tarjetas, préstamos y letras en un solo lugar.',
              items: const [
                AyudaItem(Icons.credit_card, 'Monto total vs pendiente',
                    'Total = lo que debías originalmente. Pendiente = lo que te falta pagar hoy.'),
                AyudaItem(Icons.percent, 'Tasa de interés (TEA)',
                    'Tasa Efectiva Anual. La encuentras en tu estado de cuenta o contrato. Ej: tarjeta Visa BAC = ~24% anual.'),
                AyudaItem(Icons.calculate_outlined, 'Cuota calculada',
                    'Al ingresar tasa + plazo + saldo, la app calcula tu cuota con la fórmula financiera estándar (PMT).'),
                AyudaItem(Icons.bar_chart_rounded, 'Estrategia avalanche',
                    'Paga primero la deuda con mayor tasa de interés. Ahorra más dinero a largo plazo.'),
                AyudaItem(Icons.bolt_outlined, 'Estrategia snowball',
                    'Paga primero la deuda más pequeña. Genera motivación al eliminar deudas rápido.'),
                AyudaItem(Icons.account_balance_wallet_outlined, 'Afecta el estado financiero',
                    'La cuota mensual de cada deuda se suma a tus gastos fijos estimados automáticamente.'),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
                _incluirSaldadas
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20),
            tooltip: _incluirSaldadas ? 'Ocultar saldadas' : 'Ver saldadas',
            onPressed: () {
              setState(() => _incluirSaldadas = !_incluirSaldadas);
              _cargar();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Situación'),
            Tab(text: 'Estrategias'),
            Tab(text: 'Simulador'),
            Tab(text: 'Mi Plan'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => CrearDeudaSheet.show(context,
                  firebaseUid: widget.firebaseUid,
                  onCreada: () {
                    _cargar();
                    setState(() {
                      _proyeccion = null;
                      _simulador = null;
                      _plan = null;
                    });
                  }),
              icon: const Icon(Icons.add),
              label: const Text('Nueva deuda'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _TabSituacion(
            deudas: _deudas,
            totalPendiente: _totalPendiente,
            totalPagoMinimo: _totalPagoMinimo,
            loading: _loading,
            uid: widget.firebaseUid,
            onRefresh: _cargar,
            onArchivar: _archivar,
            onAbono: (deuda) => AbonoDeudaSheet.show(context,
                deuda: deuda,
                firebaseUid: widget.firebaseUid,
                onAbonado: () {
                  _cargar();
                  setState(() {
                    _proyeccion = null;
                    _simulador = null;
                    _plan = null;
                  });
                }),
            onEditar: (deuda) => CrearDeudaSheet.show(context,
                firebaseUid: widget.firebaseUid,
                deudaExistente: deuda,
                onCreada: () {
                  _cargar();
                  setState(() {
                    _proyeccion = null;
                    _simulador = null;
                    _plan = null;
                  });
                }),
            onCrear: () => CrearDeudaSheet.show(context,
                firebaseUid: widget.firebaseUid,
                onCreada: () {
                  _cargar();
                  setState(() {
                    _proyeccion = null;
                    _simulador = null;
                    _plan = null;
                  });
                }),
          ),
          _TabEstrategias(
            proyeccion: _proyeccion,
            loading: _loadingProy,
            onLoad: _cargarProyeccion,
          ),
          _TabSimulador(
            simulador: _simulador,
            loading: _loadingSim,
            extraMensual: _extraMensual,
            estrategia: _estrategia,
            deudas: _deudas,
            onChanged: (extra, est) {
              setState(() {
                _extraMensual = extra;
                _estrategia = est;
                _simulador = null;
                _plan = null;
              });
              _cargarSimulador();
            },
          ),
          _TabPlan(
            plan: _plan,
            loading: _loadingPlan,
            onLoad: _cargarPlan,
            estrategia: _estrategia,
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Situación actual ────────────────────────────────────────────────────

class _TabSituacion extends StatelessWidget {
  final List<dynamic> deudas;
  final double totalPendiente;
  final double totalPagoMinimo;
  final bool loading;
  final String uid;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int, String) onArchivar;
  final void Function(Map<String, dynamic>) onAbono;
  final void Function(Map<String, dynamic>) onEditar;
  final VoidCallback onCrear;

  const _TabSituacion({
    required this.deudas,
    required this.totalPendiente,
    required this.totalPagoMinimo,
    required this.loading,
    required this.uid,
    required this.onRefresh,
    required this.onArchivar,
    required this.onAbono,
    required this.onEditar,
    required this.onCrear,
  });

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (deudas.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 24),
        children: [
          EmptyState(
            icon: Icons.credit_card_off_outlined,
            title: 'Sin deudas registradas',
            subtitle: 'Lleva el control de tarjetas, préstamos y letras.',
            actionLabel: 'Registrar deuda',
            onAction: onCrear,
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── PRÓXIMA ACCIÓN ─────────────────────────────────────────────
          _ProximaAccion(deudas: deudas, totalPagoMinimo: totalPagoMinimo),
          const SizedBox(height: 12),

          // Resumen
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Deuda total pendiente',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${Money.fmt(totalPendiente)}',
                      style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
              if (totalPagoMinimo > 0)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Pago mínimo mensual',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('${Money.fmt(totalPagoMinimo)}',
                      style: const TextStyle(
                          color: AppTheme.warning,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ]),
            ]),
          ),
          const SizedBox(height: 12),

          // ── I4: progreso consolidado (cuánto llevo pagado del total) ───────
          Builder(builder: (_) {
            double orig = 0;
            for (final d in deudas) {
              final mt = _d(d['monto_total']);
              final mp = _d(d['monto_pendiente']);
              orig += mt > 0 ? mt : mp; // si no hay original, usa el pendiente
            }
            if (orig <= 0) return const SizedBox.shrink();
            final pagado = (orig - totalPendiente).clamp(0.0, orig);
            final pct = (pagado / orig).clamp(0.0, 1.0);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Progreso total de tus deudas',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text('${(pct * 100).toStringAsFixed(0)}% pagado',
                      style: const TextStyle(color: AppTheme.success,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 8,
                    color: AppTheme.success, backgroundColor: AppTheme.surfaceAlt,
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Original: ${Money.fmt(orig)}',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  Text('Pagado: ${Money.fmt(pagado)}',
                      style: const TextStyle(color: AppTheme.success, fontSize: 11)),
                  Text('Falta: ${Money.fmt(totalPendiente)}',
                      style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
                ]),
              ]),
            );
          }),
          const SizedBox(height: 16),
          // Banner de deudas con información incompleta (creadas desde el perfil)
          Builder(builder: (_) {
            final incompletas = deudas.where((d) =>
              (d['monto_pendiente'] == null || d['monto_pendiente'] == 0) ||
              d['tasa_interes'] == null
            ).toList();
            if (incompletas.isEmpty) return const SizedBox.shrink();
            final primera = incompletas.first as Map<String, dynamic>;
            // I1 — decir exactamente qué falta en la primera deuda incompleta
            final faltantes = <String>[];
            if (primera['monto_pendiente'] == null || primera['monto_pendiente'] == 0) {
              faltantes.add('saldo pendiente');
            }
            if (primera['tasa_interes'] == null) faltantes.add('tasa de interés');
            final nombrePrimera = primera['nombre'] as String? ?? 'una deuda';
            final detalleFalta = faltantes.join(' y ');
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    incompletas.length > 1
                        ? '${incompletas.length} deudas tienen información incompleta. A "$nombrePrimera" le falta: $detalleFalta.'
                        : 'A "$nombrePrimera" le falta: $detalleFalta. Complétalo para proyectarla correctamente.',
                    style: const TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
                  )),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onEditar(primera),
                    icon: const Icon(Icons.edit_outlined, size: 15, color: AppTheme.warning),
                    label: Text('Completar "$nombrePrimera"',
                        style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ]),
            );
          }),
          ...deudas.asMap().entries.map((e) {
            final d = e.value as Map<String, dynamic>;
            final infoIncompleta = (d['monto_pendiente'] == null ||
                d['monto_pendiente'] == 0) || d['tasa_interes'] == null;
            return _DeudaTile(
              deuda: d,
              uid: uid,
              esMayorTasa: e.key == 0 &&
                  deudas.length > 1 &&
                  _d(d['tasa_interes']) > 0,
              infoIncompleta: infoIncompleta,
              onAbono: () => onAbono(d),
              onArchivar: () =>
                  onArchivar(d['id'] as int, d['nombre'] as String? ?? ''),
              onEditar: () => onEditar(d),
            );
          }),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ── Tab 2: Estrategias ─────────────────────────────────────────────────────────

class _TabEstrategias extends StatelessWidget {
  final Map<String, dynamic>? proyeccion;
  final bool loading;
  final VoidCallback onLoad;
  const _TabEstrategias(
      {required this.proyeccion, required this.loading, required this.onLoad});

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (proyeccion == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Toca para cargar el análisis',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onLoad, child: const Text('Cargar')),
        ]),
      );
    }
    if (proyeccion!['sin_deudas'] == true) {
      return Center(
        child: Text('No tienes deudas activas para analizar',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final trayectoria = proyeccion!['trayectoria_actual'] as Map<String, dynamic>?;
    final av = proyeccion!['avalanche'] as Map<String, dynamic>;
    final sw = proyeccion!['snowball'] as Map<String, dynamic>;
    final ahorroAv = _d(proyeccion!['ahorro_avalanche_vs_snowball']);
    // Estrategias son idénticas cuando no hay pago extra (matemáticamente correcto)
    final estrategiasIguales = (av['meses_totales'] == sw['meses_totales']) &&
        (_d(av['total_intereses']) - _d(sw['total_intereses'])).abs() < 0.01;

    // I2 — gancho motivacional de Snowball con números reales (orden de pago real)
    final swOrden = (sw['orden'] as List?) ?? const [];
    final mesesSaldado = swOrden
        .map((d) => (d as Map)['mes_saldado'] as int?)
        .where((m) => m != null && m > 0)
        .cast<int>()
        .toList()
      ..sort();
    final int? primeraSaldadaMes = mesesSaldado.isNotEmpty ? mesesSaldado.first : null;
    final saldadasEn3m = mesesSaldado.where((m) => m <= 3).length;
    final numDeudas = swOrden.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Situación actual
        _SeccionHeader('Tu trayectoria actual'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: [
            _InfoRow('Deuda total',
                '${Money.fmt(_d(proyeccion!['total_pendiente']))}',
                AppTheme.danger),
            _InfoRow('Pagas mensualmente (mínimos)',
                '${Money.fmt(_d(proyeccion!['total_pago_minimo']))}',
                AppTheme.textPrimary),
            _InfoRow('Si sigues así, terminas en',
                (trayectoria?['fecha_fin'] ?? av['fecha_fin']) as String? ?? '—',
                AppTheme.textSecondary),
            _InfoRow('Total de intereses a pagar',
                '${Money.fmt(_d(trayectoria?['total_intereses'] ?? av['total_intereses']))}',
                AppTheme.warning),
          ]),
        ),

        const SizedBox(height: 24),
        _SeccionHeader('Compara las estrategias'),
        const SizedBox(height: 8),

        if (estrategiasIguales) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: AppTheme.info, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Con solo los pagos mínimos ambas estrategias llegan al mismo resultado — '
                  'la diferencia aparece cuando agregas dinero extra. '
                  'Ve al Simulador para verlo en acción.',
                  style: TextStyle(color: AppTheme.info, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Comparativa lado a lado
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _EstrategiaCard(
              titulo: 'Avalanche',
              subtitulo: 'Mayor tasa primero',
              icono: Icons.local_fire_department_outlined,
              color: AppTheme.danger,
              meses: av['meses_totales'] as int? ?? 0,
              fechaFin: av['fecha_fin'] as String? ?? '—',
              intereses: _d(av['total_intereses']),
              recomendado: true,
              ahorro: ahorroAv > 0 ? ahorroAv : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _EstrategiaCard(
              titulo: 'Snowball',
              subtitulo: 'Menor saldo primero',
              icono: Icons.ac_unit_outlined,
              color: AppTheme.info,
              meses: sw['meses_totales'] as int? ?? 0,
              fechaFin: sw['fecha_fin'] as String? ?? '—',
              intereses: _d(sw['total_intereses']),
              recomendado: false,
            ),
          ),
        ]),

        if (ahorroAv > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: AppTheme.success, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Avalanche te ahorra ${Money.fmt(ahorroAv)} en intereses '
                  'comparado con Snowball.',
                  style: const TextStyle(
                      color: AppTheme.success, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

        // I2 — gancho motivacional de Snowball con números reales
        if (numDeudas > 1 && primeraSaldadaMes != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.emoji_events_outlined, color: AppTheme.info, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  saldadasEn3m >= 2
                      ? 'Con Snowball eliminas $saldadasEn3m deudas en los primeros 3 meses — '
                        'ese impulso temprano ayuda a no rendirse.'
                      : 'Con Snowball saldas tu primera deuda en el mes $primeraSaldadaMes — '
                        'una victoria temprana que motiva a seguir.',
                  style: const TextStyle(color: AppTheme.info, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        Text(
          'Snowball da más motivación al saldar deudas pequeñas rápido. '
          'Avalanche es matemáticamente más eficiente.',
          style: TextStyle(
              color: AppTheme.textMuted, fontSize: 12, height: 1.5),
        ),
      ]),
    );
  }
}

class _EstrategiaCard extends StatelessWidget {
  final String titulo, subtitulo, fechaFin;
  final IconData icono;
  final Color color;
  final int meses;
  final double intereses;
  final bool recomendado;
  final double? ahorro;
  const _EstrategiaCard({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.meses,
    required this.fechaFin,
    required this.intereses,
    required this.recomendado,
    this.ahorro,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: recomendado ? color.withOpacity(0.5) : AppTheme.border,
            width: recomendado ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(
              child: Text(titulo,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14))),
        ]),
        Text(subtitulo,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        if (recomendado)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Recomendado',
                style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ),
        Divider(color: AppTheme.border, height: 16),
        _MiniRow('Terminas en', fechaFin),
        _MiniRow('Meses', '$meses'),
        _MiniRow('Intereses', '${Money.fmt(intereses)}'),
      ]),
    );
  }

  Widget _MiniRow(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Text(v,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ── Tab 3: Simulador ───────────────────────────────────────────────────────────

class _TabSimulador extends StatefulWidget {
  final Map<String, dynamic>? simulador;
  final bool loading;
  final double extraMensual;
  final String estrategia;
  final List<dynamic> deudas;
  final void Function(double, String) onChanged;
  const _TabSimulador({
    required this.simulador,
    required this.loading,
    required this.extraMensual,
    required this.estrategia,
    required this.deudas,
    required this.onChanged,
  });

  @override
  State<_TabSimulador> createState() => _TabSimuladorState();
}

class _TabSimuladorState extends State<_TabSimulador> {
  late double _local;
  late String _estrategiaLocal;
  bool _sliderDirty = false;

  @override
  void initState() {
    super.initState();
    _local = widget.extraMensual;
    _estrategiaLocal = widget.estrategia;
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final sim = widget.simulador;
    final mesesAhorrados = sim != null ? (sim['meses_ahorrados'] as int? ?? 0) : 0;
    final interesesAhorrados =
        sim != null ? _d(sim['intereses_ahorrados']) : 0.0;
    final deudaObjetivo = sim?['deuda_objetivo'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SeccionHeader('¿Cuánto puedes pagar de más?'),
        const SizedBox(height: 16),

        // Slider de monto extra
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Abono extra mensual',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text('${Money.fmt0(_local)}/mes',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ]),
            Slider(
              value: _local,
              min: 0,
              max: 500,
              divisions: 50,
              activeColor: AppTheme.primary,
              inactiveColor: AppTheme.border,
              onChanged: (v) => setState(() {
                _local = v;
                _sliderDirty = true;
              }),
              onChangeEnd: (_) {
                _sliderDirty = false;
                widget.onChanged(_local, _estrategiaLocal);
              },
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('B/. 0',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              Text('B/. 500',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        // Selector de estrategia
        Row(children: [
          _EstrategiaBtn(
            label: 'Avalanche',
            selected: _estrategiaLocal == 'avalanche',
            onTap: () {
              setState(() => _estrategiaLocal = 'avalanche');
              widget.onChanged(_local, 'avalanche');
            },
          ),
          const SizedBox(width: 10),
          _EstrategiaBtn(
            label: 'Snowball',
            selected: _estrategiaLocal == 'snowball',
            onTap: () {
              setState(() => _estrategiaLocal = 'snowball');
              widget.onChanged(_local, 'snowball');
            },
          ),
        ]),

        const SizedBox(height: 20),

        if (widget.loading)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else if (sim == null)
          Center(
            child: Text('Ajusta el slider para ver el resultado',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          )
        else if (sim['sin_deudas'] == true)
          Center(
              child: Text('No tienes deudas activas',
                  style: TextStyle(color: AppTheme.textSecondary)))
        else ...[
          // Deuda objetivo — prominente y claro
          if (deudaObjetivo != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DÓNDE VA EL DINERO EXTRA', style: TextStyle(
                    color: AppTheme.danger, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.bolt, color: AppTheme.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '${Money.fmt0(_local)}/mes extra → "${deudaObjetivo['nombre']}"',
                    style: TextStyle(color: AppTheme.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w700),
                  )),
                ]),
                const SizedBox(height: 4),
                Text(
                  _estrategiaLocal == 'avalanche'
                      ? 'Estrategia Avalanche: se ataca primero la deuda con mayor tasa de interés'
                      : 'Estrategia Snowball: se ataca primero la deuda con menor saldo',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          _SeccionHeader('QUÉ GANÁS CON ESTE EXTRA'),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: _ResultCard(
                label: 'Meses ahorrados',
                value: '$mesesAhorrados',
                color:
                    mesesAhorrados > 0 ? AppTheme.success : AppTheme.textMuted,
                icon: Icons.schedule_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResultCard(
                label: 'Intereses ahorrados',
                value: '${Money.fmt(interesesAhorrados)}',
                color: interesesAhorrados > 0
                    ? AppTheme.success
                    : AppTheme.textMuted,
                icon: Icons.savings_outlined,
              ),
            ),
          ]),

          if (deudaObjetivo != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.primary.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.bolt, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El extra se aplica a: ${deudaObjetivo['nombre']}',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 12),

          // Comparativa de fechas
          _ComparativaFechas(
            sinExtra: sim['sin_extra'] as Map<String, dynamic>?,
            conExtra: sim['con_extra'] as Map<String, dynamic>?,
          ),
        ],

        const SizedBox(height: 40),
      ]),
    );
  }
}

class _ComparativaFechas extends StatelessWidget {
  final Map<String, dynamic>? sinExtra;
  final Map<String, dynamic>? conExtra;
  const _ComparativaFechas({this.sinExtra, this.conExtra});

  @override
  Widget build(BuildContext context) {
    final fechaSin = sinExtra?['fecha_fin'] as String? ?? '—';
    final fechaCon = conExtra?['fecha_fin'] as String? ?? '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Sin abono extra',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          Text(fechaSin,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Con abono extra',
              style: TextStyle(color: AppTheme.success, fontSize: 12)),
          Text(fechaCon,
              style: const TextStyle(
                  color: AppTheme.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

class _EstrategiaBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _EstrategiaBtn(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withOpacity(0.1)
                  : AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.border,
                  width: selected ? 2 : 1),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
      );
}

class _ResultCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _ResultCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
        ]),
      );
}

// ── Tab 4: Mi Plan ─────────────────────────────────────────────────────────────

class _TabPlan extends StatelessWidget {
  final Map<String, dynamic>? plan;
  final bool loading;
  final VoidCallback onLoad;
  final String estrategia;
  const _TabPlan(
      {required this.plan,
      required this.loading,
      required this.onLoad,
      required this.estrategia});

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (plan == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Genera tu plan de ataque',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onLoad,
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: const Text('Generar plan'),
          ),
        ]),
      );
    }
    if (plan!['sin_deudas'] == true) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, color: AppTheme.success, size: 56),
          SizedBox(height: 12),
          Text('¡Sin deudas activas!',
              style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }

    final pasos = (plan!['pasos'] as List? ?? []);
    final fechaLibertad = plan!['fecha_libertad'] as String? ?? '—';
    final totalIntereses = _d(plan!['total_intereses']);
    final meses = plan!['meses_totales'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Resumen del plan
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Fecha de libertad financiera',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text(fechaLibertad,
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Meses restantes',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text('$meses meses',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total en intereses',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text('${Money.fmt(totalIntereses)}',
                  style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Estrategia',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text(
                  estrategia == 'avalanche'
                      ? 'Avalanche (mayor tasa primero)'
                      : 'Snowball (menor saldo primero)',
                  style: const TextStyle(
                      color: AppTheme.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),

        const SizedBox(height: 20),
        _SeccionHeader('Orden de ataque'),
        const SizedBox(height: 10),

        ...pasos.asMap().entries.map((e) {
          final paso = e.value as Map<String, dynamic>;
          final isFirst = e.key == 0;
          final mesSaldado = paso['mes_saldado'] as int?;
          final fechaSaldada = paso['fecha_saldada'] as String? ?? '—';
          final interesesPagados = _d(paso['intereses_pagados']);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Indicador de paso
              Column(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isFirst
                        ? AppTheme.danger
                        : AppTheme.surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isFirst
                            ? AppTheme.danger
                            : AppTheme.border),
                  ),
                  child: Center(
                    child: Text('${e.key + 1}',
                        style: TextStyle(
                            color: isFirst
                                ? Colors.white
                                : AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
                if (e.key < pasos.length - 1)
                  Container(
                      width: 2, height: 30,
                      color: AppTheme.border),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isFirst
                            ? AppTheme.danger.withOpacity(0.4)
                            : AppTheme.border),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                        child: Text(paso['nombre'] as String? ?? '',
                            style: TextStyle(
                                color: isFirst
                                    ? AppTheme.danger
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                      if (isFirst)
                        const Icon(Icons.bolt,
                            color: AppTheme.danger, size: 16),
                    ]),
                    const SizedBox(height: 4),
                    Text(paso['recomendacion'] as String? ?? '',
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            height: 1.4)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 12, children: [
                      if (mesSaldado != null)
                        Text('Saldada en: $fechaSaldada',
                            style: const TextStyle(
                                color: AppTheme.success, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      if (interesesPagados > 0)
                        Text('Intereses: ${Money.fmt(interesesPagados)}',
                            style: const TextStyle(
                                color: AppTheme.warning, fontSize: 11)),
                    ]),
                  ]),
                ),
              ),
            ]),
          );
        }),

        const SizedBox(height: 40),
      ]),
    );
  }
}

// ── Próxima Acción ─────────────────────────────────────────────────────────────

class _ProximaAccion extends StatelessWidget {
  final List<dynamic> deudas;
  final double totalPagoMinimo;
  const _ProximaAccion({required this.deudas, required this.totalPagoMinimo});

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final activas = deudas.where((d) => (d as Map)['activa'] == 1).toList();
    if (activas.isEmpty) return const SizedBox.shrink();

    // Deudas ya vienen ordenadas por tasa DESC
    final principal = activas.first as Map<String, dynamic>;
    final nombre = principal['nombre'] as String? ?? '—';
    final tasa   = _d(principal['tasa_interes']);
    final pagoMin = _d(principal['pago_minimo']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.bolt, color: AppTheme.primary, size: 15),
          SizedBox(width: 6),
          Text('PRÓXIMA ACCIÓN', style: TextStyle(
              color: AppTheme.primary, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.0)),
        ]),
        const SizedBox(height: 10),
        _paso(Icons.check_box_outline_blank, AppTheme.textSecondary,
            totalPagoMinimo > 0
                ? 'Paga el mínimo en todas tus deudas (${Money.fmt(totalPagoMinimo)}/mes en total)'
                : 'Paga el mínimo en todas tus deudas'),
        const SizedBox(height: 6),
        _paso(Icons.bolt, AppTheme.danger,
            'Todo dinero extra → "$nombre" (${tasa.toStringAsFixed(0)}% TEA — la que más te cuesta)'),
        const SizedBox(height: 6),
        _paso(Icons.block, AppTheme.warning,
            'No adquieras deuda nueva mientras esto esté pendiente'),
        if (pagoMin > 0) ...[
          const SizedBox(height: 8),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 8),
          Text(
            'Cada \$1 extra que pagues a "$nombre" reduce drásticamente los intereses totales.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
          ),
        ],
      ]),
    );
  }

  Widget _paso(IconData icon, Color color, String texto) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(texto,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, height: 1.4))),
    ],
  );
}

// ── Widgets auxiliares compartidos ────────────────────────────────────────────

class _SeccionHeader extends StatelessWidget {
  final String text;
  const _SeccionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _InfoRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
      );
}

// ── DeudaTile (componente de lista de deudas) ──────────────────────────────────

class _DeudaTile extends StatelessWidget {
  final Map<String, dynamic> deuda;
  final String uid;
  final VoidCallback onAbono;
  final VoidCallback onArchivar;
  final VoidCallback onEditar;
  final bool esMayorTasa;
  final bool infoIncompleta;
  const _DeudaTile(
      {required this.deuda,
      required this.uid,
      required this.onAbono,
      required this.onArchivar,
      required this.onEditar,
      this.esMayorTasa = false,
      this.infoIncompleta = false});

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final nombre = deuda['nombre'] as String? ?? '';
    final tipo = deuda['tipo'] as String? ?? 'personal';
    final montoTotal = _d(deuda['monto_total']);
    final montoPendiente = _d(deuda['monto_pendiente']);
    final pagoMinimo = _d(deuda['pago_minimo']);
    final tasa = _d(deuda['tasa_interes']);
    final fechaPago =
        (deuda['fecha_proximo_pago'] as String?)?.substring(0, 10);
    final activa = (deuda['activa'] as int? ?? 1) == 1;
    final pct =
        montoTotal > 0 ? (montoPendiente / montoTotal).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: activa ? onEditar : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: activa ? AppTheme.surface : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: activa ? AppTheme.border : AppTheme.border.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header: ícono + nombre + monto ──
          Row(children: [
            _TipoIcon(tipo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre,
                    style: TextStyle(
                        color: activa ? AppTheme.textPrimary : AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Row(children: [
                  _TipoChip(tipo),
                  if (esMayorTasa) ...[
                    const SizedBox(width: 5),
                    const _MiniTag(Icons.bolt, 'Atacar primero', AppTheme.danger),
                  ],
                  if (infoIncompleta) ...[
                    const SizedBox(width: 5),
                    _TappableMiniTag(
                      icon: Icons.edit_outlined,
                      label: 'Completar info',
                      color: AppTheme.warning,
                      onTap: onEditar,
                    ),
                  ],
                  if (!activa) ...[
                    const SizedBox(width: 5),
                    const _MiniTag(Icons.check, 'Saldada', AppTheme.success),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${Money.fmt(montoPendiente)}',
                  style: TextStyle(
                      color: activa ? AppTheme.danger : AppTheme.textMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              if (tasa > 0)
                Text('${tasa.toStringAsFixed(1)}% TEA',
                    style: const TextStyle(color: AppTheme.warning, fontSize: 10)),
            ]),
          ]),

          // ── Barra de progreso ──
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppTheme.success.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                  activa ? AppTheme.danger.withValues(alpha: 0.6) : AppTheme.textMuted),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Pendiente: ${Money.fmt(montoPendiente)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            if (pagoMinimo > 0)
              Text('Cuota: ${Money.fmt(pagoMinimo)}/mes',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            if (fechaPago != null)
              Text('Pago: $fechaPago',
                  style: const TextStyle(color: AppTheme.info, fontSize: 10)),
          ]),

          // ── Acciones ──
          if (activa) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAbono,
                  icon: const Icon(Icons.payments_outlined, size: 14),
                  label: const Text('Abonar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.success,
                    side: const BorderSide(color: AppTheme.success),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => HistorialAbonosSheet.show(
                    context,
                    deudaId: deuda['id'] as int,
                    deudaNombre: nombre,
                    firebaseUid: uid,
                  ),
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('Historial'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.info,
                    side: const BorderSide(color: AppTheme.info),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _IconAction(
                icon: Icons.edit_outlined,
                color: AppTheme.primary,
                tooltip: 'Editar',
                onTap: onEditar,
              ),
              const SizedBox(width: 4),
              _IconAction(
                icon: Icons.archive_outlined,
                color: AppTheme.textMuted,
                tooltip: 'Archivar',
                onTap: onArchivar,
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _TipoIcon(String tipo) {
    IconData icon;
    Color color;
    switch (tipo) {
      case 'tarjeta_credito':
        icon = Icons.credit_card;
        color = AppTheme.danger;
        break;
      case 'hipoteca':
        icon = Icons.home_outlined;
        color = AppTheme.info;
        break;
      case 'auto':
        icon = Icons.directions_car_outlined;
        color = AppTheme.primary;
        break;
      case 'prestamo':
        icon = Icons.account_balance_outlined;
        color = AppTheme.warning;
        break;
      default:
        icon = Icons.receipt_long_outlined;
        color = AppTheme.textSecondary;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String tipo;
  const _TipoChip(this.tipo);
  @override
  Widget build(BuildContext context) {
    const labels = {
      'tarjeta_credito': 'Tarjeta',
      'prestamo': 'Préstamo',
      'hipoteca': 'Hipoteca',
      'auto': 'Auto',
      'personal': 'Personal',
      'otro': 'Otro',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(labels[tipo] ?? tipo,
          style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniTag(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 9),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _TappableMiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _TappableMiniTag(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 9),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      );
}
