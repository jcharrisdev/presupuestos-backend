import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'theme/app_theme.dart';
import 'utils/money.dart';
import 'widgets/empty_state.dart';
import 'services/api_client.dart';
import 'services/estado_anual_service.dart';
import 'services/pdf_service.dart';
import 'services/registros_service.dart';
import 'services/gastos_variables_service.dart';
import 'services/productos_catalogo_service.dart';
import 'widgets/ayuda_sheet.dart';
import 'widgets/financiero/agregar_gasto_sheet.dart';
import 'widgets/financiero/categoria_selector.dart';
import 'widgets/financiero/cierre_mes_sheet.dart';
import 'widgets/financiero/resumen_mensual_card.dart';
import 'invoice_scanner/invoice_scanner_screen.dart';
import 'ia/ia_chat_screen.dart';
import 'ia/ia_diagnostico_sheet.dart';
import 'services/ia_service.dart';

/// Categoría canónica para un compromiso (gasto fijo/deuda) al marcarlo pagado.
/// Prefiere `categoria`; si no, usa `tipo` cuando es una categoría canónica
/// (transporte, servicios, vivienda…); si no, 'otro' (singular, canónico).
/// Antes caía en 'otros' (plural) y fragmentaba el envelope y las alertas.
String categoriaCanonicaCompromiso(Map<String, dynamic> g) {
  final cat = (g['categoria'] as String? ?? '').trim();
  if (cat.isNotEmpty) return cat;
  final tipo = (g['tipo'] as String? ?? '').trim();
  final esCanonica = CategoriaSelector.canonicas.any((c) => c['value'] == tipo);
  return esCanonica ? tipo : 'otro';
}

class MesDetalleScreen extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final int mes;
  final String label;
  final int initialTabIndex; // 0=Resumen 1=Gastos 2=Quincenas 3=Análisis

  const MesDetalleScreen({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    required this.mes,
    required this.label,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  State<MesDetalleScreen> createState() => _MesDetalleScreenState();
}

class _MesDetalleScreenState extends State<MesDetalleScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _alertas = [];
  bool _loading = true;
  String? _error;
  int _quincenasKey = 0; // Incrementar fuerza reload de _TabQuincenas

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex.clamp(0, 3));
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await EstadoAnualService.getMes(widget.firebaseUid, widget.anio, widget.mes);
      if (!mounted) return;
      setState(() { _data = data; _loading = false; });
      // Cargar alertas del mes en segundo plano
      try {
        final al = await EstadoAnualService.getAlertas(
          widget.firebaseUid, anio: widget.anio, mes: widget.mes);
        if (mounted) {
          setState(() {
            _alertas = (al['alertas'] as List? ?? []).cast<Map<String, dynamic>>();
          });
        }
      } catch (_) {}
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('${widget.label} ${widget.anio}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 21),
            tooltip: 'Diagnóstico IA',
            onPressed: () => IaDiagnosticoSheet.show(context, widget.firebaseUid),
          ),
          IconButton(
            icon: const Icon(Icons.chat_outlined, size: 21),
            tooltip: 'Asesor IA',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => IaChatScreen(firebaseUid: widget.firebaseUid),
            )).then((_) {
              // Forzar reload del Tab Quincenas por si el usuario confirmó una acción
              if (mounted) setState(() => _quincenasKey++);
              _cargar();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => AyudaSheet.show(context,
              titulo: 'Detalle del Mes',
              subtitulo: 'Todo lo que pasó (o planificaste) en este mes.',
              items: const [
                AyudaItem(Icons.receipt_outlined, 'Tab Gastos',
                    'Muestra tus compromisos planificados (gastos fijos y deudas) y los gastos reales que registraste. Pendiente = aún no registrado.'),
                AyudaItem(Icons.bar_chart_rounded, 'Tab Resumen',
                    'Compara lo que planeabas gastar vs lo que gastaste realmente. Verde = bajo control, Rojo = te pasaste.'),
                AyudaItem(Icons.lightbulb_outline, 'Tab Análisis',
                    'Recomendaciones basadas en tus últimos meses. Sugiere ajustar tu presupuesto si hay desviaciones constantes.'),
                AyudaItem(Icons.add_circle_outline, 'Botón +',
                    'Registra un gasto real: nombre, monto, categoría. Esto actualiza tu "real" mensual.'),
                AyudaItem(Icons.qr_code_scanner, 'Escanear factura',
                    'Escanea el QR de un recibo DGI. La app extrae los datos y los asigna al mes automáticamente.'),
                AyudaItem(Icons.check_circle_outline, 'Marcar pagado',
                    'Confirma si el dinero ya salió. En el resumen de caja, el gasto pasa de pendiente a pagado y actualiza tu disponible.'),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 22),
            tooltip: 'Exportar PDF',
            onPressed: _exportarPdf,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            tooltip: 'Escanear factura',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
            )),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Resumen'),
            Tab(text: 'Gastos'),
            Tab(text: 'Quincenas'),
            Tab(text: 'Análisis'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirAgregarGasto,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off,
                  title: 'No pudimos cargar este mes',
                  subtitle: 'Revisa tu conexión o genera tu estado financiero primero.',
                  actionLabel: 'Reintentar',
                  onAction: _cargar,
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _TabResumen(
                        data: _data!,
                        alertas: _alertas,
                        uid: widget.firebaseUid,
                        anio: widget.anio,
                        mes: widget.mes,
                        labelMes: widget.label,
                        onChanged: _cargar,
                      ),
                      _TabGastos(
                        data: _data!,
                        alertas: _alertas,
                        uid: widget.firebaseUid,
                        anio: widget.anio,
                        mes: widget.mes,
                        onChanged: _cargar,
                        onAgregar: _abrirAgregarGasto,
                      ),
                      _TabQuincenas(
                        key: ValueKey(_quincenasKey),
                        uid: widget.firebaseUid,
                        anio: widget.anio,
                        mes: widget.mes,
                      ),
                      _TabAnalisis(data: _data!, uid: widget.firebaseUid),
                    ],
                  ),
                ),
    );
  }

  Future<void> _exportarPdf() async {
    if (_data == null) return;
    try {
      final pdf = await PdfService.generarPdfMes(_data!, widget.label, widget.anio);
      await Printing.layoutPdf(onLayout: (_) async => pdf,
          name: 'Salarying_${widget.label}_${widget.anio}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar PDF: $e')));
    }
  }

  void _abrirAgregarGasto() async {
    final cats = (_data?['analisis_categorias'] as List?)?.cast<Map<String, dynamic>>();
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgregarGastoSheet(
        firebaseUid: widget.firebaseUid,
        anio: widget.anio,
        mes: widget.mes,
        analisisCategorias: cats,
      ),
    );
    if (res == true) _cargar();
  }
}

// ── TAB 1: RESUMEN ────────────────────────────────────────────────────────

class _TabResumen extends StatelessWidget {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> alertas;
  final String uid;
  final int anio;
  final int mes;
  final String labelMes;
  final VoidCallback onChanged;

