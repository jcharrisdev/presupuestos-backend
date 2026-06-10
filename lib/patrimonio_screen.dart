import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'deudas/deudas_screen.dart';

class PatrimonioScreen extends StatefulWidget {
  final String firebaseUid;
  const PatrimonioScreen({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  State<PatrimonioScreen> createState() => _PatrimonioScreenState();
}

class _PatrimonioScreenState extends State<PatrimonioScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient.get('/user/patrimonio?firebase_uid=${widget.firebaseUid}');
      if (r.statusCode == 200 && mounted) {
        setState(() { _data = jsonDecode(r.body); _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final activos  = (_data?['activos']  as List? ?? []).cast<Map<String, dynamic>>();
    final pasivos  = (_data?['deudas']   as List? ?? []).cast<Map<String, dynamic>>();
    final totalA   = _d(_data?['total_activos']);
    final totalP   = _d(_data?['total_pasivos']);
    final patNeto  = _d(_data?['patrimonio_neto']);
    final color    = patNeto >= 0 ? AppTheme.success : AppTheme.danger;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Patrimonio Neto')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarActivo,
        icon: const Icon(Icons.add, color: AppTheme.background),
        label: const Text('Agregar activo', style: TextStyle(color: AppTheme.background)),
        backgroundColor: AppTheme.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Card patrimonio neto
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Column(children: [
                    const Text('Tu patrimonio neto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('\$${patNeto.toStringAsFixed(2)}',
                        style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(patNeto >= 0 ? '¡Tus activos superan tus deudas!' : 'Tus deudas superan tus activos.',
                        style: TextStyle(color: color, fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _MiniKpi('Activos', totalA, AppTheme.success)),
                      Container(width: 1, height: 40, color: color.withValues(alpha: 0.2)),
                      Expanded(child: _MiniKpi('Pasivos', totalP, AppTheme.danger)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                // R1 — diferenciar patrimonio (stock) de presupuesto (flujo)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Icon(Icons.lightbulb_outline, color: AppTheme.info, size: 16),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Tu patrimonio es lo que tienes acumulado. Tu presupuesto mensual controla lo que entra y sale cada mes. Son dos vistas del mismo dinero.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
                    )),
                  ]),
                ),
                const SizedBox(height: 20),

                // Activos
                _seccion('ACTIVOS (lo que tenés)'),
                if (activos.isEmpty)
                  _empty('Agrega tus activos: casa, carro, ahorros, inversiones…')
                else
                  ...activos.map((a) => _ActivoTile(
                    activo: a,
                    onEdit: () => _editarActivo(a),
                    onDelete: () => _eliminarActivo(a['id'] as int),
                  )),
                const SizedBox(height: 20),

                // Pasivos
                _seccion('PASIVOS (lo que debés)'),
                if (pasivos.isEmpty)
                  _empty('Sin deudas activas. ¡Excelente!')
                else
                  ...pasivos.map((d) => _PasivoTile(
                        deuda: d,
                        onVerDeuda: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => DeudasScreen(firebaseUid: widget.firebaseUid),
                        )).then((_) => _cargar()),
                      )),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }

  Widget _seccion(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
  );

  Widget _empty(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(msg, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
  );

  Future<void> _agregarActivo([Map<String, dynamic>? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ActivoForm(uid: widget.firebaseUid, existing: existing),
    );
    if (result == true) _cargar();
  }

  Future<void> _editarActivo(Map<String, dynamic> a) => _agregarActivo(a);

  Future<void> _eliminarActivo(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar activo', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('¿Estás seguro?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await ApiClient.delete('/user/activos/$id?firebase_uid=${widget.firebaseUid}');
      _cargar();
    }
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final double valor;
  final Color color;
  const _MiniKpi(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text('\$${valor.toStringAsFixed(2)}',
        style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
  ]);
}

class _ActivoTile extends StatelessWidget {
  final Map<String, dynamic> activo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ActivoTile({required this.activo, required this.onEdit, required this.onDelete});

  static const _tipoIcon = {
    'inmueble': Icons.home_outlined,
    'vehiculo': Icons.directions_car_outlined,
    'cuenta_banco': Icons.account_balance_outlined,
    'inversiones': Icons.trending_up,
    'efectivo': Icons.money,
    'otro': Icons.category_outlined,
  };

  // AC2 — meses desde la última actualización del valor
  int? _mesesDesdeActualizacion() {
    final raw = activo['updated_at'] ?? activo['created_at'];
    if (raw == null) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    final now = DateTime.now();
    return (now.difference(d).inDays / 30).floor();
  }

  @override
  Widget build(BuildContext context) {
    final valor = double.tryParse(activo['valor'].toString()) ?? 0;
    final icon  = _tipoIcon[activo['tipo'] as String? ?? 'otro'] ?? Icons.category_outlined;
    final meses = _mesesDesdeActualizacion();
    final desactualizado = meses != null && meses >= 6;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: desactualizado ? AppTheme.warning.withValues(alpha: 0.5) : AppTheme.border),
      ),
      child: Row(children: [
        Icon(icon, color: AppTheme.success, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(activo['nombre'] as String, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(activo['tipo'] as String? ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          if (desactualizado)
            GestureDetector(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  const Icon(Icons.update, color: AppTheme.warning, size: 12),
                  const SizedBox(width: 4),
                  Text('Valor de hace $meses meses · ¿Actualizar?',
                      style: const TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ])),
        Text('\$${valor.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.success, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
          onSelected: (v) { if (v == 'edit') onEdit(); else onDelete(); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
          ],
        ),
      ]),
    );
  }
}

class _PasivoTile extends StatelessWidget {
  final Map<String, dynamic> deuda;
  final VoidCallback? onVerDeuda; // AC1 — navegar a la deuda en Mis Deudas
  const _PasivoTile({required this.deuda, this.onVerDeuda});
  @override
  Widget build(BuildContext context) {
    final saldo = double.tryParse((deuda['monto_pendiente'] ?? deuda['monto_total']).toString()) ?? 0;
    return GestureDetector(
      onTap: onVerDeuda,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          const Icon(Icons.credit_card, color: AppTheme.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deuda['nombre'] as String? ?? '—', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(deuda['tipo'] as String? ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            if (onVerDeuda != null) ...[
              const SizedBox(height: 3),
              Row(children: const [
                Text('Ver deuda', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: AppTheme.primary, size: 14),
              ]),
            ],
          ])),
          Text('\$${saldo.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _ActivoForm extends StatefulWidget {
  final String uid;
  final Map<String, dynamic>? existing;
  const _ActivoForm({required this.uid, this.existing});
  @override
  State<_ActivoForm> createState() => _ActivoFormState();
}

class _ActivoFormState extends State<_ActivoForm> {
  final _nombreCtrl = TextEditingController();
  final _valorCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  String _tipo = 'otro';
  bool _guardando = false;

  static const _tipos = [
    {'value': 'inmueble',     'label': 'Inmueble',      'icon': Icons.home_outlined},
    {'value': 'vehiculo',     'label': 'Vehículo',      'icon': Icons.directions_car_outlined},
    {'value': 'cuenta_banco', 'label': 'Cuenta banco',  'icon': Icons.account_balance_outlined},
    {'value': 'inversiones',  'label': 'Inversiones',   'icon': Icons.trending_up},
    {'value': 'efectivo',     'label': 'Efectivo',      'icon': Icons.money},
    {'value': 'otro',         'label': 'Otro',          'icon': Icons.category_outlined},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nombreCtrl.text = widget.existing!['nombre'] as String? ?? '';
      _valorCtrl.text  = (widget.existing!['valor'] ?? '').toString();
      _descCtrl.text   = widget.existing!['descripcion'] as String? ?? '';
      _tipo = widget.existing!['tipo'] as String? ?? 'otro';
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _valorCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final valor  = double.tryParse(_valorCtrl.text) ?? 0;
    if (nombre.isEmpty || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre y valor son requeridos')));
      return;
    }
    setState(() => _guardando = true);
    final body = {'firebase_uid': widget.uid, 'nombre': nombre, 'tipo': _tipo, 'valor': valor, 'descripcion': _descCtrl.text.trim()};
    final existing = widget.existing;
    if (existing != null) {
      await ApiClient.put('/user/activos/${existing['id']}', body);
    } else {
      await ApiClient.post('/user/activos', body);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing != null ? 'Editar activo' : 'Nuevo activo',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          // R2 — explicar para qué sirve registrar un activo
          const Text(
            'Registrar tus activos te ayuda a ver tu salud financiera completa. No afecta tu presupuesto mensual.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(controller: _nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre (ej: Apartamento, Toyota Yaris)')),
          const SizedBox(height: 12),
          TextField(controller: _valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Valor en dólares', prefixText: '\$ ')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tipo,
            dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: _tipos.map((t) => DropdownMenuItem(
              value: t['value'] as String,
              child: Text(t['label'] as String),
            )).toList(),
            onChanged: (v) => setState(() => _tipo = v ?? 'otro'),
          ),
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
                  : const Text('Guardar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}
