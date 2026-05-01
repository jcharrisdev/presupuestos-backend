import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class ProgresoAhorroScreen extends StatefulWidget {
  final String firebaseUid;
  const ProgresoAhorroScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _ProgresoAhorroScreenState createState() => _ProgresoAhorroScreenState();
}

class _ProgresoAhorroScreenState extends State<ProgresoAhorroScreen> {
  List<dynamic> ahorros = [];
  bool isLoading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiClient.get('/ahorros?firebase_uid=${widget.firebaseUid}');
      setState(() {
        ahorros = res.statusCode == 200 ? json.decode(res.body) : [];
        isLoading = false;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar meta', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Confirmas eliminar esta meta de ahorro?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiClient.delete('/ahorros/$id');
    if (res.statusCode == 200) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progreso de Ahorros'),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ahorros.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: ahorros.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _AhorroCard(ahorro: ahorros[i], onDelete: () => _eliminar(ahorros[i]['id'])),
                  ),
                ),
    );
  }

  Widget _empty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.savings_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.4)),
    const SizedBox(height: 16),
    const Text('Sin metas de ahorro', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    const Text('Crea tu primera meta en la pantalla anterior', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
  ]));
}

class _AhorroCard extends StatelessWidget {
  final Map<String, dynamic> ahorro;
  final VoidCallback onDelete;
  const _AhorroCard({required this.ahorro, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final meta     = double.tryParse(ahorro['monto_meta'].toString()) ?? 0;
    final ahorrado = double.tryParse(ahorro['monto_ahorrado'].toString()) ?? 0;
    final pct      = meta > 0 ? (ahorrado / meta).clamp(0.0, 1.0) : 0.0;
    final restante = meta - ahorrado;

    Color statusColor;
    String statusLabel;
    if (pct >= 1) { statusColor = AppTheme.success; statusLabel = 'Completado'; }
    else if (pct >= 0.75) { statusColor = AppTheme.warning; statusLabel = 'Casi listo'; }
    else { statusColor = AppTheme.colorFijo; statusLabel = 'En progreso'; }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppTheme.colorAhorro.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.savings_outlined, color: AppTheme.colorAhorro, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ahorro['nombre'], style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ])),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 18),
            onPressed: onDelete,
          ),
        ]),

        const SizedBox(height: 18),

        // Montos
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ahorrado', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text('\$${ahorrado.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.colorAhorro, fontSize: 18, fontWeight: FontWeight.w800)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Meta', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text('\$${meta.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
        ]),

        const SizedBox(height: 14),

        // Barra progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 8,
            backgroundColor: AppTheme.surfaceAlt,
            color: statusColor,
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(pct * 100).toStringAsFixed(1)}% completado', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          if (restante > 0)
            Text('Faltan \$${restante.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      ]),
    );
  }
}
