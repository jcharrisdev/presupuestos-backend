import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';
import 'services/consejero_service.dart';
import 'services/api_client.dart';
import 'mes_detalle_screen.dart';
import 'perfil_financiero_screen.dart';
import 'invoice_scanner/invoice_scanner_screen.dart';
import 'cierre_anio_screen.dart';
import 'alertas_screen.dart';
import 'eventos/eventos_screen.dart';
import 'widgets/ayuda_sheet.dart';
import 'utils/money.dart';
import 'services/ia_service.dart';

class EstadoFinancieroAnualScreen extends StatefulWidget {
  final String firebaseUid;
  final String periodoInicial;
  final void Function(String)? onPeriodoChanged;
  const EstadoFinancieroAnualScreen({
    Key? key,
    required this.firebaseUid,
    this.periodoInicial = 'mensual',
    this.onPeriodoChanged,
  }) : super(key: key);

  @override
  State<EstadoFinancieroAnualScreen> createState() => _EstadoFinancieroAnualScreenState();
}

class _EstadoFinancieroAnualScreenState extends State<EstadoFinancieroAnualScreen> {
  final int _anio = DateTime.now().year;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _sinPerfil = false;
  bool _mesesExpanded = true; // K1 — meses visibles por defecto (mes actual resaltado)
  int _alertasCount = 0;
  Map<int, Map<String, dynamic>> _alertasResumen = {};
  late String _vista; // 'mensual' | 'quincenal' | 'anual'
  Map<String, dynamic>? _consejero;
  Map<String, dynamic>? _comparativa;
  Map<String, dynamic>? _consejeroIA;
  bool _loadingIA = false;
  String? _frecuenciaCobro;        // K3 — para sugerir Vista Quincenal
  bool _hintQuincenalCerrado = false;
  bool? _tieneRegistrosMes;        // U5 — ¿ya registró su primer gasto del mes?
  bool _checklistCerrado = false;  // U5 — checklist de setup descartado (sesión)
  String? _nudge;
  bool _loadingNudge = false;

