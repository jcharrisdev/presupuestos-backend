import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class ClienteEstadoCuentaScreen extends StatefulWidget {
  final String firebaseUid;
  final String nombreCliente;
  const ClienteEstadoCuentaScreen({
    Key? key,
    required this.firebaseUid,
    required this.nombreCliente,
  }) : super(key: key);

  @override
  State<ClienteEstadoCuentaScreen> createState() => _ClienteEstadoCuentaScreenState();
}

class _ClienteEstadoCuentaScreenState extends State<ClienteEstadoCuentaScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  final fmt = NumberFormat('#,##0.00', 'es');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final nombre = Uri.encodeComponent(widget.nombreCliente);
      final res = await ApiClient.get(
        '/clientes/$nombre/estado-cuenta?firebase_uid=${widget.firebaseUid}',
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        if (mounted) setState(() { _data = body; _loading = false; });
      } else if (res.statusCode == 404) {
        if (mounted) setState(() { _error = 'Sin historial para este cliente'; _loading = false; });
      } else {
        if (mounted) setState(() { _error = 'Error ${res.statusCode}'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombreCliente)),
      body: Container(
        color: AppTheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ))
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _cargar,
                    child: _buildContent(),
                  ),
      ),
    );
  }

  Widget _buildContent() {
    final cobros = (_data!['cobros'] as List).cast<Map<String, dynamic>>();
    final totalCobrado  = double.tryParse(_data!['total_cobrado']?.toString()  ?? '0') ?? 0;
    final totalPendiente = double.tryParse(_data!['total_pendiente']?.toString() ?? '0') ?? 0;
    final cantVentas    = int.tryParse(_data!['cantidad_ventas']?.toString()  ?? '0') ?? 0;

    // Agrupar cobros por venta
    final Map<int, List<Map<String, dynamic>>> porVenta = {};
    final Map<int, String> nombreVenta = {};
    for (final c in cobros) {
      final vid = c['venta_id'] as int;
      porVenta.putIfAbsent(vid, () => []).add(c);
      nombreVenta[vid] = c['venta_nombre'] as String? ?? 'Venta #$vid';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Chips de totales
        Row(children: [
          _chip('\$${fmt.format(totalCobrado)}', 'Cobrado', AppTheme.success),
          const SizedBox(width: 8),
          _chip('\$${fmt.format(totalPendiente)}', 'Pendiente', AppTheme.primary),
          const SizedBox(width: 8),
          _chip('$cantVentas', cantVentas == 1 ? 'Venta' : 'Ventas', AppTheme.colorFijo),
        ]),
        const SizedBox(height: 20),

        if (cobros.isEmpty)
          Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('Sin cobros registrados', style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          )
        else
          ...porVenta.entries.map((entry) {
            final vid = entry.key;
            final lista = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header de la venta
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Expanded(child: Divider(color: AppTheme.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        nombreVenta[vid]!.toUpperCase(),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppTheme.border)),
                  ]),
                ),
                ...lista.map((cobro) => _CobroItem(cobro: cobro, fmt: fmt)),
                const SizedBox(height: 4),
              ],
            );
          }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _CobroItem extends StatelessWidget {
  final Map<String, dynamic> cobro;
  final NumberFormat fmt;
  const _CobroItem({required this.cobro, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final cobrado = cobro['estado'] == 'cobrado';
    final monto = double.tryParse(cobro['monto']?.toString() ?? '0') ?? 0;
    final montoCobrado = cobro['monto_cobrado'] != null
        ? double.tryParse(cobro['monto_cobrado'].toString()) : null;
    final fecha = cobro['fecha_cobro']?.toString() ?? cobro['fecha_cobrado']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cobrado ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cobrado ? AppTheme.success.withOpacity(0.2) : AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (fecha != null)
              Text(fecha, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text('\$${fmt.format(monto)}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            if (cobrado && montoCobrado != null)
              Text('Cobrado: \$${fmt.format(montoCobrado)}', style: const TextStyle(color: AppTheme.success, fontSize: 11)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cobrado ? AppTheme.success.withOpacity(0.12) : AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cobrado ? 'Cobrado' : 'Pendiente',
              style: TextStyle(color: cobrado ? AppTheme.success : AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
