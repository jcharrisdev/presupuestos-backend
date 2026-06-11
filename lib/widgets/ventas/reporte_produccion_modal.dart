import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/money.dart';

class ReporteProduccionModal {
  static void show(BuildContext context, List<dynamic> cobros) {
    final Map<String, Map<String, dynamic>> agrupado = {};
    for (final cobro in cobros) {
      final items = (cobro['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final item in items) {
        final desc  = item['descripcion']?.toString() ?? '';
        final precio = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
        final cant   = double.tryParse(item['cantidad']?.toString() ?? '0') ?? 0;
        final key    = '$desc||${precio.toStringAsFixed(2)}';
        if (agrupado.containsKey(key)) {
          agrupado[key]!['cantidad'] = (agrupado[key]!['cantidad'] as double) + cant;
        } else {
          agrupado[key] = {'descripcion': desc, 'precio': precio, 'cantidad': cant};
        }
      }
    }

    final lista = agrupado.values.toList()
      ..sort((a, b) => (a['descripcion'] as String).compareTo(b['descripcion'] as String));

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.92, minChildSize: 0.4, expand: false,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.summarize_outlined, color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
                const Text('Reporte de Producción',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${lista.length} producto${lista.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              const Divider(color: AppTheme.border, height: 1),
            ]),
          ),
          Expanded(child: lista.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Ningún cliente tiene productos del catálogo.\nAgrega clientes con pedidos del catálogo para ver el reporte.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ))
              : ListView.separated(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                  itemBuilder: (_, i) {
                    final item  = lista[i];
                    final cant  = item['cantidad'] as double;
                    final precio = item['precio'] as double;
                    final cantStr = cant % 1 == 0 ? cant.toInt().toString() : cant.toStringAsFixed(1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['descripcion'].toString(),
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          Text('${Money.fmt(precio)} c/u',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$cantStr uds',
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text('${Money.fmt((cant * precio))}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ]),
                      ]),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }
}
