import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
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
        title: const Text('Dashboard'),
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
        const Icon(Icons.cloud_off, color: AppTheme.textMuted, size: 48),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _MiniStat('Ingreso', '\$${ingreso.toStringAsFixed(2)}', AppTheme.success)),
                Expanded(child: _MiniStat('Gastado', '\$${gastos.toStringAsFixed(2)}',
                    pct > 0.9 ? AppTheme.danger : pct > 0.7 ? AppTheme.warning : AppTheme.textPrimary)),
                Expanded(child: _MiniStat('Remanente', '\$${remReal.toStringAsFixed(2)}',
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
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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

        // ── ALERTAS ───────────────────────────────────────────────────────
        if (_alertas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('ALERTAS', Icons.notifications_active, AppTheme.warning),
          const SizedBox(height: 8),
          ..._alertas.take(3).map((a) {
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
          _SectionLabel('PRÓXIMOS PAGOS', Icons.calendar_today, AppTheme.info),
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
                return Column(children: [
                  if (i > 0) const Divider(color: AppTheme.border, height: 1),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    leading: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: AppTheme.info.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.payment, color: AppTheme.info, size: 16),
                    ),
                    title: Text(p['titulo'] as String? ?? '',
                        style: const TextStyle(color: AppTheme.textPrimary,
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(fecha,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    trailing: Text('\$${monto.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.info,
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
            child: const Text('Sin pagos pendientes este mes.',
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
                      style: const TextStyle(color: AppTheme.textPrimary,
                          fontSize: 13, fontWeight: FontWeight.w600))),
                  Text('\$${actual.toStringAsFixed(0)} / \$${meta.toStringAsFixed(0)}',
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
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
      ),
    );
    if (res == true) _cargar();
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

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
    Text(label, style: const TextStyle(color: AppTheme.textMuted,
        fontSize: 10, letterSpacing: 0.4)),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(color: color,
        fontSize: 14, fontWeight: FontWeight.w700)),
  ]);
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
