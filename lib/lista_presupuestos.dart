/// Pantalla de listado de presupuestos del usuario.
///
/// Carga todos los presupuestos mediante [PresupuestoService] y los muestra
/// como tarjetas. Al tocar una tarjeta navega a [DetallesPresupuesto].
/// Al crear uno nuevo navega a [CrearPresupuesto] y recarga al regresar.
/// Soporta pull-to-refresh para recargar manualmente.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'crear_presupuesto.dart';
import 'presupuestos_service.dart';
import 'services/api_client.dart';
import 'services/cache_service.dart';
import 'widgets/widgets.dart';
import 'detalles_presupuesto.dart';

/// Pantalla de lista de presupuestos con FAB para crear uno nuevo.
class ListaPresupuestos extends StatefulWidget {
  final String firebaseUid;
  const ListaPresupuestos({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _ListaPresupuestosState createState() => _ListaPresupuestosState();
}

class _ListaPresupuestosState extends State<ListaPresupuestos> {
  List<dynamic> presupuestos = [];
  final _service = PresupuestoService();
  bool isLoading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final cacheKey = '${widget.firebaseUid}_presupuestos';
    final cached = CacheService.get(cacheKey);

    if (cached != null && !silencioso) {
      setState(() { presupuestos = List<dynamic>.from(cached); isLoading = false; _refreshing = true; });
    } else if (!silencioso) {
      setState(() => isLoading = true);
    } else {
      setState(() => _refreshing = true);
    }

    try {
      final res = await ApiClient.get('/presupuestos?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        await CacheService.set(cacheKey, data);
        if (mounted) setState(() { presupuestos = data; isLoading = false; _refreshing = false; });
      } else {
        if (mounted) setState(() { isLoading = false; _refreshing = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; _refreshing = false; });
        if (presupuestos.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Mostrando datos guardados.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Presupuestos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Mis Presupuestos',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Aquí se listan todos tus presupuestos.\n\n'
                  '1. Toca el botón "Nuevo" para crear un presupuesto.\n'
                  '2. Toca una tarjeta para ver el detalle del período activo.\n'
                  '3. Desliza hacia abajo para actualizar la lista.\n\n'
                  'Cada presupuesto tiene un ciclo quincenal (14 días) o mensual (30 días). '
                  'El sistema abre períodos automáticamente según el día de inicio que configuraste.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing)
            const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary, backgroundColor: AppTheme.surfaceAlt),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : presupuestos.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: AppTheme.primary,
                        backgroundColor: AppTheme.surface,
                        onRefresh: () => _cargar(silencioso: true),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: presupuestos.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _PresupuestoCard(
                            presupuesto: presupuestos[i],
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => DetallesPresupuesto(
                                  presupuesto: presupuestos[i],
                                  firebaseUid: widget.firebaseUid,
                                ),
                              ));
                              _cargar(silencioso: true);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => CrearPresupuesto(firebaseUid: widget.firebaseUid),
          ));
          _cargar(); // recargar tras crear para mostrar el nuevo presupuesto
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }

  Widget _empty() => EmptyState(
    icon: Icons.account_balance_wallet_outlined,
    title: 'Sin presupuestos',
    subtitle: 'Crea tu primer presupuesto',
  );
}

/// Tarjeta visual para un presupuesto individual.
///
/// Muestra nombre, tipo de período, monto total y día de inicio.
class _PresupuestoCard extends StatelessWidget {
  final Map<String, dynamic> presupuesto;
  final VoidCallback onTap;
  const _PresupuestoCard({required this.presupuesto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(presupuesto['monto_total'].toString()) ?? 0;
    final tipo  = presupuesto['tipo_periodo'] ?? '';
    final dia   = presupuesto['dia_inicio_periodo']?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    presupuesto['nombre'],
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                // Badge del tipo de período
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tipo == 'quincenal' ? 'Quincenal' : 'Mensual',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Monto total del período
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Presupuesto total', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      '\$${monto.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                    ),
                  ],
                ),
                const Spacer(),
                // Día de inicio del ciclo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Inicio período', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text('Día $dia', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Indicador de acción "Ver detalle"
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Ver detalle', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward, color: AppTheme.primary, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
