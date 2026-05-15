import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';
import 'crear_deuda_sheet.dart';
import 'abono_deuda_sheet.dart';

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
    if (i == 3 && _plan == null) _cargarPlan();
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
        title: const Text('Archivar deuda',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('¿Marcar "$nombre" como saldada/archivada?',
            style: const TextStyle(color: AppTheme.textSecondary)),
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

  const _TabSituacion({
    required this.deudas,
    required this.totalPendiente,
    required this.totalPagoMinimo,
    required this.loading,
    required this.uid,
    required this.onRefresh,
    required this.onArchivar,
    required this.onAbono,
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
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.credit_card_off_outlined,
                size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('Sin deudas registradas',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Toca el botón + para registrar una deuda',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ]),
        ),
      ]);
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  const Text('Deuda total pendiente',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('\$${totalPendiente.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
              if (totalPagoMinimo > 0)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Pago mínimo mensual',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('\$${totalPagoMinimo.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppTheme.warning,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ]),
            ]),
          ),
          const SizedBox(height: 16),
          // Banner de deudas con información incompleta (creadas desde el perfil)
          Builder(builder: (_) {
            final incompletas = deudas.where((d) =>
              (d['monto_pendiente'] == null || d['monto_pendiente'] == 0) ||
              d['tasa_interes'] == null
            ).toList();
            if (incompletas.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '${incompletas.length} deuda${incompletas.length > 1 ? 's' : ''} '
                  'creada${incompletas.length > 1 ? 's' : ''} desde el perfil '
                  '${incompletas.length > 1 ? 'tienen' : 'tiene'} información incompleta. '
                  'Agrega el saldo total y la tasa de interés para poder proyectarlas correctamente.',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
                )),
              ]),
            );
          }),
          ...deudas.asMap().entries.map((e) {
            final d = e.value as Map<String, dynamic>;
            final infoIncompleta = (d['monto_pendiente'] == null ||
                d['monto_pendiente'] == 0) || d['tasa_interes'] == null;
            return _DeudaTile(
              deuda: d,
              esMayorTasa: e.key == 0 &&
                  deudas.length > 1 &&
                  _d(d['tasa_interes']) > 0,
              infoIncompleta: infoIncompleta,
              onAbono: () => onAbono(d),
              onArchivar: () =>
                  onArchivar(d['id'] as int, d['nombre'] as String? ?? ''),
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
          const Text('Toca para cargar el análisis',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onLoad, child: const Text('Cargar')),
        ]),
      );
    }
    if (proyeccion!['sin_deudas'] == true) {
      return const Center(
        child: Text('No tienes deudas activas para analizar',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final av = proyeccion!['avalanche'] as Map<String, dynamic>;
    final sw = proyeccion!['snowball'] as Map<String, dynamic>;
    final ahorroAv = _d(proyeccion!['ahorro_avalanche_vs_snowball']);

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
                '\$${_d(proyeccion!['total_pendiente']).toStringAsFixed(2)}',
                AppTheme.danger),
            _InfoRow('Pagas mensualmente (mínimos)',
                '\$${_d(proyeccion!['total_pago_minimo']).toStringAsFixed(2)}',
                AppTheme.textPrimary),
            _InfoRow('Si sigues así, terminas en',
                av['fecha_fin'] as String? ?? '—', AppTheme.textSecondary),
            _InfoRow('Total de intereses a pagar',
                '\$${_d(av['total_intereses']).toStringAsFixed(2)}',
                AppTheme.warning),
          ]),
        ),

        const SizedBox(height: 24),
        _SeccionHeader('Compara las estrategias'),
        const SizedBox(height: 8),

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
              color: AppTheme.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.success.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: AppTheme.success, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Avalanche te ahorra \$${ahorroAv.toStringAsFixed(2)} en intereses '
                  'comparado con Snowball.',
                  style: const TextStyle(
                      color: AppTheme.success, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        const Text(
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
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
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
        const Divider(color: AppTheme.border, height: 16),
        _MiniRow('Terminas en', fechaFin),
        _MiniRow('Meses', '$meses'),
        _MiniRow('Intereses', '\$${intereses.toStringAsFixed(2)}'),
      ]),
    );
  }

  Widget _MiniRow(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Text(v,
              style: const TextStyle(
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
  final void Function(double, String) onChanged;
  const _TabSimulador({
    required this.simulador,
    required this.loading,
    required this.extraMensual,
    required this.estrategia,
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
              const Text('Abono extra mensual',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text('\$${_local.toStringAsFixed(0)}/mes',
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
              const Text('\$0',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              const Text('\$500',
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
          const Center(
            child: Text('Ajusta el slider para ver el resultado',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          )
        else if (sim['sin_deudas'] == true)
          const Center(
              child: Text('No tienes deudas activas',
                  style: TextStyle(color: AppTheme.textSecondary)))
        else ...[
          _SeccionHeader('Resultado'),
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
                value: '\$${interesesAhorrados.toStringAsFixed(2)}',
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
                    style: const TextStyle(
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
          const Text('Sin abono extra',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          Text(fechaSin,
              style: const TextStyle(
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
              style: const TextStyle(
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
          const Text('Genera tu plan de ataque',
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
              const Text('Fecha de libertad financiera',
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
              const Text('Meses restantes',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text('$meses meses',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total en intereses',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              Text('\$${totalIntereses.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Estrategia',
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
                        style: const TextStyle(
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
                        Text('Intereses: \$${interesesPagados.toStringAsFixed(2)}',
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

// ── Widgets auxiliares compartidos ────────────────────────────────────────────

class _SeccionHeader extends StatelessWidget {
  final String text;
  const _SeccionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
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
                  style: const TextStyle(
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
  final VoidCallback onAbono;
  final VoidCallback onArchivar;
  final bool esMayorTasa;
  final bool infoIncompleta;
  const _DeudaTile(
      {required this.deuda,
      required this.onAbono,
      required this.onArchivar,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: activa ? AppTheme.surface : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: activa
                ? AppTheme.border
                : AppTheme.border.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _TipoIcon(tipo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Expanded(
                  child: Text(nombre,
                      style: TextStyle(
                          color: activa
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                if (esMayorTasa)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.danger.withOpacity(0.4)),
                    ),
                    child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt,
                              color: AppTheme.danger, size: 11),
                          SizedBox(width: 3),
                          Text('Atacar primero',
                              style: TextStyle(
                                  color: AppTheme.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
              ]),
              Row(children: [
                _TipoChip(tipo),
                if (infoIncompleta) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_outlined, color: AppTheme.warning, size: 10),
                      SizedBox(width: 3),
                      Text('Completar info', style: TextStyle(
                          color: AppTheme.warning, fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ],
                if (!activa) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Saldada',
                        style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ]),
          ),
          Text('\$${montoPendiente.toStringAsFixed(2)}',
              style: TextStyle(
                  color: activa ? AppTheme.danger : AppTheme.textMuted,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ]),

        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.success.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(
                activa ? AppTheme.danger : AppTheme.textMuted),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '\$${montoPendiente.toStringAsFixed(2)} pendiente de '
          '\$${montoTotal.toStringAsFixed(2)}  '
          '(${(pct * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),

        if (pagoMinimo > 0 || tasa > 0 || fechaPago != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 12, children: [
            if (pagoMinimo > 0)
              Text('Pago mínimo: \$${pagoMinimo.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            if (tasa > 0)
              Text('Tasa: ${tasa.toStringAsFixed(1)}%/año',
                  style: const TextStyle(
                      color: AppTheme.warning, fontSize: 12)),
            if (fechaPago != null)
              Text('Próximo pago: $fechaPago',
                  style: const TextStyle(
                      color: AppTheme.info, fontSize: 12)),
          ]),
        ],

        if (activa) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAbono,
                icon: const Icon(Icons.payments_outlined, size: 15),
                label: const Text('Registrar abono'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.success,
                  side: const BorderSide(color: AppTheme.success),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onArchivar,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textMuted,
                side: const BorderSide(color: AppTheme.border),
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
              child: const Text('Archivar'),
            ),
          ]),
        ],
      ]),
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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20),
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
          style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}
