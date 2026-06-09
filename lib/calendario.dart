/// Pantalla del calendario de pagos y cobros.
///
/// Organizada en 2 tabs:
///   - **Calendario**: vista mensual con puntitos de colores sobre cada día
///     que tiene eventos. Al seleccionar un día se muestra el panel de eventos.
///   - **Lista**: todos los eventos del mes con filtros por estado.
///
/// ## FIX CRÍTICO: comparación de fechas por string
/// `table_calendar` crea sus `DateTime` internamente con hora 00:00:00 UTC,
/// pero `json.decode` puede parsear fechas con offset local. `isSameDay()` del
/// paquete compara con precisión de microsegundos y puede fallar por timezone.
///
/// La solución es formatear ambas fechas a `"YYYY-MM-DD"` y comparar strings:
/// ```dart
/// String _toDateStr(DateTime d) =>
///     '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
/// ```
/// Esto es 100% timezone-proof y evita el bug de "día en blanco".
///
/// ## Notificaciones
/// Al cargar los eventos del mes, filtra los pendientes en los próximos 3 días
/// y llama a [NotificationService.mostrarResumenDiario] si hay alguno.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/notification_service.dart';

/// Pantalla de calendario de pagos y cobros con tabs Calendario / Lista.
class CalendarioScreen extends StatefulWidget {
  final String firebaseUid;
  const CalendarioScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CalendarioScreenState createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  /// Mes actualmente visible en el calendario. Cambia al navegar entre meses.
  DateTime _focusedDay  = DateTime.now();

  /// Día seleccionado por el usuario. Almacenado SIN componente de hora
  /// para evitar problemas de timezone en las comparaciones.
  DateTime? _selectedDay;

  /// Lista de eventos del mes cargado (todos, sin filtrar).
  List<Map<String, dynamic>> _eventos = [];
  bool _loading = true;