  static const _mesesLabel = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  void initState() {
    super.initState();
    _vista = widget.periodoInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; _sinPerfil = false; });
    try {
      final data = await EstadoAnualService.getEstadoAnual(widget.firebaseUid, _anio);
      if (!(data['existe'] as bool)) {
        // Primera vez: generar automáticamente desde el perfil
        try {
          await EstadoAnualService.generarEstadoAnual(widget.firebaseUid, anio: _anio);
          final nuevo = await EstadoAnualService.getEstadoAnual(widget.firebaseUid, _anio);
          setState(() { _data = nuevo; _loading = false; });
        } catch (e) {
          setState(() { _sinPerfil = true; _loading = false; });
          return;
        }
      } else {
        setState(() { _data = data; _loading = false; });
      }
      // Cargar alertas y resumen por mes en segundo plano
      try {
        final alertas = await EstadoAnualService.getAlertas(widget.firebaseUid, anio: _anio);
        if (mounted) setState(() => _alertasCount = alertas['no_leidas'] as int? ?? 0);
      } catch (e) { debugPrint('[estado_financiero_anual] no se pudo cargar contador de alertas: $e'); }
      try {
        final resumen = await EstadoAnualService.getResumenAlertas(widget.firebaseUid, _anio);
        final porMes = (resumen['por_mes'] as Map? ?? {})
            .map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, Map<String, dynamic>.from(v as Map)));
        if (mounted) setState(() => _alertasResumen = porMes);
      } catch (e) { debugPrint('[estado_financiero_anual] no se pudo cargar resumen de alertas: $e'); }
      // K3 — frecuencia de cobro para sugerir Vista Quincenal a quien cobra quincenal
      try {
        final r = await ApiClient.get('/user/income?firebase_uid=${widget.firebaseUid}');
        if (r.statusCode == 200 && mounted) {
          final inc = jsonDecode(r.body) as Map<String, dynamic>;
          setState(() => _frecuenciaCobro = inc['frecuencia_cobro'] as String?);
        }
      } catch (e) { debugPrint('[estado_financiero_anual] no se pudo cargar frecuencia de cobro: $e'); }
      // U5 — ¿ya registró su primer gasto del mes actual? (para el checklist de setup)
      try {
        final mesActual = DateTime.now().month;
        final mesData = await EstadoAnualService.getMes(widget.firebaseUid, _anio, mesActual);
        final regs = (mesData['registros'] as List? ?? []);
        if (mounted) setState(() => _tieneRegistrosMes = regs.isNotEmpty);
      } catch (e) { debugPrint('[estado_financiero_anual] no se pudo verificar registros del mes: $e'); }
      _cargarConsejero();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _cargarConsejero() async {
    try {
      final now = DateTime.now();
      final c = await ConsejeroService.get(widget.firebaseUid, anio: _anio, mes: now.month);
      if (mounted) setState(() => _consejero = c);
    } catch (e) { debugPrint('[estado_financiero_anual] no se pudo cargar consejero: $e'); }
    _cargarComparativa();
    _cargarConsejeroIA();
    _cargarNudge();
  }

  Future<void> _cargarNudge() async {
    if (mounted) setState(() => _loadingNudge = true);
    try {
      final mes = DateTime.now().month;
      final txt = await IaService.nudge(widget.firebaseUid, anio: _anio, mes: mes);
      if (mounted) setState(() { _nudge = txt.isEmpty ? null : txt; _loadingNudge = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingNudge = false);
    }
  }

  Future<void> _cargarComparativa() async {
    try {
      final now = DateTime.now();
      final r = await ApiClient.get(
          '/user/comparativa?firebase_uid=${widget.firebaseUid}&anio=$_anio&mes=${now.month}');
      if (r.statusCode == 200 && mounted) {
        setState(() => _comparativa = jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (e) { debugPrint('[estado_financiero_anual] no se pudo cargar comparativa: $e'); }
  }

  Future<void> _cargarConsejeroIA() async {
    if (mounted) setState(() => _loadingIA = true);
    try {
      final now = DateTime.now();
      final r = await ApiClient.get(
          '/user/consejero-ia?firebase_uid=${widget.firebaseUid}&anio=$_anio&mes=${now.month}');
      if (r.statusCode == 200 && mounted) {
        setState(() { _consejeroIA = jsonDecode(r.body) as Map<String, dynamic>; _loadingIA = false; });
      } else {
        if (mounted) setState(() => _loadingIA = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingIA = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        // U4 — rol del Estado Financiero: el PLAN (proyección y comparación anual)
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Estado Financiero $_anio'),
            Text('Tu plan: proyección del año y comparación mes a mes',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _mostrarAyuda(context),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            tooltip: 'Escanear factura',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _regenerar,
            tooltip: 'Recalcular',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sinPerfil
              ? _buildSinPerfil()
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(onRefresh: _cargar, child: _buildBody()),
    );
  }

  Widget _buildSinPerfil() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_outline, color: AppTheme.primary, size: 64),
        const SizedBox(height: 16),
        Text('Configura tu perfil primero',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          'Para generar tu estado financiero anual necesitas registrar tu ingreso y tus gastos fijos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Ir a Mi Perfil Financiero'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PerfilFinancieroScreen(firebaseUid: widget.firebaseUid)),
          ).then((_) => _cargar()),
        ),
      ]),
    ),
  );

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

  void _cambiarVista(String v) {
    setState(() => _vista = v);
    if (v != 'anual') widget.onPeriodoChanged?.call(v);
  }

  // U5 — checklist de primeros pasos: guía al usuario nuevo a registrar su
  // primer gasto. Perfil y estado ya están hechos (si llegamos aquí), así que
  // se muestran ✓; el paso pendiente es registrar el primer gasto del mes.
  // Se descarta con la X (sesión) y desaparece solo al registrar un gasto.
  Widget _buildSetupChecklist() {
    final mesActual = DateTime.now().month;
    Widget paso(IconData icon, String texto, bool hecho, {VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(hecho ? Icons.check_circle : icon,
              color: hecho ? AppTheme.success : AppTheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(texto,
              style: TextStyle(
                color: hecho ? AppTheme.textMuted : AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: hecho ? FontWeight.normal : FontWeight.w600,
                decoration: hecho ? TextDecoration.lineThrough : null,
              ))),
          if (!hecho && onTap != null)
            const Icon(Icons.chevron_right, color: AppTheme.primary, size: 18),
        ]),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.rocket_launch_outlined, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('Primeros pasos · 2 de 3 listos',
              style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w800))),
          GestureDetector(
            onTap: () => setState(() => _checklistCerrado = true),
            child: Icon(Icons.close, color: AppTheme.textMuted, size: 18),
          ),
        ]),
        const SizedBox(height: 4),
        paso(Icons.account_circle_outlined, 'Crea tu perfil financiero', true),
        paso(Icons.bar_chart_rounded, 'Genera tu estado financiero', true),
        paso(Icons.add_circle_outline, 'Registra tu primer gasto del mes', false,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MesDetalleScreen(
              firebaseUid: widget.firebaseUid,
              anio: _anio, mes: mesActual, label: _mesesLabel[mesActual],
            ),
          )).then((_) => _cargar()),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    final ea = _data!['estado_anual'] as Map<String, dynamic>;
    final meses = (_data!['meses'] as List).cast<Map<String, dynamic>>();
    final mesFactor = _vista == 'quincenal' ? 0.5 : 1.0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── U5 · CHECKLIST DE PRIMEROS PASOS ──────────────────────────────
        if (!_checklistCerrado && _tieneRegistrosMes == false) ...[
          _buildSetupChecklist(),
          const SizedBox(height: 16),
        ],
        // ── Sección Consejero ─────────────────────────────────────────────
        if (_consejero != null && !(_consejero!['sin_perfil'] as bool? ?? false)) ...[
          _buildScoreCard(_consejero!),
          const SizedBox(height: 10),
          _buildEnfoqueCard(_consejero!),
          const SizedBox(height: 16),
        ] else if (_consejero == null) ...[
          _buildConsejeroSkeleton(),
          const SizedBox(height: 16),
        ],
        // K3 — sugerir Vista Quincenal a quien cobra quincenal y no la ha activado
        if (_frecuenciaCobro == 'quincenal' && _vista != 'quincenal' && !_hintQuincenalCerrado) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.tips_and_updates_outlined, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cobras por quincena',
                    style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Activa la Vista Quincenal para ver tus compromisos adaptados a tus dos cobros del mes.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _cambiarVista('quincenal'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
                    child: Text('Activar Vista Quincenal',
                        style: TextStyle(color: AppTheme.background, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ])),
              GestureDetector(
                onTap: () => setState(() => _hintQuincenalCerrado = true),
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, color: AppTheme.textMuted, size: 16),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Toggle de vista
        Row(children: [
          _VistaChip('Quincenal', 'quincenal', _vista, _cambiarVista),
          const SizedBox(width: 8),
          _VistaChip('Mensual',   'mensual',   _vista, _cambiarVista),
          const SizedBox(width: 8),
          _VistaChip('Anual',     'anual',     _vista, _cambiarVista),
        ]),
        const SizedBox(height: 12),
        _CardAnual(ea: ea, anio: _anio, vista: _vista,
            onTap: () => setState(() => _mesesExpanded = !_mesesExpanded)),
        // ── Nudge IA (insight de 1-2 frases, carga rápida) ──────────────
        if (_loadingNudge)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(
              color: AppTheme.primary, backgroundColor: AppTheme.surfaceAlt, minHeight: 2),
          )
        else if (_nudge != null) ...[
          _safe(() => _buildNudge(_nudge!)),
          const SizedBox(height: 12),
        ],
        // ── Claude IA (análisis detallado) ────────────────────────────────
        if (_loadingIA) ...[
          _safe(() => _buildIASkeleton()),
          const SizedBox(height: 12),
        ] else if (_consejeroIA != null) ...[
          _safe(() => _buildConsejeroIA(_consejeroIA!)),
          const SizedBox(height: 12),
        ],
        // ── Gráfica tendencia + comparativa ───────────────────────────────
        if (_comparativa != null) ...[
          _safe(() => _buildTendenciaChart(_comparativa!)),
          const SizedBox(height: 12),
          _safe(() => _buildComparativa(_comparativa!)),
          const SizedBox(height: 12),
        ],
        // ── Insights ──────────────────────────────────────────────────────
        if (_consejero != null && !(_consejero!['sin_perfil'] as bool? ?? false)) ...[
          _safe(() => _buildInsights(_consejero!)),
          const SizedBox(height: 8),
        ],
        if (_alertasCount > 0)
          _AlertaBanner(
            count: _alertasCount,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlertasScreen(
                firebaseUid: widget.firebaseUid,
                anio: _anio,
              )),
            ).then((_) => _cargar()),
          ),
        const SizedBox(height: 8),
        if (_mesesExpanded) ...[
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Text('MESES DEL AÑO',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8))),
              Text('toca un mes para ver el detalle',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontStyle: FontStyle.italic)),
            ]),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.1,
            ),
            itemCount: 12,
            itemBuilder: (_, i) {
              final m = meses.length > i ? meses[i] : null;
              return _MesCard(
                mes: i + 1,
                label: _mesesLabel[i + 1],
                data: m,
                factor: mesFactor,
                alertasBadge: _alertasResumen[i + 1],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MesDetalleScreen(
                    firebaseUid: widget.firebaseUid,
                    anio: _anio,
                    mes: i + 1,
                    label: _mesesLabel[i + 1],
                  )),
                ).then((_) => _cargar()),
              );
            },
          ),
        ] else
          _TocaMeses(onTap: () => setState(() => _mesesExpanded = true)),

        const SizedBox(height: 24),
        Divider(color: AppTheme.border),
        const SizedBox(height: 12),
        // Botón Eventos
        OutlinedButton.icon(
          icon: const Icon(Icons.celebration_outlined, size: 16),
          label: Text('Eventos $_anio'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventosScreen(
              firebaseUid: widget.firebaseUid,
              anio: _anio,
            )),
          ).then((_) => _cargar()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.lock_outline, size: 16),
          label: Text('Cerrar año $_anio / Proyección ${_anio + 1}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CierreAnioScreen(
              firebaseUid: widget.firebaseUid,
              anio: _anio,
            )),
          ).then((_) => _cargar()),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Consejero helpers ────────────────────────────────────────────────────

  static Color _scoreColor(int s) =>
      s >= 75 ? AppTheme.success : s >= 50 ? AppTheme.warning : AppTheme.danger;

  static String _scoreLabel(int s) =>
      s >= 75 ? 'Excelente' : s >= 60 ? 'Buena' : s >= 45 ? 'Regular' : 'Crítica';

  static IconData _iconMap(String name) => switch (name) {
    'savings'      => Icons.savings,
    'warning'      => Icons.warning_rounded,
    'pie_chart'    => Icons.pie_chart_outline,
    'credit_card'  => Icons.credit_card,
    'trending_up'  => Icons.trending_up,
    'schedule'     => Icons.schedule,
    'shield'       => Icons.shield_outlined,
    'receipt_long' => Icons.receipt_long,
    'cut'          => Icons.content_cut,
    'bolt'         => Icons.bolt,
    'check_circle' => Icons.check_circle_outline,
    _              => Icons.info_outline,
  };

  static Color _tipoColor(String tipo) => switch (tipo) {
    'positivo'   => AppTheme.success,
    'advertencia'=> AppTheme.warning,
    'critico'    => AppTheme.danger,
    _            => AppTheme.primary,
  };

  Widget _buildConsejeroSkeleton() => Container(
    height: 88,
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border),
    ),
    child: const Center(child: SizedBox(
      width: 20, height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
    )),
  );

  Widget _buildScoreCard(Map<String, dynamic> c) {
    final score    = (c['score'] as num).toInt();
    final color    = _scoreColor(score);
    final label    = _scoreLabel(score);
    final m        = c['metricas'] as Map<String, dynamic>;
    final bd       = c['score_breakdown'] as Map<String, dynamic>?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Score circle
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(child: Text('$score',
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Salud financiera: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Fijos+deudas: ${m['pct_fijos']}%  ·  Ahorro: ${m['tasa_ahorro_pct']}%',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            Text('Te sobran ${Money.fmt(num.tryParse(m['remanente'].toString()))}/mes  ·  ${Money.fmt(num.tryParse(m['remanente_quincenal'].toString()))}/quincena',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ])),
        ]),
        // ── Desglose del score: explica de dónde sale el número ──────────
        if (bd != null) ...[
          const SizedBox(height: 12),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 10),
          Text('CÓMO SE CALCULA (máx 25 c/u)',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 9, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Row(children: [
            _scoreSeg('Deudas',  (bd['dti'] as num?)?.toInt() ?? 0),
            _scoreSeg('Ahorro',  (bd['ahorro'] as num?)?.toInt() ?? 0),
            _scoreSeg('Fijos',   (bd['fijos'] as num?)?.toInt() ?? 0),
            _scoreSeg('Control', (bd['control'] as num?)?.toInt() ?? 0),
          ]),
        ],
      ]),
    );
  }

  Widget _scoreSeg(String label, int pts) {
    final c = pts >= 20 ? AppTheme.success : pts >= 12 ? AppTheme.warning : AppTheme.danger;
    return Expanded(child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (pts / 25).clamp(0.0, 1.0),
            minHeight: 4, color: c, backgroundColor: AppTheme.surfaceAlt,
          ),
        ),
        const SizedBox(height: 2),
        Text('$pts', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    ));
  }

  Widget _buildEnfoqueCard(Map<String, dynamic> c) {
    final ef      = c['enfoque'] as Map<String, dynamic>;
    final urgencia = ef['urgencia'] as String;
    final color   = urgencia == 'alta' ? AppTheme.danger
                  : urgencia == 'media' ? AppTheme.warning
                  : AppTheme.success;
    final icon    = _iconMap(ef['icono'] as String);
    final mesLabel = (c['mes_label'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TU ACCIÓN PRIORITARIA · $mesLabel'.toUpperCase(),
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(ef['titulo'] as String,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(ef['texto'] as String,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _buildInsights(Map<String, dynamic> c) {
    final items = (c['insights'] as List).cast<Map<String, dynamic>>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('ANÁLISIS', style: TextStyle(
            color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
      ),
      ...items.map((insight) {
        final color = _tipoColor(insight['tipo'] as String);
        final icon  = _iconMap(insight['icono'] as String);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(insight['titulo'] as String,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(insight['texto'] as String,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
            ])),
          ]),
        );
      }),
    ]);
  }

  Widget _safe(Widget Function() builder) {
    try { return builder(); } catch (_) { return const SizedBox.shrink(); }
  }

  Widget _buildNudge(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 15),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.5)),
        ),
      ]),
    );
  }

  Widget _buildIASkeleton() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 14),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Análisis IA', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Generando análisis personalizado…', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ])),
      const SizedBox(width: 12),
      const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
    ]),
  );

  Widget _buildConsejeroIA(Map<String, dynamic> c) {
    final disponible = c['disponible'] as bool? ?? false;
    if (!disponible) {
      final razon   = c['razon']   as String? ?? 'desconocido';
      final detalle = c['detalle'] as String? ?? '';
      final msg = razon == 'sin_api_key'
          ? 'IA: API key no configurada en el servidor.'
          : razon == 'sin_perfil'
              ? 'IA: completa tu perfil financiero primero.'
              : 'IA error ($razon)${detalle.isNotEmpty ? ": $detalle" : ""}';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Icon(Icons.auto_awesome, color: AppTheme.textMuted, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        ]),
      );
    }
    final analisis      = c['analisis']     as String? ?? '';
    final generadoA     = c['generado_a']   as String? ?? '';
    final tokensUsados  = (c['tokens_usados'] as num? ?? 0).toInt();
    if (analisis.isEmpty) return const SizedBox.shrink();
    final mesLabel = c['mes_label'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.06), AppTheme.surface],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header inequívoco
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('ASESOR IA — Claude Haiku',
              style: TextStyle(color: AppTheme.primary, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 1.0))),
          if (generadoA.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Generado $generadoA',
                  style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('Análisis personalizado para $mesLabel · $tokensUsados tokens',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        const SizedBox(height: 12),
        Divider(color: AppTheme.border, height: 1),
        const SizedBox(height: 12),
        Text(analisis, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.6)),
        const SizedBox(height: 10),
        // Footer que confirma origen
        Row(children: [
          const Icon(Icons.verified, color: AppTheme.primary, size: 12),
          const SizedBox(width: 4),
          Text('Generado por Claude AI · Anthropic',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _buildTendenciaChart(Map<String, dynamic> comp) {
    final tendencia = (comp['tendencia'] as List? ?? []).cast<Map<String, dynamic>>();
    if (tendencia.isEmpty) return const SizedBox.shrink();

    final valores = tendencia.map((m) {
      final real = m['remanente_real'];
      final est  = (m['remanente_est'] as num? ?? 0).toDouble();
      return real != null ? (real as num).toDouble() : est;
    }).toList();

    final labels = tendencia.map((m) => m['label'] as String? ?? '').toList();
    final maxAbs = valores.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final escala = maxAbs > 0 ? 60.0 / maxAbs : 1.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TENDENCIA DEL AÑO', style: TextStyle(
            color: AppTheme.textMuted, fontSize: 11,
            letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('Te sobró por mes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(valores.length, (i) {
              final v    = valores[i];
              final pos  = v >= 0;
              final h    = (v.abs() * escala).clamp(4.0, 60.0);
              final color = pos ? AppTheme.success : AppTheme.danger;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: '${Money.fmt0(v)}',
                        child: Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 8),
                          overflow: TextOverflow.visible,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  Widget _buildComparativa(Map<String, dynamic> comp) {
    final actual   = comp['actual']   as Map<String, dynamic>?;
    final anterior = comp['anterior'] as Map<String, dynamic>?;
    if (actual == null || anterior == null) return const SizedBox.shrink();

    double dbl(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

    final remAct = dbl(actual['remanente']);
    final remAnt = dbl(anterior['remanente']);
    final diff   = remAct - remAnt;
    final mejoro = diff >= 0;
    final esEst  = actual['es_estimado'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VS MES ANTERIOR', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _CompCol(label: anterior['label'] as String, remanente: remAnt, active: false)),
          Container(width: 1, height: 48, color: AppTheme.border, margin: const EdgeInsets.symmetric(horizontal: 12)),
          Expanded(child: _CompCol(label: '${actual['label'] as String}${esEst ? '*' : ''}', remanente: remAct, active: true)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mejoro ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(mejoro ? Icons.trending_up : Icons.trending_down,
                color: mejoro ? AppTheme.success : AppTheme.danger, size: 16),
            const SizedBox(width: 8),
            Text(
              mejoro
                  ? 'Mejoraste ${Money.fmt(diff.abs())} vs ${anterior['label']}'
                  : 'Bajaste ${Money.fmt(diff.abs())} vs ${anterior['label']}',
              style: TextStyle(
                color: mejoro ? AppTheme.success : AppTheme.danger,
                fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        if (esEst)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('* Basado en planificación — registra gastos para ver el real.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ),
      ]),
    );
  }

  void _mostrarAyuda(BuildContext context) {
    AyudaSheet.show(context,
      titulo: 'Estado Financiero Anual',
      subtitulo: 'Tu panorama financiero completo del año.',
      items: const [
        AyudaItem(Icons.bar_chart_rounded, 'Estimado vs Real',
            'Estimado = lo que planificaste. Real = lo que realmente entraste y gastaste según tus registros.'),
        AyudaItem(Icons.calendar_today_outlined, 'Los 12 meses',
            'Toca "Ver los 12 meses" para ver cada mes. Verde = remanente positivo, Rojo = gastaste más de lo que entraste.'),
        AyudaItem(Icons.toggle_on_outlined, 'Toggle Quincenal / Mensual / Anual',
            'Cambia la vista para ver cuánto representa cada quincena, mes o el año completo.'),
        AyudaItem(Icons.refresh, 'Recalcular',
            'Si cambias tu perfil financiero (ingreso o gastos fijos), toca aquí para actualizar todos los meses.'),
        AyudaItem(Icons.info_outline, 'Real mensual 0 o bajo',
            'El "real" solo refleja lo que registraste manualmente o escaneaste. Si no has registrado gastos, el real estará vacío.'),
      ],
    );
  }

  Future<void> _regenerar() async {
    setState(() => _loading = true);
    try {
      await EstadoAnualService.generarEstadoAnual(widget.firebaseUid, anio: _anio);
      await _cargar();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }
}

// ── CARD ANUAL ─────────────────────────────────────────────────────────────

class _VistaChip extends StatelessWidget {
  final String label, valor, selected;
  final ValueChanged<String> onTap;
  const _VistaChip(this.label, this.valor, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == valor;
    return GestureDetector(
      onTap: () => onTap(valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? AppTheme.primary : AppTheme.border, width: sel ? 1.5 : 1),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
        )),
      ),
    );
  }
}

class _CardAnual extends StatelessWidget {
  final Map<String, dynamic> ea;
  final int anio;
  final String vista;
  final VoidCallback onTap;
  const _CardAnual({required this.ea, required this.anio, required this.vista, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final factor = vista == 'anual' ? 1.0 : vista == 'mensual' ? 1 / 12 : 1 / 24;
    final label  = vista == 'anual' ? 'Anual' : vista == 'mensual' ? 'Mensual' : 'Quincenal';

    // Estimados: siempre dividir por 12 (ó 24 quincenal) porque el anual = mensual × 12
    final ingresoEst = _d(ea['ingreso_anual_estimado'])  * factor;
    final fijosEst   = _d(ea['gastos_fijos_anuales'])    * factor;
    final varEst     = _d(ea['gastos_variables_anuales'])* factor;
    final remEst     = _d(ea['remanente_anual_estimado']) * factor;

    // Reales:
    // - Ingreso usa /12 igual que estimado (incluye meses sin dato real como fallback estimado)
    // - Gastos usan /meses_con_datos para mostrar el promedio real de los meses con registros
    final divisorGastos = vista == 'anual' ? 1
        : vista == 'mensual'
            ? (_i(ea['meses_con_fijos_reales']) > 0 ? _i(ea['meses_con_fijos_reales']) : 1)
            : (_i(ea['meses_con_fijos_reales']) > 0 ? _i(ea['meses_con_fijos_reales']) * 2 : 1);
    final divisorVars  = vista == 'anual' ? 1
        : vista == 'mensual'
            ? (_i(ea['meses_con_vars_reales']) > 0 ? _i(ea['meses_con_vars_reales']) : 1)
            : (_i(ea['meses_con_vars_reales']) > 0 ? _i(ea['meses_con_vars_reales']) * 2 : 1);
    final divisorNoPres= vista == 'anual' ? 1
        : vista == 'mensual'
            ? (_i(ea['meses_con_no_pres']) > 0 ? _i(ea['meses_con_no_pres']) : 1)
            : (_i(ea['meses_con_no_pres']) > 0 ? _i(ea['meses_con_no_pres']) * 2 : 1);

    final ingresoReal = _d(ea['ingreso_anual_real'])       * factor;
    final fijosReal   = _d(ea['gastos_fijos_reales'])      / divisorGastos;
    final varReal     = _d(ea['gastos_variables_reales'])  / divisorVars;
    final noPres      = _d(ea['compras_no_presup_reales']) / divisorNoPres;
    final remReal     = ingresoReal - fijosReal - varReal - noPres;
    final tieneReal   = _d(ea['gastos_fijos_reales']) > 0 || _d(ea['gastos_variables_reales']) > 0
                     || _d(ea['compras_no_presup_reales']) > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Estado Financiero $anio',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Icon(Icons.expand_more, color: AppTheme.textMuted, size: 20),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(flex: 1, child: SizedBox()),
            Expanded(child: _Col('Est. $label', color: AppTheme.textSecondary)),
            Expanded(child: _Col('Real $label', color: AppTheme.primary)),
          ]),
          const SizedBox(height: 10),
          _Fila('Ingreso', ingresoEst, tieneReal ? ingresoReal : null, AppTheme.success),
          _Fila('Gastos fijos', fijosEst, tieneReal ? fijosReal : null, AppTheme.danger),
          _Fila('Gastos variables', varEst, tieneReal ? varReal : null, AppTheme.warning),
          if (tieneReal) _Fila('No presupuestados', 0, noPres, AppTheme.danger),
          Divider(color: AppTheme.border, height: 24),
          _Fila('Remanente', remEst, tieneReal ? remReal : null,
              remReal >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
        ]),
      ),
    );
  }

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  int    _i(dynamic v) => v == null ? 0   : int.tryParse(v.toString()) ?? 0;
}

class _Col extends StatelessWidget {
  final String label;
  final Color color;
  const _Col(this.label, {required this.color});
  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4));
}

