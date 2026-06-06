import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/registros_service.dart';
import '../../services/gastos_variables_service.dart';
import '../../services/api_client.dart';
import 'mes_rango_selector.dart';
import 'categoria_selector.dart';
import 'split_section.dart';

class AgregarGastoSheet extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final int mes;
  final List<Map<String, dynamic>>? analisisCategorias;

  const AgregarGastoSheet({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    required this.mes,
    this.analisisCategorias,
  }) : super(key: key);

  @override
  State<AgregarGastoSheet> createState() => _AgregarGastoSheetState();
}

class _AgregarGastoSheetState extends State<AgregarGastoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombre  = TextEditingController();
  final _monto   = TextEditingController();
  final _notas   = TextEditingController();

  String  _tipo            = 'variable';
  String  _categoria       = 'alimentacion';
  String? _categoriaCustom;
  late DateTime _fecha;
  bool _guardando       = false;
  bool _guardarComoBase = false;
  String _frecuenciaBase   = 'mensual';
  final _splitKey = GlobalKey<SplitSectionState>();
  int  _mesInicio          = 1;
  int  _mesFin             = 12;

  // Gastos reutilizables
  List<Map<String, dynamic>> _definiciones = [];
  bool _loadingDefs = true;
  int? _defSeleccionada;

  // Envelope tracking
  Map<String, dynamic>? _catInfo;
  bool _tipoAutoSet = false;

  static const _tipos = [
    {'value': 'fijo',             'label': 'Gasto fijo',       'icon': Icons.lock_clock,       'color': AppTheme.colorFijo},
    {'value': 'variable',         'label': 'Variable',          'icon': Icons.shopping_bag,     'color': AppTheme.warning},
    {'value': 'no_presupuestado', 'label': 'No presupuestado', 'icon': Icons.add_shopping_cart, 'color': AppTheme.danger},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = (widget.anio == now.year && widget.mes == now.month)
        ? now
        : DateTime(widget.anio, widget.mes, 15);
    _mesInicio = widget.mes;
    _mesFin    = 12;
    _cargarDefiniciones();
  }

  @override
  void dispose() {
    _nombre.dispose(); _monto.dispose(); _notas.dispose();
    super.dispose();
  }

  Future<void> _cargarDefiniciones() async {
    try {
      final res = await ApiClient.get('/user/expense-definitions?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        if (mounted) setState(() {
          _definiciones = data.cast<Map<String, dynamic>>();
          _loadingDefs = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingDefs = false);
  }

  Map<String, dynamic>? _findCatInfo(String cat) {
    final list = widget.analisisCategorias;
    if (list == null) return null;
    for (final c in list) {
      if (c['categoria'] == cat) return c;
    }
    return {'categoria': cat, 'presupuestado': 0, 'total_gastado': 0};
  }

  void _seleccionarDefinicion(Map<String, dynamic> def) {
    final ultimoMonto = def['ultimo_monto'];
    setState(() {
      _defSeleccionada = def['id'] as int;
      _nombre.text     = def['nombre'] as String;
      _categoria       = def['categoria'] as String;
      _tipo            = def['tipo_habitual'] as String? ?? 'variable';
      if (ultimoMonto != null) {
        _monto.text = double.tryParse(ultimoMonto.toString())?.toStringAsFixed(2) ?? '';
      }
      _categoriaCustom = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Agregar gasto',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Registrando en: ${const ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][widget.mes]} ${widget.anio}',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── GASTOS ANTERIORES ─────────────────────────────────────────────
            if (_loadingDefs)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(color: AppTheme.primary, backgroundColor: AppTheme.surfaceAlt, minHeight: 2),
              )
            else if (_definiciones.isNotEmpty) ...[
              const Text('GASTOS ANTERIORES',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _definiciones.map((def) {
                    final sel = _defSeleccionada == def['id'];
                    final cat = def['categoria'] as String;
                    final ultimo = def['ultimo_monto'];
                    return GestureDetector(
                      onTap: () => _seleccionarDefinicion(def),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel ? AppTheme.primary : AppTheme.border,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(def['nombre'] as String,
                              style: TextStyle(
                                color: sel ? AppTheme.primary : AppTheme.textPrimary,
                                fontSize: 12, fontWeight: FontWeight.w600,
                              )),
                          if (ultimo != null)
                            Text(
                              '\$${double.tryParse(ultimo.toString())?.toStringAsFixed(2) ?? ultimo} · $cat',
                              style: TextStyle(
                                color: sel ? AppTheme.primary.withValues(alpha: 0.7) : AppTheme.textMuted,
                                fontSize: 10,
                              ),
                            ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 16),
            ],

            // ── Tipo ─────────────────────────────────────────────────────────
            const Text('TIPO', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: _tipos.map((t) {
              final sel = _tipo == t['value'];
              final color = t['color'] as Color;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() {
                  _tipo = t['value'] as String;
                  _defSeleccionada = null; // deselect si cambia tipo manualmente
                }),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? color.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? color : AppTheme.border, width: sel ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(t['icon'] as IconData, color: sel ? color : AppTheme.textMuted, size: 18),
                    const SizedBox(height: 4),
                    Text(t['label'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: sel ? color : AppTheme.textMuted,
                            fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                  ]),
                ),
              ));
            }).toList()),
            const SizedBox(height: 16),

            // ── Nombre ───────────────────────────────────────────────────────
            TextFormField(
              controller: _nombre,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre del gasto'),
              onChanged: (_) => setState(() => _defSeleccionada = null),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),

            // ── Monto ────────────────────────────────────────────────────────
            TextFormField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Monto (\$)', prefixText: '\$ '),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requerido';
                if (double.tryParse(v) == null) return 'Número inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Categoría con "Otro" personalizable ───────────────────────
            CategoriaSelector(
              firebaseUid: widget.firebaseUid,
              categoriaActual: _categoria,
              color: _tipo == 'fijo' ? AppTheme.colorFijo
                   : _tipo == 'no_presupuestado' ? AppTheme.danger
                   : AppTheme.warning,
              onChanged: (cat, custom) => setState(() {
                _categoria       = cat;
                _categoriaCustom = custom;
                final info = _findCatInfo(cat);
                _catInfo = info;
                if (info != null) {
                  final presup = double.tryParse(info['presupuestado'].toString()) ?? 0.0;
                  if (presup == 0 && _tipo == 'variable') {
                    _tipo = 'no_presupuestado';
                    _tipoAutoSet = true;
                  } else if (presup > 0 && _tipoAutoSet && _tipo == 'no_presupuestado') {
                    _tipo = 'variable';
                    _tipoAutoSet = false;
                  }
                }
              }),
            ),
            if (_catInfo != null) ...[
              const SizedBox(height: 8),
              _CatBalanceHint(cat: _catInfo!),
            ],
            const SizedBox(height: 16),

            // ── Fecha ────────────────────────────────────────────────────
            GestureDetector(
              onTap: _seleccionarFecha,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(DateFormat('dd MMM yyyy', 'es').format(_fecha),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _fecha.day <= 15 ? 'Q1 · 1–15' : 'Q2 · 16–fin',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // ── Notas ────────────────────────────────────────────────────
            TextFormField(
              controller: _notas,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 16),

            // ── Guardar como variable base ────────────────────────────────
            if (_tipo != 'fijo') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Checkbox(
                      value: _guardarComoBase,
                      onChanged: (v) => setState(() => _guardarComoBase = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'Agregar a mi presupuesto variable base',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ]),
                  if (_guardarComoBase) ...[
                    const SizedBox(height: 12),
                    const Text('Frecuencia',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (final f in const [
                        ('mensual',   'Mensual'),
                        ('quincenal', 'Quincenal'),
                        ('semanal',   'Semanal'),
                        ('anual',     'Anual'),
                      ])
                        Expanded(child: GestureDetector(
                          onTap: () => setState(() => _frecuenciaBase = f.$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _frecuenciaBase == f.$1
                                  ? AppTheme.primary.withValues(alpha: 0.12)
                                  : AppTheme.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _frecuenciaBase == f.$1
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Text(f.$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _frecuenciaBase == f.$1
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: _frecuenciaBase == f.$1
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                )),
                          ),
                        )),
                    ]),
                    const SizedBox(height: 12),
                    MesRangoSelector(
                      mesInicio: _mesInicio,
                      mesFin: _mesFin,
                      onChange: (i, f) => setState(() { _mesInicio = i; _mesFin = f; }),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── ¿Gasto compartido? ───────────────────────────────────────
            SplitSection(
              key: _splitKey,
              getTotal: () => double.tryParse(_monto.text.replaceAll(',', '')) ?? 0,
            ),
            const SizedBox(height: 16),

            // ── Botón guardar ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background))
                    : const Text('Guardar gasto'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final lastDay = DateTime(widget.anio, widget.mes + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(widget.anio, widget.mes, 1),
      lastDate: lastDay,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoria == 'otro' && (_categoriaCustom == null || _categoriaCustom!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el nombre de la categoría personalizada')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final categoriaFinal = (_categoria == 'otro' && _categoriaCustom != null)
          ? _categoriaCustom!
          : _categoria;
      final creado = await RegistrosService.crear(
        uid: widget.firebaseUid, anio: widget.anio, mes: widget.mes,
        tipo: _tipo, categoria: categoriaFinal,
        nombre: _nombre.text.trim(),
        monto: double.parse(_monto.text),
        fecha: DateFormat('yyyy-MM-dd').format(_fecha),
        notas: _notas.text.isEmpty ? null : _notas.text.trim(),
        definitionId: _defSeleccionada,
        pagado: _tipo == 'fijo' ? 1 : 0,
      );
      if (_guardarComoBase && _tipo != 'fijo') {
        await GastosVariablesService.crear(
          uid: widget.firebaseUid, nombre: _nombre.text.trim(),
          categoria: categoriaFinal,
          montoEstimado: double.parse(_monto.text),
          frecuencia: _frecuenciaBase,
          mesInicio: _mesInicio, mesFin: _mesFin,
        );
      }
      final splitState = _splitKey.currentState;
      if (splitState != null && splitState.activo) {
        await enviarSplitPuntual(
          firebaseUid: widget.firebaseUid,
          descripcion: _nombre.text.trim(),
          montoTotal: double.parse(_monto.text.replaceAll(',', '')),
          participantes: splitState.participantes,
          tipo: splitState.tipo,
          registroGastoId: creado['id'] as int?,
        );
      }
      // T1 — continuidad: si fue no presupuestado y no se guardó como base,
      // ofrecer agregarlo al presupuesto para que no quede como punto ciego.
      if (mounted && _tipo == 'no_presupuestado' && !_guardarComoBase) {
        await _ofrecerAgregarPresupuesto(categoriaFinal, creado['id'] as int?);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _ofrecerAgregarPresupuesto(String categoria, int? registroId) async {
    if (registroId == null) return;
    final monto = double.tryParse(_monto.text.replaceAll(',', '')) ?? 0;
    final catLabel = categoria.isNotEmpty
        ? '${categoria[0].toUpperCase()}${categoria.substring(1)}'
        : categoria;
    final agregar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Gasto fuera de tu plan',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'Registraste \$${monto.toStringAsFixed(2)} en "$catLabel" que no estaba presupuestado.\n\n'
          '¿Quieres agregar esta categoría a tu presupuesto para controlarla cada mes?',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Agregar al presupuesto',
                style: TextStyle(color: AppTheme.background)),
          ),
        ],
      ),
    );
    if (agregar == true) {
      try {
        await RegistrosService.convertirAVariable(widget.firebaseUid, registroId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$catLabel" agregada a tu presupuesto base'),
                backgroundColor: AppTheme.success));
      } catch (_) {}
    }
  }
}

class _CatBalanceHint extends StatelessWidget {
  final Map<String, dynamic> cat;
  const _CatBalanceHint({required this.cat});

  @override
  Widget build(BuildContext context) {
    final presup = double.tryParse(cat['presupuestado'].toString()) ?? 0.0;
    final total  = double.tryParse(cat['total_gastado'].toString()) ?? 0.0;

    if (presup == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppTheme.danger, size: 14),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Esta categoría no está en tu presupuesto',
            style: TextStyle(color: AppTheme.danger, fontSize: 12),
          )),
        ]),
      );
    }

    final quedan = presup - total;
    final excede = quedan < 0;
    final bar    = (total / presup).clamp(0.0, 1.0);
    final color  = excede ? AppTheme.danger : bar > 0.8 ? AppTheme.warning : AppTheme.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(
            excede
                ? 'Excedido \$${(-quedan).toStringAsFixed(2)} · gastado \$${total.toStringAsFixed(2)} de \$${presup.toStringAsFixed(2)}'
                : 'Te quedan \$${quedan.toStringAsFixed(2)} · gastado \$${total.toStringAsFixed(2)} de \$${presup.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          )),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: bar,
            minHeight: 3,
            color: color,
            backgroundColor: AppTheme.surfaceAlt,
          ),
        ),
      ]),
    );
  }
}