  const _TabResumen({
    required this.data,
    required this.alertas,
    required this.uid,
    required this.anio,
    required this.mes,
    required this.labelMes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final r = data['resumen'] as Map<String, dynamic>;
    final tieneResumenCaja = ResumenMensualCard.tieneDatos(r);
    final ingEst  = _d(r['ingreso_estimado']);
    final ingReal = _d(r['ingreso_real']);
    final fijosEst  = _d(r['fijos_estimados']);
    final fijosReal = _d(r['fijos_reales']);
    final varEst  = _d(r['variables_estimados']);
    final varReal = _d(r['variables_reales']);
    final noPres  = _d(r['no_presupuestados']);
    final hormigaTotal = _d(r['hormiga_total']);
    final hormigaCount = (r['hormiga_count'] as num?)?.toInt() ?? 0;
    final remEst  = _d(r['remanente_estimado']);
    final remReal = _d(r['remanente_real']);
    final sano    = r['presupuesto_sano'] as bool? ?? true;

    // Disponible libre = ingreso - todo lo gastado real
    final ingresoRef   = ingReal > 0 ? ingReal : ingEst;
    final yaGastado    = fijosReal + varReal + noPres;
    final disponible   = ingresoRef - yaGastado;
    final hayReal      = fijosReal > 0 || varReal > 0;
    final dispColor    = disponible > ingresoRef * 0.20 ? AppTheme.success
                       : disponible > 0                 ? AppTheme.warning
                       : AppTheme.danger;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── DISPONIBLE LIBRE ─────────────────────────────────────────────
        if (tieneResumenCaja)
          ResumenMensualCard(resumen: r)
        else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: BoxDecoration(
            color: dispColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dispColor.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                hayReal ? 'Te queda disponible' : 'Estimado disponible',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 6),
              // V2 — define qué compone el total para que cuadre en todas las pantallas
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 6),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                message: 'Lo gastado incluye todo lo registrado este mes: '
                    'gastos fijos, deudas pagadas, variables, no presupuestados, '
                    'gustitos, compartido y eventos. Es el mismo total en Dashboard y Estado Anual.',
                child: Icon(Icons.info_outline, size: 13, color: AppTheme.textMuted),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              Money.fmt(disponible),
              style: TextStyle(color: dispColor, fontSize: 38, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              hayReal
                  ? 'de ${Money.fmt(ingresoRef)} · ya gastaste ${Money.fmt(yaGastado)}'
                  : 'basado en tu planificación — registra gastos para ver el real',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            // Mini barra de consumo
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ingresoRef > 0 ? (yaGastado / ingresoRef).clamp(0.0, 1.0) : 0,
                minHeight: 6,
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation(dispColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ingresoRef > 0 ? 'Usaste el ${(yaGastado / ingresoRef * 100).toStringAsFixed(0)}% de tu ingreso' : '',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Banner sano / en déficit
        if (!tieneResumenCaja)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: sano ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sano ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.danger.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(sano ? Icons.check_circle : Icons.warning_amber_rounded,
                color: sano ? AppTheme.success : AppTheme.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              sano ? 'Mes bajo control' : 'Gastos superan el ingreso',
              style: TextStyle(color: sano ? AppTheme.success : AppTheme.danger,
                  fontWeight: FontWeight.w700, fontSize: 13),
            )),
          ]),
        ),
        const SizedBox(height: 12),

        // Ingreso real
        _IngresoRealCard(
          ingEst: ingEst, ingReal: ingReal,
          uid: uid, anio: anio, mes: mes, onChanged: onChanged,
        ),

        // Alertas del mes
        if (alertas.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...alertas.map((a) => _AlertaMesCard(alerta: a, uid: uid)),
        ],

        const SizedBox(height: 12),

        // F1 — detalle colapsable: reduce la sobrecarga visual del Resumen.
        // Lo principal (disponible, banner, alertas) queda arriba siempre visible.
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            iconColor: AppTheme.primary,
            collapsedIconColor: AppTheme.textMuted,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('Detalle del mes',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('Comparación, uso del ingreso y compromisos',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            children: [
              const SizedBox(height: 8),
              // Tabla planificado vs real
              _seccion(tieneResumenCaja
                  ? 'PLAN VS GASTOS REGISTRADOS (PAGADOS Y PENDIENTES)'
                  : 'LO QUE PLANIFICASTE VS LO QUE GASTASTE'),
              _FilaComparativa('Ingreso', ingEst, ingReal, AppTheme.success),
              _FilaComparativa('Gastos fijos', fijosEst, fijosReal, AppTheme.colorFijo),
              _FilaComparativa('Gastos variables', varEst, varReal, AppTheme.warning),
              if (noPres > 0) _FilaComparativa('No presupuestados', 0, noPres, AppTheme.danger),
              if (hormigaCount > 0 && hormigaTotal > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Text('🐜', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '$hormigaCount pequeña${hormigaCount == 1 ? '' : 's'} compra${hormigaCount == 1 ? '' : 's'} '
                      '— ${Money.fmt(hormigaTotal)} en total este mes',
                      style: const TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
                    )),
                    if (ingresoRef > 0)
                      Text(
                        '${(hormigaTotal / ingresoRef * 100).toStringAsFixed(1)}%\ndel ingreso',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.warning, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                  ]),
                ),
              ],
              Divider(color: AppTheme.border, height: 24),
              _FilaComparativa(tieneResumenCaja ? 'Tras lo registrado' : 'Te sobra', remEst, remReal,
                  remReal >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
              const SizedBox(height: 24),

              // Barra de progreso de uso del mes
              if (!tieneResumenCaja) _seccion('USO DEL INGRESO'),
              const SizedBox(height: 8),
              if (!tieneResumenCaja) _BarraUso(ingreso: ingReal > 0 ? ingReal : ingEst,
                  fijos: fijosReal, variables: varReal, noPres: noPres),
              const SizedBox(height: 24),

              // Compromisos fijos del mes
              _CompromisosSection(data: data),
            ],
          ),
        ),

        // Botón cierre mensual (solo si el mes está activo)
        if ((data['mes']?['estado'] as String? ?? '') == 'activo') ...[
          const SizedBox(height: 28),
          Divider(color: AppTheme.border),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.insights_outlined, size: 16),
              label: Text('Ver cómo me fue en $labelMes'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final res = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => DraggableScrollableSheet(
                    initialChildSize: 0.75,
                    minChildSize: 0.5,
                    maxChildSize: 0.95,
                    expand: false,
                    builder: (_, ctrl) => CierreMesSheet(
                      firebaseUid: uid,
                      anio: anio,
                      mes: mes,
                      labelMes: labelMes,
                      data: data,
                      alertas: alertas,
                    ),
                  ),
                );
                if (res == true) onChanged();
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Guarda un resumen de cómo te fue. Tu historial se conserva — no pierdes acceso.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _seccion(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
  );

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}

class _FilaComparativa extends StatelessWidget {
  final String nombre;
  final double estimado;
  final double real;
  final Color color;
  final bool bold;
  const _FilaComparativa(this.nombre, this.estimado, this.real, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final diff = real - estimado;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(flex: 3, child: Text(nombre,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Expanded(flex: 2, child: Text('${Money.fmt(estimado)}',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        Expanded(flex: 2, child: Text('${Money.fmt(real)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: bold ? 15 : 13))),
        if (estimado > 0) SizedBox(
          width: 56,
          child: Text(
            '${diff >= 0 ? '+' : ''}${Money.fmt0(diff)}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: diff > 0 ? AppTheme.danger : AppTheme.success),
          ),
        ),
      ]),
    );
  }
}

class _BarraUso extends StatelessWidget {
  final double ingreso;
  final double fijos;
  final double variables;
  final double noPres;
  const _BarraUso({required this.ingreso, required this.fijos, required this.variables, required this.noPres});

  @override
  Widget build(BuildContext context) {
    final total = fijos + variables + noPres;
    final pct = ingreso > 0 ? (total / ingreso).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          minHeight: 12,
          color: pct > 0.9 ? AppTheme.danger : pct > 0.7 ? AppTheme.warning : AppTheme.success,
          backgroundColor: AppTheme.surfaceAlt,
        ),
      ),
      const SizedBox(height: 6),
      Text('${(pct * 100).toStringAsFixed(1)}% del ingreso usado · ${Money.fmt(total)} de ${Money.fmt(ingreso)}',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]);
  }
}

// ── TAB 2: GASTOS ────────────────────────────────────────────────────────

class _TabGastos extends StatefulWidget {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> alertas;
  final String uid;
  final int anio;
  final int mes;
  final VoidCallback onChanged;
  final VoidCallback onAgregar;
  const _TabGastos({
    required this.data,
    required this.alertas,
    required this.uid,
    required this.anio,
    required this.mes,
    required this.onChanged,
    required this.onAgregar,
  });

  @override
  State<_TabGastos> createState() => _TabGastosState();
}

class _TabGastosState extends State<_TabGastos> {
  bool _operando = false;
  bool _sobresExpandido = true;
  String _busqueda = '';
  String? _filtroTipo;
  String _orden = 'fecha_desc';
  final _buscadorCtrl = TextEditingController();

  @override
  void dispose() {
    _buscadorCtrl.dispose();
    super.dispose();
  }