  /// Filtro activo en la vista Lista: 'todos' | 'pendiente' | 'pagado' | 'vencido'.
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    // Inicializar el día seleccionado sin hora (solo año/mes/día)
    _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _cargarEventos();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  // ─── FIX CLAVE: comparación por string ──────────────────────────────────────
  // Convierte un DateTime a "YYYY-MM-DD" para comparar sin timezone.
  // NO usar isSameDay() de table_calendar — tiene bug con fechas parseadas desde JSON.
  String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Extrae solo la parte de fecha "YYYY-MM-DD" de un valor del backend.
  /// El backend devuelve fechas como "2025-05-15T00:00:00.000Z" o "2025-05-15".
  String _fechaEvStr(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// Retorna los eventos del [day] comparando solo la fecha (sin hora).
  /// Este método lo usa `table_calendar` como `eventLoader`.
  List<Map<String, dynamic>> _eventosDelDia(DateTime day) {
    final dayStr = _toDateStr(day);
    return _eventos.where((e) => _fechaEvStr(e['fecha_evento']) == dayStr).toList();
  }
  // ────────────────────────────────────────────────────────────────────────────

  /// Carga los eventos del mes visible desde GET /calendario/eventos.
  ///
  /// Envía `mes` y `anio` del `_focusedDay` para que el backend filtre
  /// solo los eventos del mes mostrado en pantalla.
  /// Tras cargar, lanza notificaciones para los próximos 3 días.
  Future<void> _cargarEventos() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/calendario/eventos?firebase_uid=${widget.firebaseUid}'
        '&mes=${_focusedDay.month}&anio=${_focusedDay.year}',
      );
      if (res.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(json.decode(res.body));
        setState(() { _eventos = data; _loading = false; });
        _notificarProximos(data); // disparar notificación si hay pagos en 3 días
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar eventos: $e')),
      );
    }
  }

  /// Filtra los eventos pendientes en los próximos 3 días y muestra notificación.
  ///
  /// Usa [_parseFechaDt] para construir un DateTime sin hora, evitando
  /// comparaciones incorrectas por timezone.
  void _notificarProximos(List<Map<String, dynamic>> eventos) {
    final hoy   = DateTime.now();
    final limite = hoy.add(const Duration(days: 3));
    final proximos = eventos.where((e) {
      if (e['estado'] != 'pendiente') return false;
      final f = _parseFechaDt(e['fecha_evento']);
      // Comparar contra el día de hoy (sin hora) para evitar falsos negativos
      return f != null
          && !f.isBefore(DateTime(hoy.year, hoy.month, hoy.day))
          && !f.isAfter(limite);
    }).toList();
    if (proximos.isNotEmpty) NotificationService.mostrarResumenDiario(proximos);
  }

  /// Parsea una fecha del backend a [DateTime] sin componente de hora.
  ///
  /// Construye el DateTime manualmente desde partes "YYYY-MM-DD"
  /// en lugar de usar `DateTime.parse()` que añade timezone local.
  DateTime? _parseFechaDt(dynamic v) {
    if (v == null) return null;
    try {
      final s     = _fechaEvStr(v);
      final parts = s.split('-');
      if (parts.length != 3) return null;
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    } catch (_) { return null; }
  }

  /// Eventos filtrados según el estado seleccionado en la pestaña Lista.
  List<Map<String, dynamic>> get _eventosFiltrados {
    if (_filtro == 'todos') return _eventos;
    return _eventos.where((e) => e['estado'] == _filtro).toList();
  }

  /// Color del punto del evento según su estado y tipo.
  ///
  /// - pagado → verde
  /// - vencido → rojo
  /// - cobro pendiente → amarillo (primario)
  /// - pago pendiente → azul
  Color _colorEvento(Map<String, dynamic> e) {
    final estado = e['estado'] as String? ?? 'pendiente';
    final tipo   = e['tipo']   as String? ?? 'pago';
    if (estado == 'pagado')  return AppTheme.success;
    if (estado == 'vencido') return AppTheme.danger;
    return tipo == 'cobro' ? AppTheme.primary : AppTheme.colorFijo;
  }

  /// Marca un evento como pagado.
  ///
  /// Siempre usa estado 'pagado' (el ENUM de calendario_eventos solo acepta
  /// 'pendiente','pagado','vencido' — 'cobrado' es inválido y causa error MySQL).
  /// Para eventos tipo 'cobro' también actualiza cobros_clientes con el monto real.
  Future<void> _marcarPagado(Map<String, dynamic> evento) async {
    if (evento['tipo'] == 'cobro' && evento['cobro_id'] != null) {
      final monto = evento['monto_esperado'];
      if (monto != null) {
        await ApiClient.put('/cobros/${evento['cobro_id']}/cobrar',
            {'monto_cobrado': monto, 'firebase_uid': widget.firebaseUid});
      }
    }
    await ApiClient.put('/calendario/eventos/${evento['id']}/estado',
        {'estado': 'pagado', 'firebase_uid': widget.firebaseUid});
    _cargarEventos();
  }

  /// Elimina un evento tras preguntar si solo este o todos los futuros.
  ///
  /// El backend interpreta el parámetro `solo_este` para decidir si
  /// elimina solo el evento seleccionado o todos los eventos futuros
  /// del mismo gasto (eventos recurrentes con mismo `gasto_id`).
  Future<void> _eliminarEvento(Map<String, dynamic> evento) async {
    final solo = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar evento', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar solo este o todos los futuros?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Todos los futuros', style: TextStyle(color: AppTheme.danger)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Solo este'),
          ),
        ],
      ),
    );
    if (solo == null) return; // usuario canceló
    await ApiClient.delete(
        '/calendario/eventos/${evento['id']}?firebase_uid=${widget.firebaseUid}&solo_este=$solo');
    _cargarEventos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Calendario de pagos',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Muestra todos tus pagos y cobros programados en el mes.\n\n'
                  'Vista Calendario:\n'
                  '  • Los puntitos de colores indican eventos en ese día.\n'
                  '  • Toca un día para ver sus eventos y marcarlos como pagados.\n\n'
                  'Vista Lista:\n'
                  '  • Filtra por estado: Todos / Pendientes / Pagados / Vencidos.\n'
                  '  • Toca "Pagar" o "Cobrar" para registrar el pago.\n\n'
                  'Colores:\n'
                  '  🔵 Azul → pago pendiente\n'
                  '  🟡 Amarillo → cobro pendiente\n'
                  '  🟢 Verde → pagado/cobrado\n'
                  '  🔴 Rojo → vencido\n\n'
                  'Los eventos se crean automáticamente al agregar gastos con "Fecha fija" '
                  'o al registrar cobros a plazo en el módulo de Ventas.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargarEventos),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Calendario'),
            Tab(icon: Icon(Icons.list, size: 18), text: 'Lista'),
            Tab(icon: Icon(Icons.waterfall_chart, size: 18), text: 'Flujo'),
          ],
        ),
      ),
      body: _loading
          ? Container(
              color: AppTheme.background,
              child: const Center(child: CircularProgressIndicator()),
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [_vistaCalendario(), _vistaLista(), _buildFlujoTab()],
            ),
    );
  }

  // ─── VISTA CALENDARIO ──────────────────────────────────────────────────────
  Widget _vistaCalendario() {
    // Obtener el string del día seleccionado para comparar con eventos
    final selStr    = _selectedDay != null ? _toDateStr(_selectedDay!) : '';
    final eventosHoy = _eventos.where((e) => _fechaEvStr(e['fecha_evento']) == selStr).toList();

    return Column(children: [
      Container(
        color: AppTheme.surface,
        child: TableCalendar<Map<String, dynamic>>(
          firstDay:  DateTime(DateTime.now().year - 1),
          lastDay:   DateTime(DateTime.now().year + 2),
          focusedDay: _focusedDay,
          // Comparar por string para evitar el bug de timezone
          selectedDayPredicate: (d) => _toDateStr(d) == selStr,
          eventLoader: _eventosDelDia,
          onDaySelected: (selected, focused) => setState(() {
            // Guardar sin hora para consistencia con _toDateStr
            _selectedDay = DateTime(selected.year, selected.month, selected.day);
            _focusedDay  = focused;
          }),
          onPageChanged: (focused) {
            // Al cambiar de mes, recargar eventos del nuevo mes
            _focusedDay = focused;
            _cargarEventos();
          },
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            selectedDecoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
            defaultTextStyle:  const TextStyle(color: AppTheme.textPrimary),
            weekendTextStyle:  const TextStyle(color: AppTheme.textSecondary),
            outsideTextStyle:  const TextStyle(color: AppTheme.textMuted),
            selectedTextStyle: const TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold),
            todayTextStyle:    const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
            markersMaxCount: 4,
            cellMargin: const EdgeInsets.all(3),
          ),
          // Constructor personalizado para los puntos de eventos
          calendarBuilders: CalendarBuilders(
            markerBuilder: (ctx, day, events) {
              if (events.isEmpty) return const SizedBox();
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  // Máximo 4 puntos visibles por día
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
            titleTextStyle:  TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
            leftChevronIcon:  Icon(Icons.chevron_left,  color: AppTheme.textSecondary, size: 20),
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

      // Panel inferior: eventos del día seleccionado.
      // FIX: Container con fondo explícito — sin esto el panel aparece blanco
      // en Android en release mode porque el Expanded no hereda el Scaffold color.
      Expanded(
        child: Container(
          color: AppTheme.background,
          child: eventosHoy.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.event_available, size: 40, color: AppTheme.textMuted.withOpacity(0.4)),
                  const SizedBox(height: 10),
                  Text(
                    _selectedDay == null
                        ? 'Selecciona un día'
                        : 'Sin eventos — ${_fmtFecha(_selectedDay!)}',
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
      ),
    ]);
  }

  // ─── VISTA LISTA ───────────────────────────────────────────────────────────
  Widget _vistaLista() {
    final eventos = _eventosFiltrados;
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _TabHint('Tus eventos por fecha: pagos y cobros programados.'),
      ),
      // Filtros de estado: Todos / Pendientes / Pagados / Vencidos
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
        child: Container(
          color: AppTheme.background,
          child: eventos.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  const Text('Sin eventos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text('Crea gastos con fecha fija para verlos aquí',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
      ),
    ]);
  }

  /// Etiqueta visible del filtro de estado.
  String _labelFiltro(String f) {
    switch (f) {
      case 'todos':     return 'Todos';
      case 'pendiente': return 'Pendientes';
      case 'pagado':    return 'Pagados';
      case 'vencido':   return 'Vencidos';
      default:          return f;
    }
  }

  /// Fecha corta en formato dd/MM/yyyy.
  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Fecha larga con día de la semana en español: "lunes, 15 mayo".
  /// Usa DateFormat con locale 'es' que se inicializó en `main()`.
  String _fmtFechaLarga(DateTime d) {
    try { return DateFormat('EEEE, d MMMM', 'es').format(d); }
    catch (_) { return _fmtFecha(d); }
  }

  double _parseMonto(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  Widget _flujoChip(String label, double val, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(color: color, fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text('\$${val.toStringAsFixed(0)}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    ),
  );

  Widget _buildFlujoTab() {
    if (_eventos.isEmpty) return Container(
      color: AppTheme.background,
      child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.waterfall_chart, size: 48, color: AppTheme.textMuted),
        SizedBox(height: 12),
        Text('Sin eventos este mes', style: TextStyle(color: AppTheme.textSecondary)),
      ])),
    );

    final ingresos = _eventos
      .where((e) => e['tipo'] == 'cobro')
      .fold<double>(0.0, (sum, e) => sum + _parseMonto(e['monto_esperado']));
    final gastos = _eventos
      .where((e) => e['tipo'] == 'pago')
      .fold<double>(0.0, (sum, e) => sum + _parseMonto(e['monto_esperado']));
    final balance = ingresos - gastos;

    final Map<String, List<Map<String, dynamic>>> porFecha = {};
    for (final e in _eventos) {
      final fecha = _fechaEvStr(e['fecha_evento']);
      porFecha.putIfAbsent(fecha, () => []).add(e);
    }
    final fechasOrdenadas = porFecha.keys.toList()..sort();

    return Container(
      color: AppTheme.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _TabHint('Cómo entra y sale el dinero cada día del mes.'),
          const SizedBox(height: 12),
          Row(children: [
            _flujoChip('INGRESOS', ingresos, AppTheme.success),
            const SizedBox(width: 8),
            _flujoChip('GASTOS', gastos, AppTheme.danger),
            const SizedBox(width: 8),
            _flujoChip('BALANCE', balance, balance >= 0 ? AppTheme.success : AppTheme.danger),
          ]),
          const SizedBox(height: 20),
          ...fechasOrdenadas.expand<Widget>((fecha) {
            final items = porFecha[fecha]!;
            return [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(fecha, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
              ),
              ...items.map((e) {
                final cobro = e['tipo'] == 'cobro';
                final monto = _parseMonto(e['monto_esperado']);
                final estado = e['estado']?.toString() ?? 'pendiente';
                Color estadoColor;
                if (estado == 'pagado') estadoColor = AppTheme.success;
                else if (estado == 'vencido') estadoColor = AppTheme.danger;
                else estadoColor = AppTheme.primary;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: IntrinsicHeight(
                    child: Row(children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: cobro ? AppTheme.success : AppTheme.danger,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(e['titulo']?.toString() ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      )),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(
                            '${cobro ? '+' : '-'}\$${monto.toStringAsFixed(2)}',
                            style: TextStyle(color: cobro ? AppTheme.success : AppTheme.danger, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: estadoColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                            child: Text(estado, style: TextStyle(color: estadoColor, fontSize: 9, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                );
              }),
            ];
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: balance >= 0 ? AppTheme.success.withOpacity(0.3) : AppTheme.danger.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Text('Balance total del mes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const Spacer(),
              Text(
                '${balance >= 0 ? '+' : ''}\$${balance.toStringAsFixed(2)}',
                style: TextStyle(color: balance >= 0 ? AppTheme.success : AppTheme.danger, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── TARJETA DE EVENTO ────────────────────────────────────────────────────────

/// Tarjeta reutilizable para mostrar un evento del calendario.
///
/// Se usa tanto en la vista Calendario (panel inferior) como en la vista Lista.
/// [showDate] controla si se muestra la fecha junto al estado (útil en la lista).
// J1 — línea explicativa de qué muestra cada tab (Lista vs Flujo)
class _TabHint extends StatelessWidget {
  final String texto;
  const _TabHint(this.texto);
  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.info_outline, color: AppTheme.textMuted, size: 13),
    const SizedBox(width: 6),
    Expanded(child: Text(texto,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontStyle: FontStyle.italic))),
  ]);
}

class _EventoCard extends StatelessWidget {
  final Map<String, dynamic> evento;
  final Color colorEvento;
  final VoidCallback onPagar, onEliminar;
  final bool showDate;
  const _EventoCard({
    required this.evento,
    required this.colorEvento,
    required this.onPagar,
    required this.onEliminar,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final estado  = evento['estado'] as String? ?? 'pendiente';
    final tipo    = evento['tipo']   as String? ?? 'pago';
    final monto   = double.tryParse(evento['monto_esperado']?.toString() ?? '0') ?? 0;
    final hecho   = estado == 'pagado' || estado == 'cobrado';
    final vencido = estado == 'vencido';

    // Calcular días restantes manualmente (no usar DateTime.difference con timezone)
    final fechaStr = evento['fecha_evento']?.toString().substring(0, 10) ?? '';
    int diasRestantes = 0;
    bool esHoy = false;
    try {
      final parts = fechaStr.split('-');
      if (parts.length == 3) {
        final f      = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final hoy    = DateTime.now();
        final hoyN   = DateTime(hoy.year, hoy.month, hoy.day); // sin hora
        diasRestantes = f.difference(hoyN).inDays;
        esHoy = diasRestantes == 0;
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hecho
            ? AppTheme.success.withOpacity(0.04)
            : vencido
                ? AppTheme.danger.withOpacity(0.04)
                : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hecho
              ? AppTheme.success.withOpacity(0.25)
              : vencido
                  ? AppTheme.danger.withOpacity(0.25)
                  : AppTheme.border,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Ícono del tipo de evento
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: colorEvento.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(_iconTipo(tipo, hecho), color: colorEvento, size: 18),
        ),
        const SizedBox(width: 12),

        // Título y badges de estado
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(evento['titulo'] ?? '', style: TextStyle(
            color: hecho ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
            decoration: hecho ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 4),
          Row(children: [
            // Badge PAGO / COBRO
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorEvento.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tipo == 'cobro' ? 'COBRO' : 'PAGO',
                style: TextStyle(color: colorEvento, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 6),
            // Badge de estado con color dinámico según urgencia
            _badgeEstado(estado, diasRestantes, esHoy),
            // Fecha opcional (vista Lista)
            if (showDate && fechaStr.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(fechaStr, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            ],
          ]),
        ])),

        // Monto y botones de acción
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: TextStyle(
            color: hecho ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15,
            decoration: hecho ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 6),
          if (!hecho)
            Row(children: [
              // Botón eliminar
              GestureDetector(onTap: onEliminar,
                  child: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16)),
              const SizedBox(width: 8),
              // Botón Pagar / Cobrar
              GestureDetector(
                onTap: onPagar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorEvento.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: colorEvento.withOpacity(0.3)),
                  ),
                  child: Text(
                    tipo == 'cobro' ? 'Cobrar' : 'Pagar',
                    style: TextStyle(color: colorEvento, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ])
          else
            const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ]),
      ]),
    );
  }

  /// Badge de estado con color y texto según urgencia y días restantes.
  ///
  /// - Listo (pagado/cobrado) → verde
  /// - Vencido → rojo con días de retraso
  /// - Hoy → amarillo "Hoy"
  /// - ≤ 3 días → amarillo "En Nd"
  /// - > 3 días → gris "En Nd"
  Widget _badgeEstado(String estado, int dias, bool esHoy) {
    String label; Color color;
    switch (estado) {
      case 'pagado':
      case 'cobrado':
        label = 'Listo';   color = AppTheme.success; break;
      case 'vencido':
        label = 'Vencido ${dias.abs()}d'; color = AppTheme.danger; break;
      default:
        if (esHoy)        { label = 'Hoy';        color = AppTheme.warning; }
        else if (dias <= 3) { label = 'En ${dias}d'; color = AppTheme.warning; }
        else               { label = 'En ${dias}d'; color = AppTheme.textMuted; }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  /// Ícono del tipo de evento.
  /// Si ya está hecho muestra un check; si no, pago=payment, cobro=attach_money.
  IconData _iconTipo(String tipo, bool hecho) {
    if (hecho) return Icons.check_circle_outline;
    return tipo == 'cobro' ? Icons.attach_money : Icons.payment;
  }
}
