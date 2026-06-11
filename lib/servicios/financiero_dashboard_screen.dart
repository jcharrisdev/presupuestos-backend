import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/servicios_service.dart';
import '../utils/money.dart';

class FinancieroDashboardScreen extends StatefulWidget {
  final String firebaseUid;
  const FinancieroDashboardScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _FinancieroDashboardScreenState createState() => _FinancieroDashboardScreenState();
}

class _FinancieroDashboardScreenState extends State<FinancieroDashboardScreen> {
  List<dynamic> _jobs = [];
  bool _loading = true;

  // Agregados de todos los trabajos
  double _totalContratado = 0;
  double _totalRecibido = 0;
  double _saldoPendiente = 0;
  double _totalGastos = 0;
  double _totalPagosColab = 0;
  double _utilidadNeta = 0;
  double _margenPromedio = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final jobs = await ServiciosService.getJobs(widget.firebaseUid);
      double contratado = 0, recibido = 0, gastos = 0, pagosColab = 0;
      double sumMargen = 0;
      int countConIngresos = 0;

      for (final j in jobs) {
        final mt = double.tryParse(j['monto_total']?.toString() ?? '0') ?? 0;
        final tr = double.tryParse(j['total_recibido']?.toString() ?? '0') ?? 0;
        final tg = double.tryParse(j['total_gastos']?.toString() ?? '0') ?? 0;
        final tp = double.tryParse(j['total_pagos_colaboradores']?.toString() ?? '0') ?? 0;
        contratado += mt;
        recibido += tr;
        gastos += tg;
        pagosColab += tp;
        if (tr > 0) {
          final u = tr - tg - tp;
          sumMargen += (u / tr) * 100;
          countConIngresos++;
        }
      }

      final utilidad = recibido - gastos - pagosColab;
      final margen = countConIngresos > 0 ? sumMargen / countConIngresos : 0.0;

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _totalContratado = contratado;
          _totalRecibido = recibido;
          _saldoPendiente = contratado - recibido;
          _totalGastos = gastos;
          _totalPagosColab = pagosColab;
          _utilidadNeta = utilidad;
          _margenPromedio = margen;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Dashboard financiero',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Vista global de las finanzas de todos tus trabajos de servicio:\n\n'
          '• Total contratado — suma de montos acordados en todos los trabajos.\n'
          '• Total recibido — suma de pagos recibidos de clientes.\n'
          '• Saldo pendiente — dinero que aún no has cobrado.\n'
          '• Gastos operativos — suma de todos los gastos registrados.\n'
          '• Pagos a colaboradores — suma de pagos realizados a tu equipo.\n'
          '• Utilidad neta — Total recibido menos gastos y pagos a colaboradores.\n'
          '• Margen promedio — rentabilidad promedio entre todos los trabajos con ingresos.\n\n'
          'Desliza hacia abajo para actualizar los datos.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard financiero'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tarjetas de resumen global
                  _sectionTitle('Ingresos'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _metricCard('Total contratado', _totalContratado, AppTheme.textPrimary, Icons.handshake_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _metricCard('Total recibido', _totalRecibido, AppTheme.success, Icons.check_circle_outline)),
                  ]),
                  const SizedBox(height: 12),
                  _metricCardWide('Saldo pendiente de clientes', _saldoPendiente, AppTheme.primary, Icons.pending_outlined),
                  const SizedBox(height: 20),
                  _sectionTitle('Costos'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _metricCard('Gastos operativos', _totalGastos, AppTheme.danger, Icons.receipt_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _metricCard('Pagos a colaboradores', _totalPagosColab, AppTheme.danger, Icons.group_outlined)),
                  ]),
                  const SizedBox(height: 20),
                  _sectionTitle('Resultado'),
                  const SizedBox(height: 8),
                  _utilidadCard(),
                  const SizedBox(height: 20),
                  if (_jobs.isNotEmpty) ...[
                    _sectionTitle('Por trabajo (${_jobs.length})'),
                    const SizedBox(height: 8),
                    ..._jobs.map((j) => _jobRow(j)).toList(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      );

  Widget _metricCard(String label, double valor, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Text('${Money.fmt(valor)}',
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _metricCardWide(String label, double valor, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
            Text('${Money.fmt(valor)}',
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _utilidadCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (_utilidadNeta >= 0 ? AppTheme.success : AppTheme.danger).withOpacity(0.4),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_outlined,
                    color: _utilidadNeta >= 0 ? AppTheme.success : AppTheme.danger, size: 22),
                const SizedBox(width: 10),
                Text('Utilidad neta global',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const Spacer(),
                Text(
                  '${Money.fmt(_utilidadNeta)}',
                  style: TextStyle(
                    color: _utilidadNeta >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Margen de rentabilidad promedio',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Text(
                  '${_margenPromedio.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _margenPromedio >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _jobRow(Map<String, dynamic> job) {
    final recibido = double.tryParse(job['total_recibido']?.toString() ?? '0') ?? 0;
    final gastos = double.tryParse(job['total_gastos']?.toString() ?? '0') ?? 0;
    final pagosColab = double.tryParse(job['total_pagos_colaboradores']?.toString() ?? '0') ?? 0;
    final utilidad = recibido - gastos - pagosColab;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job['nombre'] as String? ?? '',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                if (job['nombre_cliente'] != null)
                  Text(job['nombre_cliente'] as String,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${Money.fmt(recibido)}',
                  style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Utilidad: ${Money.fmt(utilidad)}',
                  style: TextStyle(
                    color: utilidad >= 0 ? AppTheme.success : AppTheme.danger,
                    fontSize: 11,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
