/// Pantalla de listado de presupuestos del usuario.
///
/// Carga todos los presupuestos mediante [PresupuestoService] y los muestra
/// como tarjetas. Al tocar una tarjeta navega a [DetallesPresupuesto].
/// Al crear uno nuevo navega a [CrearPresupuesto] y recarga al regresar.
/// Soporta pull-to-refresh para recargar manualmente.
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'crear_presupuesto.dart';
import 'presupuestos_service.dart';
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

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga (o recarga) la lista de presupuestos desde el backend.
  /// Muestra spinner durante la carga y SnackBar si hay error de red.
  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final datos = await _service.obtenerPresupuestos(widget.firebaseUid);
      setState(() { presupuestos = datos; isLoading = false; });
    } catch (_) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al cargar presupuestos')),
      );
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : presupuestos.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: presupuestos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PresupuestoCard(
                      presupuesto: presupuestos[i],
                      onTap: () async {
                        // Espera a que el usuario regrese de DetallesPresupuesto
                        // y recarga en caso de que haya modificado datos.
                        await Navigator.push(context, MaterialPageRoute(
                          builder: (_) => DetallesPresupuesto(
                            presupuesto: presupuestos[i],
                            firebaseUid: widget.firebaseUid,
                          ),
                        ));
                        _cargar();
                      },
                    ),
                  ),
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

  /// Pantalla vacía cuando el usuario no tiene presupuestos todavía.
  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('Sin presupuestos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Crea tu primer presupuesto', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
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
