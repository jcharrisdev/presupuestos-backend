import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';
import 'mes_detalle_screen.dart';
import 'perfil_financiero_screen.dart';
import 'invoice_scanner/invoice_scanner_screen.dart';
import 'cierre_anio_screen.dart';
import 'alertas_screen.dart';

class EstadoFinancieroAnualScreen extends StatefulWidget {
  final String firebaseUid;
  const EstadoFinancieroAnualScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<EstadoFinancieroAnualScreen> createState() => _EstadoFinancieroAnualScreenState();
}

class _EstadoFinancieroAnualScreenState extends State<EstadoFinancieroAnualScreen> {
  final int _anio = DateTime.now().year;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _sinPerfil = false;
  bool _mesesExpanded = false;
  int _alertasCount = 0;
  Map<int, Map<String, dynamic>> _alertasResumen = {};

  static const _mesesLabel = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  void initState() {
    super.initState();
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
      } catch (_) {}
      try {
        final resumen = await EstadoAnualService.getResumenAlertas(widget.firebaseUid, _anio);
        final porMes = (resumen['por_mes'] as Map? ?? {})
            .map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, Map<String, dynamic>.from(v as Map)));
        if (mounted) setState(() => _alertasResumen = porMes);
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
        title: Text('Estado Financiero $_anio'),
        actions: [
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
        const Text('Configura tu perfil primero',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const Text(
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
    final ea = _data!['estado_anual'] as Map<String, dynamic>;
    final meses = (_data!['meses'] as List).cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CardAnual(ea: ea, anio: _anio, onTap: () => setState(() => _mesesExpanded = !_mesesExpanded)),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('MESES DEL AÑO',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
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
        const Divider(color: AppTheme.border),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.lock_outline, size: 16),
          label: Text('Cerrar año $_anio / Proyección ${_anio + 1}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.border),
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

class _CardAnual extends StatelessWidget {
  final Map<String, dynamic> ea;
  final int anio;
  final VoidCallback onTap;
  const _CardAnual({required this.ea, required this.anio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ingresoEst  = _d(ea['ingreso_anual_estimado']);
    final fijosEst    = _d(ea['gastos_fijos_anuales']);
    final varEst      = _d(ea['gastos_variables_anuales']);
    final remEst      = _d(ea['remanente_anual_estimado']);
    final ingresoReal = _d(ea['ingreso_anual_real']);
    final fijosReal   = _d(ea['gastos_fijos_reales']);
    final varReal     = _d(ea['gastos_variables_reales']);
    final noPres      = _d(ea['compras_no_presup_reales']);
    final remReal     = _d(ea['remanente_anual_real']);
    final tieneReal   = ingresoReal > 0 || fijosReal > 0;

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
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            const Icon(Icons.expand_more, color: AppTheme.textMuted, size: 20),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(flex: 1, child: SizedBox()),
            Expanded(child: _Col('Estimado', color: AppTheme.textSecondary)),
            Expanded(child: _Col('Real', color: AppTheme.primary)),
          ]),
          const SizedBox(height: 10),
          _Fila('Ingreso anual', ingresoEst, tieneReal ? ingresoReal : null, AppTheme.success),
          _Fila('Gastos fijos', fijosEst, tieneReal ? fijosReal : null, AppTheme.danger),
          _Fila('Gastos variables', varEst, tieneReal ? varReal : null, AppTheme.warning),
          if (tieneReal) _Fila('No presupuestados', 0, noPres, AppTheme.danger),
          const Divider(color: AppTheme.border, height: 24),
          _Fila('Remanente', remEst, tieneReal ? remReal : null,
              remReal >= 0 ? AppTheme.success : AppTheme.danger, bold: true),
        ]),
      ),
    );
  }

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
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
        Expanded(child: Text('\$${estimado.toStringAsFixed(2)}', style: style.copyWith(color: AppTheme.textSecondary))),
        Expanded(child: real != null
            ? Text('\$${real!.toStringAsFixed(2)}',
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
  final Map<String, dynamic>? alertasBadge;
  final VoidCallback onTap;
  const _MesCard({required this.mes, required this.label, this.data, this.alertasBadge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final estado = data?['estado'] as String? ?? 'futuro';
    final remReal = data != null ? _d(data!['remanente_real']) : null;
    final remEst  = data != null ? _d(data!['remanente_estimado']) : null;
    final esActual = estado == 'activo';
    final esCerrado = estado == 'cerrado';

    Color borderColor = AppTheme.border;
    if (esActual) borderColor = AppTheme.primary;
    if (esCerrado && remReal != null && remReal < 0) borderColor = AppTheme.danger;

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
              color: esActual ? AppTheme.primary.withOpacity(0.08) : AppTheme.surface,
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
                if (esCerrado && remReal != null)
                  Text('\$${remReal.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, color: remReal >= 0 ? AppTheme.success : AppTheme.danger, fontWeight: FontWeight.w600))
                else if (remEst != null)
                  Text('\$${remEst.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))
                else
                  const Text('—', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (esActual)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)),
                    child: const Text('HOY', style: TextStyle(color: AppTheme.background, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
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
        color: AppTheme.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
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
