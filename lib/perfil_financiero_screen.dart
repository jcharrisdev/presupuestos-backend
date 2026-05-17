import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/user_profile_service.dart';
import 'services/gastos_variables_service.dart';
import 'deudas/deudas_screen.dart';

/// Pantalla central del perfil financiero global del usuario.
/// Fuente de verdad de: ingreso, gastos fijos, deudas y gastos variables.
/// Todo impacta en el "disponible real" que sirve de base para todos los módulos.
class PerfilFinancieroScreen extends StatefulWidget {
  final String firebaseUid;
  const PerfilFinancieroScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<PerfilFinancieroScreen> createState() => _PerfilFinancieroScreenState();
}

class _PerfilFinancieroScreenState extends State<PerfilFinancieroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _income;
  List<dynamic> _gastos = [];
  List<dynamic> _ahorros = [];
  List<dynamic> _variablesBase = [];
  double _totalMensual = 0;
  double _totalAhorrosMensual = 0;
  double _totalVariablesMensual = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    // Sincronizar deudas del perfil sin deuda_id antes de cargar
    await UserProfileService.syncDeudas(widget.firebaseUid);
    final results = await Future.wait([
      UserProfileService.getIncome(widget.firebaseUid),
      UserProfileService.getGastosFijos(widget.firebaseUid),
      UserProfileService.getAhorrosActivos(widget.firebaseUid),
      GastosVariablesService.getAll(widget.firebaseUid),
    ]);
    if (!mounted) return;
    final income = results[0] as Map<String, dynamic>?;
    final gfData = results[1] as Map<String, dynamic>;
    final ahData = results[2] as Map<String, dynamic>;
    final varData = results[3] as Map<String, dynamic>;
    setState(() {
      _income = income;
      _gastos = gfData['gastos'] as List? ?? [];
      _totalMensual = _d(gfData['total_mensual']);
      _ahorros = ahData['ahorros'] as List? ?? [];
      _totalAhorrosMensual = _d(ahData['total_cuota_mensual']);
      _variablesBase = varData['gastos'] as List? ?? [];
      _totalVariablesMensual = _d(varData['total_mensual']);
      _loading = false;
    });
  }

  void _irADeudas() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DeudasScreen(firebaseUid: widget.firebaseUid),
    )).then((_) => _cargar());
  }

  double get _ingreso => _d(_income?['ingreso_neto_mensual']);
  double get _disponible => _ingreso - _totalMensual - _totalAhorrosMensual;
  bool get _esSostenible => _disponible >= 0;

  List<dynamic> get _gastosFijos =>
      _gastos.where((g) => (g['es_deuda'] as int? ?? 0) == 0 && (g['frecuencia'] as String? ?? 'fijo') == 'fijo').toList();
  List<dynamic> get _deudas =>
      _gastos.where((g) => (g['es_deuda'] as int? ?? 0) == 1).toList();
  List<dynamic> get _variables =>
      _gastos.where((g) => (g['es_deuda'] as int? ?? 0) == 0 && (g['frecuencia'] as String? ?? 'fijo') == 'variable').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Mi perfil financiero'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargar),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [Tab(text: 'Ingresos'), Tab(text: 'Fijos'), Tab(text: 'Variables')],
        ),
      ),
      body: _loading
          ? Container(color: AppTheme.background,
              child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)))
          : Column(children: [
              _buildResumenBanner(),
              Expanded(child: TabBarView(controller: _tabs, children: [
                Container(color: AppTheme.background, child: _buildTabIngreso()),
                Container(color: AppTheme.background, child: _buildTabGastos()),
                Container(color: AppTheme.background, child: _buildTabVariablesBase()),
              ])),
            ]),
    );
  }

  // ── Banner de resumen ─────────────────────────────────────────────────────
  Widget _buildResumenBanner() {
    if (_income == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: AppTheme.surface,
        child: const Text(
          'Configura tu ingreso para ver tu disponible real.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _ResumenItem('Ingreso neto', '\$${_ingreso.toStringAsFixed(2)}/mes', AppTheme.success)),
          Container(width: 1, height: 36, color: AppTheme.border),
          Expanded(child: _ResumenItem('Gastos', '\$${_totalMensual.toStringAsFixed(2)}/mes', AppTheme.danger)),
          if (_totalAhorrosMensual > 0) ...[
            Container(width: 1, height: 36, color: AppTheme.border),
            Expanded(child: _ResumenItem('Ahorros', '\$${_totalAhorrosMensual.toStringAsFixed(2)}/mes', AppTheme.colorAhorro)),
          ],
          Container(width: 1, height: 36, color: AppTheme.border),
          Expanded(child: _ResumenItem(
            'Disponible',
            '\$${_disponible.abs().toStringAsFixed(2)}/mes',
            _esSostenible ? AppTheme.success : AppTheme.danger,
            prefix: _esSostenible ? '' : '-',
          )),
        ]),
      ]),
    );
  }

  // ── Tab 1: Ingreso ────────────────────────────────────────────────────────
  Widget _buildTabIngreso() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_esSostenible && _income != null)
          _AlertaBanner(
            'Tus gastos superan tu ingreso en \$${_disponible.abs().toStringAsFixed(2)}/mes. '
            'Revisa tus compromisos o ajusta tu plan.',
          ),
        if (_income == null)
          _EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: '¿Cuánto ganas?',
            subtitle: 'Configura tu ingreso neto para que la app calcule tu disponible real.',
            action: 'Configurar ingreso',
            onAction: _mostrarFormIngreso,
          )
        else ...[
          _InfoCard(rows: [
            _InfoRow('Tipo de ingreso', _labelTipoIngreso(_income!['tipo_ingreso'])),
            _InfoRow('Bruto mensual', '\$${_d(_income!["ingreso_bruto_mensual"]).toStringAsFixed(2)}'),
            if (_d(_income!['desc_seguro']) > 0)
              _InfoRow('  − CSS (9.75%)', '-\$${_d(_income!["desc_seguro"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
            if (_d(_income!['desc_pension']) > 0)
              _InfoRow('  − Educativo (1.25%)', '-\$${_d(_income!["desc_pension"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
            if (_d(_income!['desc_impuesto']) > 0)
              _InfoRow('  − ISR', '-\$${_d(_income!["desc_impuesto"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
            if (_d(_income!['desc_otros']) > 0)
              _InfoRow('  − Otros descuentos', '-\$${_d(_income!["desc_otros"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              const Text('Neto mensual que recibes',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('\$${_ingreso.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.success, fontSize: 28, fontWeight: FontWeight.bold)),
              Text(
                _income!['frecuencia_cobro'] == 'quincenal'
                    ? 'Quincenal: \$${(_ingreso / 2).toStringAsFixed(2)}'
                    : 'Mensual',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _mostrarFormIngreso,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar ingreso'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
              ),
            )),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _confirmarEliminarIngreso,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Eliminar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  // ── Tab 2: Mis gastos (Fijos + Deudas + Variables) ────────────────────────
  Widget _buildTabGastos() {
    final hayGastos = _gastos.isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(child: Text(
            hayGastos
                ? '${_gastos.length} gastos · \$${_totalMensual.toStringAsFixed(2)}/mes'
                : 'Sin gastos registrados',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          )),
          TextButton.icon(
            onPressed: _mostrarFormGasto,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Agregar'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
        ]),
      ),
      Expanded(child: !hayGastos
          ? Center(child: _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin gastos registrados',
              subtitle: 'Agrega tus gastos fijos, deudas y gastos variables estimados.',
              action: 'Agregar gasto',
              onAction: _mostrarFormGasto,
            ))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_gastosFijos.isNotEmpty) ...[
                  _SeccionHeader('GASTOS FIJOS', _gastosFijos.length,
                      '\$${_gastosFijos.fold(0.0, (s, g) => s + _d(g['monto_mensual'])).toStringAsFixed(2)}/mes',
                      const Color(0xFF1890FF)),
                  const SizedBox(height: 6),
                  ..._gastosFijos.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GastoTile(
                      gasto: g as Map<String, dynamic>,
                      onEdit: () => _mostrarFormGasto(gasto: g),
                      onDelete: () => _eliminarGasto((g)['id'] as int),
                    ),
                  )),
                  const SizedBox(height: 8),
                ],
                if (_deudas.isNotEmpty) ...[
                  _SeccionHeader('DEUDAS', _deudas.length,
                      '\$${_deudas.fold(0.0, (s, g) => s + _d(g['monto_mensual'])).toStringAsFixed(2)}/mes',
                      AppTheme.danger),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.touch_app_outlined, color: AppTheme.info, size: 14),
                      const SizedBox(width: 8),
                      const Expanded(child: Text(
                        'Toca una deuda para ir a Mis Deudas y completar su información.',
                        style: TextStyle(color: AppTheme.info, fontSize: 11),
                      )),
                    ]),
                  ),
                  ..._deudas.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GastoTile(
                      gasto: g as Map<String, dynamic>,
                      onEdit: () => _mostrarFormGasto(gasto: g),
                      onDelete: () => _eliminarGasto((g)['id'] as int),
                      onTapDeuda: _irADeudas,
                    ),
                  )),
                  const SizedBox(height: 8),
                ],
                if (_variables.isNotEmpty) ...[
                  _SeccionHeader('GASTOS VARIABLES', _variables.length,
                      '~\$${_variables.fold(0.0, (s, g) => s + _d(g['monto_mensual'])).toStringAsFixed(2)}/mes',
                      AppTheme.warning),
                  const SizedBox(height: 6),
                  ..._variables.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GastoTile(
                      gasto: g as Map<String, dynamic>,
                      onEdit: () => _mostrarFormGasto(gasto: g),
                      onDelete: () => _eliminarGasto((g)['id'] as int),
                    ),
                  )),
                  const SizedBox(height: 8),
                ],
                if (_ahorros.isNotEmpty) ...[
                  _SeccionHeader('METAS DE AHORRO ACTIVAS', _ahorros.length,
                      '\$${_totalAhorrosMensual.toStringAsFixed(2)}/mes',
                      AppTheme.colorAhorro),
                  const SizedBox(height: 6),
                  ..._ahorros.map((a) => _AhorroTile(ahorro: a as Map<String, dynamic>)),
                ],
              ],
            ),
      ),
    ]);
  }

  void _mostrarFormIngreso() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _IngresoFormSheet(
        firebaseUid: widget.firebaseUid,
        incomeActual: _income,
        onGuardado: (_) { Navigator.pop(context); _cargar(); },
      ),
    );
  }

  void _mostrarFormGasto({Map<String, dynamic>? gasto}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _GastoFormSheet(
        firebaseUid: widget.firebaseUid,
        gastoActual: gasto,
        onGuardado: () { Navigator.pop(context); _cargar(); },
      ),
    );
  }

  Future<void> _eliminarGasto(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar gasto', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '¿Eliminar este gasto del perfil? Se borrará también su recordatorio del calendario.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await UserProfileService.eliminarGastoFijo(id, widget.firebaseUid);
      _cargar();
    }
  }

  Future<void> _confirmarEliminarIngreso() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar ingreso', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '¿Seguro que quieres eliminar tu ingreso configurado? '
          'Los cálculos de disponible quedarán en cero hasta que lo vuelvas a configurar.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await UserProfileService.deleteIncome(widget.firebaseUid);
      _cargar();
    }
  }

  String _labelTipoIngreso(dynamic t) {
    const map = {'salario': 'Salario', 'informal': 'Informal', 'ocasional': 'Ocasional', 'otro': 'Otro'};
    return map[t?.toString()] ?? 'Salario';
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  // ── Tab Variables Base ────────────────────────────────────────────────────
  Widget _buildTabVariablesBase() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Encabezado
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gastos variables presupuestados',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Supermercado, gasolina, medicinas… gastos esperados pero de monto variable.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.account_balance_wallet, color: AppTheme.warning, size: 16),
              const SizedBox(width: 6),
              Text('Total estimado: \$${_totalVariablesMensual.toStringAsFixed(2)}/mes',
                  style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        if (_variablesBase.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                const Icon(Icons.shopping_cart_outlined, color: AppTheme.textMuted, size: 48),
                const SizedBox(height: 12),
                const Text('Sin gastos variables base', style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _agregarVariableBase,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Agregar primero'),
                ),
              ]),
            ),
          )
        else ...[
          ..._variablesBase.map((g) => _VariableBaseTile(
            gasto: g,
            onDelete: () async {
              await GastosVariablesService.eliminar(widget.firebaseUid, g['id'] as int);
              _cargar();
            },
          )),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          onPressed: _agregarVariableBase,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Agregar gasto variable base'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
        ),
      ],
    );
  }

  void _agregarVariableBase() {
    final nombreCtrl  = TextEditingController();
    final montoCtrl   = TextEditingController();
    String categoria  = 'alimentacion';
    String frecuencia = 'mensual';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setModal) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Nuevo gasto variable base',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre (ej: Supermercado)'),
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto estimado (\$)', prefixText: '\$ '),
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              dropdownColor: AppTheme.surfaceAlt,
              style: const TextStyle(color: AppTheme.textPrimary),
              items: const [
                DropdownMenuItem(value: 'alimentacion', child: Text('Alimentación')),
                DropdownMenuItem(value: 'transporte',   child: Text('Transporte')),
                DropdownMenuItem(value: 'salud',        child: Text('Salud')),
                DropdownMenuItem(value: 'ocio',         child: Text('Ocio')),
                DropdownMenuItem(value: 'ropa',         child: Text('Ropa')),
                DropdownMenuItem(value: 'deportes',     child: Text('Deportes')),
                DropdownMenuItem(value: 'tecnologia',   child: Text('Tecnología')),
                DropdownMenuItem(value: 'familia',      child: Text('Familia')),
                DropdownMenuItem(value: 'otro',         child: Text('Otro')),
              ],
              onChanged: (v) => setModal(() => categoria = v ?? categoria),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: frecuencia,
              decoration: const InputDecoration(labelText: 'Frecuencia'),
              dropdownColor: AppTheme.surfaceAlt,
              style: const TextStyle(color: AppTheme.textPrimary),
              items: const [
                DropdownMenuItem(value: 'mensual',   child: Text('Mensual')),
                DropdownMenuItem(value: 'quincenal', child: Text('Quincenal')),
                DropdownMenuItem(value: 'semanal',   child: Text('Semanal')),
                DropdownMenuItem(value: 'anual',     child: Text('Anual')),
              ],
              onChanged: (v) => setModal(() => frecuencia = v ?? frecuencia),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nombreCtrl.text.isEmpty || montoCtrl.text.isEmpty) return;
                  final monto = double.tryParse(montoCtrl.text);
                  if (monto == null) return;
                  await GastosVariablesService.crear(
                    uid: widget.firebaseUid, nombre: nombreCtrl.text.trim(),
                    categoria: categoria, montoEstimado: monto, frecuencia: frecuencia,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _cargar();
                },
                child: const Text('Guardar'),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

