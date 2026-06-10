import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/gustitos_service.dart';
import '../services/api_client.dart';
import 'crear_gustito_sheet.dart';

class GustitosScreen extends StatefulWidget {
  final String firebaseUid;
  const GustitosScreen({super.key, required this.firebaseUid});

  @override
  State<GustitosScreen> createState() => _GustitosScreenState();
}

class _GustitosScreenState extends State<GustitosScreen> {
  List<dynamic> _gustitos = [];
  bool _loading = true;
  double _presupuesto = 0; // L2 — presupuesto mensual de gustitos (0 = sin límite)

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final lista = await GustitosService.listar(widget.firebaseUid);
      if (mounted) setState(() { _gustitos = lista; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // L2 — presupuesto de gustitos (no bloquea la lista si falla)
    try {
      final r = await ApiClient.get('/user/settings?firebase_uid=${widget.firebaseUid}');
      if (r.statusCode == 200 && mounted) {
        final s = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _presupuesto = (double.tryParse(s['presupuesto_gustitos'].toString()) ?? 0));
      }
    } catch (_) {}
  }

  Future<void> _editarPresupuesto() async {
    final ctrl = TextEditingController(
        text: _presupuesto > 0 ? _presupuesto.toStringAsFixed(2) : '');
    final nuevo = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Presupuesto de gustitos', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Cuánto quieres permitirte en gustitos cada mes? (0 = sin límite)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.3)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Monto mensual (B/.)', prefixText: 'B/. '),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevo == null) return;
    try {
      await ApiClient.patch('/user/settings', {
        'firebase_uid': widget.firebaseUid,
        'presupuesto_gustitos': nuevo,
      });
      if (mounted) setState(() => _presupuesto = nuevo);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el presupuesto'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _eliminar(int id) async {
    try {
      await GustitosService.eliminar(id, widget.firebaseUid);
      _cargar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al eliminar'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  double get _totalEsteMes {
    final now = DateTime.now();
    return _gustitos.fold(0.0, (sum, g) {
      final fecha = DateTime.tryParse(g['spent_at'] ?? '');
      if (fecha == null || fecha.year != now.year || fecha.month != now.month) return sum;
      return sum + (double.tryParse(g['amount'].toString()) ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Mis Gustitos',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo gustito', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => CrearGustitoSheet.show(
          context,
          firebaseUid: widget.firebaseUid,
          onCreado: _cargar,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              color: AppTheme.primary,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _ResumenHeader(
                    total: _totalEsteMes,
                    presupuesto: _presupuesto,
                    onEditarPresupuesto: _editarPresupuesto,
                  )),
                  if (_gustitos.isEmpty)
                    const SliverFillRemaining(child: _EstadoVacio())
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _GustitoTile(
                          gustito: _gustitos[i],
                          onEliminar: () => _eliminar(_gustitos[i]['id'] as int),
                        ),
                        childCount: _gustitos.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
    );
  }
}

class _ResumenHeader extends StatelessWidget {
  final double total;
  final double presupuesto;
  final VoidCallback onEditarPresupuesto;
  const _ResumenHeader({
    required this.total,
    required this.presupuesto,
    required this.onEditarPresupuesto,
  });

  @override
  Widget build(BuildContext context) {
    // L2 — color e información según el presupuesto definido
    final tieneLimite = presupuesto > 0;
    final ratio = tieneLimite ? (total / presupuesto).clamp(0.0, 1.0) : 0.0;
    final excede = tieneLimite && total > presupuesto;
    final barColor = !tieneLimite ? AppTheme.primary
        : excede ? AppTheme.danger
        : ratio > 0.8 ? AppTheme.warning : AppTheme.success;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt, color: barColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gustitos este mes',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            Text(
              tieneLimite
                  ? 'B/. ${total.toStringAsFixed(2)} de B/. ${presupuesto.toStringAsFixed(2)}'
                  : 'B/. ${total.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ])),
          IconButton(
            onPressed: onEditarPresupuesto,
            icon: Icon(tieneLimite ? Icons.edit_outlined : Icons.add_chart, color: AppTheme.textMuted, size: 18),
            tooltip: tieneLimite ? 'Editar presupuesto' : 'Definir presupuesto',
          ),
        ]),
        if (tieneLimite) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio, minHeight: 6,
              color: barColor, backgroundColor: AppTheme.surfaceAlt,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            excede
                ? 'Te pasaste B/. ${(total - presupuesto).toStringAsFixed(2)} de tu límite de gustitos'
                : 'Te quedan B/. ${(presupuesto - total).toStringAsFixed(2)} para gustitos este mes',
            style: TextStyle(color: barColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ] else ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onEditarPresupuesto,
            child: const Text('Define un presupuesto mensual para controlar tus gustitos →',
                style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

class _GustitoTile extends StatelessWidget {
  final Map<String, dynamic> gustito;
  final VoidCallback onEliminar;
  const _GustitoTile({required this.gustito, required this.onEliminar});

  static const _emocionColor = {
    'antojo': AppTheme.warning,
    'premio': AppTheme.success,
    'social': AppTheme.info,
    'impulso': AppTheme.danger,
    'estres': Colors.deepOrange,
    'otro': AppTheme.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(gustito['amount'].toString()) ?? 0;
    final fecha = gustito['spent_at'] as String? ?? '';
    final emocion = gustito['emotion_tag'] as String?;
    final merchant = gustito['merchant'] as String?;
    final color = (emocion != null ? _emocionColor[emocion] : null) ?? AppTheme.primary;

    return Dismissible(
      key: ValueKey(gustito['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppTheme.danger.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: AppTheme.danger),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('¿Eliminar gustito?',
                style: TextStyle(color: AppTheme.textPrimary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onEliminar(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.bolt, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                gustito['name'] as String? ?? '',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              if (merchant != null && merchant.isNotEmpty)
                Text(merchant,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              Row(children: [
                Text(fecha.length >= 10 ? fecha.substring(0, 10) : fecha,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                if (emocion != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(emocion,
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
                  ),
                ],
              ]),
            ]),
          ),
          Text('B/. ${monto.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt_outlined, size: 56, color: AppTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('Sin gustitos aún',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Un gustito es una compra consciente sin culpa.\nRegistra tus pequeños placeres aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => CrearGustitoSheet.show(
              context,
              firebaseUid: (context.findAncestorStateOfType<_GustitosScreenState>())
                      ?.widget.firebaseUid ?? '',
              onCreado: () => context
                  .findAncestorStateOfType<_GustitosScreenState>()
                  ?._cargar(),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Registrar primer gustito'),
          ),
        ]),
      ),
    );
  }
}