  // B1 — mini-sheet de pago: permite pago completo o parcial (varias quincenas)
  Future<void> _abrirPagoFijo(
      Map<String, dynamic> g, List<Map<String, dynamic>> regs) async {
    final planeado  = _num(g['monto']);
    final pagadoSum = regs.fold<double>(0.0, (s, r) => s + _num(r['monto']));
    final falta     = planeado - pagadoSum;
    final sugerido  = falta > 0.01 ? falta : planeado;
    final montoCtrl = TextEditingController(text: sugerido.toStringAsFixed(2));
    DateTime fecha  = DateTime.now();
    bool guardando  = false;

    String fmtFecha(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String apiFecha(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Pagar ${g['nombre']}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // Resumen planeado / pagado / falta
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(child: _ResumenPago('Planeado', planeado, AppTheme.textSecondary)),
              Expanded(child: _ResumenPago('Pagado', pagadoSum, AppTheme.success)),
              Expanded(child: _ResumenPago('Falta', falta > 0 ? falta : 0, AppTheme.warning)),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: '¿Cuánto pagaste?',
              prefixText: 'B/. ',
              suffixIcon: TextButton(
                onPressed: () => setS(() =>
                    montoCtrl.text = (falta > 0.01 ? falta : planeado).toStringAsFixed(2)),
                child: const Text('Pagar todo', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Selector de fecha (default hoy)
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: fecha,
                firstDate: DateTime(widget.anio - 1),
                lastDate: DateTime(widget.anio + 1, 12, 31),
              );
              if (picked != null) setS(() => fecha = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today, color: AppTheme.textMuted, size: 16),
                const SizedBox(width: 10),
                Text('Fecha: ${fmtFecha(fecha)}',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                const Spacer(),
                Icon(Icons.edit, color: AppTheme.textMuted, size: 14),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: guardando ? null : () async {
              final monto = double.tryParse(montoCtrl.text);
              if (monto == null || monto <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Monto inválido')));
                return;
              }
              setS(() => guardando = true);
              try {
                await RegistrosService.crear(
                  uid: widget.uid,
                  anio: widget.anio,
                  mes: widget.mes,
                  tipo: 'fijo',
                  categoria: categoriaCanonicaCompromiso(g),
                  nombre: g['nombre'] as String? ?? '',
                  monto: monto,
                  fecha: apiFecha(fecha),
                  origenFijoId: g['id'] as int,
                  pagado: 1,
                );
                if (!sheetCtx.mounted) return;
                Navigator.pop(sheetCtx);
                widget.onChanged();
              } catch (e) {
                setS(() => guardando = false);
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
              }
            },
            child: guardando
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Registrar pago'),
          )),
          // Pagos ya registrados (eliminar para corregir)
          if (regs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pagos registrados',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...regs.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.check_circle, color: AppTheme.success, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${Money.fmt(_num(r['monto']))} · ${(r['fecha']?.toString() ?? '').split('T').first}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                )),
                GestureDetector(
                  onTap: () async {
                    try {
                      await RegistrosService.eliminar(widget.uid, (r['id'] as num).toInt());
                      if (!sheetCtx.mounted) return;
                      Navigator.pop(sheetCtx);
                      widget.onChanged();
                    } catch (_) {}
                  },
                  child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 16),
                ),
              ]),
            )),
          ],
        ]),
      )),
    );
  }

  double _num(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  void _mostrarOpcionesFijo(BuildContext context, Map<String, dynamic> g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.history, color: AppTheme.info),
            title: Text('Ver historial de pagos', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Qué meses lo has pagado este año',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              _mostrarHistorialFijo(context, g['id'] as int);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
            title: Text('Editar gasto fijo', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Cambia nombre o monto para todos los meses',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              EditarGastoFijoSheet.show(
                context,
                id: g['id'] as int,
                nombre: g['nombre'] as String,
                monto: _num(g['monto']),
                firebaseUid: widget.uid,
                disponibleActual: _num((widget.data['resumen'] as Map?)?['remanente_estimado']),
                onGuardado: widget.onChanged,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
            title: const Text('Eliminar gasto fijo', style: TextStyle(color: AppTheme.danger)),
            subtitle: Text('Se elimina de todos los meses',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            onTap: () async {
              Navigator.pop(context);
              final confirmar = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: Text('¿Eliminar gasto fijo?',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  content: Text(
                    'Se eliminará "${g['nombre']}" de todos los meses. Esta acción no se puede deshacer.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
                    ),
                  ],
                ),
              );
              if (confirmar == true) {
                try {
                  await ApiClient.delete(
                      '/user/gastos-fijos/${g['id']}?firebase_uid=${widget.uid}');
                  widget.onChanged();
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // D2 — detalle de la categoría: lista de registros de ese mes (sin navegar lejos)
  void _mostrarDetalleCategoria(
      BuildContext context, String categoria, List<Map<String, dynamic>> registros) {
    final delCat = registros.where((r) => r['categoria'] == categoria).toList()
      ..sort((a, b) => (b['fecha']?.toString() ?? '').compareTo(a['fecha']?.toString() ?? ''));
    final total = delCat.fold<double>(0, (s, r) => s + (_num(r['monto'])));
    final catLabel = categoria.isNotEmpty
        ? '${categoria[0].toUpperCase()}${categoria.substring(1)}'
        : categoria;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(catLabel,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700))),
              Text('${delCat.length} ${delCat.length == 1 ? 'gasto' : 'gastos'} · ${Money.fmt(total)}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            if (delCat.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Sin gastos registrados en esta categoría este mes.',
                    style: TextStyle(color: AppTheme.textSecondary))),
              )
            else
              Expanded(child: ListView.separated(
                controller: scrollCtrl,
                itemCount: delCat.length,
                separatorBuilder: (_, __) => Divider(color: AppTheme.border, height: 1),
                itemBuilder: (_, i) {
                  final r = delCat[i];
                  final fecha = (r['fecha']?.toString() ?? '');
                  final fechaCorta = fecha.length >= 10 ? fecha.substring(0, 10) : fecha;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['nombre']?.toString() ?? '—',
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(fechaCorta, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      ])),
                      Text('${Money.fmt(_num(r['monto']))}',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  );
                },
              )),
          ]),
        ),
      ),
    );
  }

  // E1 — historial de pagos del gasto fijo (qué meses se pagó este año)
  void _mostrarHistorialFijo(BuildContext context, int fijoId) {
    const labels = ['', 'Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: FutureBuilder(
          future: ApiClient.get(
              '/user/gastos-fijos/$fijoId/historial?firebase_uid=${widget.uid}&anio=${widget.anio}'),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 180,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
            }
            if (!snap.hasData || snap.data!.statusCode != 200) {
              return SizedBox(height: 120,
                  child: Center(child: Text('No se pudo cargar el historial',
                      style: TextStyle(color: AppTheme.textSecondary))));
            }
            final data = jsonDecode(snap.data!.body) as Map<String, dynamic>;
            final meses = (data['meses'] as List).cast<Map<String, dynamic>>();
            final presup = (double.tryParse(data['presupuestado'].toString()) ?? 0);
            final promedio = (double.tryParse(data['promedio_pagado'].toString()) ?? 0);
            final mesesPagados = (data['meses_pagados'] as int? ?? 0);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(data['nombre']?.toString() ?? 'Gasto fijo',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Presupuestado: ${Money.fmt(presup)}/mes · ${widget.anio}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              // Grid de 12 meses
              Wrap(spacing: 8, runSpacing: 8, children: meses.map((m) {
                final mes = m['mes'] as int;
                final pagado = m['pagado'] as bool? ?? false;
                final futuro = m['futuro'] as bool? ?? false;
                final color = pagado ? AppTheme.success : futuro ? AppTheme.textMuted : AppTheme.danger;
                return Container(
                  width: 64, height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: futuro ? 0.05 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: futuro ? 0.2 : 0.4)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(labels[mes], style: TextStyle(
                        color: futuro ? AppTheme.textMuted : color, fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Icon(pagado ? Icons.check_circle : futuro ? Icons.remove : Icons.cancel,
                        color: color, size: 13),
                  ]),
                );
              }).toList()),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _HistKpi('Pagado este año', '$mesesPagados ${mesesPagados == 1 ? 'mes' : 'meses'}', AppTheme.success)),
                Expanded(child: _HistKpi('Promedio pagado', Money.fmt(promedio), AppTheme.textPrimary)),
              ]),
              if (promedio > 0 && presup > 0 && (promedio - presup).abs() > 0.5) ...[
                const SizedBox(height: 10),
                Text(
                  promedio > presup
                      ? 'Pagas en promedio ${Money.fmt(promedio - presup)} más que lo presupuestado.'
                      : 'Pagas en promedio ${Money.fmt(presup - promedio)} menos que lo presupuestado.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _HistKpi(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ],
  );

  Future<void> _mostrarOpcionesVariable(BuildContext context, String categoria) async {
    // Cargar líneas de presupuesto variable para esta categoría
    List<Map<String, dynamic>> lineas = [];
    try {
      final data = await GastosVariablesService.getAll(widget.uid);
      final todas = (data['gastos'] as List? ?? []).cast<Map<String, dynamic>>();
      lineas = todas.where((g) => g['categoria'] == categoria).toList();
    } catch (_) {}

    if (!context.mounted) return;

    if (lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay líneas de presupuesto para esta categoría'),
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text(
              'Presupuesto · ${categoria[0].toUpperCase()}${categoria.substring(1)}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Mantén presionado una línea para editarla',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 14),
            ...lineas.map((g) => _LineaVariableRow(
              g: g,
              uid: widget.uid,
              disponibleActual: _num((widget.data['resumen'] as Map?)?['remanente_estimado']),
              onChanged: () {
                Navigator.pop(context);
                widget.onChanged();
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _marcarDeuda(Map<String, dynamic> d, bool pagado, int? registroId) async {
    if (_operando) return;
    setState(() => _operando = true);
    try {
      if (!pagado) {
        final hoy = DateTime.now();
        final fecha = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
        await RegistrosService.crear(
          uid: widget.uid,
          anio: widget.anio,
          mes: widget.mes,
          tipo: 'fijo',
          categoria: 'deudas',
          nombre: d['nombre'] as String? ?? '',
          monto: (d['cuota'] as num? ?? 0).toDouble(),
          fecha: fecha,
          origenDeudaId: d['id'] as int,
          pagado: 1,
        );
      } else if (registroId != null) {
        await RegistrosService.eliminar(widget.uid, registroId);
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _operando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registros   = (widget.data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    final compromisos = widget.data['compromisos_fijos'] as Map<String, dynamic>? ?? {};
    final gastosFijos = (compromisos['gastos_fijos'] as List? ?? []).cast<Map<String, dynamic>>();
    final deudas      = (compromisos['deudas'] as List? ?? []).cast<Map<String, dynamic>>();

    // B1 — Mapa fijoId → lista de sus registros (soporta pagos parciales múltiples)
    final fijoARegistros = <int, List<Map<String, dynamic>>>{};
    for (final r in registros) {
      final origenId = r['origen_fijo_id'];
      if (origenId != null) {
        final fijoId = (origenId as num?)?.toInt() ?? -1;
        if (fijoId >= 0) {
          (fijoARegistros[fijoId] ??= []).add(r);
        }
      }
    }

    // Mapa deudaId → registroId para saber qué registro borrar al desmarcar pago de deuda
    final deudaARegistroId = <int, int>{};
    final deudasPagadasIds = <int>{};
    for (final r in registros) {
      final origenDeudaId = r['origen_deuda_id'];
      if (origenDeudaId != null) {
        final deudaId = (origenDeudaId as num?)?.toInt() ?? -1;
        final regId   = (r['id'] as num?)?.toInt() ?? -1;
        if (deudaId >= 0 && regId >= 0) {
          deudasPagadasIds.add(deudaId);
          deudaARegistroId[deudaId] = regId;
        }
      }
    }

    final sobres = (widget.data['analisis_categorias'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((c) {
          final p = double.tryParse(c['presupuestado'].toString()) ?? 0.0;
          final t = double.tryParse(c['total_gastado'].toString()) ?? 0.0;
          return p > 0 || t > 0;
        }).toList();

    final alertasCriticas = widget.alertas
        .where((a) => (a['nivel'] as String? ?? '') == 'danger')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // ── BANNER DE ALERTAS CRÍTICAS ────────────────────────────
        if (alertasCriticas.isNotEmpty) ...[
          ...alertasCriticas.take(2).map((a) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['titulo'] as String? ?? '',
                    style: const TextStyle(color: AppTheme.danger,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                if ((a['accion_sugerida'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(a['accion_sugerida'] as String,
                      style: TextStyle(color: AppTheme.textSecondary,
                          fontSize: 11, height: 1.3)),
                ],
              ])),
            ]),
          )),
          const SizedBox(height: 4),
        ],

        // ── SOBRES POR CATEGORÍA ──────────────────────────────────
        if (sobres.isNotEmpty) ...[
          GestureDetector(
            onTap: () => setState(() => _sobresExpandido = !_sobresExpandido),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Text('SOBRES DEL MES',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const Spacer(),
                Icon(_sobresExpandido ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textMuted, size: 18),
              ]),
            ),
          ),
          if (_sobresExpandido)
            ...sobres.map((c) => _SobreRow(
              cat: c,
              onTap: () => _mostrarDetalleCategoria(
                  context, c['categoria'] as String, registros),
              onLongPress: () => _mostrarOpcionesVariable(
                  context, c['categoria'] as String),
            )),
          Divider(color: AppTheme.border, height: 24),
        ],

        // ── COMPROMISOS FIJOS DEL MES ────────────────────────────
        if (gastosFijos.isNotEmpty || deudas.isNotEmpty) ...[
          _SeccionLabel('COMPROMISOS DEL MES',
              '${gastosFijos.length + deudas.length} ítems planificados'),
          ...gastosFijos.map((g) {
            final fijoId = (g['id'] as num?)?.toInt() ?? -1;
            final regs = fijoARegistros[fijoId] ?? const <Map<String, dynamic>>[];
            final pagadoSum = regs.fold<double>(0.0, (s, r) => s + _num(r['monto']));
            return _PlanTile(
              nombre: g['nombre'] as String? ?? '',
              monto: _num(g['monto']),
              tipo: g['tipo'] as String? ?? 'otro',
              pagadoSum: pagadoSum,
              esPago: false,
              onTap: (_operando || fijoId < 0) ? null : () => _abrirPagoFijo(g, regs),
              onLongPress: fijoId < 0 ? null : () => _mostrarOpcionesFijo(context, g),
            );
          }),
          ...deudas.map((d) {
            final deudaId = (d['id'] as num?)?.toInt() ?? -1;
            final pagado  = deudasPagadasIds.contains(deudaId);
            return _PlanTile(
              nombre: d['nombre'] as String? ?? '',
              monto: (d['cuota'] as num? ?? 0).toDouble(),
              tipo: 'deuda',
              pagado: pagado,
              esPago: true,
              cuotasRestantes: d['cuotas_restantes'] as int?,
              onTap: (_operando || deudaId < 0) ? null : () => _marcarDeuda(d, pagado, deudaARegistroId[deudaId]),
            );
          }),
          Divider(color: AppTheme.border, height: 24),
        ],

        // ── REGISTROS REALES ────────────────────────────────────
        if (registros.isNotEmpty) ...[
          // Búsqueda + chips (solo si hay suficientes registros)
          if (registros.length > 3) ...[
            TextField(
              controller: _buscadorCtrl,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: InputDecoration(
                hintText: 'Buscar gasto…',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: AppTheme.textMuted, size: 18),
                suffixIcon: _busqueda.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() {
                          _busqueda = '';
                          _buscadorCtrl.clear();
                        }),
                        child: Icon(Icons.clear, color: AppTheme.textMuted, size: 16),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final entry in const [
                  (null,               'Todos'),
                  ('fijo',             'Fijos'),
                  ('variable',         'Variable'),
                  ('no_presupuestado', 'No presup.'),
                ])
                  GestureDetector(
                    onTap: () => setState(() => _filtroTipo = entry.$1),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _filtroTipo == entry.$1
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _filtroTipo == entry.$1
                              ? AppTheme.primary
                              : AppTheme.border,
                          width: _filtroTipo == entry.$1 ? 1.5 : 1,
                        ),
                      ),
                      child: Text(entry.$2,
                          style: TextStyle(
                            color: _filtroTipo == entry.$1
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: _filtroTipo == entry.$1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          )),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          // Lista filtrada
          Builder(builder: (_) {
            final filtrados = registros.where((r) {
              final matchBusq = _busqueda.isEmpty ||
                  (r['nombre'] as String? ?? '').toLowerCase().contains(_busqueda.toLowerCase()) ||
                  (r['categoria'] as String? ?? '').toLowerCase().contains(_busqueda.toLowerCase());
              final matchTipo = _filtroTipo == null || r['tipo'] == _filtroTipo;
              return matchBusq && matchTipo;
            }).toList();
            // sort client-side
            filtrados.sort((a, b) {
              if (_orden == 'monto_desc') {
                return (double.tryParse(b['monto'].toString()) ?? 0)
                    .compareTo(double.tryParse(a['monto'].toString()) ?? 0);
              }
              final fa = (a['fecha'] as String? ?? '');
              final fb = (b['fecha'] as String? ?? '');
              return _orden == 'fecha_asc' ? fa.compareTo(fb) : fb.compareTo(fa);
            });
            final label = (filtrados.length == registros.length)
                ? '${registros.length} transacciones'
                : '${filtrados.length} de ${registros.length}';
            // cycle: fecha_desc → fecha_asc → monto_desc → fecha_desc
            final nextOrden = _orden == 'fecha_desc'
                ? 'fecha_asc'
                : _orden == 'fecha_asc'
                    ? 'monto_desc'
                    : 'fecha_desc';
            final ordenIcon = _orden == 'monto_desc'
                ? Icons.attach_money
                : _orden == 'fecha_asc'
                    ? Icons.arrow_upward
                    : Icons.arrow_downward;
            final ordenLabel = _orden == 'monto_desc'
                ? 'Mayor monto'
                : _orden == 'fecha_asc'
                    ? 'Más antiguo'
                    : 'Más reciente';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text('GASTOS REGISTRADOS',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 0.6))),
                  GestureDetector(
                    onTap: () => setState(() => _orden = nextOrden),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ordenIcon, size: 11, color: AppTheme.primary),
                      const SizedBox(width: 3),
                      Text(ordenLabel,
                          style: const TextStyle(color: AppTheme.primary, fontSize: 11)),
                      const SizedBox(width: 6),
                      Text(label,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
              if (filtrados.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Sin resultados para "$_busqueda"',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                )
              else
                ...filtrados.map((r) => _RegistroTile(
                    reg: r, uid: widget.uid, onChanged: widget.onChanged)),
            ]);
          }),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Aún no tienes gastos este mes',
              subtitle: 'Registra tu primer gasto o escanea una factura QR',
              actionLabel: 'Registrar primer gasto',
              onAction: widget.onAgregar,
            ),
          ),

        // ── E2: totales del mes por tipo ──────────────────────────────
        if (registros.isNotEmpty) ...[
          const SizedBox(height: 16),
          Builder(builder: (_) {
            double comprometido = 0, variable = 0, noPres = 0;
            for (final r in registros) {
              final m = _num(r['monto']);
              switch (r['tipo'] as String? ?? '') {
                case 'fijo': comprometido += m; break;
                case 'no_presupuestado': noPres += m; break;
                default: variable += m;
              }
            }
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(children: [
                _totalRow('Comprometido (fijos + deudas)', comprometido, AppTheme.colorFijo),
                const SizedBox(height: 6),
                _totalRow('Variable registrado', variable, AppTheme.warning),
                const SizedBox(height: 6),
                _totalRow('No presupuestado (impulso)', noPres, AppTheme.danger),
              ]),
            );
          }),
        ],
      ],
    );
  }

  Widget _totalRow(String label, double monto, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ]),
      Text(Money.fmt(monto),
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ],
  );
}

