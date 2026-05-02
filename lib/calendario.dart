import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/notification_service.dart';

class CalendarioScreen extends StatefulWidget {
  final String firebaseUid;
  const CalendarioScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CalendarioScreenState createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  DateTime _focusedDay  = DateTime.now();
  DateTime? _selectedDay;

  List<Map<String, dynamic>> _eventos = [];
  bool _loading = true;
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _cargarEventos();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  // ─── FIX CLAVE: comparación por string (evita problemas de timezone) ────────
  String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fechaEvStr(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  List<Map<String, dynamic>> _eventosDelDia(DateTime day) {
    final dayStr = _toDateStr(day);
    return _eventos.where((e) => _fechaEvStr(e['fecha_evento']) == dayStr).toList();
  }
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _cargarEventos() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/calendario/eventos?firebase_uid=${widget.firebaseUid}&mes=${_focusedDay.month}&anio=${_focusedDay.year}',
      );
      if (res.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(json.decode(res.body));
        setState(() { _eventos = data; _loading = false; });
        _notificarProximos(data);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) { setState(() => _loading = false); }
  }

  void _notificarProximos(List<Map<String, dynamic>> eventos) {
    final hoy = DateTime.now();
    final limite = hoy.add(const Duration(days: 3));
    final proximos = eventos.where((e) {
      if (e['estado'] != 'pendiente') return false;
      final f = _parseFechaDt(e['fecha_evento']);
      return f != null && !f.isBefore(DateTime(hoy.year, hoy.month, hoy.day)) && !f.isAfter(limite);
    }).toList();
    if (proximos.isNotEmpty) NotificationService.mostrarResumenDiario(proximos);
  }

  DateTime? _parseFechaDt(dynamic v) {
    if (v == null) return null;
    try {
      final s = _fechaEvStr(v);
      final parts = s.split('-');
      if (parts.length != 3) return null;
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    } catch (_) { return null; }
  }

  List<Map<String, dynamic>> get _eventosFiltrados {
    if (_filtro == 'todos') return _eventos;
    return _eventos.where((e) => e['estado'] == _filtro).toList();
  }

  Color _colorEvento(Map<String, dynamic> e) {
    final estado = e['estado'] as String? ?? 'pendiente';
    final tipo   = e['tipo'] as String? ?? 'pago';
    if (estado == 'pagado')  return AppTheme.success;
    if (estado == 'vencido') return AppTheme.danger;
    return tipo == 'cobro' ? AppTheme.primary : AppTheme.colorFijo;
  }

  Future<void> _marcarPagado(Map<String, dynamic> evento) async {
    final nuevoEstado = evento['tipo'] == 'cobro' ? 'cobrado' : 'pagado';
    // For cobros, update via cobros endpoint; for pagos, use calendario
    if (evento['tipo'] == 'cobro' && evento['cobro_id'] != null) {
      await ApiClient.put('/cobros/${evento['cobro_id']}/cobrar',
          {'monto_cobrado': evento['monto_esperado'], 'firebase_uid': widget.firebaseUid});
    }
    await ApiClient.put('/calendario/eventos/${evento['id']}/estado',
        {'estado': nuevoEstado, 'firebase_uid': widget.firebaseUid});
    _cargarEventos();
  }

  Future<void> _eliminarEvento(Map<String, dynamic> evento) async {
    final solo = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar evento', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar solo este o todos los futuros?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Todos los futuros', style: TextStyle(color: AppTheme.danger))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Solo este')),
        ],
      ),
    );
    if (solo == null) return;
    await ApiClient.delete('/calendario/eventos/${evento['id']}?firebase_uid=${widget.firebaseUid}&solo_este=$solo');
    _cargarEventos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargarEventos)],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Calendario'),
            Tab(icon: Icon(Icons.list, size: 18), text: 'Lista'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [_vistaCalendario(), _vistaLista()],
            ),
    );
  }

  // ─── VISTA CALENDARIO ────────────────────────────────────────────────────────
  Widget _vistaCalendario() {
    final selStr = _selectedDay != null ? _toDateStr(_selectedDay!) : '';
    final eventosHoy = _eventos.where((e) => _fechaEvStr(e['fecha_evento']) == selStr).toList();

    return Column(children: [
      Container(
        color: AppTheme.surface,
        child: TableCalendar<Map<String, dynamic>>(
          firstDay: DateTime(DateTime.now().year - 1),
          lastDay: DateTime(DateTime.now().year + 2),
          focusedDay: _focusedDay,
          selectedDayPredicate: (d) => _toDateStr(d) == selStr,
          eventLoader: _eventosDelDia,
          onDaySelected: (selected, focused) => setState(() {
            _selectedDay = DateTime(selected.year, selected.month, selected.day);
            _focusedDay  = focused;
          }),
          onPageChanged: (focused) {
            _focusedDay = focused;
            _cargarEventos();
          },
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            selectedDecoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
            defaultTextStyle: const TextStyle(color: AppTheme.textPrimary),
            weekendTextStyle: const TextStyle(color: AppTheme.textSecondary),
            outsideTextStyle: const TextStyle(color: AppTheme.textMuted),
            selectedTextStyle: const TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold),
            todayTextStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
            markersMaxCount: 4,
            cellMargin: const EdgeInsets.all(3),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (ctx, day, events) {
              if (events.isEmpty) return const SizedBox();
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: events.take(4).map((e) => Container(
                    width: 5, height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: _colorEvento(e), shape: BoxShape.circle),
                  )).toList(),
                ),
              );
            },
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
            leftChevronIcon: Icon(Icons.chevron_left, color: AppTheme.textSecondary, size: 20),
            rightChevronIcon: Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
            decoration: BoxDecoration(color: AppTheme.surface),
          ),
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            weekendStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          rowHeight: 44,
        ),
      ),
      const Divider(color: AppTheme.border, height: 1),

      // Panel de eventos del día
      Expanded(
        child: eventosHoy.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.event_available, size: 40, color: AppTheme.textMuted.withOpacity(0.4)),
                const SizedBox(height: 10),
                Text(
                  _selectedDay == null ? 'Selecciona un día' : 'Sin eventos — ${_fmtFecha(_selectedDay!)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ]))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _selectedDay != null ? _fmtFechaLarga(_selectedDay!) : '',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ),
                  ...eventosHoy.map((e) => _EventoCard(
                    evento: e,
                    colorEvento: _colorEvento(e),
                    onPagar: () => _marcarPagado(e),
                    onEliminar: () => _eliminarEvento(e),
                  )),
                ],
              ),
      ),
    ]);
  }

  // ─── VISTA LISTA ─────────────────────────────────────────────────────────────
  Widget _vistaLista() {
    final eventos = _eventosFiltrados;
    return Column(children: [
      Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['todos','pendiente','pagado','vencido'].map((f) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filtro = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _filtro == f ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _filtro == f ? AppTheme.primary : AppTheme.border),
                ),
                child: Text(_labelFiltro(f), style: TextStyle(
                  color: _filtro == f ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 12, fontWeight: _filtro == f ? FontWeight.w700 : FontWeight.normal,
                )),
              ),
            ),
          )).toList()),
        ),
      ),
      const Divider(color: AppTheme.border, height: 1),
      Expanded(
        child: eventos.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('Sin eventos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                const SizedBox(height: 6),
                const Text('Crea gastos con fecha fija para verlos aquí', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: eventos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _EventoCard(
                  evento: eventos[i],
                  colorEvento: _colorEvento(eventos[i]),
                  onPagar: () => _marcarPagado(eventos[i]),
                  onEliminar: () => _eliminarEvento(eventos[i]),
                  showDate: true,
                ),
              ),
      ),
    ]);
  }

  String _labelFiltro(String f) {
    switch (f) {
      case 'todos':     return 'Todos';
      case 'pendiente': return 'Pendientes';
      case 'pagado':    return 'Pagados';
      case 'vencido':   return 'Vencidos';
      default:          return f;
    }
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtFechaLarga(DateTime d) {
    try { return DateFormat('EEEE, d MMMM', 'es').format(d); } catch (_) { return _fmtFecha(d); }
  }
}

