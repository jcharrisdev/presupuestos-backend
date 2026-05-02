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

  // Filtro para la vista lista
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _tabCtrl  = TabController(length: 2, vsync: this);
    _selectedDay = DateTime.now();
    _cargarEventos();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEventos() async {
    setState(() => _loading = true);
    try {
      final mes  = _focusedDay.month;
      final anio = _focusedDay.year;
      final res = await ApiClient.get('/calendario/eventos?firebase_uid=${widget.firebaseUid}&mes=$mes&anio=$anio');
      if (res.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(json.decode(res.body));
        setState(() { _eventos = data; _loading = false; });
        _verificarProximos(data);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _verificarProximos(List<Map<String, dynamic>> eventos) {
    final hoy   = DateTime.now();
    final limite = hoy.add(const Duration(days: 3));
    final proximos = eventos.where((e) {
      if (e['estado'] != 'pendiente') return false;
      final f = _parseFecha(e['fecha_evento']);
      return f != null && !f.isBefore(hoy) && !f.isAfter(limite);
    }).toList();
    if (proximos.isNotEmpty) NotificationService.mostrarResumenDiario(proximos);
  }

  List<Map<String, dynamic>> _eventosDelDia(DateTime day) {
    return _eventos.where((e) {
      final f = _parseFecha(e['fecha_evento']);
      return f != null && isSameDay(f, day);
    }).toList();
  }

  List<Map<String, dynamic>> get _eventosFiltrados {
    if (_filtro == 'todos') return _eventos;
    return _eventos.where((e) => e['estado'] == _filtro).toList();
  }

  DateTime? _parseFecha(dynamic v) {
    if (v == null) return null;
    try { return DateTime.parse(v.toString().split('T')[0]); } catch (_) { return null; }
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'pagado':  return AppTheme.success;
      case 'vencido': return AppTheme.danger;
      default:        return AppTheme.colorFijo;
    }
  }

  IconData _iconEstado(String? estado) {
    switch (estado) {
      case 'pagado':  return Icons.check_circle;
      case 'vencido': return Icons.warning_amber_rounded;
      default:        return Icons.radio_button_unchecked;
    }
  }

  Future<void> _marcarPagado(Map<String, dynamic> evento) async {
    final res = await ApiClient.put('/calendario/eventos/${evento['id']}/estado',
        {'estado': 'pagado', 'firebase_uid': widget.firebaseUid});
    if (res.statusCode == 200) _cargarEventos();
  }

  Future<void> _eliminarEvento(Map<String, dynamic> evento) async {
    final solo = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar evento', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar solo este evento o todos los futuros de este gasto?', style: TextStyle(color: AppTheme.textSecondary)),
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

  Widget _vistaCalendario() {
    final eventosSeleccionados = _selectedDay != null ? _eventosDelDia(_selectedDay!) : <Map<String, dynamic>>[];

    return Column(children: [
      // Calendario
      TableCalendar<Map<String, dynamic>>(
        firstDay: DateTime(DateTime.now().year - 1),
        lastDay: DateTime(DateTime.now().year + 2),
        focusedDay: _focusedDay,
        selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
        eventLoader: _eventosDelDia,
        onDaySelected: (selected, focused) => setState(() { _selectedDay = selected; _focusedDay = focused; }),
        onPageChanged: (focused) {
          _focusedDay = focused;
          _cargarEventos();
        },
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          selectedDecoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.25), shape: BoxShape.circle),
          defaultTextStyle: const TextStyle(color: AppTheme.textPrimary),
          weekendTextStyle: const TextStyle(color: AppTheme.textSecondary),
          outsideTextStyle: const TextStyle(color: AppTheme.textMuted),
          selectedTextStyle: const TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold),
          todayTextStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
          markersMaxCount: 3,
          markerDecoration: const BoxDecoration(color: AppTheme.colorFijo, shape: BoxShape.circle),
          markerSize: 5.5,
          markerMargin: const EdgeInsets.symmetric(horizontal: 1),
          cellMargin: const EdgeInsets.all(4),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (ctx, day, events) {
            if (events.isEmpty) return const SizedBox();
            return Positioned(
              bottom: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: events.take(3).map((e) => Container(
                  width: 5, height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: _colorEstado(e['estado']), shape: BoxShape.circle),
                )).toList(),
              ),
            );
          },
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
          leftChevronIcon: const Icon(Icons.chevron_left, color: AppTheme.textSecondary, size: 20),
          rightChevronIcon: const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(color: AppTheme.surface),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          weekendStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        calendarFormat: CalendarFormat.month,
        rowHeight: 44,
      ),

      const Divider(color: AppTheme.border, height: 1),

      // Panel de eventos del día seleccionado
      Expanded(child: _selectedDay == null || eventosSeleccionados.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.event_available, size: 40, color: AppTheme.textMuted.withOpacity(0.4)),
              const SizedBox(height: 10),
              Text(
                _selectedDay == null ? 'Selecciona un día' : 'Sin eventos este día',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ]))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    DateFormat('EEEE, d MMMM', 'es').format(_selectedDay!),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.5),
                  ),
                ),
                ...eventosSeleccionados.map((e) => _EventoCard(
                  evento: e,
                  onPagar: () => _marcarPagado(e),
                  onEliminar: () => _eliminarEvento(e),
                )),
              ],
            ),
      ),
    ]);
  }

  Widget _vistaLista() {
    final eventos = _eventosFiltrados;

    return Column(children: [
      // Filtros
      Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          _FiltroChip('todos',    'Todos',    _filtro, (v) => setState(() => _filtro = v)),
          const SizedBox(width: 8),
          _FiltroChip('pendiente','Pendientes',_filtro,(v) => setState(() => _filtro = v)),
          const SizedBox(width: 8),
          _FiltroChip('pagado',  'Pagados',   _filtro, (v) => setState(() => _filtro = v)),
          const SizedBox(width: 8),
          _FiltroChip('vencido', 'Vencidos',  _filtro, (v) => setState(() => _filtro = v)),
        ]),
      ),
      const Divider(color: AppTheme.border, height: 1),

      Expanded(child: eventos.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text('Sin eventos ${_filtro == "todos" ? "" : "($_filtro)"}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              const SizedBox(height: 6),
              const Text('Crea gastos con fecha fija para verlos aquí', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: eventos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _EventoCard(
                evento: eventos[i],
                onPagar: () => _marcarPagado(eventos[i]),
                onEliminar: () => _eliminarEvento(eventos[i]),
                showDate: true,
              ),
            ),
      ),
    ]);
  }
}