class _LineaVariableRow extends StatefulWidget {
  final Map<String, dynamic> g;
  final String uid;
  final VoidCallback onChanged;
  final double disponibleActual; // D3 — para previsualizar el impacto
  const _LineaVariableRow({
    required this.g,
    required this.uid,
    required this.onChanged,
    this.disponibleActual = 0,
  });
  @override
  State<_LineaVariableRow> createState() => _LineaVariableRowState();
}

class _LineaVariableRowState extends State<_LineaVariableRow> {
  bool _editando = false;
  bool _guardando = false;
  late TextEditingController _nombreCtrl;
  late TextEditingController _montoCtrl;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.g['nombre'] as String? ?? '');
    _montoCtrl  = TextEditingController(
        text: double.tryParse(widget.g['monto_estimado'].toString())?.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_montoCtrl.text);
    if (monto == null || monto <= 0) return;
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _guardando = true);
    try {
      await GastosVariablesService.editar(widget.uid, widget.g['id'] as int,
          {'nombre': nombre, 'monto_estimado': monto});
      setState(() { _editando = false; _guardando = false; });
      widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('¿Eliminar línea?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Se eliminará "${widget.g['nombre']}" del presupuesto.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GastosVariablesService.eliminar(widget.uid, widget.g['id'] as int);
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(widget.g['monto_estimado'].toString()) ?? 0.0;
    final frec  = widget.g['frecuencia'] as String? ?? 'mensual';

    if (_editando) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _nombreCtrl,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Nombre', isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Monto (\$)', prefixText: 'B/. ', isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
          // D3 — preview del impacto en el disponible mensual
          Builder(builder: (_) {
            final original = double.tryParse(widget.g['monto_estimado'].toString()) ?? 0.0;
            final nm = double.tryParse(_montoCtrl.text) ?? original;
            if ((nm - original).abs() <= 0.001) return const SizedBox(height: 10);
            final nuevoDisp = widget.disponibleActual + (original - nm);
            final mejora = nuevoDisp >= widget.disponibleActual;
            final color = nuevoDisp < 0 ? AppTheme.danger : mejora ? AppTheme.success : AppTheme.warning;
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(mejora ? Icons.trending_up : Icons.trending_down, color: color, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Nuevo disponible: ${Money.fmt(nuevoDisp)} · antes ${Money.fmt(widget.disponibleActual)}',
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            );
          }),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => setState(() => _editando = false),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8)),
              child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 8)),
              child: _guardando
                  ? const SizedBox(height: 14, width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Guardar', style: TextStyle(fontSize: 12, color: Colors.black)),
            )),
          ]),
        ]),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(widget.g['nombre'] as String? ?? '',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      subtitle: Text('$frec',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${Money.fmt(monto)}',
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _editando = true),
          child: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _eliminar,
          child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
        ),
      ]),
    );
  }
}

class _SobreRow extends StatelessWidget {
  final Map<String, dynamic> cat;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap; // D2 — abrir detalle de registros de la categoría
  const _SobreRow({required this.cat, this.onLongPress, this.onTap});

  @override
  Widget build(BuildContext context) {
    final rawCat = cat['categoria'] as String? ?? '';
    final nombre = rawCat.isNotEmpty
        ? '${rawCat[0].toUpperCase()}${rawCat.substring(1)}'
        : rawCat;
    final presup = double.tryParse(cat['presupuestado'].toString()) ?? 0.0;
    final total  = double.tryParse(cat['total_gastado'].toString()) ?? 0.0;
    final bar    = presup > 0 ? (total / presup).clamp(0.0, 1.0) : 0.0;
    final excede = presup > 0 && total > presup;
    final barColor = excede
        ? AppTheme.danger
        : bar > 0.8
            ? AppTheme.warning
            : AppTheme.success;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nombre,
                style: TextStyle(color: AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600))),
            if (onTap != null)
              Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 13),
            if (onLongPress != null)
              Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 11),
            const SizedBox(width: 4),
            Text(
              excede
                  ? '${Money.fmt(total)} · +${Money.fmt((total - presup))} excedido'
                  : presup > 0
                      ? '${Money.fmt(total)} de ${Money.fmt(presup)}'
                      : '${Money.fmt(total)}',
              style: TextStyle(color: barColor, fontSize: 11),
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 4,
              color: barColor,
              backgroundColor: AppTheme.surfaceAlt,
            ),
          ),
        ]),
      ),
    );
  }
}

class _SeccionLabel extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  const _SeccionLabel(this.titulo, this.subtitulo);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Expanded(child: Text(titulo,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 0.6))),
      Text(subtitulo, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]),
  );
}

