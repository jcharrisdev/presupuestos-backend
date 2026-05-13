import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';

/// Calculadora de precio de venta sugerido.
///
/// No guarda nada — es una herramienta de proyección offline.
/// El usuario ingresa la inversión (desde un presupuesto de producción),
/// cuántas unidades va a vender y el % de ganancia deseado (markup sobre costo).
///
/// Fórmula: precio_sugerido = (invertido × (1 + markup)) / unidades
class ProyeccionScreen extends StatefulWidget {
  final double invertidoInicial;
  final String nombreProduccion;

  const ProyeccionScreen({
    super.key,
    required this.invertidoInicial,
    required this.nombreProduccion,
  });

  @override
  State<ProyeccionScreen> createState() => _ProyeccionScreenState();
}

class _ProyeccionScreenState extends State<ProyeccionScreen> {
  late double _invertido;
  double _markup = 0.50; // 50% por defecto
  final _unidadesCtrl = TextEditingController(text: '1');
  final _invertidoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _invertido = widget.invertidoInicial;
    _invertidoCtrl.text = widget.invertidoInicial.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _unidadesCtrl.dispose();
    _invertidoCtrl.dispose();
    super.dispose();
  }

  double get _unidades => double.tryParse(_unidadesCtrl.text) ?? 1;

  double get _precioEquilibrio => _unidades > 0 ? _invertido / _unidades : 0;
  double get _gananciaTotal    => _invertido * _markup;
  double get _ingresoTotal     => _invertido + _gananciaTotal;
  double get _precioSugerido   => _unidades > 0 ? _ingresoTotal / _unidades : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Proyección de precio', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('¿Cómo funciona?',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Esta calculadora te ayuda a decidir el precio de venta de tu producto '
                  'antes de crearlo en el catálogo.\n\n'
                  '• Inversión: el costo total de tu producción.\n'
                  '• Unidades a vender: cuántos productos tienes para vender.\n'
                  '• % de ganancia: cuánto quieres ganar sobre lo que invertiste.\n\n'
                  'Ejemplo: invertiste \$12, produces 32 cinnamon rolls, '
                  'quieres ganar 50% sobre el costo.\n'
                  '→ Ganancia esperada: \$6.00\n'
                  '→ Precio por roll: \$0.56\n\n'
                  'Nada se guarda al salir. Usa el precio sugerido al crear tu producto.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Nombre de la producción ────────────────────────────────────
          if (widget.nombreProduccion.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.nombreProduccion,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // ── Inputs ─────────────────────────────────────────────────────
          _sectionLabel('INVERSIÓN TOTAL'),
          const SizedBox(height: 8),
          TextField(
            controller: _invertidoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18),
              hintText: '0.00',
            ),
            onChanged: (v) => setState(() => _invertido = double.tryParse(v) ?? 0),
          ),

          const SizedBox(height: 20),
          _sectionLabel('UNIDADES A VENDER'),
          const SizedBox(height: 8),
          TextField(
            controller: _unidadesCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: '1'),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 20),
          _sectionLabel('GANANCIA DESEADA SOBRE COSTO'),
          const SizedBox(height: 4),
          Text(
            '${(_markup * 100).toStringAsFixed(0)}%  →  si inviertes \$1 quieres ganar \$${_markup.toStringAsFixed(2)} adicionales',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          Slider(
            value: _markup,
            min: 0.05,
            max: 2.00,
            divisions: 39,
            activeColor: AppTheme.primary,
            label: '${(_markup * 100).toStringAsFixed(0)}%',
            onChanged: (v) => setState(() => _markup = v),
          ),
          // Botones rápidos de markup
          Wrap(spacing: 8, children: [
            for (final pct in [0.10, 0.20, 0.30, 0.50, 0.75, 1.00])
              ChoiceChip(
                label: Text('${(pct * 100).toInt()}%'),
                selected: (_markup - pct).abs() < 0.001,
                onSelected: (_) => setState(() => _markup = pct),
                selectedColor: AppTheme.primary.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: (_markup - pct).abs() < 0.001 ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600, fontSize: 12,
                ),
              ),
          ]),

          const SizedBox(height: 24),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 20),

          // ── Resultados ─────────────────────────────────────────────────
          _sectionLabel('RESULTADOS'),
          const SizedBox(height: 12),

          _resultCard(
            icon: Icons.warning_amber_outlined,
            iconColor: AppTheme.warning,
            label: 'Precio mínimo (punto de equilibrio)',
            value: '\$${_precioEquilibrio.toStringAsFixed(2)}',
            sublabel: 'Vendes sin ganar ni perder',
          ),
          const SizedBox(height: 10),

          _resultCard(
            icon: Icons.attach_money,
            iconColor: AppTheme.success,
            label: 'Precio sugerido por unidad',
            value: '\$${_precioSugerido.toStringAsFixed(2)}',
            sublabel: 'Con ${(_markup * 100).toStringAsFixed(0)}% de ganancia sobre costo',
            destacado: true,
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: _miniCard('Ganancia total', '\$${_gananciaTotal.toStringAsFixed(2)}', AppTheme.success)),
            const SizedBox(width: 10),
            Expanded(child: _miniCard('Ingresos totales', '\$${_ingresoTotal.toStringAsFixed(2)}', AppTheme.primary)),
          ]),

          const SizedBox(height: 24),

          // Botón copiar precio sugerido
          if (_precioSugerido > 0)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text('Copiar precio: \$${_precioSugerido.toStringAsFixed(2)}'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _precioSugerido.toStringAsFixed(2)));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Precio copiado al portapapeles'),
                    backgroundColor: AppTheme.success,
                    duration: Duration(seconds: 2),
                  ));
                },
              ),
            ),

          const SizedBox(height: 12),
          const Text(
            'Esta pantalla no guarda nada. Usa el precio sugerido al crear tu producto en el catálogo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600),
  );

  Widget _resultCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String sublabel,
    bool destacado = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: destacado ? AppTheme.primary.withOpacity(0.06) : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destacado ? AppTheme.primary.withOpacity(0.25) : AppTheme.border,
          width: destacado ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(sublabel, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ])),
        Text(value, style: TextStyle(
          color: destacado ? AppTheme.primary : AppTheme.textPrimary,
          fontWeight: FontWeight.w800, fontSize: destacado ? 20 : 16,
        )),
      ]),
    );
  }

  Widget _miniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
    );
  }
}
