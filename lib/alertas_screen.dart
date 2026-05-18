import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/estado_anual_service.dart';

class AlertasScreen extends StatefulWidget {
  final String firebaseUid;
  final int anio;

  const AlertasScreen({
    Key? key,
    required this.firebaseUid,
    required this.anio,
  }) : super(key: key);

  @override
  State<AlertasScreen> createState() => _AlertasScreenState();
}

class _AlertasScreenState extends State<AlertasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alertas = [];
  String _filtroNivel = 'todos'; // todos | danger | warning | info

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
      final data = await EstadoAnualService.getAlertas(widget.firebaseUid, anio: widget.anio);
      if (!mounted) return;
      setState(() {
        _alertas = (data['alertas'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _marcarLeida(Map<String, dynamic> alerta) async {
    if (alerta['leida'] == 1 || alerta['leida'] == true) return;
    try {
      await EstadoAnualService.marcarAlertaLeida(widget.firebaseUid, alerta['id'] as int);
      if (!mounted) return;
      setState(() => alerta['leida'] = 1);
    } catch (_) {}
  }

  Future<void> _marcarTodasLeidas() async {
    final noLeidas = _alertas.where((a) => a['leida'] == 0 || a['leida'] == false).toList();
    for (final a in noLeidas) {
      try {
        await EstadoAnualService.marcarAlertaLeida(widget.firebaseUid, a['id'] as int);
        a['leida'] = 1;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _alertasFiltradas {
    if (_filtroNivel == 'todos') return _alertas;
    return _alertas.where((a) => a['nivel'] == _filtroNivel).toList();
  }

  @override
  Widget build(BuildContext context) {
    final noLeidas = _alertas.where((a) => a['leida'] == 0 || a['leida'] == false).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Alertas ${widget.anio}${noLeidas > 0 ? ' ($noLeidas nuevas)' : ''}',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
        actions: [
          if (noLeidas > 0)
            TextButton(
              onPressed: _marcarTodasLeidas,
              child: const Text('Marcar todo leído',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? _buildError()
              : _buildContent(),
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
    final filtradas = _alertasFiltradas;

    // Agrupar por mes
    final porMes = <int, List<Map<String, dynamic>>>{};
    for (final a in filtradas) {
      final m = a['mes'] as int? ?? 0;
      porMes.putIfAbsent(m, () => []).add(a);
    }
    final mesesOrdenados = porMes.keys.toList()..sort((a, b) => b.compareTo(a));

    final danger   = _alertas.where((a) => a['nivel'] == 'danger').length;
    final warning  = _alertas.where((a) => a['nivel'] == 'warning').length;
    final info     = _alertas.where((a) => a['nivel'] == 'info').length;

    return Column(
      children: [
        // Filtros + resumen
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chips resumen
              Row(
                children: [
                  if (danger > 0) _chipResumen('$danger crítica${danger > 1 ? 's' : ''}', AppTheme.danger),
                  if (danger > 0) const SizedBox(width: 6),
                  if (warning > 0) _chipResumen('$warning advertencia${warning > 1 ? 's' : ''}', AppTheme.warning),
                  if (warning > 0) const SizedBox(width: 6),
                  if (info > 0) _chipResumen('$info info', AppTheme.info),
                ],
              ),
              const SizedBox(height: 10),
              // Filtros
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filtroChip('Todas', 'todos'),
                    const SizedBox(width: 8),
                    _filtroChip('Críticas', 'danger'),
                    const SizedBox(width: 8),
                    _filtroChip('Advertencias', 'warning'),
                    const SizedBox(width: 8),
                    _filtroChip('Informativas', 'info'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: AppTheme.border, height: 1),

        // Lista
        Expanded(
          child: filtradas.isEmpty
              ? _buildVacio()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: mesesOrdenados.length,
                    itemBuilder: (_, i) {
                      final m = mesesOrdenados[i];
                      final items = porMes[m]!;
                      return _GrupoMes(
                        label: m > 0 && m <= 12 ? _mesesLabel[m] : 'General',
                        alertas: items,
                        onMarcarLeida: _marcarLeida,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildVacio() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.notifications_none, color: AppTheme.textMuted, size: 48),
      const SizedBox(height: 12),
      Text(
        _filtroNivel == 'todos'
            ? 'Sin alertas para ${widget.anio}'
            : 'Sin alertas de este tipo',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
      ),
      const SizedBox(height: 6),
      const Text('Las alertas se generan al registrar gastos en cada mes.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    ]),
  );

  Widget _chipResumen(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _filtroChip(String label, String valor) {
    final activo = _filtroNivel == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroNivel = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: activo ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: activo ? AppTheme.primary : AppTheme.border,
              width: activo ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: activo ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: activo ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _GrupoMes extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> alertas;
  final Future<void> Function(Map<String, dynamic>) onMarcarLeida;

  const _GrupoMes({
    required this.label,
    required this.alertas,
    required this.onMarcarLeida,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8)),
        ),
        ...alertas.map((a) => _AlertaTile(alerta: a, onMarcarLeida: onMarcarLeida)),
      ],
    );
  }
}

class _AlertaTile extends StatelessWidget {
  final Map<String, dynamic> alerta;
  final Future<void> Function(Map<String, dynamic>) onMarcarLeida;

  const _AlertaTile({required this.alerta, required this.onMarcarLeida});

  Color get _color {
    switch (alerta['nivel'] as String? ?? '') {
      case 'danger':  return AppTheme.danger;
      case 'warning': return AppTheme.warning;
      default:        return AppTheme.info;
    }
  }

  IconData get _icon {
    switch (alerta['nivel'] as String? ?? '') {
      case 'danger':  return Icons.error_outline;
      case 'warning': return Icons.warning_amber_outlined;
      default:        return Icons.info_outline;
    }
  }

  bool get _leida => alerta['leida'] == 1 || alerta['leida'] == true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onMarcarLeida(alerta),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _leida ? AppTheme.surfaceAlt : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _leida ? AppTheme.border : _color.withOpacity(0.4),
              width: _leida ? 1 : 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: _leida ? AppTheme.textMuted : _color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alerta['titulo'] as String? ?? '',
                          style: TextStyle(
                              color: _leida ? AppTheme.textSecondary : AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: _leida ? FontWeight.normal : FontWeight.w600),
                        ),
                      ),
                      if (!_leida)
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alerta['mensaje'] as String? ?? '',
                    style: TextStyle(
                        color: _leida ? AppTheme.textMuted : AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                  ),
                  if ((alerta['accion_sugerida'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '→ ${alerta['accion_sugerida']}',
                      style: TextStyle(
                          color: _leida ? AppTheme.textMuted : _color,
                          fontSize: 11,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
