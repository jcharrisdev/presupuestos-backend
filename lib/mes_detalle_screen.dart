import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/estado_anual_service.dart';
import 'services/pdf_service.dart';
import 'services/registros_service.dart';
import 'services/productos_catalogo_service.dart';
import 'widgets/ayuda_sheet.dart';
import 'widgets/financiero/agregar_gasto_sheet.dart';
import 'widgets/financiero/cierre_mes_sheet.dart';
import 'invoice_scanner/invoice_scanner_screen.dart';

class MesDetalleScreen extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final int mes;
  final String label;

  const MesDetalleScreen({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    required this.mes,
    required this.label,
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
                    'Toca un gasto para marcarlo como pagado. No afecta el monto real, solo el control visual.'),
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
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
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
                        uid: widget.firebaseUid,
                        onChanged: _cargar,
                      ),
                      _TabQuincenas(
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
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgregarGastoSheet(
        firebaseUid: widget.firebaseUid,
        anio: widget.anio,
        mes: widget.mes,
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: BoxDecoration(
            color: dispColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dispColor.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Column(children: [
            Text(
              hayReal ? 'Te queda disponible' : 'Estimado disponible',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              '\$${disponible.toStringAsFixed(2)}',
              style: TextStyle(color: dispColor, fontSize: 38, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              hayReal
                  ? 'de \$${ingresoRef.toStringAsFixed(2)} · ya gastaste \$${yaGastado.toStringAsFixed(2)}'
                  : 'basado en tu planificación — registra gastos para ver el real',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Banner sano / en déficit
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
          ...alertas.map((a) => _AlertaMesCard(alerta: a)),
        ],

        const SizedBox(height: 20),

        // Tabla planificado vs real
        _seccion('LO QUE PLANIFICASTE VS LO QUE GASTASTE'),
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
                '— \$${hormigaTotal.toStringAsFixed(2)} en total este mes',
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
        const Divider(color: AppTheme.border, height: 24),
        _FilaComparativa('Te sobra', remEst, remReal,
            remReal >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
        const SizedBox(height: 24),

        // Barra de progreso de uso del mes
        _seccion('USO DEL INGRESO'),
        const SizedBox(height: 8),
        _BarraUso(ingreso: ingReal > 0 ? ingReal : ingEst,
            fijos: fijosReal, variables: varReal, noPres: noPres),
        const SizedBox(height: 24),

        // Compromisos fijos del mes
        _CompromisosSection(data: data),

        // Botón cierre mensual (solo si el mes está activo)
        if ((data['mes']?['estado'] as String? ?? '') == 'activo') ...[
          const SizedBox(height: 28),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Cerrar mes'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
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
          const Text(
            'El cierre guarda un snapshot del mes y lo marca como histórico.',
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
    child: Text(t, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
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
        Expanded(flex: 2, child: Text('\$${estimado.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        Expanded(flex: 2, child: Text('\$${real.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: bold ? 15 : 13))),
        if (estimado > 0) SizedBox(
          width: 56,
          child: Text(
            '${diff >= 0 ? '+' : ''}\$${diff.toStringAsFixed(0)}',
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
      Text('${(pct * 100).toStringAsFixed(1)}% del ingreso usado · \$${total.toStringAsFixed(2)} de \$${ingreso.toStringAsFixed(2)}',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]);
  }
}

// ── TAB 2: GASTOS ────────────────────────────────────────────────────────

class _TabGastos extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  final VoidCallback onChanged;
  const _TabGastos({required this.data, required this.uid, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final registros    = (data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    final compromisos  = data['compromisos_fijos'] as Map<String, dynamic>? ?? {};
    final gastosFijos  = (compromisos['gastos_fijos'] as List? ?? []).cast<Map<String, dynamic>>();
    final deudas       = (compromisos['deudas'] as List? ?? []).cast<Map<String, dynamic>>();

    // IDs de registros que ya tienen origen_id vinculado a un gasto fijo
    final registradosIds = registros
        .where((r) => r['origen_fijo_id'] != null)
        .map((r) => r['origen_fijo_id'] as int)
        .toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // ── COMPROMISOS FIJOS DEL MES ──────────────────────────────────
        if (gastosFijos.isNotEmpty || deudas.isNotEmpty) ...[
          _SeccionLabel('COMPROMISOS DEL MES',
              '${gastosFijos.length + deudas.length} ítems planificados'),
          ...gastosFijos.map((g) {
            final pagado = registradosIds.contains(g['id'] as int? ?? -1);
            return _PlanTile(
              nombre: g['nombre'] as String? ?? '',
              monto: (g['monto'] as num).toDouble(),
              tipo: g['tipo'] as String? ?? 'otro',
              pagado: pagado,
              esPago: false,
            );
          }),
          ...deudas.map((d) => _PlanTile(
            nombre: d['nombre'] as String? ?? '',
            monto: (d['cuota'] as num? ?? 0).toDouble(),
            tipo: 'deuda',
            pagado: false,
            esPago: true,
            cuotasRestantes: d['cuotas_restantes'] as int?,
          )),
          const Divider(color: AppTheme.border, height: 24),
        ],

        // ── REGISTROS REALES ───────────────────────────────────────────
        if (registros.isNotEmpty) ...[
          _SeccionLabel('GASTOS REGISTRADOS', '${registros.length} transacciones'),
          ...registros.map((r) => _RegistroTile(reg: r, uid: uid, onChanged: onChanged)),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.textMuted, size: 16),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Aún no registraste gastos reales. Presiona + para agregar o escanea una factura QR.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              )),
            ]),
          ),
      ],
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
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 0.6))),
      Text(subtitulo, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]),
  );
}