// ── Sección header ────────────────────────────────────────────────────────────
class _SeccionHeader extends StatelessWidget {
  final String titulo;
  final int cantidad;
  final String monto;
  final Color color;
  const _SeccionHeader(this.titulo, this.cantidad, this.monto, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 14, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(titulo, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    const SizedBox(width: 6),
    Text('($cantidad)', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    const Spacer(),
    Text(monto, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
  ]);
}

// ── Alert banner ──────────────────────────────────────────────────────────────
class _AlertaBanner extends StatelessWidget {
  final String mensaje;
  const _AlertaBanner(this.mensaje);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(mensaje,
          style: const TextStyle(color: AppTheme.danger, fontSize: 12, height: 1.4))),
    ]),
  );
}

// ── Widgets de presentación ───────────────────────────────────────────────────
class _ResumenItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String prefix;
  const _ResumenItem(this.label, this.value, this.color, {this.prefix = ''});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.5)),
    const SizedBox(height: 2),
    Text('$prefix$value', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
  ]);
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(children: rows.map((r) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(r.label, style: TextStyle(color: r.color ?? AppTheme.textSecondary, fontSize: 12)),
        Text(r.value, style: TextStyle(
            color: r.color ?? AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    )).toList()),
  );
}

class _InfoRow {
  final String label;
  final String value;
  final Color? color;
  const _InfoRow(this.label, this.value, {this.color});
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onAction;
  const _EmptyState({required this.icon, required this.title, required this.subtitle,
    required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppTheme.textMuted, size: 48),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: onAction, child: Text(action)),
    ]),
  );
}

