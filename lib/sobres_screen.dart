import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/sobres_service.dart';

/// Pantalla de sobres (envelope budgeting) para un presupuesto individual.
/// Muestra categorías de gasto con su asignación vs gastado real.
class SobresScreen extends StatefulWidget {
  final int presupuestoId;
  final String firebaseUid;
  final String nombrePresupuesto;
  final int? periodoId;
  final double disponiblePeriodo;

  const SobresScreen({
    Key? key,
    required this.presupuestoId,
    required this.firebaseUid,
    required this.nombrePresupuesto,
    this.periodoId,
    this.disponiblePeriodo = 0,
  }) : super(key: key);

  @override
  State<SobresScreen> createState() => _SobresScreenState();
}

class _SobresScreenState extends State<SobresScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _resumen;
  List<dynamic> _gastos = [];
  bool _loadingResumen = true;
  bool _loadingGastos = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && _tabs.index == 1 && _gastos.isEmpty) {
        _cargarGastos();
      }
    });
    _cargarResumen();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarResumen() async {
    setState(() => _loadingResumen = true);
    try {
      final data = await SobresService.getResumenSobres(
        widget.presupuestoId, widget.firebaseUid,
        periodoId: widget.periodoId,
      );
      if (!mounted) return;
      setState(() { _resumen = data; _loadingResumen = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingResumen = false);
    }
  }

  Future<void> _cargarGastos() async {
    setState(() => _loadingGastos = true);
    try {
      final data = await SobresService.getGastos(
        widget.presupuestoId, widget.firebaseUid,
        periodoId: widget.periodoId,
      );
      if (!mounted) return;
      setState(() {
        _gastos = data['gastos'] as List? ?? [];
        _loadingGastos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingGastos = false);
    }
  }

  void _mostrarFormCategoria([Map<String, dynamic>? cat]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CategoriaFormSheet(
        presupuestoId: widget.presupuestoId,
        firebaseUid: widget.firebaseUid,
        categoria: cat,
        disponible: widget.disponiblePeriodo,
        onGuardado: () { Navigator.pop(context); _cargarResumen(); },
      ),
    );
  }

  void _mostrarFormGasto() {
    final categorias =
        (_resumen?['categorias'] as List? ?? []).cast<Map<String, dynamic>>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _GastoRapidoSheet(
        presupuestoId: widget.presupuestoId,
        firebaseUid: widget.firebaseUid,
        periodoId: widget.periodoId,
        categorias: categorias,
        onGuardado: () {
          Navigator.pop(context);
          _cargarResumen();
          if (_tabs.index == 1) _cargarGastos();
        },
      ),
    );
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
        title: Text('Sobres — ${widget.nombrePresupuesto}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            tooltip: 'Nueva categoría',
            onPressed: _mostrarFormCategoria,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Mis Sobres'),
            Tab(text: 'Registro'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormGasto,
        icon: const Icon(Icons.add),
        label: const Text('Registrar gasto'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TabSobres(
            resumen: _resumen,
            loading: _loadingResumen,
            disponible: widget.disponiblePeriodo,
            onRefresh: _cargarResumen,
            onEditarCategoria: _mostrarFormCategoria,
          ),
          _TabRegistro(
            gastos: _gastos,
            loading: _loadingGastos,
            onRefresh: _cargarGastos,
            onEliminar: (id) async {
              await SobresService.eliminarGasto(
                  widget.presupuestoId, id, widget.firebaseUid);
              _cargarResumen();
              _cargarGastos();
            },
          ),
        ],
      ),
    );
  }
}

// ── Tab Sobres ─────────────────────────────────────────────────────────────────

