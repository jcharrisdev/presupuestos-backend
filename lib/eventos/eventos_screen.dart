import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/eventos_service.dart';
import '../widgets/empty_state.dart';
import 'crear_evento_sheet.dart';
import 'evento_detalle_screen.dart';
import '../utils/money.dart';

class EventosScreen extends StatefulWidget {
  final String firebaseUid;
  final int anio;

  const EventosScreen({Key? key, required this.firebaseUid, required this.anio}) : super(key: key);

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _eventos = [];

  static const _mesesLabel = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await EventosService.getEventos(widget.firebaseUid, widget.anio);
      if (!mounted) return;
      setState(() {
        _eventos = (data['eventos'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _abrirCrear() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CrearEventoSheet(firebaseUid: widget.firebaseUid, anio: widget.anio),
    );
    if (ok == true) _cargar();
  }

  double _totalPresupuestado() =>
      _eventos.fold(0.0, (s, e) => s + (e['monto_total'] as num).toDouble());

  double _totalGastado() =>
      _eventos.fold(0.0, (s, e) => s + (e['gastado_real'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Eventos ${widget.anio}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirCrear,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? _buildError()
              : RefreshIndicator(onRefresh: _cargar, child: _buildContent()),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
      const SizedBox(height: 12),
      Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
    ]),
  );

  Widget _buildContent() {
    if (_eventos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 24),
        children: [
          EmptyState(
            icon: Icons.celebration_outlined,
            title: 'Sin eventos presupuestados',
            subtitle: 'Vacaciones, bodas, cumpleaños...',
            actionLabel: 'Crear evento',
            onAction: _abrirCrear,
          ),
        ],
      );
    }

    final total = _totalPresupuestado();
    final gastado = _totalGastado();
    final pct = total > 0 ? (gastado / total).clamp(0.0, 1.0) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Resumen anual
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Resumen de eventos',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _statCol('Presupuestado', '${Money.fmt(total)}', AppTheme.textPrimary)),
              Expanded(child: _statCol('Gastado', '${Money.fmt(gastado)}', AppTheme.warning)),
              Expanded(child: _statCol('Disponible',
                  '${Money.fmt((total - gastado))}',
                  total - gastado >= 0 ? AppTheme.success : AppTheme.danger)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                color: pct > 0.9 ? AppTheme.danger : pct > 0.7 ? AppTheme.warning : AppTheme.primary,
                backgroundColor: AppTheme.surfaceAlt,
              ),
            ),
            const SizedBox(height: 4),
            Text('${(pct * 100).toStringAsFixed(0)}% del presupuesto total usado',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 16),

        // Lista de eventos
        ..._eventos.map((e) => _EventoCard(
          evento: e,
          mesesLabel: _mesesLabel,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventoDetalleScreen(
              firebaseUid: widget.firebaseUid,
              eventoId: e['id'] as int,
            )),
          ).then((_) => _cargar()),
        )),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _statCol(String label, String valor, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(valor, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
    ],
  );
}

class _EventoCard extends StatelessWidget {
  final Map<String, dynamic> evento;
  final List<String> mesesLabel;
  final VoidCallback onTap;

  const _EventoCard({required this.evento, required this.mesesLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final monto   = (evento['monto_total'] as num).toDouble();
    final gastado = (evento['gastado_real'] as num).toDouble();
    final cuota   = (evento['cuota_mensual'] as num).toDouble();
    final pct     = (evento['pct_avance'] as num).toDouble();
    final mesIni  = evento['mes_inicio'] as int;
    final mesFin  = evento['mes_fin'] as int;
    final emoji   = evento['emoji'] as String? ?? '🎯';
    final numMeses = evento['num_meses'] as int;

    final color = pct >= 100 ? AppTheme.danger : pct >= 80 ? AppTheme.warning : AppTheme.success;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(evento['nombre'] as String? ?? '',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  mesIni == mesFin
                      ? mesesLabel[mesIni]
                      : '${mesesLabel[mesIni]} → ${mesesLabel[mesFin]} ($numMeses meses)',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${Money.fmt(monto)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              Text('${Money.fmt(cuota)}/mes',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: AppTheme.surfaceAlt,
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Gastado: ${Money.fmt(gastado)}',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            Text('${pct.toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}