// ── Tile de gasto (fijo, deuda o variable) ────────────────────────────────────
class _GastoTile extends StatelessWidget {
  final Map<String, dynamic> gasto;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTapDeuda;
  const _GastoTile({required this.gasto, required this.onEdit, required this.onDelete, this.onTapDeuda});

  @override
  Widget build(BuildContext context) {
    final esDeuda = (gasto['es_deuda'] as int? ?? 0) == 1;
    final frecuencia = gasto['frecuencia'] as String? ?? 'fijo';
    final monto = double.tryParse(gasto['monto_mensual']?.toString() ?? '0') ?? 0;
    final diaPago = gasto['dia_pago'] as int?;
    final recordatorio = (gasto['recordatorio'] as int? ?? 0) == 1;
    final Color accentColor = esDeuda
        ? AppTheme.danger
        : frecuencia == 'variable'
            ? AppTheme.warning
            : const Color(0xFF1890FF);

    final infoIncompleta = esDeuda && (gasto['deuda_info_completa'] as int? ?? 0) == 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: infoIncompleta
              ? AppTheme.warning.withValues(alpha: 0.5)
              : esDeuda ? AppTheme.danger.withValues(alpha: 0.3) : AppTheme.border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 44, decoration: BoxDecoration(
              color: accentColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gasto['descripcion'] as String? ?? '',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              _Chip(_labelTipo(gasto['tipo'] as String? ?? 'otro'), color: AppTheme.textSecondary),
              if (esDeuda) _Chip('Deuda', color: AppTheme.danger),
              if (frecuencia == 'variable') _Chip('Variable', color: AppTheme.warning),
              if (diaPago != null)
                _Chip('Día $diaPago', color: AppTheme.info, icon: Icons.calendar_today),
              if (recordatorio)
                _Chip('Recordatorio', color: AppTheme.primary, icon: Icons.notifications_outlined),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${monto.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(frecuencia == 'variable' ? '~estimado/mes' : '/mes',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ]),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            color: AppTheme.surfaceAlt,
            icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
            onSelected: (v) { if (v == 'edit') onEdit(); else onDelete(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',
                  child: Text('Editar', style: TextStyle(color: AppTheme.textPrimary))),
              const PopupMenuItem(value: 'delete',
                  child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
            ],
          ),
        ]),
        // Botón "Completar info" separado — toque directo y visible
        if (infoIncompleta && onTapDeuda != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onTapDeuda,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.edit_outlined, color: AppTheme.warning, size: 14),
                SizedBox(width: 6),
                Text('Completar información de la deuda →',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  static String _labelTipo(String t) {
    const map = {'vivienda': 'Vivienda', 'transporte': 'Transporte', 'deuda': 'Deuda',
      'servicios': 'Servicios', 'educacion': 'Educación', 'salud': 'Salud',
      'alimentacion': 'Alimentación', 'otro': 'Otro'};
    return map[t] ?? 'Otro';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  const _Chip(this.label, {this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? AppTheme.textSecondary).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 9, color: color ?? AppTheme.textSecondary),
        const SizedBox(width: 3),
      ],
      Text(label, style: TextStyle(
          color: color ?? AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Tile de ahorro activo (solo lectura — se gestiona desde Ahorro y Metas) ──
class _AhorroTile extends StatelessWidget {
  final Map<String, dynamic> ahorro;
  const _AhorroTile({required this.ahorro});

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    final nombre = ahorro['nombre'] as String? ?? '';
    final cuotaMensual = _d(ahorro['cuota_mensual']);
    final cuotaPeriodo = _d(ahorro['cuota_periodo']);
    final tipoPeriodo = ahorro['tipo_periodo'] as String? ?? 'mensual';
    final periodosRestantes = ahorro['periodos_restantes'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Container(width: 4, height: 44, decoration: BoxDecoration(
            color: AppTheme.colorAhorro, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            _Chip('Ahorro', color: AppTheme.colorAhorro),
            if (periodosRestantes != null)
              _Chip('$periodosRestantes períodos restantes', color: AppTheme.textSecondary),
            _Chip('\$${cuotaPeriodo.toStringAsFixed(2)}/${tipoPeriodo == 'quincenal' ? 'quincena' : 'mes'}',
                color: AppTheme.textMuted),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${cuotaMensual.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppTheme.colorAhorro, fontWeight: FontWeight.bold, fontSize: 15)),
          const Text('/mes', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
        const SizedBox(width: 6),
        const Tooltip(
          message: 'Gestiona tus ahorros desde\n"Ahorro y Metas" en el menú',
          child: Icon(Icons.info_outline, color: AppTheme.textMuted, size: 16),
        ),
      ]),
    );
  }
}

// ── Bottom Sheet: Formulario de ingreso ──────────────────────────────────────
class _IngresoFormSheet extends StatefulWidget {
  final String firebaseUid;
  final Map<String, dynamic>? incomeActual;
  final void Function(Map<String, dynamic>) onGuardado;
  const _IngresoFormSheet(
      {required this.firebaseUid, this.incomeActual, required this.onGuardado});

  @override
  State<_IngresoFormSheet> createState() => _IngresoFormSheetState();
}

class _IngresoFormSheetState extends State<_IngresoFormSheet> {
  String _tipo = 'salario';
  String _frecuencia = 'quincenal';
  bool _autoCalc = false;
  bool _guardando = false;

  final _brutoCtrl = TextEditingController();
  final _seguroCtrl = TextEditingController(text: '0');
  final _pensionCtrl = TextEditingController(text: '0');
  final _impuestoCtrl = TextEditingController(text: '0');
  final _otrosCtrl = TextEditingController(text: '0');
  final _netoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final inc = widget.incomeActual;
    if (inc != null) {
      _tipo = inc['tipo_ingreso'] ?? 'salario';
      _frecuencia = inc['frecuencia_cobro'] ?? 'quincenal';
      _autoCalc = (inc['calcular_automatico'] as int? ?? 0) == 1;
      _brutoCtrl.text = _f(inc['ingreso_bruto_mensual']);
      _seguroCtrl.text = _f(inc['desc_seguro']);
      _pensionCtrl.text = _f(inc['desc_pension']);
      _impuestoCtrl.text = _f(inc['desc_impuesto']);
      _otrosCtrl.text = _f(inc['desc_otros']);
      _netoCtrl.text = _f(inc['ingreso_neto_mensual']);
    }
    _brutoCtrl.addListener(() { if (_autoCalc) _calcular(); setState(() {}); });
    for (final c in [_seguroCtrl, _pensionCtrl, _impuestoCtrl, _otrosCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_brutoCtrl, _seguroCtrl, _pensionCtrl, _impuestoCtrl, _otrosCtrl, _netoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String _f(dynamic v) => (double.tryParse(v?.toString() ?? '0') ?? 0).toStringAsFixed(2);
  double _parseD(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  double get _netoCalculado {
    if (_tipo != 'salario') return 0;
    return _parseD(_brutoCtrl.text) - _parseD(_seguroCtrl.text)
        - _parseD(_pensionCtrl.text) - _parseD(_impuestoCtrl.text) - _parseD(_otrosCtrl.text);
  }

  void _calcular() {
    if (!_autoCalc || _tipo != 'salario') return;
    final bruto = _parseD(_brutoCtrl.text);
    _seguroCtrl.text = (bruto * 0.0975).toStringAsFixed(2);
    _pensionCtrl.text = (bruto * 0.0125).toStringAsFixed(2);
    _impuestoCtrl.text = max(0, (bruto - 916.67) * 0.15).toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _guardar() async {
    final neto = _tipo == 'salario' ? _netoCalculado : _parseD(_netoCtrl.text);
    if (neto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El ingreso neto debe ser mayor a 0')));
      return;
    }
    setState(() => _guardando = true);
    final body = <String, dynamic>{
      'tipo_ingreso': _tipo,
      'frecuencia_cobro': _frecuencia,
      'calcular_automatico': _autoCalc ? 1 : 0,
      'ingreso_neto_mensual': neto,
      'ingreso_bruto_mensual': _tipo == 'salario' ? _parseD(_brutoCtrl.text) : neto,
      'desc_seguro': _tipo == 'salario' ? _parseD(_seguroCtrl.text) : 0,
      'desc_pension': _tipo == 'salario' ? _parseD(_pensionCtrl.text) : 0,
      'desc_impuesto': _tipo == 'salario' ? _parseD(_impuestoCtrl.text) : 0,
      'desc_otros': _tipo == 'salario' ? _parseD(_otrosCtrl.text) : 0,
    };
    final saved = await UserProfileService.upsertIncome(widget.firebaseUid, body);
    if (mounted) setState(() => _guardando = false);
    if (saved != null && mounted) widget.onGuardado(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('¿Cuánto recibes?',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          const Text('Ingresa tu salario o ingreso mensual neto.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          _label('Tipo de ingreso'),
          Wrap(spacing: 8, children: ['salario', 'informal', 'ocasional', 'otro'].map((t) =>
            GestureDetector(
              onTap: () => setState(() => _tipo = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _tipo == t ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _tipo == t ? AppTheme.primary : AppTheme.border),
                ),
                child: Text({'salario': 'Salario', 'informal': 'Informal',
                    'ocasional': 'Ocasional', 'otro': 'Otro'}[t]!,
                    style: TextStyle(
                        color: _tipo == t ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: _tipo == t ? FontWeight.w700 : FontWeight.normal)),
              ),
            ),
          ).toList()),
          const SizedBox(height: 16),
          _label('Frecuencia de cobro'),
          Row(children: ['quincenal', 'mensual'].map((f) =>
            Expanded(child: Padding(
              padding: EdgeInsets.only(right: f == 'quincenal' ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _frecuencia = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _frecuencia == f ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _frecuencia == f ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Text({'quincenal': 'Quincenal', 'mensual': 'Mensual'}[f]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _frecuencia == f ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: _frecuencia == f ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
            )),
          ).toList()),
          const SizedBox(height: 16),
          if (_tipo == 'salario') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.info, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Ingresa siempre el salario MENSUAL. Si cobras quincenal, la app lo divide.',
                  style: TextStyle(color: AppTheme.info, fontSize: 11))),
              ]),
            ),
            const SizedBox(height: 12),
            _buildCampo('Salario bruto mensual', _brutoCtrl),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Calcular deducciones (Panamá)',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              Switch(value: _autoCalc, activeColor: AppTheme.primary,
                  onChanged: (v) { setState(() => _autoCalc = v); if (v) _calcular(); }),
            ]),
            const SizedBox(height: 8),
            _buildCampo('CSS (9.75%)', _seguroCtrl, readOnly: _autoCalc),
            const SizedBox(height: 8),
            _buildCampo('Educativo (1.25%)', _pensionCtrl, readOnly: _autoCalc),
            const SizedBox(height: 8),
            _buildCampo('ISR', _impuestoCtrl, readOnly: _autoCalc),
            const SizedBox(height: 8),
            _buildCampo('Otros descuentos', _otrosCtrl),
            const SizedBox(height: 16),
            if (_netoCalculado > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  const Text('Neto mensual', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('\$${_netoCalculado.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.success, fontSize: 24, fontWeight: FontWeight.bold)),
                  if (_frecuencia == 'quincenal')
                    Text('Quincenal: \$${(_netoCalculado / 2).toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ]),
              ),
          ] else ...[
            _buildCampo('Monto mensual que recibes (neto)', _netoCtrl),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Guardar ingreso'),
          )),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _buildCampo(String label, TextEditingController ctrl, {bool readOnly = false}) =>
    TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      style: TextStyle(color: readOnly ? AppTheme.textMuted : AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        prefixText: '\$ ',
        prefixStyle: const TextStyle(color: AppTheme.textSecondary),
      ),
    );
}

// ── Bottom Sheet: Formulario de gasto (fijo, deuda o variable) ───────────────
class _GastoFormSheet extends StatefulWidget {
  final String firebaseUid;
  final Map<String, dynamic>? gastoActual;
  final VoidCallback onGuardado;
  const _GastoFormSheet(
      {required this.firebaseUid, this.gastoActual, required this.onGuardado});

  @override
  State<_GastoFormSheet> createState() => _GastoFormSheetState();
}

class _GastoFormSheetState extends State<_GastoFormSheet> {
  final _descCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _diaPagoCtrl = TextEditingController();
  String _tipo = 'otro';
  String _clasificacion = 'importante';
  String _frecuencia = 'fijo';
  bool _esDeuda = false;
  bool _recordatorio = false;
  bool _guardando = false;

  static const _tipos = ['vivienda','transporte','deuda','servicios','educacion','salud','alimentacion','otro'];
  static const _labelsTipo = {
    'vivienda': 'Vivienda', 'transporte': 'Transporte', 'deuda': 'Deuda',
    'servicios': 'Servicios', 'educacion': 'Educación', 'salud': 'Salud',
    'alimentacion': 'Alimentación', 'otro': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    final g = widget.gastoActual;
    if (g != null) {
      _descCtrl.text = g['descripcion'] ?? '';
      _montoCtrl.text = (double.tryParse(g['monto_mensual']?.toString() ?? '0') ?? 0).toStringAsFixed(2);
      _tipo = g['tipo'] ?? 'otro';
      _clasificacion = g['clasificacion'] ?? 'importante';
      _frecuencia = g['frecuencia'] as String? ?? 'fijo';
      _esDeuda = (g['es_deuda'] as int? ?? 0) == 1;
      _recordatorio = (g['recordatorio'] as int? ?? 0) == 1;
      final dp = g['dia_pago'];
      if (dp != null) _diaPagoCtrl.text = dp.toString();
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose(); _montoCtrl.dispose(); _diaPagoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final desc = _descCtrl.text.trim();
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (desc.isEmpty || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa descripción y monto')));
      return;
    }
    final diaPago = int.tryParse(_diaPagoCtrl.text.trim());
    if (_recordatorio && diaPago == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indica el día de pago para activar el recordatorio')));
      return;
    }
    setState(() => _guardando = true);
    final body = <String, dynamic>{
      'descripcion': desc,
      'monto_mensual': monto,
      'tipo': _tipo,
      'clasificacion': _clasificacion,
      'es_deuda': _esDeuda ? 1 : 0,
      'frecuencia': _frecuencia,
      'dia_pago': diaPago,
      'recordatorio': _recordatorio ? 1 : 0,
    };
    bool ok;
    if (widget.gastoActual != null) {
      ok = await UserProfileService.actualizarGastoFijo(
          widget.gastoActual!['id'] as int, widget.firebaseUid, body);
    } else {
      final result = await UserProfileService.crearGastoFijo(widget.firebaseUid, body);
      ok = result != null;
    }
    if (mounted) setState(() => _guardando = false);
    if (ok && mounted) widget.onGuardado();
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.gastoActual != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(esEdicion ? 'Editar gasto' : 'Agregar gasto',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),

          // ── Tipo de gasto: Fijo o Variable ─────────────────────────────
          const Text('¿Es un gasto fijo o variable?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Fijo: siempre el mismo monto (hipoteca, carro). Variable: estimado que varía (comida, gasolina).',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 8),
          Row(children: [
            for (final f in ['fijo', 'variable'])
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: f == 'fijo' ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _frecuencia = f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _frecuencia == f ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _frecuencia == f ? AppTheme.primary : AppTheme.border),
                    ),
                    child: Text(f == 'fijo' ? 'Fijo' : 'Variable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _frecuencia == f ? AppTheme.primary : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: _frecuencia == f ? FontWeight.w700 : FontWeight.normal)),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 16),

          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
                labelText: 'Descripción (ej: Hipoteca, Carro, Internet, Supermercado)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: _frecuencia == 'variable' ? 'Estimado mensual' : 'Monto mensual',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 16),

          // ── Categoría ──────────────────────────────────────────────────
          const Text('Categoría',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _tipos.map((t) =>
            GestureDetector(
              onTap: () => setState(() {
                _tipo = t;
                if (t == 'deuda') _esDeuda = true;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _tipo == t ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _tipo == t ? AppTheme.primary : AppTheme.border),
                ),
                child: Text(_labelsTipo[t]!,
                    style: TextStyle(
                        color: _tipo == t ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 12)),
              ),
            ),
          ).toList()),
          const SizedBox(height: 16),

          // ── Clasificación ──────────────────────────────────────────────
          const Text('Prioridad',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            for (final c in ['esencial', 'importante', 'flexible'])
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: c != 'flexible' ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _clasificacion = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _clasificacion == c ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _clasificacion == c ? AppTheme.primary : AppTheme.border),
                    ),
                    child: Text({'esencial': 'Esencial', 'importante': 'Importante', 'flexible': 'Flexible'}[c]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _clasificacion == c ? AppTheme.primary : AppTheme.textSecondary,
                          fontSize: 11)),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 12),

          // ── Es deuda ───────────────────────────────────────────────────
          _SwitchRow(
            label: 'Es una deuda (con interés)',
            sublabel: 'Aparecerá también en la sección Mis Deudas.',
            value: _esDeuda,
            onChanged: (v) => setState(() => _esDeuda = v),
          ),
          const SizedBox(height: 8),

          // ── Día de pago ────────────────────────────────────────────────
          TextField(
            controller: _diaPagoCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Día de pago (1–31, opcional)',
              helperText: 'Ej: 15 para el quince de cada mes',
              helperStyle: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              prefixIcon: Icon(Icons.calendar_today, size: 16, color: AppTheme.textMuted),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && (n < 1 || n > 31)) _diaPagoCtrl.text = '';
              setState(() {});
            },
          ),
          const SizedBox(height: 8),