class _Fila extends StatelessWidget {
  final String nombre;
  final double estimado;
  final double? real;
  final Color color;
  final bool bold;
  const _Fila(this.nombre, this.estimado, this.real, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: bold ? AppTheme.textPrimary : AppTheme.textSecondary,
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(nombre, style: style)),
        Expanded(child: Text('${Money.fmt(estimado)}', style: style.copyWith(color: AppTheme.textSecondary))),
        Expanded(child: real != null
            ? Text('${Money.fmt(real!)}',
                style: style.copyWith(color: color, fontWeight: FontWeight.w700))
            : Text('—', style: style.copyWith(color: AppTheme.textMuted))),
      ]),
    );
  }
}

// ── MES CARD ───────────────────────────────────────────────────────────────

class _MesCard extends StatelessWidget {
  final int mes;
  final String label;
  final Map<String, dynamic>? data;
  final double factor;
  final Map<String, dynamic>? alertasBadge;
  final VoidCallback onTap;
  const _MesCard({required this.mes, required this.label, this.data, this.factor = 1.0, this.alertasBadge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final estado   = data?['estado'] as String? ?? 'futuro';
    final remReal  = data != null ? _d(data!['remanente_real'])  * factor : null;
    final remEst   = data != null ? _d(data!['remanente_estimado']) * factor : null;
    final tieneReal = data != null &&
        (_d(data!['fijos_reales']) > 0 ||
         _d(data!['variables_reales']) > 0 ||
         _d(data!['no_presupuestados_reales']) > 0 ||
         _d(data!['ingreso_real']) > 0);
    final esActual  = estado == 'activo';
    final esCerrado = estado == 'cerrado';

    Color borderColor = AppTheme.border;
    if (esActual) borderColor = AppTheme.primary;
    if ((esCerrado || (esActual && tieneReal)) && remReal != null && remReal < 0) {
      borderColor = AppTheme.danger;
    }

    final noLeidas = alertasBadge?['no_leidas'] as int? ?? 0;
    final hayPeligro = (alertasBadge?['peligro'] as int? ?? 0) > 0;
    final badgeColor = hayPeligro ? AppTheme.danger : AppTheme.warning;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: esActual ? AppTheme.primary.withValues(alpha: 0.08) : AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: esActual ? 1.5 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(
                  color: esActual ? AppTheme.primary : AppTheme.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 4),
                if ((esCerrado || (esActual && tieneReal)) && remReal != null)
                  Text('${Money.fmt0(remReal)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: remReal >= 0 ? AppTheme.success : AppTheme.danger,
                          fontWeight: FontWeight.w600))
                else if (remEst != null)
                  Text('${Money.fmt0(remEst)}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
                else
                  Text('—', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (esActual)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)),
                    child: Text('HOY', style: TextStyle(color: AppTheme.background, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          // K1 — chevron sutil que indica que la tarjeta abre el detalle del mes
          Positioned(
            bottom: 2,
            right: 4,
            child: Icon(Icons.chevron_right,
                size: 13, color: (esActual ? AppTheme.primary : AppTheme.textMuted).withValues(alpha: 0.6)),
          ),
          // Badge de alertas no leídas
          if (noLeidas > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.background, width: 1.5),
                ),
                child: Text('$noLeidas',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}

class _TocaMeses extends StatelessWidget {
  final VoidCallback onTap;
  const _TocaMeses({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.calendar_month, color: AppTheme.primary, size: 18),
        SizedBox(width: 10),
        Text('Ver los 12 meses del año', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        SizedBox(width: 6),
        Icon(Icons.expand_more, color: AppTheme.primary, size: 18),
      ]),
    ),
  );
}

class _AlertaBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AlertaBanner({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.notifications_active, color: AppTheme.warning, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$count alerta${count > 1 ? "s" : ""} sin leer — toca para ver',
              style: const TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        const Icon(Icons.chevron_right, color: AppTheme.warning, size: 18),
      ]),
    ),
  );
}

class _CompCol extends StatelessWidget {
  final String label;
  final double remanente;
  final bool active;
  const _CompCol({required this.label, required this.remanente, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = remanente >= 0 ? AppTheme.success : AppTheme.danger;
    return Column(children: [
      Text(label, style: TextStyle(
        color: active ? AppTheme.primary : AppTheme.textMuted,
        fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.normal,
      )),
      const SizedBox(height: 4),
      Text('${Money.fmt(remanente)}',
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      Text('te sobró', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
    ]);
  }
}

