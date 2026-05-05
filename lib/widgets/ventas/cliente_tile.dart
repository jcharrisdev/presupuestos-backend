/// Tarjeta de un cliente dentro de la lista de cobros de una venta.
///
/// Si el cobro tiene `items[]` (pedido con catálogo), muestra el detalle de
/// productos debajo del nombre. Si no, muestra solo el monto manual.
///
/// Compatibilidad: cobros sin items[] funcionan igual que antes.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../cliente_estado_cuenta_screen.dart';

class ClienteTile extends StatelessWidget {
  final Map<String, dynamic> cobro;
  final VoidCallback onCobrar;
  final VoidCallback onEliminar;
  final String firebaseUid;

  const ClienteTile({
    Key? key,
    required this.cobro,
    required this.onCobrar,
    required this.onEliminar,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cobrado      = cobro['estado'] == 'cobrado';
    final monto        = double.tryParse(cobro['monto']?.toString() ?? '0') ?? 0;
    final montoCobrado = cobro['monto_cobrado'] != null
        ? double.tryParse(cobro['monto_cobrado'].toString()) : null;
    final items = (cobro['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Etiqueta de condición de pago con fecha si aplica
    String condicion;
    final fechaCobro = cobro['fecha_cobro']?.toString();
    switch (cobro['condicion_pago']) {
      case 'plazo':
        condicion = fechaCobro != null
            ? 'Plazo · $fechaCobro'
            : 'A plazo · ${cobro['dias_plazo'] ?? '?'}d';
        break;
      case 'fecha_especifica':
        condicion = fechaCobro != null ? 'Fecha · $fechaCobro' : 'Fecha exacta';
        break;
      default:
        condicion = 'Contra entrega';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cobrado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cobrado ? AppTheme.success.withOpacity(0.25) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── FILA PRINCIPAL ─────────────────────────────────────────────────
        Row(children: [
        // Avatar con la inicial del nombre del cliente
        CircleAvatar(
          backgroundColor: cobrado
              ? AppTheme.success.withOpacity(0.15) : AppTheme.primary.withOpacity(0.1),
          radius: 20,
          child: Text(
            (cobro['nombre_cliente'] as String? ?? '?').isNotEmpty
                ? (cobro['nombre_cliente'] as String)[0].toUpperCase() : '?',
            style: TextStyle(
              color: cobrado ? AppTheme.success : AppTheme.primary,
              fontWeight: FontWeight.w800, fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Info del cliente
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(cobro['nombre_cliente'] ?? '', style: TextStyle(
              color: cobrado ? AppTheme.textSecondary : AppTheme.textPrimary,
              fontWeight: FontWeight.w600, fontSize: 14,
            ))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ClienteEstadoCuentaScreen(
                  firebaseUid: firebaseUid,
                  nombreCliente: cobro['nombre_cliente'] ?? '',
                ),
              )),
              child: const Icon(Icons.account_circle_outlined, color: AppTheme.textMuted, size: 18),
            ),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(4)),
              child: Text(condicion, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            ),
            if (cobrado && montoCobrado != null) ...[
              const SizedBox(width: 6),
              Text('\$${montoCobrado.toStringAsFixed(2)} cobrado',
                  style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
        ])),

        // Monto y acciones
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: cobrado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
          )),
          const SizedBox(height: 6),
          if (!cobrado)
            Row(children: [
              GestureDetector(onTap: onEliminar,
                  child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCobrar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                  ),
                  child: const Text('Cobrar',
                      style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ])
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),  // cierra Row principal

        // ── DETALLE DE ITEMS (solo si hay pedido con catálogo) ───────────────
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 8),
          ...items.map((item) {
            final cant   = double.tryParse(item['cantidad']?.toString() ?? '1') ?? 1;
            final precio = double.tryParse(item['precio_unitario']?.toString() ?? '0') ?? 0;
            final sub    = double.tryParse(item['subtotal']?.toString() ?? '0') ?? (cant * precio);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(children: [
                const Icon(Icons.circle, size: 5, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${cant % 1 == 0 ? cant.toInt() : cant} × ${item['descripcion'] ?? ''}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                )),
                Text('\$${sub.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ]),  // cierra Column principal
    );
  }
}