class _PlanTile extends StatelessWidget {
  final String nombre;
  final double monto;
  final String tipo;
  final bool pagado;
  final bool esPago;
  final int? cuotasRestantes;
  const _PlanTile({
    required this.nombre, required this.monto, required this.tipo,
    required this.pagado, required this.esPago,
    this.cuotasRestantes,
  });

  @override
  Widget build(BuildContext context) {
    final color = tipo == 'deuda' ? AppTheme.danger
        : tipo == 'vivienda' ? AppTheme.colorFijo
        : AppTheme.colorFijo;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pagado ? AppTheme.success.withOpacity(0.06) : AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pagado ? AppTheme.success.withOpacity(0.3) : AppTheme.border,
        ),
      ),
      child: Row(children: [
        Icon(
          pagado ? Icons.check_circle : (esPago ? Icons.credit_card_outlined : Icons.receipt_outlined),
          color: pagado ? AppTheme.success : color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontSize: 13, fontWeight: FontWeight.w600,
          )),
          if (cuotasRestantes != null)
            Text('$cuotasRestantes cuotas restantes',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}',
              style: TextStyle(
                color: pagado ? AppTheme.textSecondary : color,
                fontWeight: FontWeight.w700, fontSize: 13,
              )),
          if (pagado)
            const Text('Registrado', style: TextStyle(color: AppTheme.success, fontSize: 9)),
          if (!pagado)
            const Text('Pendiente', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
        ]),
      ]),
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
    final tipo  = reg['tipo'] as String;
    final monto = double.tryParse(reg['monto'].toString()) ?? 0.0;
    final color = tipo == 'fijo' ? AppTheme.colorFijo
        : tipo == 'no_presupuestado' ? AppTheme.danger
        : AppTheme.warning;
    final tipoLabel = tipo == 'fijo' ? 'Fijo'
        : tipo == 'no_presupuestado' ? 'No presup.'
        : 'Variable';
    final pagado = (reg['pagado'] as int? ?? 0) == 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(_iconCategoria(reg['categoria'] as String? ?? ''), color: color, size: 16),
      ),
      title: Text(reg['nombre'] as String? ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
      subtitle: Text('${reg['categoria']} · $tipoLabel',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('\$${monto.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Icon(pagado ? Icons.check_circle : Icons.radio_button_unchecked,
            color: pagado ? AppTheme.success : AppTheme.textMuted, size: 14),
      ]),
      onTap: () => _opciones(context),
    );
  }

  void _opciones(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: AppTheme.success),
            title: const Text('Marcar pagado/pendiente', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () async {
              Navigator.pop(context);
              final pagado = (reg['pagado'] as int? ?? 0) == 1;
              await RegistrosService.marcarPagado(uid, reg['id'] as int, !pagado);
              onChanged();
            },
          ),
          if (reg['tipo'] == 'no_presupuestado') ListTile(
            leading: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            title: const Text('Convertir a gasto variable base', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () async {
              Navigator.pop(context);
              await RegistrosService.convertirAVariable(uid, reg['id'] as int);
              onChanged();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Agregado a tu presupuesto variable')));
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
      const Text('COMPROMISOS DEL MES',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
      const SizedBox(height: 4),
      const Text('Gastos fijos y deudas activos este mes',
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
          Text(nombre, style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w600)),
          if (subtitulo.isNotEmpty)
            Text(subtitulo, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ])),
        Text('\$${monto.toStringAsFixed(2)}',
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
  const _TabQuincenas({required this.uid, required this.anio, required this.mes});
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
    _cargar();
  }

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
            const Text('No se pudo cargar la vista quincenal.',
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
          if (_q1 != null) _QuincenaCard(data: _q1!, activa: esActual && esQ1),
          const SizedBox(height: 12),
          if (_q2 != null) _QuincenaCard(data: _q2!, activa: esActual && !esQ1),
          const SizedBox(height: 20),
          const Text(
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

class _QuincenaCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool activa;
  const _QuincenaCard({required this.data, required this.activa});

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
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
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activa ? AppTheme.primary : AppTheme.border,
          width: activa ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Quincena $q', style: TextStyle(
                  color: activa ? AppTheme.primary : AppTheme.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
                if (activa) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4)),
                    child: const Text('HOY', style: TextStyle(color: AppTheme.background, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              Text('Días $dias', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${disponible.toStringAsFixed(2)}',
                  style: TextStyle(color: dispColor, fontSize: 22, fontWeight: FontWeight.w800)),
              const Text('disponible', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
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
            Text('Ingreso: \$${ingQ.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            Text('Gastado: \$${gastado.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ),
        if (compromisos.isNotEmpty) ...[
          const Divider(color: AppTheme.border, height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: const Text('COMPROMISOS DEL MES',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
          ),
          ...compromisos.map((c) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            leading: Icon(
              (c['tipo'] as String? ?? '') == 'fijo' ? Icons.lock_outline : Icons.repeat_outlined,
              size: 15,
              color: (c['tipo'] as String? ?? '') == 'fijo' ? AppTheme.colorFijo : AppTheme.warning,
            ),
            title: Text(c['nombre'] as String? ?? '—',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            trailing: Text('\$${_d(c['monto']).toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          )),
        ],
        if (registros.isNotEmpty) ...[
          const Divider(color: AppTheme.border, height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text('${registros.length} gastos registrados',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
          ),
          ...registros.take(5).map((r) {
            final esMensual = r['es_mensual'] == true || r['es_mensual'] == 1;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              title: Row(children: [
                Expanded(child: Text(r['nombre'] as String? ?? '—',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
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
              subtitle: Text(r['categoria'] as String? ?? '',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              trailing: Text('\$${_d(r['monto']).toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            );
          }),
          if (registros.length > 5)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text('+${registros.length - 5} más',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ),
        ] else if (compromisos.isEmpty)
          const Padding(
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
          const Text('RECOMENDACIONES', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
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
        const Text('PRESUPUESTADO VS REAL ESTE MES', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.6)),
        const SizedBox(height: 12),
        if (cats.isEmpty)
          const Center(child: Text('Agrega gastos para ver el análisis.',
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
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(reducir ? 'Optimizar' : 'Revisar',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(r['mensaje'] as String,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        Row(children: [
          _statMin('Actual', '\$${presupActual.toStringAsFixed(2)}', AppTheme.textMuted),
          const SizedBox(width: 16),
          _statMin('Sugerido', '\$${presupSug.toStringAsFixed(2)}', color),
          if (ahorro != null) ...[
            const SizedBox(width: 16),
            _statMin('Ahorro/mes', '\$${ahorro.toStringAsFixed(2)}', AppTheme.success),
          ],
        ]),
      ]),
    );
  }

  Widget _statMin(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
    ],
  );
}

class _CategoriaCard extends StatelessWidget {
  final Map<String, dynamic> cat;
  const _CategoriaCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    final nombre    = cat['categoria'] as String;
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
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
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
          Expanded(child: Text('Presup: \$${presup.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
          Expanded(child: Text('Real: \$${total.toStringAsFixed(2)}',
              style: TextStyle(color: excedido ? AppTheme.danger : AppTheme.success,
                  fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        if (noPres > 0) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('No presupuestado: \$${noPres.toStringAsFixed(2)}',
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
          const Text('Ingreso cobrado este mes',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            tieneReal
                ? '\$${ingReal.toStringAsFixed(2)}'
                : 'Sin registrar — estimado: \$${ingEst.toStringAsFixed(2)}',
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
          const Text('Ingreso real del mes',
              style: TextStyle(color: AppTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Estimado: \$${ingEst.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Monto cobrado',
              prefixText: '\$ ',
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
class _AlertaMesCard extends StatelessWidget {
  final Map<String, dynamic> alerta;
  const _AlertaMesCard({required this.alerta});

  @override
  Widget build(BuildContext context) {
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alerta['titulo'] as String? ?? '',
              style: TextStyle(color: color,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(alerta['mensaje'] as String? ?? '',
              style: const TextStyle(color: AppTheme.textSecondary,
                  fontSize: 11, height: 1.4)),
          if ((alerta['accion_sugerida'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text('→ ${alerta['accion_sugerida']}',
                style: TextStyle(color: color, fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
        ])),
      ]),
    );
  }
}
