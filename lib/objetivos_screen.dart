import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

class ObjetivosScreen extends StatefulWidget {
  final String firebaseUid;
  const ObjetivosScreen({super.key, required this.firebaseUid});

  @override
  State<ObjetivosScreen> createState() => _ObjetivosScreenState();
}

class _ObjetivosScreenState extends State<ObjetivosScreen> {
  List<Map<String, dynamic>> _objetivos = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient.get('/user/objetivos?firebase_uid=${widget.firebaseUid}');
      if (r.statusCode == 200 && mounted) {
        setState(() {
          _objetivos = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Objetivos Financieros')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearObjetivo,
        icon: const Icon(Icons.add, color: AppTheme.background),
        label: const Text('Nuevo objetivo', style: TextStyle(color: AppTheme.background)),
        backgroundColor: AppTheme.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _objetivos.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _objetivos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _ObjetivoCard(
                        objetivo: _objetivos[i],
                        uid: widget.firebaseUid,
                        onChanged: _cargar,
                        onDelete: () => _eliminar(_objetivos[i]['id'] as int),
                      ),
                    ),
            ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.flag_outlined, color: AppTheme.primary, size: 64),
        const SizedBox(height: 16),
        const Text('Sin objetivos aún', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Define metas financieras concretas: un fondo de emergencia, un carro, vacaciones.\nSalarying te dice cuánto necesitás ahorrar por mes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text('Crear mi primer objetivo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          onPressed: _crearObjetivo,
        ),
      ]),
    ),
  );

  Future<void> _crearObjetivo() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ObjetivoForm(uid: widget.firebaseUid),
    );
    if (ok == true) _cargar();
  }

  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar objetivo', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Estás seguro?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await ApiClient.delete('/user/objetivos/$id?firebase_uid=${widget.firebaseUid}');
      _cargar();
    }
  }
}

class _ObjetivoCard extends StatelessWidget {
  final Map<String, dynamic> objetivo;
  final String uid;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _ObjetivoCard({
    required this.objetivo, required this.uid,
    required this.onChanged, required this.onDelete,
  });

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  static const _tipoColor = {
    'ahorro':      AppTheme.success,
    'compra':      AppTheme.primary,
    'emergencia':  AppTheme.warning,
    'inversion':   AppTheme.info,
    'otro':        AppTheme.textSecondary,
  };

  static const _tipoIcon = {
    'ahorro':      Icons.savings_outlined,
    'compra':      Icons.shopping_bag_outlined,
    'emergencia':  Icons.shield_outlined,
    'inversion':   Icons.trending_up,
    'otro':        Icons.flag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final meta        = _d(objetivo['monto_meta']);
    final actual      = _d(objetivo['monto_actual']);
    final falta       = _d(objetivo['falta']);
    final pct         = _d(objetivo['pct_avance']) / 100;
    final cuota       = _d(objetivo['cuota_mensual']);
    final mesesR      = (objetivo['meses_restantes'] as num?)?.toInt() ?? 0;
    final tipo        = objetivo['tipo'] as String? ?? 'otro';
    final color       = _tipoColor[tipo] ?? AppTheme.textSecondary;
    final icon        = _tipoIcon[tipo] ?? Icons.flag_outlined;
    final completado  = pct >= 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: completado ? AppTheme.success : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(objetivo['nombre'] as String? ?? '—',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            if ((objetivo['fecha_limite'] as String?) != null)
              Text('Meta: ${objetivo['fecha_limite']}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ])),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
            onSelected: (v) {
              if (v == 'abonar') { _abonar(context); }
              if (v == 'delete') { onDelete(); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'abonar', child: Text('Registrar abono')),
              PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
            ],
          ),
        ]),
        const SizedBox(height: 14),

        // Barra progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppTheme.border,
            valueColor: AlwaysStoppedAnimation(completado ? AppTheme.success : color),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('\$${actual.toStringAsFixed(2)} de \$${meta.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),

        if (!completado && cuota > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.calendar_month_outlined, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                'Ahorrá \$${cuota.toStringAsFixed(2)}/mes · faltan \$${falta.toStringAsFixed(2)} en $mesesR mes${mesesR != 1 ? "es" : ""}',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ],

        if (completado) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_outline, color: AppTheme.success, size: 14),
              SizedBox(width: 6),
              Text('¡Objetivo completado!', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
  }

  Future<void> _abonar(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Registrar abono', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(labelText: 'Monto a abonar', prefixText: '\$ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abonar')),
        ],
      ),
    );
    if (ok == true) {
      final monto = double.tryParse(ctrl.text) ?? 0;
      if (monto > 0) {
        await ApiClient.patch('/user/objetivos/${objetivo['id']}/abonar',
            {'firebase_uid': uid, 'monto': monto});
        onChanged();
      }
    }
  }
}