class _PlanTile extends StatelessWidget {
  final String nombre;
  final double monto;
  final String tipo;
  final bool pagado;          // usado por deudas (binario)
  final double? pagadoSum;    // B1 — usado por fijos (soporta pago parcial)
  final bool esPago;
  final int? cuotasRestantes;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _PlanTile({
    required this.nombre, required this.monto, required this.tipo,
    required this.esPago,
    this.pagado = false,
    this.pagadoSum,
    this.cuotasRestantes,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = tipo == 'deuda' ? AppTheme.danger
        : tipo == 'vivienda' ? AppTheme.colorFijo
        : AppTheme.colorFijo;

    // Estado: completo / parcial / pendiente
    final usaParcial = pagadoSum != null;
    final completo = usaParcial ? (pagadoSum! >= monto - 0.01) : pagado;
    final parcial  = usaParcial && pagadoSum! > 0.01 && pagadoSum! < monto - 0.01;
    final falta    = monto - (pagadoSum ?? 0);

    final borderColor = completo ? AppTheme.success.withValues(alpha: 0.3)
        : parcial ? AppTheme.warning.withValues(alpha: 0.4)
        : AppTheme.border;
    final bgColor = completo ? AppTheme.success.withValues(alpha: 0.06)
        : parcial ? AppTheme.warning.withValues(alpha: 0.05)
        : AppTheme.surface;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        Icon(
          completo ? Icons.check_circle
              : parcial ? Icons.timelapse
              : (esPago ? Icons.credit_card_outlined : Icons.receipt_outlined),
          color: completo ? AppTheme.success : parcial ? AppTheme.warning : color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: TextStyle(
            color: completo ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontSize: 13, fontWeight: FontWeight.w600,
          )),
          if (parcial)
            Text('Pagado ${Money.fmt(pagadoSum!)} de ${Money.fmt(monto)} · falta ${Money.fmt(falta)}',
                style: const TextStyle(color: AppTheme.warning, fontSize: 10, fontWeight: FontWeight.w600))
          else if (cuotasRestantes != null)
            Text('$cuotasRestantes cuotas restantes',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${Money.fmt(monto)}',
              style: TextStyle(
                color: completo ? AppTheme.textSecondary : color,
                fontWeight: FontWeight.w700, fontSize: 13,
              )),
          if (completo)
            const Text('Registrado', style: TextStyle(color: AppTheme.success, fontSize: 9))
          else if (parcial)
            const Text('Pago parcial', style: TextStyle(color: AppTheme.warning, fontSize: 9))
          else if (onTap != null)
            Text('Toca para pagar', style: TextStyle(color: AppTheme.textMuted, fontSize: 9))
          else
            Text('Pendiente', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
        ]),
      ]),
    ),
    );
  }
}

// B1 — celda de resumen en el sheet de pago (Planeado / Pagado / Falta)
class _ResumenPago extends StatelessWidget {
  final String label;
  final double valor;
  final Color color;
  const _ResumenPago(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
    const SizedBox(height: 3),
    Text(Money.fmt(valor),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
  ]);
}

class EditarGastoFijoSheet {
  static void show(
    BuildContext context, {
    required int id,
    required String nombre,
    required double monto,
    required String firebaseUid,
    required VoidCallback onGuardado,
    double disponibleActual = 0, // N2 — para previsualizar el impacto
  }) {
    final nombreCtrl = TextEditingController(text: nombre);
    final montoCtrl  = TextEditingController(text: monto.toStringAsFixed(2));
    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Editar gasto fijo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('El cambio aplica a todos los meses',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 20),
          TextField(
            controller: nombreCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Nombre'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Monto mensual (\$)', prefixText: 'B/. '),
            onChanged: (_) => setS(() {}),
          ),
          // N2 — preview del impacto en el disponible mensual
          Builder(builder: (_) {
            final nm = double.tryParse(montoCtrl.text) ?? monto;
            final nuevoDisp = disponibleActual + (monto - nm);
            final cambio = (nm - monto).abs() > 0.001;
            if (!cambio) return const SizedBox(height: 16);
            final mejora = nuevoDisp >= disponibleActual;
            final color = nuevoDisp < 0 ? AppTheme.danger : mejora ? AppTheme.success : AppTheme.warning;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(mejora ? Icons.trending_up : Icons.trending_down, color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Nuevo disponible mensual: ${Money.fmt(nuevoDisp)}  ·  antes ${Money.fmt(disponibleActual)}',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            );
          }),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: guardando ? null : () async {
              final nuevoMonto = double.tryParse(montoCtrl.text);
              if (nuevoMonto == null || nuevoMonto <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Monto inválido')));
                return;
              }
              final nuevoNombre = nombreCtrl.text.trim();
              if (nuevoNombre.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresa un nombre')));
                return;
              }
              setS(() => guardando = true);
              try {
                await ApiClient.put('/user/gastos-fijos/$id', {
                  'firebase_uid': firebaseUid,
                  'descripcion':  nuevoNombre,
                  'monto_mensual': nuevoMonto,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                onGuardado();
              } catch (e) {
                setS(() => guardando = false);
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
              }
            },
            child: guardando
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Guardar cambios'),
          )),
        ]),
      )),
    );
  }
}

class _RegistroTile extends StatelessWidget {
  final Map<String, dynamic> reg;
  final String uid;
  final VoidCallback onChanged;
  const _RegistroTile({required this.reg, required this.uid, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tipo       = reg['tipo'] as String;
    final monto      = double.tryParse(reg['monto'].toString()) ?? 0.0;
    final esGustito  = reg['origen_gustito_id'] != null;
    final color = esGustito   ? AppTheme.primary
        : tipo == 'fijo'      ? AppTheme.colorFijo
        : tipo == 'no_presupuestado' ? AppTheme.danger
        : AppTheme.warning;
    final tipoLabel = esGustito ? 'Gustito'
        : tipo == 'fijo'      ? 'Fijo'
        : tipo == 'no_presupuestado' ? 'No presup.'
        : 'Variable';
    final pagado = (reg['pagado'] as int? ?? 0) == 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.12),
        child: esGustito
            ? Icon(Icons.bolt, color: color, size: 16)
            : Icon(_iconCategoria(reg['categoria'] as String? ?? ''), color: color, size: 16),
      ),
      title: Text(reg['nombre'] as String? ?? '', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
      subtitle: Row(children: [
        Text('${reg['categoria']} · $tipoLabel',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        if (esGustito) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('⚡', style: TextStyle(fontSize: 9)),
          ),
        ],
      ]),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${Money.fmt(monto)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Icon(pagado ? Icons.check_circle : Icons.radio_button_unchecked,
            color: pagado ? AppTheme.success : AppTheme.textMuted, size: 14),
      ]),
      onTap: () => _opciones(context),
    );
  }

  void _opciones(BuildContext context) {
    final esGustito = reg['origen_gustito_id'] != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (esGustito)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.bolt, color: AppTheme.primary, size: 15),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Este gasto viene de un Gustito. Para eliminarlo, hazlo desde la pantalla de Gustitos.',
                  style: TextStyle(color: AppTheme.primary, fontSize: 11),
                )),
              ]),
            ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: AppTheme.success),
            title: Text('Marcar pagado/pendiente', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () async {
              Navigator.pop(context);
              final pagado = (reg['pagado'] as int? ?? 0) == 1;
              try {
                await RegistrosService.marcarPagado(
                  uid,
                  reg['id'] as int,
                  !pagado,
                );
                onChanged();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se pudo actualizar el gasto. Inténtalo nuevamente.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
          if (!esGustito) ...[
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
              title: Text('Editar', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _mostrarEditarSheet(context);
              },
            ),
            if (reg['tipo'] == 'no_presupuestado') ListTile(
              leading: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
              title: Text('Convertir a gasto variable base', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () async {
                Navigator.pop(context);
                await RegistrosService.convertirAVariable(uid, reg['id'] as int);
                onChanged();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Agregado a tu presupuesto variable')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
              onTap: () async {
                Navigator.pop(context);
                await RegistrosService.eliminar(uid, reg['id'] as int);
                onChanged();
              },
            ),
          ],
        ]),
      ),
    );
  }

  IconData _iconCategoria(String cat) {
    switch (cat) {
      case 'alimentacion': return Icons.restaurant;
      case 'transporte':   return Icons.directions_car;
      case 'vivienda':     return Icons.home;
      case 'salud':        return Icons.local_hospital;
      case 'educacion':    return Icons.school;
      case 'ocio':         return Icons.sports_esports;
      case 'deudas':       return Icons.account_balance;
      case 'ropa':         return Icons.checkroom;
      case 'deportes':     return Icons.fitness_center;
      case 'familia':      return Icons.family_restroom;
      default:             return Icons.receipt;
    }
  }

  void _mostrarEditarSheet(BuildContext context) {
    final nombreCtrl = TextEditingController(text: reg['nombre'] as String? ?? '');
    final montoCtrl  = TextEditingController(
        text: double.tryParse(reg['monto'].toString())?.toStringAsFixed(2) ?? '');
    final notasCtrl  = TextEditingController(text: reg['notas'] as String? ?? '');
    String tipo      = reg['tipo'] as String? ?? 'variable';
    String categoria = reg['categoria'] as String? ?? 'otro';
    String? categoriaCustom;
    DateTime fecha   = DateTime.tryParse(reg['fecha'] as String? ?? '') ?? DateTime.now();
    bool guardando   = false;

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')} '
        '${['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][d.month - 1]} '
        '${d.year}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Editar gasto',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // Tipo
              Row(children: [
                for (final t in [
                  ('fijo',             'Fijo',        AppTheme.colorFijo),
                  ('variable',         'Variable',    AppTheme.warning),
                  ('no_presupuestado', 'No presup.',  AppTheme.danger),
                ])
                  Expanded(child: GestureDetector(
                    onTap: () => setS(() => tipo = t.$1),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: tipo == t.$1
                            ? t.$3.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: tipo == t.$1 ? t.$3 : AppTheme.border),
                      ),
                      child: Text(t.$2, textAlign: TextAlign.center,
                          style: TextStyle(
                            color: tipo == t.$1 ? t.$3 : AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: tipo == t.$1
                                ? FontWeight.w700 : FontWeight.normal,
                          )),
                    ),
                  )),
              ]),
              const SizedBox(height: 12),

              // Nombre
              TextField(
                controller: nombreCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Nombre del gasto'),
              ),
              const SizedBox(height: 12),

              // Monto
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Monto', prefixText: 'B/. '),
              ),
              const SizedBox(height: 16),

              // Categoría
              CategoriaSelector(
                firebaseUid: uid,
                categoriaActual: categoria,
                color: AppTheme.primary,
                onChanged: (cat, custom) =>
                    setS(() { categoria = cat; categoriaCustom = custom; }),
              ),
              const SizedBox(height: 16),

              // Fecha
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: fecha,
                    firstDate: DateTime(fecha.year - 2),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                          colorScheme: const ColorScheme.dark(
                              primary: AppTheme.primary)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setS(() => fecha = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 10),
                    Text(fmt(fecha),
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Notas
              TextField(
                controller: notasCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Notas (opcional)'),
              ),
              const SizedBox(height: 20),

              // Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: guardando ? null : () async {
                    final nombre = nombreCtrl.text.trim();
                    final monto  = double.tryParse(montoCtrl.text);
                    if (nombre.isEmpty || monto == null) return;
                    setS(() => guardando = true);
                    try {
                      final catFinal = (categoria == 'otro' &&
                              categoriaCustom != null)
                          ? categoriaCustom!
                          : categoria;
                      await RegistrosService.editar(uid, reg['id'] as int, {
                        'nombre': nombre,
                        'monto':  monto,
                        'categoria': catFinal,
                        'tipo':  tipo,
                        'fecha': '${fecha.year}-'
                            '${fecha.month.toString().padLeft(2, '0')}-'
                            '${fecha.day.toString().padLeft(2, '0')}',
                        'notas': notasCtrl.text.isEmpty
                            ? null : notasCtrl.text.trim(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      onChanged();
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppTheme.danger));
                      }
                    } finally {
                      if (ctx.mounted) setS(() => guardando = false);
                    }
                  },
                  child: guardando
                      ? SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.background))
                      : const Text('Guardar cambios'),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() {
      nombreCtrl.dispose();
      montoCtrl.dispose();
      notasCtrl.dispose();
    });
  }
}

