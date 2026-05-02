/// Pantalla para crear un nuevo presupuesto.
///
/// Campos del formulario:
///   - Nombre descriptivo (ej: "Casa", "Trabajo")
///   - Monto total del período (límite de gasto por ciclo)
///   - Tipo de período: quincenal (14 días) o mensual (30 días)
///   - Día de inicio del período: del 1 al 31
///
/// Al confirmar llama a POST /presupuestos y hace `Navigator.pop()`
/// para regresar a [ListaPresupuestos], que recarga automáticamente.
import 'package:flutter/material.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'services/api_client.dart';

/// Formulario de creación de presupuesto.
class CrearPresupuesto extends StatefulWidget {
  final String firebaseUid;
  const CrearPresupuesto({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  _CrearPresupuestoState createState() => _CrearPresupuestoState();
}

class _CrearPresupuestoState extends State<CrearPresupuesto> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl  = TextEditingController();

  /// Tipo de período seleccionado. Por defecto mensual.
  String _tipoPeriodo = 'mensual';

  /// Día del mes en que inicia cada nuevo período (1–31).
  int _diaInicio = 1;

  /// true mientras se espera respuesta del backend.
  bool _loading = false;

  /// Envía el formulario al backend.
  ///
  /// Valida que el nombre no esté vacío y que el monto sea positivo.
  /// En caso de error de servidor, muestra el mensaje retornado por la API.
  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    final monto  = double.tryParse(_montoCtrl.text.trim());

    if (nombre.isEmpty || monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos correctamente')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await ApiClient.post('/presupuestos', {
        'nombre': nombre,
        'monto_total': monto,
        'firebase_uid': widget.firebaseUid,
        'tipo_periodo': _tipoPeriodo,
        'dia_inicio_periodo': _diaInicio,
      });

      if (res.statusCode == 201) {
        if (!mounted) return;
        Navigator.pop(context); // regresa a ListaPresupuestos que recargará
      } else {
        final err = json.decode(res.body);
        throw Exception(err['error'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _montoCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Presupuesto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Crear presupuesto',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Un presupuesto define cuánto puedes gastar en cada ciclo.\n\n'
                  '• Nombre — ponle un nombre que identifique para qué es (ej: "Casa", "Trabajo").\n'
                  '• Monto total — el límite de gasto por período.\n'
                  '• Tipo de período — Quincenal (cada 14 días) o Mensual (cada 30 días).\n'
                  '• Día de inicio — el día del mes en que comienza cada nuevo ciclo.\n\n'
                  'Una vez creado, podrás agregar gastos fijos, variables y metas de ahorro dentro de él.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── NOMBRE ────────────────────────────────────────────────────
            _label('Nombre del presupuesto'),
            TextField(
              controller: _nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Ej: Casa, Trabajo, Personal...'),
            ),
            const SizedBox(height: 20),

            // ── MONTO ─────────────────────────────────────────────────────
            _label('Monto total del período'),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),

            // ── TIPO DE PERÍODO ───────────────────────────────────────────
            // Toggle visual entre Quincenal y Mensual.
            // _PeriodOption usa AnimatedContainer para suavizar la selección.
            _label('Tipo de período'),
            Row(children: [
              _PeriodOption(
                label: 'Quincenal', sub: '14 días',
                selected: _tipoPeriodo == 'quincenal',
                onTap: () => setState(() => _tipoPeriodo = 'quincenal'),
              ),
              const SizedBox(width: 12),
              _PeriodOption(
                label: 'Mensual', sub: '30 días',
                selected: _tipoPeriodo == 'mensual',
                onTap: () => setState(() => _tipoPeriodo = 'mensual'),
              ),
            ]),
            const SizedBox(height: 20),

            // ── DÍA DE INICIO ─────────────────────────────────────────────
            // El backend usa este día para calcular automáticamente
            // las fechas de inicio y fin de cada período.
            _label('Día de inicio del período'),
            DropdownButtonFormField<int>(
              value: _diaInicio,
              dropdownColor: AppTheme.surfaceAlt,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(),
              items: List.generate(31, (i) => DropdownMenuItem(
                value: i + 1,
                child: Text('Día ${i + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
              )),
              onChanged: (v) => setState(() => _diaInicio = v!),
            ),
            const SizedBox(height: 36),

            // ── BOTÓN CREAR ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : ElevatedButton(onPressed: _crear, child: const Text('Crear Presupuesto')),
            ),
          ],
        ),
      ),
    );
  }

  /// Etiqueta de campo de formulario con estilo consistente.
  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.4)),
  );
}

/// Botón de toggle para seleccionar tipo de período (Quincenal / Mensual).
///
/// Usa [AnimatedContainer] para una transición suave al cambiar la selección.
class _PeriodOption extends StatelessWidget {
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodOption({required this.label, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            // Fondo amarillo semitransparente si está seleccionado
            color: selected ? AppTheme.primary.withOpacity(0.1) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 14,
            )),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(
              color: selected ? AppTheme.primary.withOpacity(0.7) : AppTheme.textMuted,
              fontSize: 11,
            )),
          ]),
        ),
      ),
    );
  }
}