class _ObjetivoForm extends StatefulWidget {
  final String uid;
  const _ObjetivoForm({required this.uid});
  @override
  State<_ObjetivoForm> createState() => _ObjetivoFormState();
}

class _ObjetivoFormState extends State<_ObjetivoForm> {
  final _nombreCtrl = TextEditingController();
  final _metaCtrl   = TextEditingController();
  final _descCtrl   = TextEditingController();
  String _tipo = 'ahorro';
  DateTime? _fechaLimite;
  bool _usarPlazo = false;
  int _plazoMeses = 12;
  bool _guardando = false;

  static const _tipos = [
    {'value': 'ahorro',     'label': 'Ahorro general'},
    {'value': 'compra',     'label': 'Compra / adquisición'},
    {'value': 'emergencia', 'label': 'Fondo de emergencia'},
    {'value': 'inversion',  'label': 'Inversión'},
    {'value': 'otro',       'label': 'Otro'},
  ];

  @override
  void initState() {
    super.initState();
    _metaCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _metaCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  double get _cuotaMensual {
    final meta = double.tryParse(_metaCtrl.text) ?? 0;
    if (!_usarPlazo || _plazoMeses <= 0 || meta <= 0) return 0;
    return (meta / _plazoMeses * 100).ceil() / 100;
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final meta   = double.tryParse(_metaCtrl.text) ?? 0;
    if (nombre.isEmpty || meta <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre y monto meta son requeridos')));
      return;
    }
    DateTime? fechaFinal = _fechaLimite;
    if (_usarPlazo && fechaFinal == null) {
      final ahora = DateTime.now();
      fechaFinal = DateTime(ahora.year, ahora.month + _plazoMeses, ahora.day);
    }
    setState(() => _guardando = true);
    await ApiClient.post('/user/objetivos', {
      'firebase_uid': widget.uid,
      'nombre': nombre,
      'descripcion': _descCtrl.text.trim(),
      'monto_meta': meta,
      'tipo': _tipo,
      if (fechaFinal != null)
        'fecha_limite': '${fechaFinal.year}-${fechaFinal.month.toString().padLeft(2, '0')}-${fechaFinal.day.toString().padLeft(2, '0')}',
    });
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primary, surface: AppTheme.surfaceAlt),
        ),
        child: child!,
      ),
    );
    if (f != null) setState(() => _fechaLimite = f);
  }

  @override
  Widget build(BuildContext context) {
    final cuota = _cuotaMensual;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nuevo objetivo', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          TextField(controller: _nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre (ej: Fondo emergencia, Carro nuevo)')),
          const SizedBox(height: 12),

          TextField(controller: _metaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Monto meta', prefixText: '\$ ')),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _tipo,
            dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: _tipos.map((t) => DropdownMenuItem(value: t['value'], child: Text(t['label']!))).toList(),
            onChanged: (v) => setState(() => _tipo = v ?? 'ahorro'),
          ),
          const SizedBox(height: 16),

          // Toggle plazo / fecha límite
          Row(children: [
            const Text('Plazo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() { _usarPlazo = !_usarPlazo; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _usarPlazo ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _usarPlazo ? AppTheme.primary : AppTheme.border),
                ),
                child: Text(
                  _usarPlazo ? 'En meses' : 'Por fecha',
                  style: TextStyle(
                    color: _usarPlazo ? AppTheme.primary : AppTheme.textMuted,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          if (_usarPlazo) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$_plazoMeses ${_plazoMeses == 1 ? "mes" : "meses"}',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
            Slider(
              value: _plazoMeses.toDouble(), min: 1, max: 60, divisions: 59,
              activeColor: AppTheme.primary,
              label: '$_plazoMeses meses',
              onChanged: (v) => setState(() => _plazoMeses = v.toInt()),
            ),
            if (cuota > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.colorAhorro.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.colorAhorro.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Cuota mensual', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Text('\$${cuota.toStringAsFixed(2)}/mes',
                      style: const TextStyle(color: AppTheme.colorAhorro, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ),
          ] else ...[
            GestureDetector(
              onTap: _elegirFecha,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppTheme.textMuted, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _fechaLimite != null
                        ? 'Fecha límite: ${_fechaLimite!.day}/${_fechaLimite!.month}/${_fechaLimite!.year}'
                        : 'Fecha límite (opcional)',
                    style: TextStyle(color: _fechaLimite != null ? AppTheme.textPrimary : AppTheme.textMuted, fontSize: 14),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 12),

          TextField(controller: _descCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Crear objetivo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}