// ── Compromisos fijos del mes ────────────────────────────────────────────

class _CompromisosSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CompromisosSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final compromisos = data['compromisos_fijos'] as Map<String, dynamic>?;
    if (compromisos == null) return const SizedBox.shrink();

    final gastosFijos = (compromisos['gastos_fijos'] as List? ?? []).cast<Map<String, dynamic>>();
    final deudas      = (compromisos['deudas']       as List? ?? []).cast<Map<String, dynamic>>();
    final eventos     = (compromisos['eventos']       as List? ?? []).cast<Map<String, dynamic>>();

    if (gastosFijos.isEmpty && deudas.isEmpty && eventos.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('COMPROMISOS DEL MES',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
      const SizedBox(height: 4),
      Text('Gastos fijos y deudas activos este mes',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      const SizedBox(height: 10),

      if (gastosFijos.isNotEmpty) ...[
        const _SubSeccionLabel('GASTOS FIJOS', Color(0xFF1890FF)),
        const SizedBox(height: 6),
        ...gastosFijos.map((g) => _CompromisoTile(
          nombre: g['nombre'] as String? ?? '',
          monto: _d(g['monto_mensual']),
          subtitulo: _diasPago(g),
          color: const Color(0xFF1890FF),
          icon: Icons.lock_clock,
        )),
        const SizedBox(height: 10),
      ],

      if (deudas.isNotEmpty) ...[
        const _SubSeccionLabel('DEUDAS ACTIVAS', AppTheme.danger),
        const SizedBox(height: 6),
        ...deudas.map((d) => _CompromisoTile(
          nombre: d['nombre'] as String? ?? '',
          monto: _d(d['pago_mensual'] ?? d['pago_minimo'] ?? d['cuota_fija']),
          subtitulo: _deudaSubtitulo(d),
          color: AppTheme.danger,
          icon: Icons.account_balance,
        )),
        const SizedBox(height: 10),
      ],

      if (eventos.isNotEmpty) ...[
        const _SubSeccionLabel('EVENTOS', AppTheme.primary),
        const SizedBox(height: 6),
        ...eventos.map((e) => _CompromisoTile(
          nombre: '${e['emoji'] ?? '🎯'} ${e['nombre'] ?? ''}',
          monto: _d(e['cuota_mensual']),
          subtitulo: 'Cuota del evento · ${e['pct_avance']?.toStringAsFixed(0) ?? '0'}% completado',
          color: AppTheme.primary,
          icon: Icons.celebration_outlined,
        )),
      ],
    ]);
  }

  String _diasPago(Map<String, dynamic> g) {
    final d1 = g['dia_pago'] as int?;
    final d2 = g['dia_pago_2'] as int?;
    if (d1 != null && d2 != null) return 'Pago día $d1 y día $d2';
    if (d1 != null) return 'Pago día $d1';
    return '';
  }

  String _deudaSubtitulo(Map<String, dynamic> d) {
    final esLetra = (d['es_letra'] as int? ?? 0) == 1;
    final cuotas  = d['num_cuotas_total'] as int?;
    if (esLetra && cuotas != null) return 'Letra · $cuotas cuotas';
    final tipo = d['tipo'] as String? ?? '';
    return tipo.isNotEmpty ? tipo[0].toUpperCase() + tipo.substring(1).replaceAll('_', ' ') : '';
  }

  static double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}

class _SubSeccionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SubSeccionLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: color, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
  ]);
}

class _CompromisoTile extends StatelessWidget {
  final String nombre;
  final double monto;
  final String subtitulo;
  final Color color;
  final IconData icon;
  const _CompromisoTile({
    required this.nombre,
    required this.monto,
    required this.subtitulo,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: TextStyle(color: AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w600)),
          if (subtitulo.isNotEmpty)
            Text(subtitulo, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ])),
        Text('${Money.fmt(monto)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

// ── TAB 3: QUINCENAS ─────────────────────────────────────────────────────────

class _TabQuincenas extends StatefulWidget {
  final String uid;
  final int anio;
  final int mes;
  const _TabQuincenas({super.key, required this.uid, required this.anio, required this.mes});
  @override
  State<_TabQuincenas> createState() => _TabQuincenasState();
}

class _TabQuincenasState extends State<_TabQuincenas> {
  Map<String, dynamic>? _q1;
  Map<String, dynamic>? _q2;
  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    IaService.actionRefreshNotifier.addListener(_onIaAction);
    _cargar();
  }

  @override
  void dispose() {
    IaService.actionRefreshNotifier.removeListener(_onIaAction);
    super.dispose();
  }

  void _onIaAction() => _cargar();

  Future<void> _cargar() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final base = '/user/quincena/${widget.anio}/${widget.mes}';
      final r1 = await ApiClient.get('$base/1?firebase_uid=${widget.uid}');
      final r2 = await ApiClient.get('$base/2?firebase_uid=${widget.uid}');
      if (!mounted) return;
      if (r1.statusCode == 200 && r2.statusCode == 200) {
        setState(() {
          _q1 = jsonDecode(r1.body);
          _q2 = jsonDecode(r2.body);
          _loading = false;
        });
      } else {
        // El mes no existe en el estado financiero anual todavía
        final err = r1.statusCode != 200 ? jsonDecode(r1.body)['error'] : jsonDecode(r2.body)['error'];
        setState(() { _errorMsg = err?.toString(); _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    final now = DateTime.now();
    final esActual = widget.anio == now.year && widget.mes == now.month;
    final esQ1 = esActual && now.day <= 15;

    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 36),
            const SizedBox(height: 12),
            Text('No se pudo cargar la vista quincenal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoBanner(esActual, esQ1),
          const SizedBox(height: 16),
          if (_q1 != null) _QuincenaCard(
            data: _q1!,
            activa: esActual && esQ1,
            cerrada: !esQ1,
            uid: widget.uid,
            anio: widget.anio,
            mes: widget.mes,
            onRefresh: _cargar,
          ),
          const SizedBox(height: 12),
          if (_q2 != null) _QuincenaCard(
            data: _q2!,
            activa: esActual && !esQ1,
            cerrada: !esActual,
            remanenteAnterior: _q1 != null
                ? (double.tryParse(_q1!['disponible'].toString()) ?? 0.0)
                : null,
            uid: widget.uid,
            anio: widget.anio,
            mes: widget.mes,
            onRefresh: _cargar,
          ),
          const SizedBox(height: 20),
          Text(
            'Tus gastos fijos y variables aparecen automáticamente en cada quincena. '
            'Registrar un gasto en el + lo añade a la quincena de su fecha.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner(bool esActual, bool esQ1) {
    if (!esActual) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: AppTheme.primary, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(
          'Estás en la ${esQ1 ? "primera" : "segunda"} quincena (días ${esQ1 ? "1–15" : "16–fin"}).',
          style: const TextStyle(color: AppTheme.primary, fontSize: 12),
        )),
      ]),
    );
  }
}

class _QuincenaCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool activa;
  final bool cerrada;
  final double? remanenteAnterior;
  final String uid;
  final int anio;
  final int mes;
  final VoidCallback onRefresh;
  const _QuincenaCard({
    required this.data,
    required this.activa,
    required this.uid,
    required this.anio,
    required this.mes,
    required this.onRefresh,
    this.cerrada = false,
    this.remanenteAnterior,
  });

  @override
  State<_QuincenaCard> createState() => _QuincenaCardState();
}

