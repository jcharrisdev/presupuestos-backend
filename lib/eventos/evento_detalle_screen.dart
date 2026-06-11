import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/eventos_service.dart';
import 'crear_evento_sheet.dart';
import '../utils/money.dart';

class EventoDetalleScreen extends StatefulWidget {
  final String firebaseUid;
  final int eventoId;

  const EventoDetalleScreen({
    Key? key,
    required this.firebaseUid,
    required this.eventoId,
  }) : super(key: key);

  @override
  State<EventoDetalleScreen> createState() => _EventoDetalleScreenState();
}

class _EventoDetalleScreenState extends State<EventoDetalleScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _evento;
  List<Map<String, dynamic>> _gastos = [];

  static const _mesesLabel = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await EventosService.getEvento(widget.firebaseUid, widget.eventoId);
      if (!mounted) return;
      setState(() {
        _evento = data['evento'] as Map<String, dynamic>;
        _gastos = (data['gastos'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _abrirAgregarGasto() async {
    final nombreCtrl = TextEditingController();
    final montoCtrl  = TextEditingController();
    final notasCtrl  = TextEditingController();
    bool guardando   = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Registrar gasto del evento',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: nombreCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _dec('Descripción del gasto'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: montoCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _dec('Monto (\$)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notasCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _dec('Notas (opcional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: guardando ? null : () async {
                      if (nombreCtrl.text.trim().isEmpty || montoCtrl.text.isEmpty) return;
                      setModal(() => guardando = true);
                      try {
                        await EventosService.agregarGasto(widget.firebaseUid, widget.eventoId, {
                          'nombre': nombreCtrl.text.trim(),
                          'monto':  double.parse(montoCtrl.text),
                          'notas':  notasCtrl.text.trim().isEmpty ? null : notasCtrl.text.trim(),
                          'fecha':  DateTime.now().toIso8601String().substring(0, 10),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _cargar();
                      } catch (e) {
                        setModal(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: guardando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Registrar gasto',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _eliminarGasto(Map<String, dynamic> gasto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar gasto', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        content: Text('¿Eliminar "${gasto['nombre']}"?',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EventosService.eliminarGasto(widget.firebaseUid, widget.eventoId, gasto['id'] as int);
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _editarEvento() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CrearEventoSheet(
        firebaseUid: widget.firebaseUid,
        anio: _evento!['anio'] as int,
        eventoExistente: _evento,
      ),
    );
    if (ok == true) _cargar();
  }

  Future<void> _cancelarEvento() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Cancelar evento', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        content: const Text('¿Cancelar este evento? Los gastos registrados se preservan.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('No', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar evento'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EventosService.cancelarEvento(widget.firebaseUid, widget.eventoId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(_evento != null ? (_evento!['nombre'] as String? ?? 'Evento') : 'Evento',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
        actions: [
          if (_evento != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: _editarEvento,
              tooltip: 'Editar',
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: AppTheme.danger),
              onPressed: _cancelarEvento,
              tooltip: 'Cancelar evento',
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirAgregarGasto,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Registrar gasto', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
              : RefreshIndicator(onRefresh: _cargar, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final e          = _evento!;
    final monto      = _d(e['monto_total']);
    final gastado    = _d(e['gastado_real']);
    final disponible = _d(e['disponible']);
    final cuota      = _d(e['cuota_mensual']);
    final pct        = _d(e['pct_avance']);
    final mesIni     = e['mes_inicio'] as int;
    final mesFin     = e['mes_fin'] as int;
    final emoji      = e['emoji'] as String? ?? '🎯';
    final numMeses   = e['num_meses'] as int;
    final color      = pct >= 100 ? AppTheme.danger : pct >= 80 ? AppTheme.warning : AppTheme.success;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card de progreso
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['nombre'] as String? ?? '',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    mesIni == mesFin
                        ? _mesesLabel[mesIni]
                        : '${_mesesLabel[mesIni]} → ${_mesesLabel[mesFin]} · $numMeses meses',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),

            // Stats
            Row(children: [
              Expanded(child: _statCol('Presupuesto', '${Money.fmt(monto)}', AppTheme.textPrimary)),
              Expanded(child: _statCol('Gastado', '${Money.fmt(gastado)}', color)),
              Expanded(child: _statCol('Disponible',
                  '${Money.fmt(disponible)}',
                  disponible >= 0 ? AppTheme.success : AppTheme.danger)),
            ]),
            const SizedBox(height: 14),

            // Barra progreso
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 10,
                color: color,
                backgroundColor: AppTheme.surfaceAlt,
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${pct.toStringAsFixed(1)}% usado',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              Text('${Money.fmt(cuota)}/mes por $numMeses mes${numMeses > 1 ? 'es' : ''}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),

            // Descripción
            if ((e['descripcion'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 12),
              Text(e['descripcion'] as String,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // Lista de gastos
        Row(children: [
          const Text('GASTOS REGISTRADOS',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Text('(${_gastos.length})',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),

        if (_gastos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Center(
              child: Text('Sin gastos registrados aún.\nToca + para agregar el primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5)),
            ),
          )
        else
          ..._gastos.map((g) => _GastoTile(gasto: g, onEliminar: () => _eliminarGasto(g))),

        const SizedBox(height: 100),
      ],
    );
  }

  Widget _statCol(String label, String valor, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(valor, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    ],
  );

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppTheme.textSecondary),
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary)),
  );
}

class _GastoTile extends StatelessWidget {
  final Map<String, dynamic> gasto;
  final VoidCallback onEliminar;
  const _GastoTile({required this.gasto, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(gasto['monto']?.toString() ?? '0') ?? 0.0;
    final fecha = gasto['fecha'] as String? ?? '';
    final notas = gasto['notas'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        const Icon(Icons.receipt_long_outlined, color: AppTheme.textMuted, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gasto['nombre'] as String? ?? '',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            if (fecha.isNotEmpty || notas.isNotEmpty)
              Text(
                [if (fecha.isNotEmpty) fecha, if (notas.isNotEmpty) notas].join(' · '),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
          ]),
        ),
        Text('${Money.fmt(monto)}',
            style: const TextStyle(color: AppTheme.warning, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onEliminar,
          child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 18),
        ),
      ]),
    );
  }
}
