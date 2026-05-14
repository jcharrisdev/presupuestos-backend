import 'package:flutter/material.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/deudas_service.dart';
import 'crear_deuda_sheet.dart';
import 'abono_deuda_sheet.dart';

class DeudasScreen extends StatefulWidget {
  final String firebaseUid;
  const DeudasScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<DeudasScreen> createState() => _DeudasScreenState();
}

class _DeudasScreenState extends State<DeudasScreen> {
  List<dynamic> _deudas = [];
  double _totalPendiente = 0;
  double _totalPagoMinimo = 0;
  bool _loading = true;
  bool _incluirSaldadas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await DeudasService.getAll(widget.firebaseUid, incluirSaldadas: _incluirSaldadas);
      if (!mounted) return;
      final lista = (data['deudas'] as List? ?? []);
      // Ordenar por tasa de interés DESC (avalanche: pagar primero la más cara)
      lista.sort((a, b) {
        final ta = _d(a['tasa_interes']);
        final tb = _d(b['tasa_interes']);
        return tb.compareTo(ta);
      });
      setState(() {
        _deudas = lista;
        _totalPendiente  = _d(data['total_pendiente']);
        _totalPagoMinimo = _d(data['total_pago_minimo']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _archivar(int id) async {
    try {
      await DeudasService.archivar(id, widget.firebaseUid);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Mis Deudas'),
        actions: [
          IconButton(
            icon: Icon(_incluirSaldadas ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
            tooltip: _incluirSaldadas ? 'Ocultar saldadas' : 'Ver saldadas',
            onPressed: () { setState(() => _incluirSaldadas = !_incluirSaldadas); _cargar(); },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Deudas', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Registra tus deudas (tarjetas, préstamos, hipoteca) para tener '
                  'visibilidad de tu carga financiera total.\n\n'
                  'Registra abonos para reducir el saldo pendiente. '
                  'Cuando el saldo llegue a cero, la deuda se archiva automáticamente.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CrearDeudaSheet.show(context,
          firebaseUid: widget.firebaseUid,
          onCreada: _cargar,
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nueva deuda'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? Container(color: AppTheme.background, child: const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: _cargar,
              child: _deudas.isEmpty ? _emptyState() : _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── RESUMEN ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Deuda total pendiente',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('\$${_totalPendiente.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.danger, fontSize: 22, fontWeight: FontWeight.w800)),
            ])),
            if (_totalPagoMinimo > 0)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Pago mínimo mensual',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                Text('\$${_totalPagoMinimo.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.warning, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ── LISTA DE DEUDAS ──────────────────────────────────────────────
        ..._deudas.asMap().entries.map((e) => _DeudaTile(
          deuda: e.value as Map<String, dynamic>,
          esMayorTasa: e.key == 0 && _deudas.length > 1 && _d((e.value)['tasa_interes']) > 0,
          onAbono: () => AbonoDeudaSheet.show(context,
            deuda: e.value,
            firebaseUid: widget.firebaseUid,
            onAbonado: _cargar,
          ),
          onArchivar: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                title: const Text('Archivar deuda',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                content: Text('¿Marcar "${(e.value as Map)['nombre']}" como saldada/archivada?',
                    style: const TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archivar')),
                ],
              ),
            );
            if (ok == true) _archivar((e.value as Map)['id'] as int);
          },
        )),

        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _emptyState() => ListView(
    children: [
      const SizedBox(height: 80),
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.credit_card_off_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text('Sin deudas registradas',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Toca el botón + para registrar una deuda',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      ])),
    ],
  );
}

class _DeudaTile extends StatelessWidget {
  final Map<String, dynamic> deuda;
  final VoidCallback onAbono;
  final VoidCallback onArchivar;
  final bool esMayorTasa;
  const _DeudaTile({required this.deuda, required this.onAbono, required this.onArchivar, this.esMayorTasa = false});

  @override
  Widget build(BuildContext context) {
    final nombre   = deuda['nombre'] as String? ?? '';
    final tipo     = deuda['tipo'] as String? ?? 'personal';
    final montoTotal    = _d(deuda['monto_total']);
    final montoPendiente = _d(deuda['monto_pendiente']);
    final pagoMinimo    = _d(deuda['pago_minimo']);
    final tasa          = _d(deuda['tasa_interes']);
    final fechaPago     = (deuda['fecha_proximo_pago'] as String?)?.substring(0, 10);
    final activa = (deuda['activa'] as int? ?? 1) == 1;
    final pct    = montoTotal > 0 ? (montoPendiente / montoTotal).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: activa ? AppTheme.surface : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: activa ? AppTheme.border : AppTheme.border.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _TipoIcon(tipo),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(nombre, style: TextStyle(
                color: activa ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: FontWeight.w700, fontSize: 15,
              ))),
              if (esMayorTasa)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt, color: AppTheme.danger, size: 11),
                    SizedBox(width: 3),
                    Text('Atacar primero',
                        style: TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
            Row(children: [
              _TipoChip(tipo),
              if (!activa) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Saldada', style: TextStyle(color: AppTheme.success, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ])),
          Text('\$${montoPendiente.toStringAsFixed(2)}',
              style: TextStyle(
                color: activa ? AppTheme.danger : AppTheme.textMuted,
                fontSize: 18, fontWeight: FontWeight.w800,
              )),
        ]),

        const SizedBox(height: 12),

        // Barra de progreso (pendiente sobre total)
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.success.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(activa ? AppTheme.danger : AppTheme.textMuted),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '\$${montoPendiente.toStringAsFixed(2)} pendiente de \$${montoTotal.toStringAsFixed(2)}  '
          '(${(pct * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),

        if (pagoMinimo > 0 || tasa > 0 || fechaPago != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 12, children: [
            if (pagoMinimo > 0)
              Text('Pago mínimo: \$${pagoMinimo.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            if (tasa > 0)
              Text('Tasa: ${tasa.toStringAsFixed(1)}%/mes',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 12)),
            if (fechaPago != null)
              Text('Próximo pago: $fechaPago',
                  style: const TextStyle(color: AppTheme.info, fontSize: 12)),
          ]),
        ],

        if (activa) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: onAbono,
              icon: const Icon(Icons.payments_outlined, size: 15),
              label: const Text('Registrar abono'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.success,
                side: const BorderSide(color: AppTheme.success),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onArchivar,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textMuted,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
              child: const Text('Archivar'),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _TipoIcon(String tipo) {
    IconData icon;
    Color color;
    switch (tipo) {
      case 'tarjeta_credito': icon = Icons.credit_card; color = AppTheme.danger; break;
      case 'hipoteca':        icon = Icons.home_outlined; color = AppTheme.info; break;
      case 'auto':            icon = Icons.directions_car_outlined; color = AppTheme.primary; break;
      case 'prestamo':        icon = Icons.account_balance_outlined; color = AppTheme.warning; break;
      default:                icon = Icons.receipt_long_outlined; color = AppTheme.textSecondary;
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _TipoChip extends StatelessWidget {
  final String tipo;
  const _TipoChip(this.tipo);
  @override
  Widget build(BuildContext context) {
    final labels = {
      'tarjeta_credito': 'Tarjeta', 'prestamo': 'Préstamo',
      'hipoteca': 'Hipoteca', 'auto': 'Auto', 'personal': 'Personal', 'otro': 'Otro',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(labels[tipo] ?? tipo,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