class _TabSobres extends StatelessWidget {
  final Map<String, dynamic>? resumen;
  final bool loading;
  final double disponible;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic>) onEditarCategoria;

  const _TabSobres({
    required this.resumen,
    required this.loading,
    required this.disponible,
    required this.onRefresh,
    required this.onEditarCategoria,
  });

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final cats = (resumen?['categorias'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final totalAsignado = _d(resumen?['total_asignado']);
    final totalGastado = _d(resumen?['total_gastado']);
    final sinAsignar = _d(resumen?['sin_asignar']);
    final sinCategoria = _d(resumen?['gastos_sin_categoria']);

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Banner resumen
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(children: [
              _ResumenRow('Disponible del período',
                  '\$${disponible.toStringAsFixed(2)}', AppTheme.primary),
              _ResumenRow('Total asignado en sobres',
                  '\$${totalAsignado.toStringAsFixed(2)}', AppTheme.textSecondary),
              _ResumenRow('Total gastado',
                  '\$${totalGastado.toStringAsFixed(2)}', AppTheme.danger),
              const Divider(color: AppTheme.border, height: 12),
              _ResumenRow(
                'Sin asignar',
                '\$${(disponible - totalAsignado).toStringAsFixed(2)}',
                (disponible - totalAsignado) >= 0
                    ? AppTheme.success
                    : AppTheme.warning,
                bold: true,
              ),
            ]),
          ),

          const SizedBox(height: 20),

          if (cats.isEmpty)
            _EmptyState(
              icon: Icons.inbox_outlined,
              mensaje: 'Crea sobres para distribuir tu dinero disponible.',
            )
          else ...[
            const _SectionLabel('TUS SOBRES'),
            const SizedBox(height: 10),
            ...cats.map((c) => _SobreTile(
                  cat: c,
                  onEditar: () => onEditarCategoria(c),
                )),

            if (sinCategoria > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  const Icon(Icons.help_outline,
                      color: AppTheme.textMuted, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gastos sin categoría: \$${sinCategoria.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class _SobreTile extends StatelessWidget {
  final Map<String, dynamic> cat;
  final VoidCallback onEditar;
  const _SobreTile({required this.cat, required this.onEditar});

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final nombre = cat['nombre'] as String? ?? '';
    final asignado = _d(cat['monto_asignado']);
    final gastado = _d(cat['monto_gastado']);
    final restante = _d(cat['restante']);
    final pct = (cat['porcentaje'] as int? ?? 0).clamp(0, 100);
    final colorHex = cat['color'] as String? ?? '#6B7280';
    final Color color = _hexColor(colorHex);
    final excedido = restante < 0;

    return GestureDetector(
      onTap: onEditar,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: excedido
                  ? AppTheme.danger.withOpacity(0.4)
                  : AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.inbox_outlined, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(nombre,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(
                    'Asignado: \$${asignado.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                excedido
                    ? '-\$${restante.abs().toStringAsFixed(2)}'
                    : '\$${restante.toStringAsFixed(2)}',
                style: TextStyle(
                    color: excedido ? AppTheme.danger : AppTheme.success,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
              Text(excedido ? 'excedido' : 'restante',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 10)),
            ]),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(
                  excedido ? AppTheme.danger : color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
              'Gastado: \$${gastado.toStringAsFixed(2)} ($pct%)',
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 10)),
        ]),
      ),
    );
  }

  Color _hexColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppTheme.textMuted;
    }
  }
}

// ── Tab Registro ───────────────────────────────────────────────────────────────

class _TabRegistro extends StatelessWidget {
  final List<dynamic> gastos;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int) onEliminar;

  const _TabRegistro({
    required this.gastos,
    required this.loading,
    required this.onRefresh,
    required this.onEliminar,
  });

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (gastos.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onRefresh: onRefresh,
        child: ListView(children: [
          const SizedBox(height: 80),
          _EmptyState(
            icon: Icons.receipt_long_outlined,
            mensaje:
                'Toca "+ Registrar gasto" para anotar lo que gastas.',
          ),
        ]),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: gastos.length,
        itemBuilder: (context, i) {
          final g = gastos[i] as Map<String, dynamic>;
          final monto = _d(g['monto']);
          final desc = g['descripcion'] as String? ?? 'Sin descripción';
          final fecha =
              (g['fecha'] as String? ?? '').substring(0, 10);
          final catNombre = g['categoria_nombre'] as String? ?? 'Sin sobre';
          final esHormiga = (g['es_hormiga'] as int? ?? 0) == 1;

          return Dismissible(
            key: ValueKey(g['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline,
                  color: AppTheme.danger),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: const Text('Eliminar gasto',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700)),
                  content: const Text('¿Eliminar este registro?',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar')),
                  ],
                ),
              );
            },
            onDismissed: (_) => onEliminar(g['id'] as int),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: esHormiga
                        ? AppTheme.warning.withOpacity(0.1)
                        : AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    esHormiga
                        ? Icons.bug_report_outlined
                        : Icons.receipt_outlined,
                    color: esHormiga
                        ? AppTheme.warning
                        : AppTheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(desc,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('$catNombre · $fecha',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                  ]),
                ),
                Text('-\$${monto.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Bottom sheets ──────────────────────────────────────────────────────────────

class _CategoriaFormSheet extends StatefulWidget {
  final int presupuestoId;
  final String firebaseUid;
  final Map<String, dynamic>? categoria;
  final double disponible;
  final VoidCallback onGuardado;

  const _CategoriaFormSheet({
    required this.presupuestoId,
    required this.firebaseUid,
    this.categoria,
    required this.disponible,
    required this.onGuardado,
  });

  @override
  State<_CategoriaFormSheet> createState() => _CategoriaFormSheetState();
}

class _CategoriaFormSheetState extends State<_CategoriaFormSheet> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _colorSeleccionado = '#4F9CF9';
  bool _loading = false;

  static const _colores = [
    '#4F9CF9', '#F97316', '#22C55E', '#EF4444',
    '#A855F7', '#F59E0B', '#06B6D4', '#EC4899',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.categoria != null) {
      _nombreCtrl.text = widget.categoria!['nombre'] as String? ?? '';
      _montoCtrl.text =
          (widget.categoria!['monto_asignado'] ?? '').toString();
      _colorSeleccionado = widget.categoria!['color'] as String? ??
          _colorSeleccionado;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0;
    if (nombre.isEmpty) return;
    setState(() => _loading = true);
    try {
      final body = {
        'firebase_uid': widget.firebaseUid,
        'nombre': nombre,
        'monto_asignado': monto,
        'color': _colorSeleccionado,
        'icono': 'inbox',
      };
      if (widget.categoria != null) {
        await SobresService.editarCategoria(
            widget.presupuestoId,
            widget.categoria!['id'] as int,
            body);
      } else {
        await SobresService.crearCategoria(widget.presupuestoId, body);
      }
      widget.onGuardado();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          widget.categoria != null ? 'Editar sobre' : 'Nuevo sobre',
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nombreCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
              hintText: 'Nombre del sobre (ej: Supermercado)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _montoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Monto asignado',
            helperText:
                'Disponible este período: \$${widget.disponible.toStringAsFixed(2)}',
            helperStyle:
                const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Color',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: _colores.map((hex) {
          final Color c = _hexColor(hex);
          final selected = hex == _colorSeleccionado;
          return GestureDetector(
            onTap: () => setState(() => _colorSeleccionado = hex),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2),
                boxShadow: selected
                    ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)]
                    : null,
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _guardar,
            child: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : Text(widget.categoria != null
                    ? 'Guardar cambios'
                    : 'Crear sobre'),
          ),
        ),
      ]),
    );
  }

  Color _hexColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppTheme.textMuted;
    }
  }
}

