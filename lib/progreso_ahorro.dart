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
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/savings_service.dart';
import 'services/api_client.dart';
import 'widgets/widgets.dart';
import 'utils/money.dart';

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

  Future<void> _cargar() async {
    setState(() => isLoading = true);
    try {
      final data = await SavingsService.getAhorros(widget.firebaseUid);
      setState(() { ahorros = data; isLoading = false; });
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar ahorros: $e')),
      );
    }
  }

  Future<void> _eliminar(int id) async {
    final ok = await showConfirmDialog(context, title: 'Eliminar meta', content: '¿Confirmas eliminar esta meta de ahorro?');
    if (!ok) return;
    try {
      await SavingsService.deleteAhorro(id, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
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
                      firebaseUid: widget.firebaseUid,
                      onDelete: () => _eliminar(ahorros[i]['id']),
                      onAportado: _cargar,
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

class _AhorroCard extends StatefulWidget {
  final Map<String, dynamic> ahorro;
  final String firebaseUid;
  final VoidCallback onDelete;
  final VoidCallback onAportado;
  const _AhorroCard({required this.ahorro, required this.firebaseUid, required this.onDelete, required this.onAportado});

  @override
  State<_AhorroCard> createState() => _AhorroCardState();
}

class _AhorroCardState extends State<_AhorroCard> {
  void _modalAportaciones() {
    final montoCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    DateTime fecha = DateTime.now();
    final gastoId = widget.ahorro['id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16, left: 130),
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
              Text('Aportaciones — ${widget.ahorro['nombre']}',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Monto', prefixText: 'B/. '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notaCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'ej: bono de trabajo'),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx, initialDate: fecha,
                    firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setModal(() => fecha = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    Text(DateFormat('dd/MM/yyyy').format(fecha), style: const TextStyle(color: AppTheme.textPrimary)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final m = double.tryParse(montoCtrl.text);
                  if (m == null || m <= 0) return;
                  try {
                    await ApiClient.post('/ahorros/$gastoId/aportaciones', {
                      'firebase_uid': widget.firebaseUid,
                      'monto': m,
                      'nota': notaCtrl.text.isEmpty ? null : notaCtrl.text,
                      'fecha': DateFormat('yyyy-MM-dd').format(fecha),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    widget.onAportado();
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const SizedBox(width: double.infinity, child: Center(child: Text('Registrar aportación'))),
              ),
              const SizedBox(height: 20),

              // Lista de aportaciones anteriores
              FutureBuilder(
                future: ApiClient.get('/ahorros/$gastoId/aportaciones?firebase_uid=${widget.firebaseUid}'),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
                  final body = json.decode(snap.data!.body) as Map<String, dynamic>;
                  final lista = (body['aportaciones'] as List? ?? []).cast<Map<String, dynamic>>();
                  if (lista.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Historial', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    ...lista.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['fecha']?.toString().substring(0,10) ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                          if (a['nota'] != null) Text(a['nota'].toString(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ])),
                        Text('${Money.fmt(double.tryParse(a['monto'].toString()) ?? 0)}',
                          style: const TextStyle(color: AppTheme.colorAhorro, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            await ApiClient.delete('/aportaciones/${a['id']}?firebase_uid=${widget.firebaseUid}');
                            if (ctx.mounted) { Navigator.pop(ctx); widget.onAportado(); }
                          },
                          child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                        ),
                      ]),
                    )),
                  ]);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // monto_meta_total = meta real (cuota × total períodos); monto_meta = cuota (fallback)
    final metaRaw    = widget.ahorro['monto_meta_total'] ?? widget.ahorro['monto_meta'];
    final meta       = double.tryParse(metaRaw?.toString() ?? '0') ?? 0;
    final ahorrado   = double.tryParse(widget.ahorro['monto_ahorrado'].toString()) ?? 0;
    final aportado   = double.tryParse(widget.ahorro['total_aportaciones']?.toString() ?? '0') ?? 0;
    final totalReal  = ahorrado + aportado;
    final pct        = meta > 0 ? (totalReal / meta).clamp(0.0, 1.0) : 0.0;
    final restante   = meta - totalReal;

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
            Text(widget.ahorro['nombre'], style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
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
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.colorAhorro, size: 20),
            tooltip: 'Agregar aportación',
            onPressed: _modalAportaciones,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 18),
            onPressed: widget.onDelete,
          ),
        ]),

        const SizedBox(height: 18),

        // ── MONTOS ──────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ahorrado', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text('${Money.fmt(totalReal)}',
                style: const TextStyle(color: AppTheme.colorAhorro, fontSize: 18, fontWeight: FontWeight.w800)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Meta', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text('${Money.fmt(meta)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w700)),
            if (aportado > 0) Text('+ ${Money.fmt(aportado)} manual',
                style: const TextStyle(color: AppTheme.colorAhorro, fontSize: 10)),
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
            Text('Faltan ${Money.fmt(restante)}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      ]),
    );
  }
}
