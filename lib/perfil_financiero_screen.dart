import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/user_profile_service.dart';

/// Pantalla central del perfil financiero global del usuario.
/// Aquí vive la realidad financiera de la persona — no de un presupuesto específico:
///   1. Su ingreso neto (qué entra cada mes)
///   2. Sus compromisos fijos (qué DEBE pagar sí o sí)
///   3. Lo que sobra (disponible real = base de todo presupuesto)
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
  List<dynamic> _gastosFijos = [];
  double _totalMensual = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final income = await UserProfileService.getIncome(widget.firebaseUid);
    final gfData = await UserProfileService.getGastosFijos(widget.firebaseUid);
    if (!mounted) return;
    setState(() {
      _income = income;
      _gastosFijos = gfData['gastos'] as List? ?? [];
      _totalMensual = double.tryParse(gfData['total_mensual']?.toString() ?? '0') ?? 0;
      _loading = false;
    });
  }

  double get _ingreso => double.tryParse(_income?['ingreso_neto_mensual']?.toString() ?? '0') ?? 0;
  double get _disponible => _ingreso - _totalMensual;
  bool get _esSostenible => _disponible >= 0;

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
          tabs: const [Tab(text: 'Ingresos'), Tab(text: 'Compromisos fijos')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(children: [
              _buildResumenBanner(),
              Expanded(child: TabBarView(controller: _tabs, children: [
                _buildTabIngreso(),
                _buildTabGastosFijos(),
              ])),
            ]),
    );
  }

  // ── Banner de resumen ────────────────────────────────────────────────────
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
      child: Row(children: [
        Expanded(child: _ResumenItem('Ingreso neto', '\$${_ingreso.toStringAsFixed(2)}/mes', AppTheme.success)),
        Container(width: 1, height: 36, color: AppTheme.border),
        Expanded(child: _ResumenItem('Compromisos', '\$${_totalMensual.toStringAsFixed(2)}/mes', AppTheme.danger)),
        Container(width: 1, height: 36, color: AppTheme.border),
        Expanded(child: _ResumenItem(
          'Disponible',
          '\$${_disponible.abs().toStringAsFixed(2)}/mes',
          _esSostenible ? AppTheme.success : AppTheme.danger,
          prefix: _esSostenible ? '' : '-',
        )),
      ]),
    );
  }

  // ── Tab 1: Ingreso ────────────────────────────────────────────────────────
  Widget _buildTabIngreso() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_esSostenible && _income != null)
          Container(
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
              Expanded(child: Text(
                'Tus compromisos fijos superan tu ingreso en \$${_disponible.abs().toStringAsFixed(2)}/mes. '
                'Tu plan financiero necesita ajustes.',
                style: const TextStyle(color: AppTheme.danger, fontSize: 12, height: 1.4),
              )),
            ]),
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
            _InfoRow('Tipo de ingreso', _labelTipo(_income!['tipo_ingreso'])),
            _InfoRow('Bruto mensual', '\$${_d(_income!["ingreso_bruto_mensual"]).toStringAsFixed(2)}'),
            if (_d(_income!['desc_seguro']) > 0)
              _InfoRow('  − Seguro Social (CSS)', '-\$${_d(_income!["desc_seguro"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
            if (_d(_income!['desc_pension']) > 0)
              _InfoRow('  − Educativo (IFARHU)', '-\$${_d(_income!["desc_pension"]).toStringAsFixed(2)}', color: AppTheme.textMuted),
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
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _mostrarFormIngreso,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Editar ingreso'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
            ),
          )),
        ],
      ]),
    );
  }

  // ── Tab 2: Compromisos fijos ───────────────────────────────────────────────
  Widget _buildTabGastosFijos() {
    final activos = _gastosFijos.where((g) => (g['activo'] as int? ?? 1) == 1).toList();
    return Column(children: [
      if (activos.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: Text(
              '${activos.length} compromisos · \$${_totalMensual.toStringAsFixed(2)}/mes',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )),
            TextButton.icon(
              onPressed: _mostrarFormGastoFijo,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ]),
        ),
      Expanded(child: activos.isEmpty
          ? Center(child: _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin compromisos registrados',
              subtitle: 'Agrega tus pagos fijos: hipoteca, carro, préstamos, servicios...',
              action: 'Agregar compromiso',
              onAction: _mostrarFormGastoFijo,
            ))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: activos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _GastoFijoTile(
                gasto: activos[i] as Map<String, dynamic>,
                onEdit: () => _mostrarFormGastoFijo(gasto: activos[i] as Map<String, dynamic>),
                onDelete: () => _eliminarGasto((activos[i] as Map)['id'] as int),
              ),
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

  void _mostrarFormGastoFijo({Map<String, dynamic>? gasto}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _GastoFijoFormSheet(
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
        title: const Text('Eliminar compromiso', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Eliminar este compromiso fijo? Desaparecerá de los próximos períodos.',
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

  String _labelTipo(dynamic t) {
    const map = {'salario': 'Salario', 'informal': 'Informal', 'ocasional': 'Ocasional', 'otro': 'Otro'};
    return map[t?.toString()] ?? 'Salario';
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
}

// ── Widgets internos ─────────────────────────────────────────────────────────

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
        Text(r.value, style: TextStyle(color: r.color ?? AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
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
      Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: onAction, child: Text(action)),
    ]),
  );
}

class _GastoFijoTile extends StatelessWidget {
  final Map<String, dynamic> gasto;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _GastoFijoTile({required this.gasto, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final tipo = gasto['tipo'] as String? ?? 'otro';
    final clasificacion = gasto['clasificacion'] as String? ?? 'importante';
    final monto = double.tryParse(gasto['monto_mensual']?.toString() ?? '0') ?? 0;
    final esDeuda = (gasto['es_deuda'] as int? ?? 0) == 1;
    final color = esDeuda ? AppTheme.danger
        : clasificacion == 'esencial' ? const Color(0xFF1890FF) : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(gasto['descripcion'] as String? ?? '', style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Row(children: [
            _Chip(_labelTipo(tipo)),
            const SizedBox(width: 6),
            if (esDeuda) _Chip('Deuda', color: AppTheme.danger),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${monto.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
          const Text('/mes', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          color: AppTheme.surfaceAlt,
          icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
          onSelected: (v) { if (v == 'edit') onEdit(); else onDelete(); },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar', style: TextStyle(color: AppTheme.textPrimary))),
            const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
          ],
        ),
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
  const _Chip(this.label, {this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? AppTheme.textSecondary).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: TextStyle(color: color ?? AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

// ── Bottom Sheet: Formulario de ingreso ─────────────────────────────────────

class _IngresoFormSheet extends StatefulWidget {
  final String firebaseUid;
  final Map<String, dynamic>? incomeActual;
  final void Function(Map<String, dynamic>) onGuardado;
  const _IngresoFormSheet({required this.firebaseUid, this.incomeActual, required this.onGuardado});

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

  String _f(dynamic v) => double.tryParse(v?.toString() ?? '0')?.toStringAsFixed(2) ?? '0';
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
                    style: TextStyle(color: _tipo == t ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 13, fontWeight: _tipo == t ? FontWeight.w700 : FontWeight.normal)),
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
                    style: TextStyle(color: _frecuencia == f ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 13, fontWeight: _frecuencia == f ? FontWeight.w700 : FontWeight.normal)),
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
                Expanded(child: Text('Ingresa siempre tu salario MENSUAL. Si cobras quincenal, igual pon el mensual — la app lo divide.',
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

// ── Bottom Sheet: Formulario de gasto fijo ───────────────────────────────────

class _GastoFijoFormSheet extends StatefulWidget {
  final String firebaseUid;
  final Map<String, dynamic>? gastoActual;
  final VoidCallback onGuardado;
  const _GastoFijoFormSheet({required this.firebaseUid, this.gastoActual, required this.onGuardado});

  @override
  State<_GastoFijoFormSheet> createState() => _GastoFijoFormSheetState();
}

class _GastoFijoFormSheetState extends State<_GastoFijoFormSheet> {
  final _descCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _tipo = 'otro';
  String _clasificacion = 'importante';
  bool _esDeuda = false;
  bool _guardando = false;

  static const _tipos = ['vivienda','transporte','deuda','servicios','educacion','salud','alimentacion','otro'];
  static const _labelsTipo = {'vivienda': 'Vivienda','transporte': 'Transporte','deuda': 'Deuda',
    'servicios': 'Servicios','educacion': 'Educación','salud': 'Salud','alimentacion': 'Alimentación','otro': 'Otro'};

  @override
  void initState() {
    super.initState();
    final g = widget.gastoActual;
    if (g != null) {
      _descCtrl.text = g['descripcion'] ?? '';
      _montoCtrl.text = (double.tryParse(g['monto_mensual']?.toString() ?? '0') ?? 0).toStringAsFixed(2);
      _tipo = g['tipo'] ?? 'otro';
      _clasificacion = g['clasificacion'] ?? 'importante';
      _esDeuda = (g['es_deuda'] as int? ?? 0) == 1;
    }
  }

  @override
  void dispose() { _descCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    final desc = _descCtrl.text.trim();
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (desc.isEmpty || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa descripción y monto mensual')));
      return;
    }
    setState(() => _guardando = true);
    final body = {'descripcion': desc, 'monto_mensual': monto, 'tipo': _tipo,
      'clasificacion': _clasificacion, 'es_deuda': _esDeuda ? 1 : 0};
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.gastoActual != null ? 'Editar compromiso' : 'Agregar compromiso',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Descripción (ej: Hipoteca, Carro, Internet)'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Monto mensual', prefixText: '\$ '),
          ),
          const SizedBox(height: 16),
          const Text('Tipo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
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
                child: Text(_labelsTipo[t]!, style: TextStyle(
                    color: _tipo == t ? AppTheme.primary : AppTheme.textSecondary, fontSize: 12)),
              ),
            ),
          ).toList()),
          const SizedBox(height: 16),
          const Text('Clasificación', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
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
                      style: TextStyle(color: _clasificacion == c ? AppTheme.primary : AppTheme.textSecondary, fontSize: 11)),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Es una deuda (con interés)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            Switch(value: _esDeuda, activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _esDeuda = v)),
          ]),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(widget.gastoActual != null ? 'Guardar cambios' : 'Agregar compromiso'),
          )),
        ]),
      ),
    );
  }
}