class _FiltroChip extends StatelessWidget {
  final String value, label, selected;
  final ValueChanged<String> onTap;
  const _FiltroChip(this.value, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
        )),
      ),
    );
  }
}

class _EventoCard extends StatelessWidget {
  final Map<String, dynamic> evento;
  final VoidCallback onPagar, onEliminar;
  final bool showDate;
  const _EventoCard({required this.evento, required this.onPagar, required this.onEliminar, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final estado = evento['estado'] as String? ?? 'pendiente';
    final monto  = double.tryParse(evento['monto_esperado']?.toString() ?? '0') ?? 0;
    final fecha  = _parseFecha(evento['fecha_evento']);
    final pagado = estado == 'pagado';
    final vencido = estado == 'vencido';

    int diasRestantes = 0;
    bool esHoy = false;
    if (fecha != null) {
      final hoy = DateTime.now();
      final diff = fecha.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
      diasRestantes = diff;
      esHoy = diff == 0;
    }

    Color borderColor = AppTheme.border;
    if (pagado) borderColor = AppTheme.success.withOpacity(0.3);
    else if (vencido) borderColor = AppTheme.danger.withOpacity(0.3);
    else if (esHoy) borderColor = AppTheme.warning.withOpacity(0.5);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pagado ? AppTheme.success.withOpacity(0.04) : vencido ? AppTheme.danger.withOpacity(0.04) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icono
        Container(
          width: 38, height: 38,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: _colorEstado(estado).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_iconEstado(estado), color: _colorEstado(estado), size: 18),
        ),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(evento['titulo'] ?? '', style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
            decoration: pagado ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 4),
          Row(children: [
            if (showDate && fecha != null) ...[
              Text(DateFormat('d MMM', 'es').format(fecha), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              const SizedBox(width: 8),
            ],
            _badgeEstado(estado, diasRestantes, esHoy),
          ]),
        ])),

        // Monto y acción
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: pagado ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
            decoration: pagado ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 6),
          if (!pagado)
            Row(children: [
              GestureDetector(
                onTap: onEliminar,
                child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPagar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: const Text('Pagar', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ])
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),
    );
  }

  Widget _badgeEstado(String estado, int dias, bool esHoy) {
    String label;
    Color color;
    if (estado == 'pagado') { label = 'Pagado'; color = AppTheme.success; }
    else if (estado == 'vencido') { label = 'Vencido ${dias.abs()}d'; color = AppTheme.danger; }
    else if (esHoy) { label = 'Hoy'; color = AppTheme.warning; }
    else if (dias <= 3) { label = 'En ${dias}d'; color = AppTheme.warning; }
    else { label = 'En ${dias}d'; color = AppTheme.textMuted; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Color _colorEstado(String? e) {
    switch (e) {
      case 'pagado':  return AppTheme.success;
      case 'vencido': return AppTheme.danger;
      default:        return AppTheme.colorFijo;
    }
  }

  IconData _iconEstado(String? e) {
    switch (e) {
      case 'pagado':  return Icons.check_circle_outline;
      case 'vencido': return Icons.error_outline;
      default:        return Icons.payment;
    }
  }

  DateTime? _parseFecha(dynamic v) {
    if (v == null) return null;
    try { return DateTime.parse(v.toString().split('T')[0]); } catch (_) { return null; }
  }
}
