import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';
import 'services/registros_service.dart';
import 'widgets/financiero/agregar_gasto_sheet.dart';
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
    _tabs = TabController(length: 3, vsync: this);
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
                        onChanged: _cargar,
                      ),
                      _TabGastos(
                        data: _data!,
                        uid: widget.firebaseUid,
                        onChanged: _cargar,
                      ),
                      _TabAnalisis(data: _data!),
                    ],
                  ),
                ),
    );
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
  final VoidCallback onChanged;

  const _TabResumen({
    required this.data,
    required this.alertas,
    required this.uid,
    required this.anio,
    required this.mes,
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
    final remEst  = _d(r['remanente_estimado']);
    final remReal = _d(r['remanente_real']);
    final sano    = r['presupuesto_sano'] as bool? ?? true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Banner de estado
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sano ? AppTheme.success.withOpacity(0.08) : AppTheme.danger.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sano ? AppTheme.success.withOpacity(0.3) : AppTheme.danger.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(sano ? Icons.check_circle : Icons.warning_amber_rounded,
                color: sano ? AppTheme.success : AppTheme.danger, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(
              sano ? 'Mes bajo control' : 'Gasto mayor al ingreso',
              style: TextStyle(
                color: sano ? AppTheme.success : AppTheme.danger,
                fontWeight: FontWeight.w700, fontSize: 14,
              ),
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

        // Tabla estimado vs real
        _seccion('BALANCE DEL MES'),
        _FilaComparativa('Ingreso', ingEst, ingReal, AppTheme.success),
        _FilaComparativa('Gastos fijos', fijosEst, fijosReal, AppTheme.colorFijo),
        _FilaComparativa('Gastos variables', varEst, varReal, AppTheme.warning),
        if (noPres > 0) _FilaComparativa('No presupuestados', 0, noPres, AppTheme.danger),
        const Divider(color: AppTheme.border, height: 24),
        _FilaComparativa('Remanente', remEst, remReal,
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
    final registros = (data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    if (registros.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.receipt_long, color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          const Text('Sin gastos registrados', style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          const Text('Presiona + para agregar', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: registros.length,
      separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
      itemBuilder: (_, i) => _RegistroTile(reg: registros[i], uid: uid, onChanged: onChanged),
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

    if (gastosFijos.isEmpty && deudas.isEmpty) return const SizedBox.shrink();

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

// ── TAB 3: ANÁLISIS ──────────────────────────────────────────────────────

class _TabAnalisis extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TabAnalisis({required this.data});

  @override
  Widget build(BuildContext context) {
    final cats = (data['analisis_categorias'] as List? ?? []).cast<Map<String, dynamic>>();
    if (cats.isEmpty) {
      return const Center(child: Text('Agrega gastos para ver el análisis por categoría.',
          style: TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center));
    }

    // Ordenar por desviación descendente
    final sorted = List.of(cats)..sort((a, b) {
      final da = double.tryParse(a['desviacion'].toString()) ?? 0.0;
      final db = double.tryParse(b['desviacion'].toString()) ?? 0.0;
      return db.compareTo(da);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Presupuestado vs Real por categoría',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.6)),
        const SizedBox(height: 12),
        ...sorted.map((c) => _CategoriaCard(cat: c)),
      ],
    );
  }
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