class _QuincenaCardState extends State<_QuincenaCard> {
  bool _operando = false;

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  // Mini-sheet de pago parcial para todos los compromisos del Tab Quincenas.
  // Permite registrar múltiples pagos (ej. $20+$20+$40 = $80) contra fijos, variables o deudas.
  Future<void> _abrirPagoParcial(Map<String, dynamic> c) async {
    final id         = c['id'] as int?;
    if (id == null) return;
    final tipo       = c['tipo'] as String? ?? 'fijo';
    final montoPres  = _d(c['monto']);
    final montoPagado = _d(c['monto_pagado'] ?? 0);
    final falta      = (montoPres - montoPagado).clamp(0.0, double.infinity);
    final registroIds = (c['registro_ids'] as List? ?? [])
        .map((e) => (e as num).toInt()).toList();

    final montoCtrl = TextEditingController(
        text: falta > 0.01 ? falta.toStringAsFixed(2) : montoPres.toStringAsFixed(2));
    final esQ1Card = ((widget.data['quincena'] as num?)?.toInt() ?? 1) == 1;
    bool guardando  = false;

    String fmtFecha(DateTime d) =>
        '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    String apiFecha(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

    final hoy = DateTime.now();
    DateTime fecha = (esQ1Card && hoy.day > 15)
        ? DateTime(widget.anio, widget.mes, 1)
        : (!esQ1Card && hoy.day <= 15)
            ? DateTime(widget.anio, widget.mes, 16)
            : hoy;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Registrar pago — ${c['nombre']}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // Resumen presupuestado / pagado / falta
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: _ResumenPago('Presupuestado', montoPres, AppTheme.textSecondary)),
              Expanded(child: _ResumenPago('Pagado', montoPagado, AppTheme.success)),
              Expanded(child: _ResumenPago('Falta', falta > 0 ? falta : 0, AppTheme.warning)),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: '¿Cuánto pagaste?',
              prefixText: 'B/. ',
              suffixIcon: TextButton(
                onPressed: () => setS(() =>
                    montoCtrl.text = (falta > 0.01 ? falta : montoPres).toStringAsFixed(2)),
                child: const Text('Pagar todo', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Selector de fecha (forzada a la quincena correcta)
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: fecha,
                firstDate: DateTime(widget.anio - 1),
                lastDate: DateTime(widget.anio + 1, 12, 31),
              );
              if (picked != null) setS(() => fecha = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today, color: AppTheme.textMuted, size: 16),
                const SizedBox(width: 10),
                Text('Fecha: ${fmtFecha(fecha)}',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                const Spacer(),
                Icon(Icons.edit, color: AppTheme.textMuted, size: 14),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: guardando ? null : () async {
              final monto = double.tryParse(montoCtrl.text);
              if (monto == null || monto <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Monto inválido')));
                return;
              }
              setS(() => guardando = true);
              try {
                final tipoReg = tipo == 'deuda' ? 'fijo' : tipo;
                await RegistrosService.crear(
                  uid: widget.uid,
                  anio: widget.anio,
                  mes: widget.mes,
                  tipo: tipoReg,
                  categoria: tipo == 'deuda' ? 'deudas' : categoriaCanonicaCompromiso(c),
                  nombre: c['nombre'] as String? ?? '',
                  monto: monto,
                  fecha: apiFecha(fecha),
                  origenFijoId:     tipo == 'fijo'     ? id : null,
                  origenVariableId: tipo == 'variable' ? id : null,
                  origenDeudaId:    tipo == 'deuda'    ? id : null,
                  pagado: 1,
                );
                if (!sheetCtx.mounted) return;
                Navigator.pop(sheetCtx);
                widget.onRefresh();
              } catch (e) {
                setS(() => guardando = false);
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
              }
            },
            child: guardando
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Registrar pago'),
          )),
          // Pagos ya registrados (con opción de eliminar)
          if (registroIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pagos de esta quincena',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...registroIds.map((rid) {
              // Buscar el registro en la lista de registros del mes para mostrar monto/fecha
              final regs = (widget.data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
              final reg = regs.firstWhere(
                  (r) => (r['id'] as num?)?.toInt() == rid,
                  orElse: () => {'id': rid, 'monto': 0, 'fecha': ''});
              final rMonto = _d(reg['monto']);
              final rFecha = (reg['fecha']?.toString() ?? '').split('T').first;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.check_circle, color: AppTheme.success, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '${Money.fmt(rMonto)} · $rFecha',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  )),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await RegistrosService.eliminar(widget.uid, rid);
                        if (!sheetCtx.mounted) return;
                        Navigator.pop(sheetCtx);
                        widget.onRefresh();
                      } catch (_) {}
                    },
                    child: Icon(Icons.delete_outline, color: AppTheme.danger, size: 16),
                  ),
                ]),
              );
            }),
          ],
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data       = widget.data;
    final activa     = widget.activa;
    final cerrada    = widget.cerrada;
    final q          = (data['quincena'] as num).toInt();
    final dias       = data['dias'] as String? ?? '';
    final ingQ       = _d(data['ingreso_quincenal']);
    final gastado    = _d(data['total_gastado']);
    final disponible = _d(data['disponible']);
    final registros    = (data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    final compromisos  = (data['compromisos_quincenal'] as List? ?? []).cast<Map<String, dynamic>>();
    final dispColor  = disponible > ingQ * 0.2 ? AppTheme.success
                     : disponible > 0           ? AppTheme.warning
                     : AppTheme.danger;
    final resultadoColor = disponible >= 0 ? AppTheme.success : AppTheme.danger;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activa ? AppTheme.primary
              : cerrada ? AppTheme.border.withValues(alpha: 0.5)
              : AppTheme.border,
          width: activa ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Banner carry-over de Q1 (solo en Q2)
        if (widget.remanenteAnterior != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (widget.remanenteAnterior! >= 0 ? AppTheme.success : AppTheme.danger)
                  .withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(children: [
              Icon(
                widget.remanenteAnterior! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                color: widget.remanenteAnterior! >= 0 ? AppTheme.success : AppTheme.danger,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                widget.remanenteAnterior! >= 0
                    ? 'Remanente Q1: +${Money.fmt(widget.remanenteAnterior!)}'
                    : 'Déficit Q1: ${Money.fmt(widget.remanenteAnterior!)}',
                style: TextStyle(
                  color: widget.remanenteAnterior! >= 0 ? AppTheme.success : AppTheme.danger,
                  fontSize: 12, fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ],

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Quincena $q', style: TextStyle(
                  color: activa ? AppTheme.primary
                      : cerrada ? AppTheme.textSecondary
                      : AppTheme.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (activa)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4)),
                    child: Text('HOY', style: TextStyle(color: AppTheme.background, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                if (cerrada)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultadoColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('CERRADA', style: TextStyle(
                        color: resultadoColor, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
              ]),
              Text('Días $dias', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${Money.fmt(disponible)}',
                  style: TextStyle(color: dispColor, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(cerrada ? 'resultado final' : 'disponible',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        // Barra
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ingQ > 0 ? (gastado / ingQ).clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: AppTheme.border,
              valueColor: AlwaysStoppedAnimation(dispColor),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Ingreso: ${Money.fmt(ingQ)}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            Text('Gastado: ${Money.fmt(gastado)}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ),
        if (compromisos.isNotEmpty) ...[
          Divider(color: AppTheme.border, height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Text('COMPROMISOS',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_operando)
                const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primary)),
            ]),
          ),
          ...compromisos.map((c) {
            final tipo        = c['tipo'] as String? ?? 'fijo';
            final montoPres   = _d(c['monto']);
            final montoPagado = _d(c['monto_pagado'] ?? (c['registro_id'] != null ? montoPres : 0));
            final completo    = montoPagado >= montoPres - 0.01;
            final parcial     = !completo && montoPagado > 0.01;
            final falta       = (montoPres - montoPagado).clamp(0.0, double.infinity);
            final barra       = montoPres > 0 ? (montoPagado / montoPres).clamp(0.0, 1.0) : 0.0;
            final iconColor   = tipo == 'fijo'  ? AppTheme.colorFijo
                              : tipo == 'deuda' ? AppTheme.danger
                              : AppTheme.warning;
            final barColor    = completo ? AppTheme.success : parcial ? AppTheme.warning : AppTheme.surfaceAlt;
            final leadingIcon = tipo == 'fijo'  ? Icons.lock_outline
                              : tipo == 'deuda' ? Icons.credit_card_outlined
                              : Icons.repeat_outlined;

            return GestureDetector(
              onTap: _operando ? null : () => _abrirPagoParcial(c),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: completo
                      ? AppTheme.success.withValues(alpha: 0.05)
                      : parcial
                          ? AppTheme.warning.withValues(alpha: 0.05)
                          : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: completo ? AppTheme.success.withValues(alpha: 0.35)
                         : parcial  ? AppTheme.warning.withValues(alpha: 0.4)
                         : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── Fila superior: ícono + nombre + monto + check ──────
                  Row(children: [
                    Icon(leadingIcon, size: 14,
                        color: completo ? AppTheme.success : parcial ? AppTheme.warning : iconColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      c['nombre'] as String? ?? '—',
                      style: TextStyle(
                        color: completo ? AppTheme.textMuted : AppTheme.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                        decoration: completo ? TextDecoration.lineThrough : null,
                      ),
                    )),
                    Text(
                      Money.fmt(montoPres),
                      style: TextStyle(
                        color: completo ? AppTheme.textMuted
                             : parcial  ? AppTheme.warning
                             : AppTheme.textSecondary,
                        fontSize: 13, fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Círculo de estado
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: completo ? AppTheme.success
                             : parcial  ? AppTheme.warning.withValues(alpha: 0.2)
                             : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: completo ? AppTheme.success
                               : parcial  ? AppTheme.warning
                               : AppTheme.border,
                          width: 1.5,
                        ),
                      ),
                      child: completo
                          ? const Icon(Icons.check, size: 14, color: Colors.black)
                          : parcial
                              ? const Icon(Icons.add, size: 14, color: AppTheme.warning)
                              : null,
                    ),
                  ]),
                  const SizedBox(height: 7),
                  // ── Barra de progreso ───────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: barra,
                      minHeight: 5,
                      color: barColor,
                      backgroundColor: AppTheme.border.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 5),
                  // ── Fila inferior: pagado · falta ───────────────────────
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(
                      completo
                          ? 'Pagado completo ✓'
                          : montoPagado > 0.01
                              ? 'Pagado ${Money.fmt(montoPagado)}'
                              : 'Sin pagos aún',
                      style: TextStyle(
                        color: completo ? AppTheme.success
                             : parcial  ? AppTheme.warning
                             : AppTheme.textMuted,
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!completo)
                      Text(
                        'Falta ${Money.fmt(falta)}',
                        style: TextStyle(
                          color: parcial ? AppTheme.warning : AppTheme.textMuted,
                          fontSize: 10, fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (c['medio'] == true && !parcial && !completo)
                      Text('½ de tu cuota',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                  ]),
                ]),
              ),
            );
          }),
        ],
        if (registros.isNotEmpty) ...[
          Divider(color: AppTheme.border, height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text('${registros.length} gastos registrados',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
          ),
          ...registros.map((r) {
            final esMensual  = r['es_mensual'] == true || r['es_mensual'] == 1;
            final esFactura  = r['scanned_invoice_id'] != null;
            final esGustito  = r['origen_gustito_id'] != null;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: esFactura
                  ? Icon(Icons.qr_code_scanner, size: 15, color: AppTheme.primary)
                  : esGustito
                      ? Icon(Icons.bolt, size: 15, color: AppTheme.colorAhorro)
                      : null,
              title: Row(children: [
                Expanded(child: Text(r['nombre'] as String? ?? '—',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
                if (esMensual)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
                    ),
                    child: const Text('½ mes',
                        style: TextStyle(color: AppTheme.info, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
              ]),
              subtitle: Text(
                r['categoria'] as String? ?? '',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              trailing: Text(Money.fmt(_d(r['monto'])),
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            );
          }),
        ] else if (compromisos.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'Sin compromisos ni gastos en esta quincena aún.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

// ── TAB 4: ANÁLISIS ──────────────────────────────────────────────────────

class _TabAnalisis extends StatefulWidget {
  final Map<String, dynamic> data;
  final String uid;
  const _TabAnalisis({required this.data, required this.uid});

  @override
  State<_TabAnalisis> createState() => _TabAnalisisState();
}

class _TabAnalisisState extends State<_TabAnalisis> {
  List<dynamic> _recomendaciones = [];
  bool _loadingRec = true;

  @override
  void initState() {
    super.initState();
    _cargarRecomendaciones();
  }

  Future<void> _cargarRecomendaciones() async {
    final data = await ProductosCatalogoService.getAnalisisVsPresupuesto(widget.uid);
    if (mounted) setState(() { _recomendaciones = data; _loadingRec = false; });
  }

  double _d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  @override
  Widget build(BuildContext context) {
    final cats = (widget.data['analisis_categorias'] as List? ?? []).cast<Map<String, dynamic>>();
    final conRec = _recomendaciones.where((r) => r['recomendacion'] != null).toList();

    final sorted = List.of(cats)..sort((a, b) {
      final da = _d(a['desviacion']);
      final db = _d(b['desviacion']);
      return db.compareTo(da);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Recomendaciones de aprendizaje ─────────────────────────────
        if (!_loadingRec && conRec.isNotEmpty) ...[
          Text('RECOMENDACIONES', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...conRec.map((r) => _RecomendacionCard(rec: r)),
          const SizedBox(height: 20),
        ],
        if (_loadingRec)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
          ),
        // ── Análisis por categoría este mes ────────────────────────────
        Text('PRESUPUESTADO VS REAL ESTE MES', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.6)),
        const SizedBox(height: 12),
        if (cats.isEmpty)
          Center(child: Text('Agrega gastos para ver el análisis.',
              style: TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center))
        else
          ...sorted.map((c) => _CategoriaCard(cat: c)),
      ],
    );
  }
}

class _RecomendacionCard extends StatelessWidget {
  final dynamic rec;
  const _RecomendacionCard({required this.rec});

  @override
  Widget build(BuildContext context) {
    final r = rec['recomendacion'] as Map<String, dynamic>;
    final tipo = r['tipo'] as String;
    final reducir = tipo == 'reducir';
    final color = reducir ? AppTheme.success : AppTheme.warning;
    final icon = reducir ? Icons.trending_down : Icons.trending_up;
    final presupActual = (r['presupuesto_actual'] as num).toDouble();
    final presupSug = (r['presupuesto_sugerido'] as num).toDouble();
    final ahorro = r['ahorro_mensual_posible'] != null ? (r['ahorro_mensual_posible'] as num).toDouble() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(rec['nombre'] as String,
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(reducir ? 'Optimizar' : 'Revisar',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(r['mensaje'] as String,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        Row(children: [
          _statMin('Actual', '${Money.fmt(presupActual)}', AppTheme.textMuted),
          const SizedBox(width: 16),
          _statMin('Sugerido', '${Money.fmt(presupSug)}', color),
          if (ahorro != null) ...[
            const SizedBox(width: 16),
            _statMin('Ahorro/mes', '${Money.fmt(ahorro)}', AppTheme.success),
          ],
        ]),
      ]),
    );
  }

  Widget _statMin(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
    ],
  );
}

class _CategoriaCard extends StatelessWidget {
  final Map<String, dynamic> cat;
  const _CategoriaCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    final rawCat    = cat['categoria'] as String;
    final nombre    = rawCat.isNotEmpty
        ? '${rawCat[0].toUpperCase()}${rawCat.substring(1)}'
        : rawCat;
    final presup    = double.tryParse(cat['presupuestado'].toString()) ?? 0.0;
    final total     = double.tryParse(cat['total_gastado'].toString()) ?? 0.0;
    final noPres    = double.tryParse(cat['gastado_no_presup'].toString()) ?? 0.0;
    final desv      = double.tryParse(cat['desviacion'].toString()) ?? 0.0;
    final pct       = cat['pct_desviacion'];
    final pctVal    = pct != null ? double.tryParse(pct.toString()) ?? 0.0 : null;
    final excedido  = desv > 0;
    final barVal    = presup > 0 ? (total / presup).clamp(0.0, 1.5) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: excedido && desv > presup * 0.2 ? AppTheme.danger.withOpacity(0.4) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(nombre,
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
          if (pctVal != null && pctVal.abs() > 5)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (excedido ? AppTheme.danger : AppTheme.success).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${excedido ? '+' : ''}${pctVal.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: excedido ? AppTheme.danger : AppTheme.success,
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Presup: ${Money.fmt(presup)}',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
          Expanded(child: Text('Real: ${Money.fmt(total)}',
              style: TextStyle(color: excedido ? AppTheme.danger : AppTheme.success,
                  fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        if (noPres > 0) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('No presupuestado: ${Money.fmt(noPres)}',
              style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: barVal.clamp(0.0, 1.0),
            minHeight: 6,
            color: barVal > 1.0 ? AppTheme.danger : barVal > 0.8 ? AppTheme.warning : AppTheme.success,
            backgroundColor: AppTheme.surfaceAlt,
          ),
        ),
      ]),
    );
  }
}

// ── Card de ingreso real ──────────────────────────────────────────────────────
class _IngresoRealCard extends StatelessWidget {
  final double ingEst;
  final double ingReal;
  final String uid;
  final int anio;
  final int mes;
  final VoidCallback onChanged;

  const _IngresoRealCard({
    required this.ingEst, required this.ingReal,
    required this.uid, required this.anio, required this.mes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tieneReal = ingReal > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tieneReal ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.border,
        ),
      ),
      child: Row(children: [
        Icon(Icons.account_balance_wallet_outlined,
            color: tieneReal ? AppTheme.success : AppTheme.textMuted, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ingreso cobrado este mes',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            tieneReal
                ? '${Money.fmt(ingReal)}'
                : 'Sin registrar — estimado: ${Money.fmt(ingEst)}',
            style: TextStyle(
              color: tieneReal ? AppTheme.success : AppTheme.textMuted,
              fontSize: tieneReal ? 15 : 12,
              fontWeight: tieneReal ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ])),
        TextButton(
          onPressed: () => _mostrarSheet(context),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          child: Text(tieneReal ? 'Editar' : 'Registrar'),
        ),
      ]),
    );
  }

  void _mostrarSheet(BuildContext context) {
    final ctrl = TextEditingController(
        text: ingReal > 0 ? ingReal.toStringAsFixed(2) : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ingreso real del mes',
              style: TextStyle(color: AppTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Estimado: ${Money.fmt(ingEst)}',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Monto cobrado',
              prefixText: 'B/. ',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (val == null || val < 0) return;
                Navigator.pop(ctx);
                try {
                  await EstadoAnualService.registrarIngresoReal(uid, anio, mes, val);
                  onChanged();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e'),
                          backgroundColor: AppTheme.danger));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Card de alerta del mes ────────────────────────────────────────────────────
class _AlertaMesCard extends StatefulWidget {
  final Map<String, dynamic> alerta;
  final String uid;
  const _AlertaMesCard({required this.alerta, required this.uid});

  @override
  State<_AlertaMesCard> createState() => _AlertaMesCardState();
}

class _AlertaMesCardState extends State<_AlertaMesCard> {
  String? _explicacion;
  bool _loadingExp = false;

  Future<void> _explicar() async {
    final id = widget.alerta['id'];
    if (id == null) return;
    setState(() { _loadingExp = true; });
    try {
      final r = await IaService.explicarAlerta(widget.uid, id as int);
      if (mounted) setState(() {
        _explicacion = r['explicacion'] as String?;
        _loadingExp = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerta = widget.alerta;
    final nivel = alerta['nivel'] as String? ?? 'info';
    final color = nivel == 'danger' ? AppTheme.danger
        : nivel == 'warning' ? AppTheme.warning
        : AppTheme.info;
    final icon = nivel == 'danger' ? Icons.error_outline
        : nivel == 'warning' ? Icons.warning_amber_rounded
        : Icons.info_outline;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alerta['titulo'] as String? ?? '',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(alerta['mensaje'] as String? ?? '',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.4)),
            if ((alerta['accion_sugerida'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text('→ ${alerta['accion_sugerida']}',
                  style: TextStyle(color: color, fontSize: 11, fontStyle: FontStyle.italic)),
            ],
          ])),
          if (alerta['id'] != null)
            _loadingExp
                ? SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
                : GestureDetector(
                    onTap: _explicacion == null ? _explicar : () => setState(() => _explicacion = null),
                    child: Icon(
                      _explicacion == null ? Icons.auto_awesome : Icons.close,
                      color: color, size: 15,
                    ),
                  ),
        ]),
        if (_explicacion != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, color: AppTheme.primary, size: 13),
              const SizedBox(width: 6),
              Expanded(child: Text(_explicacion!,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, height: 1.5))),
            ]),
          ),
        ],
      ]),
    );
  }
}
