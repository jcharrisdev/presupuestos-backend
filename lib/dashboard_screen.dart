import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'cobros_home.dart';

class DashboardScreen extends StatefulWidget {
  final String firebaseUid;
  const DashboardScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _presupuesto;
  Map<String, dynamic>? _proximoCobro;
  Map<String, dynamic>? _metaAhorro;
  Map<String, dynamic>? _resumenVentas;

  bool _loadingPresupuesto = true;
  bool _loadingCobro = true;
  bool _loadingAhorro = true;
  bool _loadingVentas = true;

  String? _errorPresupuesto;
  String? _errorCobro;
  String? _errorAhorro;
  String? _errorVentas;

  final fmt = NumberFormat('#,##0.00', 'es');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final now = DateTime.now();
    setState(() {
      _loadingPresupuesto = true;
      _loadingCobro = true;
      _loadingAhorro = true;
      _loadingVentas = true;
      _errorPresupuesto = null;
      _errorCobro = null;
      _errorAhorro = null;
      _errorVentas = null;
    });

    await Future.wait([
      _cargarPresupuesto(),
      _cargarProximoCobro(now.month, now.year),
      _cargarAhorro(),
      _cargarVentas(),
    ]);
  }

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

  Future<void> _cargarProximoCobro(int mes, int anio) async {
    try {
      final res = await ApiClient.get(
        '/calendario/eventos?firebase_uid=${widget.firebaseUid}&mes=$mes&anio=$anio',
      );
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        final pendientes = list
            .where((e) => e['estado'] == 'pendiente' && e['tipo'] == 'cobro')
            .toList();
        pendientes.sort((a, b) => (a['fecha_evento'] as String).compareTo(b['fecha_evento'] as String));
        if (mounted) setState(() {
          _proximoCobro = pendientes.isNotEmpty ? pendientes.first : null;
          _loadingCobro = false;
        });
      } else {
        if (mounted) setState(() { _errorCobro = 'Error ${res.statusCode}'; _loadingCobro = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorCobro = e.toString(); _loadingCobro = false; });
    }
  }

  Future<void> _cargarAhorro() async {
    try {
      final res = await ApiClient.get('/ahorros?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        if (list.isEmpty) {
          if (mounted) setState(() { _metaAhorro = null; _loadingAhorro = false; });
          return;
        }
        Map<String, dynamic>? mejorMeta;
        double mejorPct = -1;
        for (final m in list) {
          final meta = double.tryParse(m['monto']?.toString() ?? '0') ?? 0;
          final ahorrado = double.tryParse(m['total_ahorrado']?.toString() ?? '0') ?? 0;
          final pct = meta > 0 ? ahorrado / meta : 0;
          if (pct > mejorPct) { mejorPct = pct.toDouble(); mejorMeta = Map<String, dynamic>.from(m); }
        }
        if (mounted) setState(() { _metaAhorro = mejorMeta; _loadingAhorro = false; });
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
        double totalCobrado = 0;
        for (final v in activas) {
          totalCobrado += double.tryParse(v['total_cobrado']?.toString() ?? '0') ?? 0;
        }
        if (mounted) setState(() {
          _resumenVentas = {'cantidad': activas.length, 'total_cobrado': totalCobrado};
          _loadingVentas = false;
        });
      } else {
        if (mounted) setState(() { _errorVentas = 'Error ${res.statusCode}'; _loadingVentas = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorVentas = e.toString(); _loadingVentas = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Container(
        color: AppTheme.background,
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPresupuestoCard(),
              const SizedBox(height: 12),
              _buildCobroCard(),
              const SizedBox(height: 12),
              _buildAhorroCard(),
              const SizedBox(height: 12),
              _buildVentasCard(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeleton({double height = 100}) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border),
    ),
  );

  Widget _cardWrapper({required String title, required Color accentColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _errorCard(String title, Color accent, String error, VoidCallback onRetry) {
    return _cardWrapper(
      title: title,
      accentColor: accent,
      child: Column(
        children: [
          Text('Error al cargar', style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildPresupuestoCard() {
    if (_loadingPresupuesto) return _skeleton(height: 110);
    if (_errorPresupuesto != null) return _errorCard('PERÍODO ACTUAL', AppTheme.colorFijo, _errorPresupuesto!, _cargarPresupuesto);
    if (_presupuesto == null) {
      return _cardWrapper(
        title: 'PERÍODO ACTUAL',
        accentColor: AppTheme.colorFijo,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sin presupuestos activos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ListaPresupuestos(firebaseUid: widget.firebaseUid),
              )),
              child: const Text('Crear mi primer presupuesto'),
            ),
          ],
        ),
      );
    }

    final monto = double.tryParse(_presupuesto!['monto_total']?.toString() ?? '0') ?? 0;
    final nombre = _presupuesto!['nombre'] ?? '';
    return _cardWrapper(
      title: 'PERÍODO ACTUAL',
      accentColor: AppTheme.colorFijo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Monto total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('\$${fmt.format(monto)}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCobroCard() {
    if (_loadingCobro) return _skeleton(height: 100);
    if (_errorCobro != null) return _errorCard('PRÓXIMO COBRO', AppTheme.success, _errorCobro!, () => _cargarProximoCobro(DateTime.now().month, DateTime.now().year));
    if (_proximoCobro == null) {
      return _cardWrapper(
        title: 'PRÓXIMO COBRO',
        accentColor: AppTheme.success,
        child: const Text('Sin cobros pendientes este mes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      );
    }

    final titulo = _proximoCobro!['titulo'] ?? '';
    final monto = double.tryParse(_proximoCobro!['monto_esperado']?.toString() ?? '0') ?? 0;
    final fecha = _proximoCobro!['fecha_evento'] ?? '';
    return _cardWrapper(
      title: 'PRÓXIMO COBRO',
      accentColor: AppTheme.success,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(fecha, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('\$${fmt.format(monto)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildAhorroCard() {
    if (_loadingAhorro) return _skeleton(height: 110);
    if (_errorAhorro != null) return _errorCard('AHORRO', AppTheme.colorAhorro, _errorAhorro!, _cargarAhorro);
    if (_metaAhorro == null) {
      return _cardWrapper(
        title: 'AHORRO',
        accentColor: AppTheme.colorAhorro,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sin metas de ahorro', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AhorroMetaScreen(firebaseUid: widget.firebaseUid),
              )),
              child: const Text('Crear meta de ahorro'),
            ),
          ],
        ),
      );
    }

    final nombre = _metaAhorro!['descripcion'] ?? _metaAhorro!['nombre'] ?? '';
    final meta = double.tryParse(_metaAhorro!['monto']?.toString() ?? '0') ?? 0;
    final ahorrado = double.tryParse(_metaAhorro!['total_ahorrado']?.toString() ?? '0') ?? 0;
    final pct = meta > 0 ? (ahorrado / meta).clamp(0.0, 1.0) : 0.0;

    return _cardWrapper(
      title: 'AHORRO',
      accentColor: AppTheme.colorAhorro,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: const AlwaysStoppedAnimation(AppTheme.colorAhorro),
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$${fmt.format(ahorrado)} ahorrado', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('Meta: \$${fmt.format(meta)}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVentasCard() {
    if (_loadingVentas) return _skeleton(height: 90);
    if (_errorVentas != null) return _errorCard('VENTAS DEL MES', AppTheme.primary, _errorVentas!, _cargarVentas);
    if (_resumenVentas == null || _resumenVentas!['cantidad'] == 0) {
      return _cardWrapper(
        title: 'VENTAS DEL MES',
        accentColor: AppTheme.primary,
        child: Row(
          children: [
            const Icon(Icons.trending_flat, color: AppTheme.textMuted, size: 20),
            const SizedBox(width: 8),
            const Text('Sin ventas activas', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CobrosHome(firebaseUid: widget.firebaseUid),
              )),
              child: const Text('Ver cobros'),
            ),
          ],
        ),
      );
    }

    final cantidad = _resumenVentas!['cantidad'] as int;
    final totalCobrado = _resumenVentas!['total_cobrado'] as double;

    return _cardWrapper(
      title: 'VENTAS DEL MES',
      accentColor: AppTheme.primary,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$cantidad ventas activas', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Total cobrado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text('\$${fmt.format(totalCobrado)}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
    );
  }
}
