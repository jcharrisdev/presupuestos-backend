/// Pantalla de progreso de metas de ahorro.
///
/// Carga todas las metas del usuario desde GET /ahorros y las muestra
/// como tarjetas con una barra de progreso visual.
///
/// El backend retorna para cada meta:
///   - `nombre`: descripción de la meta
///   - `monto_meta`: objetivo total (el monto original ingresado)
///   - `monto_ahorrado`: suma de movimientos pagados de tipo 'ahorro'
///
/// El progreso se calcula localmente: `monto_ahorrado / monto_meta`.
///
/// Los estados visuales son:
///   - < 75% → "En progreso" (azul)
///   - 75–99% → "Casi listo" (amarillo)
///   - 100%   → "Completado" (verde)
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

/// Lista de metas de ahorro con progreso.
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

  /// Carga las metas de ahorro desde el backend.
  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiClient.get('/ahorros?firebase_uid=${widget.firebaseUid}');
      setState(() {
        ahorros = res.statusCode == 200 ? json.decode(res.body) : [];
        isLoading = false;
      });
    } catch (e) {
      // FIX: catch silencioso mostraba lista vacía sin avisar al usuario.
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar ahorros: $e')),
      );
    }
  }

  /// Elimina una meta de ahorro tras confirmación del usuario.
  ///
  /// Muestra un diálogo de confirmación antes de llamar DELETE /ahorros/:id.
  /// Al confirmar, recarga la lista.
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
    // FIX: se agrega firebase_uid al query para que el backend valide propiedad del recurso
    final res = await ApiClient.delete('/ahorros/$id?firebase_uid=${widget.firebaseUid}');
    if (res.statusCode == 200) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progreso de Ahorros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Progreso de ahorros',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Muestra el avance de todas tus metas de ahorro activas.\n\n'
                  '• La barra verde indica cuánto llevas ahorrado vs la meta total.\n'
                  '• "En progreso" → menos del 75% completado.\n'
                  '• "Casi listo" → entre el 75% y el 99%.\n'
                  '• "Completado" → llegaste a la meta.\n\n'
                  'El saldo se actualiza automáticamente cada vez que marcas como pagada '
                  'la cuota de ahorro en el detalle del presupuesto.\n\n'
                  'Toca el ícono de basura para eliminar una meta.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
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
                    itemBuilder: (_, i) => _AhorroCard(
                      ahorro: ahorros[i],
                      onDelete: () => _eliminar(ahorros[i]['id']),
                    ),
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

/// Tarjeta de una meta de ahorro con barra de progreso y estado.
///
/// Calcula el porcentaje en base a `monto_ahorrado / monto_meta`
/// y asigna un color y etiqueta según el avance.
class _AhorroCard extends StatelessWidget {
  final Map<String, dynamic> ahorro;
  final VoidCallback onDelete;
  const _AhorroCard({required this.ahorro, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final meta     = double.tryParse(ahorro['monto_meta'].toString()) ?? 0;
    final ahorrado = double.tryParse(ahorro['monto_ahorrado'].toString()) ?? 0;
    // Porcentaje completado, acotado a [0, 1] para no romper la barra
    final pct      = meta > 0 ? (ahorrado / meta).clamp(0.0, 1.0) : 0.0;
    final restante = meta - ahorrado;

    // Determinar estado visual según el porcentaje
    Color statusColor;
    String statusLabel;
    if (pct >= 1)         { statusColor = AppTheme.success; statusLabel = 'Completado'; }
    else if (pct >= 0.75) { statusColor = AppTheme.warning; statusLabel = 'Casi listo'; }
    else                  { statusColor = AppTheme.colorFijo; statusLabel = 'En progreso'; }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── HEADER ──────────────────────────────────────────────────────
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
            // Badge de estado con color dinámico
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ])),
          // Botón de eliminar meta
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 18),
            onPressed: onDelete,
          ),
        ]),

        const SizedBox(height: 18),

        // ── MONTOS ──────────────────────────────────────────────────────
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

        // ── BARRA DE PROGRESO ────────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 8,
            backgroundColor: AppTheme.surfaceAlt,
            color: statusColor, // color cambia según el estado
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(pct * 100).toStringAsFixed(1)}% completado',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          // Mostrar "Faltan $X" solo si queda algo por ahorrar
          if (restante > 0)
            Text('Faltan \$${restante.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      ]),
    );
  }
}