// ─── TARJETA DE EVENTO ─────────────────────────────────────────────────────────
class _EventoCard extends StatelessWidget {
  final Map<String, dynamic> evento;
  final Color colorEvento;
  final VoidCallback onPagar, onEliminar;
  final bool showDate;
  const _EventoCard({required this.evento, required this.colorEvento, required this.onPagar, required this.onEliminar, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final estado  = evento['estado'] as String? ?? 'pendiente';
    final tipo    = evento['tipo']   as String? ?? 'pago';
    final monto   = double.tryParse(evento['monto_esperado']?.toString() ?? '0') ?? 0;
    final hecho   = estado == 'pagado' || estado == 'cobrado';
    final vencido = estado == 'vencido';

    final fechaStr = evento['fecha_evento']?.toString().substring(0, 10) ?? '';
    int diasRestantes = 0;
    bool esHoy = false;
    try {
      final parts = fechaStr.split('-');
      if (parts.length == 3) {
        final f = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final hoy = DateTime.now();
        final hoyNorm = DateTime(hoy.year, hoy.month, hoy.day);
        diasRestantes = f.difference(hoyNorm).inDays;
        esHoy = diasRestantes == 0;
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hecho ? AppTheme.success.withOpacity(0.04) : vencido ? AppTheme.danger.withOpacity(0.04) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hecho ? AppTheme.success.withOpacity(0.25) : vencido ? AppTheme.danger.withOpacity(0.25) : AppTheme.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icono tipo
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: colorEvento.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(_iconTipo(tipo, hecho), color: colorEvento, size: 18),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(evento['titulo'] ?? '', style: TextStyle(
            color: hecho ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
            decoration: hecho ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 4),
          Row(children: [
            // Badge tipo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorEvento.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tipo == 'cobro' ? 'COBRO' : 'PAGO', style: TextStyle(color: colorEvento, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 6),
            _badgeEstado(estado, diasRestantes, esHoy),
            if (showDate && fechaStr.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(fechaStr, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            ],
          ]),
        ])),

        // Monto y acción
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: hecho ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
            decoration: hecho ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 6),
          if (!hecho)
            Row(children: [
              GestureDetector(onTap: onEliminar, child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPagar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorEvento.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: colorEvento.withOpacity(0.3)),
                  ),
                  child: Text(tipo == 'cobro' ? 'Cobrar' : 'Pagar',
                      style: TextStyle(color: colorEvento, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ])
          else
            Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),
    );
  }

  Widget _badgeEstado(String estado, int dias, bool esHoy) {
    String label; Color color;
    switch (estado) {
      case 'pagado':  case 'cobrado': label = 'Listo';   color = AppTheme.success; break;
      case 'vencido': label = 'Vencido ${dias.abs()}d'; color = AppTheme.danger;  break;
      default:
        if (esHoy)      { label = 'Hoy';       color = AppTheme.warning; }
        else if (dias <= 3) { label = 'En ${dias}d'; color = AppTheme.warning; }
        else              { label = 'En ${dias}d'; color = AppTheme.textMuted;  }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  IconData _iconTipo(String tipo, bool hecho) {
    if (hecho) return Icons.check_circle_outline;
    return tipo == 'cobro' ? Icons.attach_money : Icons.payment;
  }
}