          // ── Recordatorio ───────────────────────────────────────────────
          _SwitchRow(
            label: 'Activar recordatorio en el calendario',
            sublabel: _diaPagoCtrl.text.isEmpty
                ? 'Ingresa el día de pago primero.'
                : 'Se crearán eventos en el calendario para los próximos 3 meses.',
            value: _recordatorio,
            enabled: _diaPagoCtrl.text.isNotEmpty,
            onChanged: (v) => setState(() => _recordatorio = v),
          ),

          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(esEdicion ? 'Guardar cambios' : 'Agregar gasto'),
          )),
        ]),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.label, required this.sublabel,
    required this.value, required this.onChanged, this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            color: enabled ? AppTheme.textPrimary : AppTheme.textMuted, fontSize: 13)),
        const SizedBox(height: 2),
        Text(sublabel, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      Switch(
        value: value,
        activeColor: AppTheme.primary,
        onChanged: enabled ? onChanged : null,
      ),
    ]),
  );
}

// ── Tile de gasto variable base ───────────────────────────────────────────────
class _VariableBaseTile extends StatelessWidget {
  final Map<String, dynamic> gasto;
  final VoidCallback onDelete;
  const _VariableBaseTile({required this.gasto, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final monto = double.tryParse(gasto['monto_estimado']?.toString() ?? '0') ?? 0;
    final frec  = gasto['frecuencia'] as String? ?? 'mensual';
    final frecLabel = frec == 'quincenal' ? 'quincenal' : frec == 'semanal' ? 'semanal'
        : frec == 'anual' ? 'anual' : 'mes';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.shopping_basket_outlined, color: AppTheme.warning, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(gasto['nombre'] as String? ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(gasto['categoria'] as String? ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('/$frecLabel', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Eliminar', style: TextStyle(color: AppTheme.textPrimary)),
              content: Text('¿Eliminar "${gasto['nombre']}"?', style: const TextStyle(color: AppTheme.textSecondary)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                TextButton(onPressed: () { Navigator.pop(context); onDelete(); },
                    child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
              ],
            ),
          ),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }
}