class _GastoRapidoSheet extends StatefulWidget {
  final int presupuestoId;
  final String firebaseUid;
  final int? periodoId;
  final List<Map<String, dynamic>> categorias;
  final VoidCallback onGuardado;

  const _GastoRapidoSheet({
    required this.presupuestoId,
    required this.firebaseUid,
    this.periodoId,
    required this.categorias,
    required this.onGuardado,
  });

  @override
  State<_GastoRapidoSheet> createState() => _GastoRapidoSheetState();
}

class _GastoRapidoSheetState extends State<_GastoRapidoSheet> {
  final _descCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  int? _categoriaSeleccionada;
  bool _esHormiga = false;
  bool _loading = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0;
    if (monto <= 0) return;
    setState(() => _loading = true);
    try {
      await SobresService.registrarGasto(widget.presupuestoId, {
        'firebase_uid': widget.firebaseUid,
        'categoria_id': _categoriaSeleccionada,
        'descripcion': _descCtrl.text.trim(),
        'monto': monto,
        'fecha': DateTime.now().toIso8601String().substring(0, 10),
        'es_hormiga': _esHormiga ? 1 : 0,
        'periodo_id': widget.periodoId,
      });
      widget.onGuardado();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Registrar gasto',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),

        // Selector de sobre
        if (widget.categorias.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('¿En qué sobre?',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _ChipSobre(
              label: 'Sin sobre',
              selected: _categoriaSeleccionada == null,
              onTap: () => setState(() => _categoriaSeleccionada = null),
            ),
            ...widget.categorias.map((c) => _ChipSobre(
                  label: c['nombre'] as String? ?? '',
                  selected: _categoriaSeleccionada == c['id'],
                  onTap: () =>
                      setState(() => _categoriaSeleccionada = c['id'] as int?),
                )),
          ]),
          const SizedBox(height: 14),
        ],

        TextField(
          controller: _montoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
          decoration:
              const InputDecoration(hintText: 'Monto', prefixText: '\$ '),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
              hintText: 'Descripción (opcional)'),
        ),
        const SizedBox(height: 10),

        // Toggle gasto hormiga
        GestureDetector(
          onTap: () => setState(() => _esHormiga = !_esHormiga),
          child: Row(children: [
            Icon(
                _esHormiga
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                color: _esHormiga ? AppTheme.primary : AppTheme.textMuted,
                size: 20),
            const SizedBox(width: 8),
            const Text('Gasto hormiga (pequeño, frecuente)',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ]),
        ),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _guardar,
            child: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('Guardar gasto'),
          ),
        ),
      ]),
    );
  }
}

class _ChipSobre extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChipSobre(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.12)
                : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.border,
                width: selected ? 1.5 : 1),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String mensaje;
  const _EmptyState({required this.icon, required this.mensaje});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppTheme.textMuted.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5)),
        ]),
      );
}

class _ResumenRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _ResumenRow(this.label, this.value, this.color, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: bold ? 15 : 13,
                  fontWeight:
                      bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8));
}
