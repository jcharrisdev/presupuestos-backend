import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'crear_presupuesto.dart';
import 'presupuestos_service.dart';
import 'detalles_presupuesto.dart';

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
      appBar: AppBar(title: const Text('Mis Presupuestos')),
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
          _cargar();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }

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

class _PresupuestoCard extends StatelessWidget {
  final Map<String, dynamic> presupuesto;
  final VoidCallback onTap;
  const _PresupuestoCard({required this.presupuesto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(presupuesto['monto_total'].toString()) ?? 0;
    final tipo = presupuesto['tipo_periodo'] ?? '';
    final dia = presupuesto['dia_inicio_periodo']?.toString() ?? '';

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
