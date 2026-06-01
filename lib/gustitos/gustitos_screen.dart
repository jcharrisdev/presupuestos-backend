import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/gustitos_service.dart';
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
                  SliverToBoxAdapter(child: _ResumenHeader(total: _totalEsteMes)),
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
  const _ResumenHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.bolt, color: AppTheme.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gustitos este mes',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(
            'B/. ${total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
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
