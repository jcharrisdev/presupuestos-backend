import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/servicios_service.dart';
import '../invoice_scanner/invoice_scanner_screen.dart';
import 'crear_trabajo_screen.dart';
import 'trabajo_detalle_screen.dart';
import 'financiero_dashboard_screen.dart';
import '../utils/money.dart';

class ServiciosDashboard extends StatefulWidget {
  final String firebaseUid;
  const ServiciosDashboard({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _ServiciosDashboardState createState() => _ServiciosDashboardState();
}

class _ServiciosDashboardState extends State<ServiciosDashboard> {
  List<dynamic> _jobs = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _cargarJobs();
  }

  Future<void> _cargarJobs({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    else setState(() => _refreshing = true);
    try {
      final jobs = await ServiciosService.getJobs(widget.firebaseUid);
      if (mounted) setState(() { _jobs = jobs; _loading = false; _refreshing = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _refreshing = false; });
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
        title: const Text('Ofrecimiento de servicios',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Gestiona trabajos, proyectos y producciones operativas.\n\n'
          'Flujo de trabajo:\n'
          '1. Crea un trabajo y define el cliente y monto acordado.\n'
          '2. Asigna colaboradores y define su compensación.\n'
          '3. Registra pagos recibidos del cliente (anticipos y saldos).\n'
          '4. Registra gastos operativos del trabajo.\n'
          '5. El sistema calcula tu utilidad neta automáticamente.\n\n'
          'Toca el botón (+) para crear un nuevo trabajo. '
          'Toca un trabajo para ver su detalle completo.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'draft': return AppTheme.textSecondary;
      case 'pending': return AppTheme.primary;
      case 'in_progress': return const Color(0xFF0EA5E9);
      case 'completed': return AppTheme.success;
      case 'cancelled': return AppTheme.danger;
      default: return AppTheme.textSecondary;
    }
  }

  String _labelEstado(String estado) {
    switch (estado) {
      case 'draft': return 'Borrador';
      case 'pending': return 'Pendiente';
      case 'in_progress': return 'En progreso';
      case 'completed': return 'Completado';
      case 'cancelled': return 'Cancelado';
      default: return estado;
    }
  }

  String _labelPayment(String status) {
    switch (status) {
      case 'pending': return 'Sin pagos';
      case 'partially_paid': return 'Pago parcial';
      case 'paid': return 'Pagado';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ofrecimiento de servicios'),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_scanner, size: 22, color: AppTheme.primary),
            tooltip: 'Escanear factura',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => InvoiceScannerScreen(firebaseUid: widget.firebaseUid),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, size: 22),
            tooltip: 'Dashboard financiero',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FinancieroDashboardScreen(firebaseUid: widget.firebaseUid)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CrearTrabajoScreen(firebaseUid: widget.firebaseUid)),
          );
          _cargarJobs(silencioso: true);
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _cargarJobs(silencioso: true),
              child: Column(
                children: [
                  if (_refreshing)
                    LinearProgressIndicator(
                      backgroundColor: AppTheme.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  Expanded(
                    child: _jobs.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _jobs.length,
                            itemBuilder: (_, i) => _buildJobCard(_jobs[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.handshake_outlined, size: 72, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            const Text('Aún no tienes trabajos',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Crea tu primer trabajo para comenzar a registrar clientes, colaboradores y pagos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CrearTrabajoScreen(firebaseUid: widget.firebaseUid)));
                _cargarJobs(silencioso: true);
              },
              icon: const Icon(Icons.add),
              label: const Text('Crear primer trabajo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final estado = job['estado'] as String? ?? 'draft';
    final paymentStatus = job['payment_status'] as String? ?? 'pending';
    final montoTotal = double.tryParse(job['monto_total']?.toString() ?? '0') ?? 0;
    final totalRecibido = double.tryParse(job['total_recibido']?.toString() ?? '0') ?? 0;
    final progreso = montoTotal > 0 ? (totalRecibido / montoTotal).clamp(0.0, 1.0) : 0.0;
    final colorEstado = _colorEstado(estado);

    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TrabajoDetalleScreen(
              firebaseUid: widget.firebaseUid,
              jobId: job['id'] as int,
            )),
          );
          _cargarJobs(silencioso: true);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job['nombre'] as String? ?? '',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorEstado.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_labelEstado(estado),
                        style: TextStyle(color: colorEstado, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (job['nombre_cliente'] != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(job['nombre_cliente'] as String,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${Money.fmt(totalRecibido)} / ${Money.fmt(montoTotal)}',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _labelPayment(paymentStatus),
                    style: TextStyle(
                      color: paymentStatus == 'paid'
                          ? AppTheme.success
                          : paymentStatus == 'partially_paid'
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progreso,
                  backgroundColor: AppTheme.background,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.success),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
