import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/gastos_variables_service.dart';

/// Selector de categoría con soporte para categorías personalizadas.
/// Cuando el usuario selecciona "Otro", aparece un campo de texto.
/// La categoría personalizada se guarda para aparecer en futuras sesiones.
class CategoriaSelector extends StatefulWidget {
  final String firebaseUid;
  final String categoriaActual;
  final void Function(String categoria, String? categoriaCustom) onChanged;
  final Color color;

  const CategoriaSelector({
    Key? key,
    required this.firebaseUid,
    required this.categoriaActual,
    required this.onChanged,
    this.color = AppTheme.primary,
  }) : super(key: key);

  /// Lista canónica de categorías de Salarying — fuente única de verdad.
  /// Usada en este selector, en el perfil financiero y como referencia
  /// para el match presupuesto↔real del motor de alertas.
  static const List<Map<String, Object>> canonicas = [
    {'value': 'alimentacion', 'label': 'Alimentación', 'icon': Icons.restaurant},
    {'value': 'transporte',   'label': 'Transporte',   'icon': Icons.directions_car},
    {'value': 'vivienda',     'label': 'Vivienda',     'icon': Icons.home},
    {'value': 'servicios',    'label': 'Servicios',    'icon': Icons.lightbulb_outline},
    {'value': 'salud',        'label': 'Salud',        'icon': Icons.local_hospital},
    {'value': 'educacion',    'label': 'Educación',    'icon': Icons.school},
    {'value': 'ocio',         'label': 'Ocio',         'icon': Icons.sports_esports},
    {'value': 'deudas',       'label': 'Deudas',       'icon': Icons.account_balance},
    {'value': 'ropa',         'label': 'Ropa',         'icon': Icons.checkroom},
    {'value': 'deportes',     'label': 'Deportes',     'icon': Icons.fitness_center},
    {'value': 'familia',      'label': 'Familia',      'icon': Icons.family_restroom},
    {'value': 'tecnologia',   'label': 'Tecnología',   'icon': Icons.devices},
    {'value': 'emergencias',  'label': 'Emergencias',  'icon': Icons.warning_amber},
    {'value': 'otro',         'label': 'Otro...',      'icon': Icons.add_circle_outline},
  ];

  @override
  State<CategoriaSelector> createState() => _CategoriaSelectorState();
}

class _CategoriaSelectorState extends State<CategoriaSelector> {
  final _customCtrl = TextEditingController();
  List<String> _categoriasCustom = [];
  bool _mostrarCustom = false;

  static const _categoriasBase = CategoriaSelector.canonicas;

  @override
  void initState() {
    super.initState();
    _cargarCustom();
    // Si la categoría actual no es una de las base, es personalizada
    final esBase = _categoriasBase.any((c) => c['value'] == widget.categoriaActual);
    if (!esBase && widget.categoriaActual != 'otro') {
      _mostrarCustom = true;
      _customCtrl.text = widget.categoriaActual;
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCustom() async {
    try {
      final subs = await GastosVariablesService.getSubcategorias(widget.firebaseUid, categoria: 'custom');
      if (mounted) {
        setState(() => _categoriasCustom = subs.map((s) => s['nombre'] as String).toList());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final todas = [
      ..._categoriasBase,
      ..._categoriasCustom.map((c) => <String, Object>{'value': c, 'label': c, 'icon': Icons.label_outline}),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('CATEGORÍA',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      SizedBox(
        height: 76,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: todas.map((c) {
            final val = c['value'] as String;
            final sel = _mostrarCustom ? val == 'otro' : widget.categoriaActual == val;
            return GestureDetector(
              onTap: () {
                if (val == 'otro') {
                  setState(() => _mostrarCustom = true);
                  widget.onChanged('otro', null);
                } else {
                  setState(() => _mostrarCustom = false);
                  widget.onChanged(val, null);
                }
              },
              child: Container(
                width: 72,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: sel ? widget.color.withValues(alpha: 0.12) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: sel ? widget.color : AppTheme.border,
                      width: sel ? 1.5 : 1),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(c['icon'] as IconData,
                      color: sel ? widget.color : AppTheme.textMuted, size: 20),
                  const SizedBox(height: 4),
                  Text(c['label'] as String,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sel ? widget.color : AppTheme.textMuted,
                        fontSize: 9,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                      )),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
      // Campo de texto para categoría personalizada
      if (_mostrarCustom) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _customCtrl,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Nombre de la categoría (ej: Mascotas)',
                prefixIcon: Icon(Icons.label_outline, color: AppTheme.textSecondary, size: 18),
              ),
              onChanged: (v) => widget.onChanged('otro', v.isNotEmpty ? v : null),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.check_circle, color: AppTheme.success, size: 24),
            onPressed: () {
              final txt = _customCtrl.text.trim();
              if (txt.isNotEmpty) {
                // Guardar en las categorías del usuario
                GastosVariablesService.crearSubcategoria(widget.firebaseUid, 'custom', txt.toLowerCase())
                    .then((_) => _cargarCustom())
                    .catchError((_) {});
                setState(() => _mostrarCustom = false);
                widget.onChanged(txt.toLowerCase(), txt.toLowerCase());
              }
            },
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Se guardará para usarla en el futuro',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    ]);
  }
}
